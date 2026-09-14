import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915190000_isg_appointments.sql');
const core=read('supabase/migrations/20260913230000_isg_module_core.sql');
const checks=read('scripts/isg/appointments_check.sql');
const fixture=read('scripts/isg/module_slice_fixture.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.match(code(slice),/PERFORM private_isg\.module_gate\('appointment',p_write\);/);
  assert.match(checks,/a closed feature refuses ahead of the module/);
  assert.match(checks,/a closed module refuses on its own/);
});

test('the slice redefines nothing the core already ships',()=>{
  // end_appointment is the core's; this slice only reaches it.
  assert.match(code(core),/CREATE FUNCTION private_isg\.end_appointment/);
  assert.doesNotMatch(code(slice),/CREATE FUNCTION private_isg\.end_appointment/);
  assert.match(code(slice),/private_isg\.end_appointment\(appointment,/);
});

test('the new tables are private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['appointment_receipts','appointment_kinds']);
  const secured=new Set([...slice.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  for(const table of created) assert.ok(secured.has(table),table);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and both are invoker',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_appointments_read_v1','isg_appointments_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,300}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('the boundary checks ownership the core function never did',()=>{
  const scope=code(core).match(/CREATE FUNCTION private_isg\.module_scope[\s\S]*?END \$\$;/)[0];
  assert.doesNotMatch(scope,/active_actor/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_appointment_company/);
  assert.match(code(slice),/AND id=\(p_payload->>'workplace_id'\)::uuid AND owner_id=actor AND NOT is_archived;/);
  assert.match(code(slice),/WHERE appointment_id=appointment AND company_id=p_company FOR UPDATE;/);
  assert.match(checks,/an appointment outside the company is refused/);
});

test('nobody is ever labelled qualified',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/qualif/i);
  assert.match(code(slice),/'qualification_verified',false/);
  assert.match(code(slice),/'qualification_check_available',false/);
  // And the schema has nowhere to put one.
  assert.doesNotMatch(slice,/ADD COLUMN[\s\S]{0,60}qualif/i);
  assert.match(checks,/a qualification claim is refused/);
  assert.match(checks,/the schema has nowhere to put a qualification/);
});

test('the product never says how many are required',()=>{
  assert.match(code(slice),/'required_count_known',false/);
  assert.doesNotMatch(slice,/required_count integer|minimum_count/);
  assert.match(checks,/that the required number is unknown/);
  assert.match(checks,/never says how many are needed/);
});

test('saying why the person holds the role is required',()=>{
  assert.match(slice,/ADD COLUMN basis text CHECK\(basis IS NULL OR basis IN \('elected','appointed'\)\)/);
  assert.match(code(slice),/IF p_payload->>'basis' IS NULL OR p_payload->>'basis' NOT IN \('elected','appointed'\) THEN[\s\S]{0,90}BASIS_REQUIRED/);
  assert.match(checks,/an appointment with no stated basis is refused/);
  assert.match(checks,/a basis the schema does not know is refused/);
});

test('the overlap rule belongs to the constraint, not to a check beside it',()=>{
  // The core raises the named error from the constraint violation itself.
  const record=code(core).match(/CREATE FUNCTION private_isg\.record_appointment[\s\S]*?END \$\$;/)[0];
  assert.match(record,/EXCEPTION WHEN exclusion_violation THEN[\s\S]{0,90}APPOINTMENT_OVERLAP/);
  // The slice adds no overlap check of its own.
  assert.doesNotMatch(code(slice),/APPOINTMENT_OVERLAP/);
  assert.match(checks,/an overlapping appointment in the same role and scope is refused/);
  assert.match(checks,/the same person in another role is allowed/);
  assert.match(checks,/stretching an end date over the next appointment is refused/);
});

test('the letter itself is never stored, only where it is',()=>{
  assert.match(slice,/ADD COLUMN letter_location text/);
  assert.match(code(slice),/'letter_stored',false/);
  assert.match(code(slice),/'letter_storage_available',false/);
  assert.match(checks,/the letter itself is not held here/);
});

test('the state is computed at read and no read claims compliance',()=>{
  assert.match(code(slice),/'state_authority','computed_at_read'/);
  assert.match(code(slice),/'compliance_verdict',NULL/);
  assert.match(code(slice),/'health_records_tracked',false/);
});

test('a role filter the schema does not know is refused',()=>{
  assert.match(code(slice),/IF p_role IS NOT NULL AND NOT EXISTS\(SELECT 1 FROM private_isg\.appointment_kinds WHERE kind=p_role\)/);
  assert.match(checks,/a role the schema does not know is refused as a filter/);
});

test('every mutation is receipted and the same id cannot mean two things',()=>{
  assert.match(code(slice),/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(code(slice),/request_hash IS DISTINCT FROM fingerprint THEN[\s\S]{0,120}IDEMPOTENCY_CONFLICT/);
  assert.match(checks,/the same id with a different body is refused/);
});

test('the shared fixture is for a disposable database only',()=>{
  assert.match(fixture,/Run only in a fresh, disposable local database, never on a project database\./);
  assert.doesNotMatch(checks,/DROP SCHEMA|DROP DATABASE/);
  assert.match(checks,/ALL APPOINTMENT CHECKS PASSED/);
});
