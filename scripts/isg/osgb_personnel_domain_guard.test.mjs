import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917144500_osgb_personnel_domain.sql',import.meta.url),'utf8');

test('every operational domain starts disabled behind an independent gate',()=>{
  assert.match(sql,/workspace_domain_rollout/);
  assert.match(sql,/read_enabled boolean NOT NULL DEFAULT false/);
  assert.match(sql,/write_enabled boolean NOT NULL DEFAULT false/);
  for(const domain of ['personnel','training','risk_nonconformity','emergency_ppe','equipment',
    'operations','files','analysis_exports','tracking_notifications']) assert.ok(sql.includes(`'${domain}'`),domain);
});

test('personnel children carry workspace-company composite scope',()=>{
  for(const table of ['workplaces','departments','employees']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`));
    assert.match(sql,new RegExp(`${table}_workspace_company_fk`));
  }
  assert.match(sql,/departments_workspace_workplace_fk/);
  assert.match(sql,/employees_workspace_department_fk/);
  assert.match(sql,/IMMUTABLE_SCOPE/);
});

test('workspace personnel RPCs authorize on server and never grant tables',()=>{
  for(const token of ['workspace_require_company','workspace_personnel_initialize','workspace_personnel_read',
    'workspace_directory_mutate','workspace_employee_mutate','workspace_personnel_metrics','workspace_record_effect']) assert.ok(sql.includes(token),token);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
  assert.match(sql,/member\.role='expert'/);
});

test('OSGB rows preserve actual author and carry no fake legacy owner',()=>{
  assert.match(sql,/VALUES\(p_workspace,p_company,NULL,clean_code,clean_name/);
  assert.match(sql,/created_by_user_id,updated_by_user_id/);
  assert.match(sql,/LEGACY_OWNER_FORBIDDEN/);
});
