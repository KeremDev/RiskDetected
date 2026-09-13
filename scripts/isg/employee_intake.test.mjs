import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {prepareIsgEmployeeCreate} from '../../supabase/functions/_shared/personnel/employee-create.ts';
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
test('simple employee corpus allows name only and rejects legacy required form fields',()=>{
  const cases=JSON.parse(read('contracts/isg/v1/fixtures/employee-create.json')).cases;
  assert.equal(cases.length,61);assert.equal(new Set(cases.map(c=>c.id)).size,61);
  for(const c of cases)assert.equal(prepareIsgEmployeeCreate(c.input)!==null,c.valid,c.id);
  const args=prepareIsgEmployeeCreate(cases[0].input);assert.equal(args.p_department,null);assert.equal(args.p_department_name,null);
  for(const key of ['hired_on','employment_ends_before','job_role_id','employee_code'])assert.ok(cases.some(c=>c.id===`forbidden-${key}`));
});
test('simple employee transaction remains private with company scoped department creation',()=>{
  const sql=read('scripts/isg/sql/employee_intake_fixture.sql');
  assert.match(sql,/ALTER COLUMN hired_on DROP NOT NULL/);assert.match(sql,/FOREIGN KEY\(company_id,intake_department_id\)/);
  assert.doesNotMatch(sql,/SECURITY DEFINER|GRANT .* TO (authenticated|anon|PUBLIC)/i);
  assert.match(sql,/AND owner_id=actor AND NOT is_archived FOR UPDATE/);assert.match(sql,/DEPARTMENT_SELECTION_REQUIRED/);
  assert.match(sql,/employee_create_receipts ENABLE ROW LEVEL SECURITY/);
  assert.ok(sql.indexOf('personnel_write_access WHERE')<sql.indexOf('SELECT * INTO receipt'));
});
test('simple intake tests execute on native clients and isolated database in CI',()=>{
  const runner=read('scripts/isg/run_database_contract.mjs'),ci=read('.github/workflows/isg-foundation.yml');
  assert.match(runner,/await runEmployeeIntakeProbe/);assert.match(runner,/employee_intake_fixture.sql/);
  assert.match(ci,/EmployeeCreateCheck.swift/);assert.match(ci,/personnel\/employee-create_test.ts/);
  for(const path of ['App/Services/Company/IsgEmployeeCreate.swift','android/core/data/src/main/kotlin/com/riskdetectedan/core/data/company/IsgEmployeeCreate.kt'])assert.doesNotMatch(read(path),/https?:\/\/|service_role|\.rpc\(/);
});
