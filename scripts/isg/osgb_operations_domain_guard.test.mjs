import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917160000_osgb_operations_domain.sql',import.meta.url),'utf8');

test('all operational roots and children carry workspace and company scope',()=>{
  for(const table of ['katip_contracts','annual_work_plans','annual_work_plan_items','board_meetings',
    'board_decisions','work_permit_forms','site_visits','site_visit_observations','notebook_archive_entries']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`),table);
  }
  for(const token of ['annual_items_workspace_parent_fk','board_decisions_workspace_parent_fk',
    'observations_workspace_parent_fk','workspace_operation_root_invariant','workspace_operation_child_invariant']){
    assert.ok(sql.includes(token),token);
  }
  assert.match(sql,/LEGACY_OWNER_FORBIDDEN/);
  assert.match(sql,/IMMUTABLE_SCOPE/);
});

test('official-system and legal-authority claims remain structurally false',()=>{
  assert.match(sql,/'official_integration',false/);
  assert.match(sql,/'authorises_work',false/);
  assert.match(sql,/'ai_text_is_official_record',false/);
  assert.doesNotMatch(sql,/official_integration\s*=\s*true|authorises_work\s*=\s*true|ai_text_is_official_record\s*=\s*true/);
  assert.doesNotMatch(sql,/https?:|e-devlet|isgkatip/i);
});

test('assets, board attendance and linked observations are tenant verified',()=>{
  assert.match(sql,/workspace_operation_asset/);
  assert.match(sql,/workspace_id=p_workspace AND company_id=p_company AND lifecycle='active'/);
  assert.match(sql,/MESSAGE='PARTICIPANT_INVALID'/);
  assert.match(sql,/FROM private_isg\.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company/);
  assert.match(sql,/ASSET_REQUIRED/);
});

test('planning and realisation remain separate and carry-over is explicit',()=>{
  assert.match(sql,/PLAN_YEAR_MISMATCH/);
  assert.match(sql,/OPEN_PLAN_ITEMS/);
  assert.match(sql,/CARRY_OVER_INVALID/);
  assert.match(sql,/state='closed',closed_on=/);
  assert.match(sql,/state='held',held_on=/);
});

test('operations APIs are assignment gated, idempotent and measured without table grants',()=>{
  for(const token of ['workspace_domain_gate','workspace_require_company','workspace_receipt_replay',
    'workspace_record_effect','VERSION_CONFLICT','isg_workspace_operations_read_v1',
    'isg_workspace_operations_mutate_v1','isg_workspace_operations_metrics_v1',"'measured',true"]){
    assert.ok(sql.includes(token),token);
  }
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});
