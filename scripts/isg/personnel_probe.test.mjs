import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
const read = p => readFileSync(resolve(ROOT, p),'utf8');
test('personnel candidate is private, owner-scoped and read-only for clients', () => {
  const sql=read('scripts/isg/sql/personnel_fixture.sql');
  assert.doesNotMatch(sql,/SECURITY DEFINER|user_metadata|service_role|https?:\/\//i);
  assert.doesNotMatch(sql,/(CREATE|ALTER|DROP)\s+(TABLE|FUNCTION)\s+(public|auth|storage)\./i);
  for(const table of ['departments','job_roles','employees','employee_assignments']) {
    assert.ok(sql.includes(`ALTER TABLE isg_workplace_fixture.${table} ENABLE ROW LEVEL SECURITY`));
    assert.ok(sql.includes(`CREATE POLICY owned_read ON isg_workplace_fixture.${table} FOR SELECT TO isg_workplace_reader`));
  }
  assert.doesNotMatch(sql,/GRANT\s+(INSERT|UPDATE|DELETE|ALL)/i);
});
test('temporal constraints and composite keys remain database-enforced', () => {
  const sql=read('scripts/isg/sql/personnel_fixture.sql');
  assert.match(sql,/EXCLUDE USING gist \(company_id WITH =, employee_id WITH =, effective_dates WITH &&\)/);
  assert.match(sql,/daterange\(starts_on, ends_before, '\[\)'\)/);
  assert.match(sql,/FOREIGN KEY\(company_id, workplace_id, department_id\)/);
  assert.match(sql,/FOREIGN KEY\(company_id, employee_id\)/);
  assert.match(sql,/FOREIGN KEY\(company_id, job_role_id\)/);
  assert.match(sql,/CHECK \(kind = 'primary'\)/);
  assert.match(sql,/EMPLOYMENT_INTERVAL_INVALID/);
  assert.match(sql,/ASSIGNMENT_IMMUTABLE/);
});
test('personnel runtime probe is executed and fingerprinted by isolated CI runner', () => {
  const runner=read('scripts/isg/run_database_contract.mjs');
  for(const path of ['scripts/isg/sql/personnel_fixture.sql','scripts/isg/personnel_probe.mjs']) assert.ok(runner.includes(`'${path}'`));
  assert.match(runner,/await runPersonnelProbe\(\{ query, concurrent, check, killSleepingTransaction \}\)/);
  assert.match(runner,/personnel_btree_gist_version/);
  const probe=read('scripts/isg/personnel_probe.mjs');
  assert.doesNotMatch(probe,/fetch\(|spawn|process\.env|supabase\.co/);
  for(const id of ['PER-05_','PER-08_','PER-14_','PER-15_','PER-16_','PER-20_','PER-23_','PER-24_','PER-26_']) assert.ok(probe.includes(id));
});
