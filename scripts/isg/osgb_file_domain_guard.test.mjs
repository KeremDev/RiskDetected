import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917161500_osgb_file_domain.sql',import.meta.url),'utf8');

test('logical entries and revisions keep workspace, company and physical asset scope',()=>{
  for(const table of ['workspace_file_entries','workspace_file_versions','workspace_file_references'])
    assert.match(sql,new RegExp(`CREATE TABLE private_isg\\.${table}`));
  assert.match(sql,/FOREIGN KEY\(workspace_id,asset_id\)/);
  assert.match(sql,/workspace_file_asset\(p_workspace uuid,p_company uuid,p_asset uuid\)/);
  assert.match(sql,/company_id IS NULL OR company_id IS NOT DISTINCT FROM p_company/);
});

test('a blob id is insufficient without a validated parent filing',()=>{
  assert.match(sql,/workspace_file_parent_exists/);
  assert.match(sql,/PARENT_SCOPE_CONFLICT/);
  assert.match(sql,/workspace_file_references/);
  assert.match(sql,/parent_kind IN \('company','employee','training','risk_assessment'/);
});

test('private, management and company visibility stay distinct',()=>{
  assert.match(sql,/visibility IN \('company_team','workspace_management','member_private'\)/);
  assert.match(sql,/workspace_file_can_access/);
  assert.match(sql,/private_to_membership_id=p_member\.id/);
  assert.match(sql,/p_member\.role IN \('owner','admin'\)/);
  assert.match(sql,/company_assignments/);
});

test('legacy paths are disclosed only through a short lived server claim',()=>{
  assert.match(sql,/workspace_legacy_file_inventory/);
  assert.match(sql,/workspace_legacy_download_open/);
  assert.match(sql,/workspace_legacy_download_claim/);
  assert.match(sql,/token_hash bytea NOT NULL UNIQUE/);
  assert.match(sql,/TO service_role/);
});

test('asset deletion is blocked while references remain',()=>{
  assert.match(sql,/workspace_asset_reference_count/);
  assert.match(sql,/ASSET_IN_USE/);
  assert.match(sql,/CREATE OR REPLACE FUNCTION private_isg\.workspace_asset_delete_request/);
});

test('file APIs are gated, assignment checked and idempotent without table grants',()=>{
  assert.match(sql,/workspace_domain_gate\('files',false\)/);
  assert.match(sql,/workspace_domain_gate\('files',true\)/);
  assert.match(sql,/workspace_require_company/);
  assert.match(sql,/workspace_receipt_replay/);
  assert.match(sql,/workspace_record_effect/);
  assert.doesNotMatch(sql,/GRANT\s+(?:SELECT|INSERT|UPDATE|DELETE|ALL)\s+ON\s+(?:TABLE\s+)?private_isg\./i);
});
