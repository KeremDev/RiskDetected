import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917151500_osgb_risk_nonconformity_domain.sql',import.meta.url),'utf8');

test('risk, nonconformity and checklist roots and children carry composite workspace scope',()=>{
  for(const table of ['risk_assessments','risk_assessment_versions','risk_source_links','nonconformities',
    'nonconformity_transitions','nonconformity_actions','verification_records','checklist_runs','checklist_run_items']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`),table);
  }
  for(const token of ['risk_versions_workspace_parent_fk','risk_sources_workspace_version_fk',
    'nonconformity_transitions_workspace_parent_fk','nonconformity_actions_workspace_parent_fk',
    'verification_records_workspace_parent_fk','checklist_items_workspace_parent_fk']) assert.ok(sql.includes(token),token);
});

test('assurance roots preserve author and reject fake OSGB ownership or tenant mutation',()=>{
  assert.match(sql,/risk_assessments ALTER COLUMN owner_id DROP NOT NULL/);
  assert.match(sql,/nonconformities ALTER COLUMN owner_id DROP NOT NULL/);
  assert.match(sql,/checklist_runs ALTER COLUMN owner_id DROP NOT NULL/);
  assert.match(sql,/LEGACY_OWNER_FORBIDDEN/);
  assert.match(sql,/IMMUTABLE_SCOPE/);
  assert.match(sql,/created_by_user_id/);
});

test('workspace assurance APIs enforce assignment, version and idempotency without table grants',()=>{
  for(const token of ['workspace_require_company','workspace_receipt_replay','workspace_record_effect',
    'isg_workspace_risk_read_v1','isg_workspace_risk_mutate_v1',
    'isg_workspace_nonconformity_read_v1','isg_workspace_nonconformity_mutate_v1',
    'isg_workspace_checklist_read_v1','isg_workspace_checklist_mutate_v1',
    'isg_workspace_assurance_metrics_v1','VERSION_CONFLICT']) assert.ok(sql.includes(token),token);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});

test('unverified client finding ids cannot create an analysis-sourced nonconformity',()=>{
  assert.match(sql,/source_kind NOT IN \('manual','risk_version','checklist'\)/);
  assert.match(sql,/D8 verified bridge/);
  assert.doesNotMatch(sql,/source_kind NOT IN \([^)]*legacy_finding/);
});

test('checklist negatives link a tenant-scoped nonconformity and metrics are measured',()=>{
  assert.match(sql,/result_code='nonconform'/);
  assert.match(sql,/'checklist',run\.run_id::text/);
  for(const token of ["'measured',true","'risk'","'nonconformity'","'checklists'"]) assert.ok(sql.includes(token),token);
});
