import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917153000_osgb_emergency_ppe_domain.sql',import.meta.url),'utf8');

test('safety roots and children carry composite workspace scope',()=>{
  for(const table of ['emergency_plan_versions','drill_records','appointments','ppe_handovers']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`),table);
    assert.match(sql,new RegExp(`${table.replaceAll('_','.*')}[\\s\\S]{0,900}UNIQUE\\(workspace_id,company_id`),table);
  }
  for(const table of ['ppe_returns']) assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`));
  for(const token of ['emergency_plans_workspace_company_fk','drills_workspace_plan_fk',
    'appointments_workspace_employee_fk','ppe_handovers_workspace_employee_fk','ppe_returns_workspace_parent_fk']){
    assert.ok(sql.includes(token),token);
  }
});

test('emergency team and drill participants are verified employees and snapshotted server-side',()=>{
  for(const token of ['TEAM_MEMBER_INVALID','PARTICIPANT_INVALID',"'employee_id','role','contact'",
    "'employee_id',e.id,'full_name',e.full_name","'id',e.id,'full_name',e.full_name"]){
    assert.ok(sql.includes(token),token);
  }
  assert.match(sql,/e\.workspace_id=p_workspace AND e\.company_id=p_company/);
  assert.doesNotMatch(sql,/team_snapshot[^\n]*p_payload->'team'/);
});

test('appointments reject overlapping effective dates at the workspace boundary',()=>{
  assert.match(sql,/daterange\(a\.starts_on,a\.ends_before,'\[\)'\) &&/);
  assert.match(sql,/APPOINTMENT_OVERLAP/);
  assert.match(sql,/ends_before'\)::date<=appointment\.starts_on/);
});

test('signed PPE claims require the later workspace asset bridge',()=>{
  assert.match(sql,/SIGNED_EVIDENCE_REQUIRED/);
  assert.match(sql,/D7 will bind signed evidence to a workspace asset/);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});

test('safety APIs are assignment gated, versioned, idempotent and measured',()=>{
  for(const token of ['workspace_domain_gate','workspace_require_company','workspace_receipt_replay',
    'workspace_record_effect','VERSION_CONFLICT','isg_workspace_safety_read_v1',
    'isg_workspace_safety_mutate_v1','isg_workspace_safety_metrics_v1',"'measured',true"]){
    assert.ok(sql.includes(token),token);
  }
  assert.match(sql,/workspace_appointment_invariant/);
  assert.match(sql,/workspace_ppe_handover_invariant/);
  assert.doesNotMatch(sql,/workspace_employee_record_invariant/);
});
