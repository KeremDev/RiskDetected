import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915130000_isg_emergency_plans.sql');
const core=read('supabase/migrations/20260913230000_isg_module_core.sql');
const checks=read('scripts/isg/emergency_plans_check.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.match(code(slice),/PERFORM private_isg\.module_gate\('emergency_plan',p_write\);/);
  // Both switches must be open, and they fail differently.
  assert.match(checks,/a closed feature refuses ahead of the module/);
  assert.match(checks,/a closed module refuses on its own/);
  assert.match(checks,/opening one module opens only that one/);
});

test('the new tables are private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['emergency_plan_receipts','emergency_team_roles']);
  const secured=new Set([...slice.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  for(const table of created) assert.ok(secured.has(table),table);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and both are invoker',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_emergency_plans_read_v1','isg_emergency_plans_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,260}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('the boundary checks ownership the core function never did',()=>{
  // module_scope proves the workplace belongs to the company, never that the
  // company belongs to the caller.
  const scope=code(core).match(/CREATE FUNCTION private_isg\.module_scope[\s\S]*?END \$\$;/)[0];
  assert.doesNotMatch(scope,/active_actor/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_emergency_company/);
  assert.match(code(slice),/AND id=\(p_payload->>'workplace_id'\)::uuid AND owner_id=actor AND NOT is_archived;/);
  // And a renewal must be aimed at a plan this company already holds.
  assert.match(code(slice),/WHERE plan_id=plan AND company_id=p_company AND owner_id=actor FOR UPDATE;/);
  assert.match(checks,/a renewal aimed at an unknown plan is refused/);
});

test('a team snapshot cannot be arbitrary JSON',()=>{
  const fn=code(slice).match(/CREATE FUNCTION private_isg\.emergency_team_snapshot[\s\S]*?END \$\$;/)[0];
  assert.match(fn,/WHERE key NOT IN \('full_name','role','contact'\)/);
  assert.match(fn,/PAYLOAD_NOT_ALLOWED/);
  assert.match(fn,/FROM private_isg\.emergency_team_roles WHERE role_code=role;/);
  assert.match(fn,/TEAM_ROLE_UNKNOWN/);
  for(const label of ['an unexpected key in a team entry is refused',
                      'a role the schema does not know is refused',
                      'a team entry with no name is refused',
                      'an empty team is refused']) assert.match(checks,new RegExp(label));
});

test('a validity date is never invented and a missing one is never valid',()=>{
  const status=code(slice).match(/CREATE FUNCTION private_isg\.emergency_plan_status[\s\S]*?END \$\$;/)[0];
  assert.match(status,/IF p_valid_until IS NULL THEN RETURN 'period_unknown'/);
  assert.ok(status.indexOf("period_unknown")<status.indexOf("RETURN 'valid'"));
  assert.match(code(slice),/'period_defaults_offered',false/);
  assert.match(code(slice),/'period_source','expert'/);
  assert.match(checks,/a plan with no end date is a gap, not a clean bill/);
});

test('the review flag follows from a written basis and nothing can set it',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/needs_review/);
  assert.match(checks,/the review flag cannot be set by the client/);
  assert.match(checks,/a plan with no written basis stays in review/);
  assert.match(checks,/a written basis clears the review flag/);
});

test('publishing is the only write, so no version is ever edited',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  const actions=[...allow.matchAll(/WHEN '([a-z_]+)' THEN/g)].map(m=>m[1]);
  assert.deepEqual(actions,['publish_plan']);
  assert.doesNotMatch(code(slice),/UPDATE private_isg\.emergency_plan_versions/);
  assert.match(checks,/renewing rewrites nothing in the version before it/);
  assert.match(checks,/only one version is active at a time/);
});

test('the board holds one row per plan, not one per version',()=>{
  assert.match(code(slice),/WHERE v\.owner_id=actor AND v\.state='active' AND NOT w\.is_archived/);
  assert.match(checks,/one row per plan, never one per version/);
});

test('the state is computed at read and says so',()=>{
  assert.match(code(slice),/'state_authority','computed_at_read'/);
  assert.doesNotMatch(code(slice),/ADD COLUMN[\s\S]{0,80}state/);
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
  assert.match(checks,/ALL EMERGENCY PLAN CHECKS PASSED/);
});
