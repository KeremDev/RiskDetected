import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {OSGB_CANDIDATE_MIGRATIONS} from './osgb_candidate_manifest.mjs';

const runner=readFileSync(new URL('./run_osgb_integrated_rehearsal.mjs',import.meta.url),'utf8');
const check=readFileSync(new URL('./osgb_integrated_rehearsal_check.sql',import.meta.url),'utf8');
const manifest=readFileSync(new URL('./osgb_candidate_manifest.mjs',import.meta.url),'utf8');

test('integrated rehearsal is disposable and cannot target a live database',()=>{
  assert.match(runner,/--network','none/);
  assert.doesNotMatch(runner,/DATABASE_URL|SUPABASE|db push|psql.*-h/);
  assert.match(runner,/finally\{\s*if\(created\)docker\(\['rm','-f',container\]\)/s);
});

test('all OSGB candidates are applied once in timestamp order',()=>{
  assert.match(runner,/OSGB_CANDIDATE_MIGRATIONS/);
  const candidateArray=manifest.slice(manifest.indexOf('Object.freeze(['),manifest.indexOf(']);'));
  const names=[...candidateArray.matchAll(/'([0-9]{14}_osgb_[^']+\.sql)'/g)].map(match=>match[1]);
  assert.equal(names.length,OSGB_CANDIDATE_MIGRATIONS.length);
  assert.ok(names.length>0);
  assert.deepEqual(names,[...names].sort());
  assert.equal(new Set(names).size,names.length);
});

test('cross-component acceptance covers revocation and financial invariants',()=>{
  for(const marker of ['workspace_provider_event_process','workspace_invite_v1','workspace_company_create_v1',
    'workspace_purchase_open_v1','workspace_purchase_record_verified','workspace_purchase_reconcile',
    'workspace_upload_open_v1','workspace_ai_submit_v1','workspace_handover_execute_v1',
    'EXPECTED_STALE_DOWNLOAD_DENIAL','EXPECTED_APPOINTMENT_OVERLAP',
    'EXPECTED_UNASSIGNED_SAFETY_DENIAL','EXPECTED_TRANSFERRED_SAFETY_DENIAL',
    'EXPECTED_UNASSIGNED_EQUIPMENT_DENIAL','EXPECTED_TRANSFERRED_EQUIPMENT_DENIAL',
    'EXPECTED_UNASSIGNED_OPERATIONS_DENIAL','EXPECTED_TRANSFERRED_OPERATIONS_DENIAL',
    'isg_workspace_file_mutate_v1','EXPECTED_UNASSIGNED_FILE_DENIAL',
    'isg_workspace_analysis_list_v1','isg_workspace_analysis_read_v1','isg_workspace_analysis_file_v1',
    'isg_workspace_export_create_v1','committed_and_visible',
    'EXPECTED_TRANSFERRED_ANALYSIS_DENIAL','EXPECTED_TRANSFERRED_EXPORT_DENIAL',
    'isg_workspace_dashboard_v1','isg_workspace_search_v1','isg_workspace_change_read_v1',
    'isg_workspace_ppe_signed_handover_v1','EXPECTED_TRANSFERRED_SEARCH_DENIAL',
    'isg_workspace_safety_metrics_v1','isg_workspace_equipment_metrics_v1',
    'isg_workspace_operations_metrics_v1','official_integration','authorises_work',
    'ai_text_is_official_record','posted_units','workspace_admin_overview']){
    assert.ok(check.includes(marker),marker);
  }
});
