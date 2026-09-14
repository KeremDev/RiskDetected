import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915170000_isg_ppe_handovers.sql');
const core=read('supabase/migrations/20260913230000_isg_module_core.sql');
const checks=read('scripts/isg/ppe_handovers_check.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.match(code(slice),/PERFORM private_isg\.module_gate\('ppe',p_write\);/);
  assert.match(checks,/a closed feature refuses ahead of the module/);
  assert.match(checks,/a closed module refuses on its own/);
});

test('the only new table is private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['ppe_receipts']);
  assert.match(slice,/ALTER TABLE private_isg\.ppe_receipts ENABLE ROW LEVEL SECURITY/);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and both are invoker',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_ppe_read_v1','isg_ppe_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,280}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('the boundary checks ownership the core functions never did',()=>{
  // record_ppe_return took a handover id and trusted it.
  const record=code(core).match(/CREATE FUNCTION private_isg\.record_ppe_return[\s\S]*?END \$\$;/)[0];
  assert.doesNotMatch(record,/active_actor|company_id=p_company/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_ppe_company/);
  assert.match(code(slice),/WHERE handover_id=handover AND company_id=p_company FOR UPDATE;/);
  assert.match(checks,/a handover outside the company is refused/);
  assert.match(checks,/an employee of another company is refused/);
});

test('the product never claims to hold a signed form',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/'signed_copy'/);
  assert.doesNotMatch(allow,/asset/);
  // The core is always called with a false flag and no asset.
  assert.match(code(slice),/\(p_payload->>'handed_on'\)::date,NULL,false,/);
  assert.match(code(slice),/'signed_copy_stored',false/);
  assert.match(code(slice),/'signed_copy_storage_available',false/);
  // What is kept instead is where the form is.
  assert.match(slice,/ADD COLUMN signed_copy_location text/);
  assert.match(checks,/the signed copy flag cannot be set by the client/);
});

test('what is still out is counted at read, never stored',()=>{
  assert.match(code(slice),/'outstanding',entry\.quantity-returned/);
  assert.match(code(slice),/'state_authority','computed_at_read'/);
  // No column holds it.
  assert.doesNotMatch(slice,/ADD COLUMN outstanding/);
  assert.match(checks,/the outstanding amount is recounted, not patched/);
});

test('a mistaken return can be taken back, and only from its own handover',()=>{
  const fn=code(slice).match(/CREATE FUNCTION private_isg\.remove_ppe_return[\s\S]*?END \$\$;/)[0];
  assert.match(fn,/DELETE FROM private_isg\.ppe_returns\s*\n?\s*WHERE return_id=p_return AND handover_id=p_handover;/);
  assert.match(fn,/IF removed=0 THEN RAISE EXCEPTION[\s\S]{0,60}ACCESS_DENIED/);
  assert.match(checks,/a return that is not on this handover cannot be removed/);
});

test('the two quantity rules stay in the core and are reached through the boundary',()=>{
  const record=code(core).match(/CREATE FUNCTION private_isg\.record_ppe_return[\s\S]*?END \$\$;/)[0];
  assert.match(record,/RETURN_BEFORE_HANDOVER/);
  assert.match(record,/RETURN_EXCEEDS_HANDOVER/);
  assert.match(code(slice),/private_isg\.record_ppe_return\(handover,/);
  assert.match(checks,/a return before the handover is refused/);
  assert.match(checks,/more coming back than went out is refused/);
  assert.match(checks,/the second return cannot push the total over either/);
});

test('nothing is handed over or returned on a day that has not happened',()=>{
  assert.match(code(slice),/HANDED_IN_THE_FUTURE/);
  assert.match(code(slice),/RETURNED_IN_THE_FUTURE/);
  assert.match(checks,/a handover dated tomorrow is refused/);
  assert.match(checks,/a return dated tomorrow is refused/);
});

test('no fixed equipment list ships',()=>{
  assert.match(code(slice),/'item_catalogue_offered',false/);
  assert.doesNotMatch(slice,/CREATE TABLE private_isg\.ppe_item/);
  assert.match(checks,/no fixed equipment list is offered either/);
});

test('no read claims compliance or a health record',()=>{
  assert.match(code(slice),/'compliance_verdict',NULL/);
  assert.match(code(slice),/'health_records_tracked',false/);
  assert.doesNotMatch(code(slice),/health_record_id|medical/i);
});

test('every mutation is receipted and the same id cannot mean two things',()=>{
  assert.match(code(slice),/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(code(slice),/request_hash IS DISTINCT FROM fingerprint THEN[\s\S]{0,120}IDEMPOTENCY_CONFLICT/);
  assert.match(checks,/the same id with a different body is refused/);
});

test('the checks are written for a disposable database only',()=>{
  assert.doesNotMatch(checks,/DROP SCHEMA|DROP DATABASE/);
  assert.match(checks,/ALL PPE HANDOVER CHECKS PASSED/);
});
