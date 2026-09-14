import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915150000_isg_drills.sql');
const core=read('supabase/migrations/20260913230000_isg_module_core.sql');
const checks=read('scripts/isg/drills_check.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.match(code(slice),/PERFORM private_isg\.module_gate\('drill',p_write\);/);
  assert.match(checks,/a closed module refuses even while another is open/);
});

test('the only new table is private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['drill_receipts']);
  assert.match(slice,/ALTER TABLE private_isg\.drill_receipts ENABLE ROW LEVEL SECURITY/);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and both are invoker',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_drills_read_v1','isg_drills_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,260}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('the boundary checks ownership the core functions never did',()=>{
  // record_drill_result took a drill id and trusted it.
  const record=code(core).match(/CREATE FUNCTION private_isg\.record_drill_result[\s\S]*?END \$\$;/)[0];
  assert.doesNotMatch(record,/active_actor|owner_id=/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_drill_company/);
  assert.match(code(slice),/WHERE drill_id=drill AND company_id=p_company FOR UPDATE;/);
  // The plan behind the drill must be the caller's too.
  assert.match(code(slice),/WHERE plan_id=entry\.plan_id AND version=entry\.plan_version AND owner_id=actor;/);
  assert.match(checks,/a plan this company does not hold is refused/);
});

test('the client cannot name a plan version',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/plan_version/);
  // The boundary resolves the version in force and hands it to the core.
  assert.match(code(slice),/AND owner_id=actor AND state='active' FOR SHARE;/);
  assert.match(code(slice),/private_isg\.plan_drill\(p_company,plan\.workplace_id,plan\.plan_id,plan\.version,/);
  assert.match(checks,/a named plan version is refused/);
  assert.match(checks,/publishing a newer plan does not re-point the drill/);
});

test('a drill rehearses its own workplace, never another',()=>{
  // The workplace comes from the plan, not from the payload.
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  const planning=allow.match(/WHEN 'plan_drill' THEN ARRAY\[([^\]]*)\]/)[1];
  assert.doesNotMatch(planning,/workplace_id/);
});

test('planning is not performing',()=>{
  const status=code(slice).match(/CREATE FUNCTION private_isg\.drill_status[\s\S]*?END \$\$;/)[0];
  // The record decides performed; only the remaining states look at a date.
  assert.match(status,/IF p_state='performed' THEN RETURN 'performed'/);
  assert.match(status,/IF p_planned_on<p_today THEN RETURN 'overdue'/);
  assert.match(code(slice),/'performed',entry\.state='performed'/);
  assert.match(checks,/a planned date that passed is overdue/);
  assert.match(checks,/and still not performed/);
});

test('a performed drill is closed',()=>{
  const cancel=code(slice).match(/CREATE FUNCTION private_isg\.cancel_drill[\s\S]*?END \$\$;/)[0];
  assert.match(cancel,/IF entry\.state<>'planned' THEN RAISE EXCEPTION[\s\S]{0,80}DRILL_PERFORMED/);
  assert.match(checks,/a second result is a replay, not a rewrite/);
  assert.match(checks,/a drill that was held is not withdrawn/);
});

test('who was there is frozen, not linked',()=>{
  assert.match(slice,/ADD COLUMN participant_snapshot jsonb/);
  // The boundary writes the snapshot only for a real save, never on a replay.
  assert.match(code(slice),/IF NOT coalesce\(\(answer->>'replayed'\)::boolean,false\) THEN/);
  assert.match(code(slice),/UPDATE private_isg\.drill_records SET participant_snapshot=snapshot WHERE drill_id=drill;/);
  assert.match(code(slice),/'participants_snapshotted',entry\.participant_snapshot IS NOT NULL/);
  assert.match(checks,/renaming a person later does not edit a performed drill/);
  assert.match(checks,/the read still shows the name of the day/);
});

test('a drill held tomorrow is refused',()=>{
  assert.match(code(slice),/PERFORMED_IN_THE_FUTURE/);
  assert.match(checks,/a drill held tomorrow is refused/);
  assert.match(checks,/a participant from another company is refused/);
});

test('cancelling demands a reason',()=>{
  const cancel=code(slice).match(/CREATE FUNCTION private_isg\.cancel_drill[\s\S]*?END \$\$;/)[0];
  assert.match(cancel,/p_reason IS NULL OR btrim\(p_reason\)=''/);
  assert.match(checks,/cancelling with no reason is refused/);
});

test('the state is computed at read and no read claims compliance',()=>{
  assert.match(code(slice),/'state_authority','computed_at_read'/);
  assert.match(code(slice),/'compliance_verdict',NULL/);
  assert.match(code(slice),/'health_records_tracked',false/);
});

test('every mutation is receipted and the same id cannot mean two things',()=>{
  assert.match(code(slice),/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(code(slice),/request_hash IS DISTINCT FROM fingerprint THEN[\s\S]{0,120}IDEMPOTENCY_CONFLICT/);
  assert.match(checks,/the same id with a different body is refused/);
});

test('the checks are written for a disposable database only',()=>{
  assert.doesNotMatch(checks,/DROP SCHEMA|DROP DATABASE/);
  assert.match(checks,/ALL DRILL CHECKS PASSED/);
});
