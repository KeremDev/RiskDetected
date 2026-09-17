import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917154500_osgb_equipment_domain.sql',import.meta.url),'utf8');

test('inventory, rules and inspection history are workspace scoped with composite parents',()=>{
  for(const table of ['equipment_items','equipment_inspection_rules','equipment_inspections']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`),table);
  }
  for(const token of ['equipment_items_workspace_company_fk','equipment_items_workspace_workplace_fk',
    'equipment_rules_workspace_company_fk','equipment_inspections_workspace_parent_fk']) assert.ok(sql.includes(token),token);
  assert.match(sql,/IMMUTABLE_REPORT_FACT/);
  assert.match(sql,/LEGACY_OWNER_FORBIDDEN/);
});

test('predefined defaults stay reviewable and custom equipment labels are supported',()=>{
  assert.match(sql,/equipment_type_label/);
  assert.match(sql,/equipment_default_periods/);
  assert.match(sql,/'regulation_default',d\.basis_note,true/);
  assert.match(sql,/source='unapproved_fixture'/);
  assert.match(sql,/source NOT IN \('manufacturer','rule_version','unapproved_fixture'\)/);
});

test('periodic checks preserve report facts and classify due dates on the server',()=>{
  for(const state of ['never_inspected','period_unknown','failed','overdue','due_soon','valid']){
    assert.ok(sql.includes(`'${state}'`),state);
  }
  assert.match(sql,/workspace_equipment_state/);
  assert.match(sql,/WHEN chosen=derived THEN 'period' ELSE 'expert'/);
  assert.match(sql,/DUE_DATE_CONFLICT/);
  assert.match(sql,/katip_official_verification',false/);
  assert.match(sql,/IMMUTABLE_REPORT_FACT/);
});

test('workspace assets must be active and match the same workspace and company',()=>{
  assert.match(sql,/workspace_asset_id uuid/);
  assert.match(sql,/asset\.workspace_id IS DISTINCT FROM NEW\.workspace_id/);
  assert.match(sql,/asset\.company_id IS DISTINCT FROM NEW\.company_id/);
  assert.match(sql,/asset\.lifecycle<>'active'/);
});

test('equipment APIs are assignment gated, idempotent and expose measured statistics without table grants',()=>{
  for(const token of ['workspace_domain_gate','workspace_require_company','workspace_receipt_replay',
    'workspace_record_effect','VERSION_CONFLICT','isg_workspace_equipment_read_v1',
    'isg_workspace_equipment_mutate_v1','isg_workspace_equipment_metrics_v1',"'measured',true"]){
    assert.ok(sql.includes(token),token);
  }
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});
