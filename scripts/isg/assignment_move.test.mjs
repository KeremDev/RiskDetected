import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
test('assignment corpus covers dates, scopes, ids, nullable previous and rejects unknown payload',()=>{
  const cases=JSON.parse(read('contracts/isg/v1/fixtures/assignment-move.json')).cases;
  assert.equal(cases.length,61);assert.equal(new Set(cases.map(c=>c.id)).size,61);
  for(const id of ['first-assignment','move-existing','max-version-overflow','missing-workplace','unknown-health','unknown-user_id','missing-previous_assignment_id','invalid-date-1900-02-29'])assert.ok(cases.some(c=>c.id===id));
});
test('native and backend parsers stay side-effect-free and CI executes the shared fixtures',()=>{
  for(const path of ['App/Services/Company/IsgAssignmentMove.swift','android/core/data/src/main/kotlin/com/riskdetectedan/core/data/company/IsgAssignmentMove.kt','supabase/functions/_shared/personnel/assignment-move.ts']) {
    const text=read(path);assert.doesNotMatch(text,/https?:\/\/|service_role|user_metadata|fetch\(|\.rpc\(/);assert.match(text,/9007199254740991/);
  }
  const ci=read('.github/workflows/isg-foundation.yml');assert.match(ci,/AssignmentMoveCheck.swift/);assert.match(ci,/personnel\/assignment-move_test.ts/);
  assert.match(read('android/core/data/build.gradle.kts'),/isgSharedFixtureCorpus/);
});
test('personnel transaction stays private and checks access before receipt replay',()=>{
  const sql=read('scripts/isg/sql/personnel_mutation_fixture.sql');
  assert.doesNotMatch(sql,/SECURITY DEFINER|GRANT .* TO (authenticated|anon|PUBLIC)/i);
  assert.ok(sql.indexOf('personnel_write_access WHERE')<sql.indexOf('SELECT * INTO receipt'));
  assert.ok(sql.indexOf('AND NOT is_archived FOR UPDATE')<sql.indexOf('SELECT * INTO receipt'));
  assert.match(sql,/pg_advisory_xact_lock/);assert.match(sql,/VERSION_CONFLICT/);assert.match(sql,/IDEMPOTENCY_CONFLICT/);
  for(const table of ['personnel_write_access','personnel_receipts','personnel_audit','personnel_outbox'])assert.ok(sql.includes(`ALTER TABLE isg_workplace_fixture.${table} ENABLE ROW LEVEL SECURITY`));
  const runner=read('scripts/isg/run_database_contract.mjs');assert.match(runner,/runPersonnelMutationProbe/);assert.match(runner,/\.slice\(0,8\)/);
});
