import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917163000_osgb_analysis_export_domain.sql',import.meta.url),'utf8');

test('analysis result preserves scored, scoreless expert and training projections',()=>{
  for(const token of ['workspace_analysis_findings','workspace_analysis_expert_items',
    'workspace_analysis_training_items','unscored_finding','expert_recommendation',
    "'risk_findings'","'expert_items'","'training_items'"]) assert.ok(sql.includes(token),token);
  assert.match(sql,/NOT f\.is_scored/);
  assert.match(sql,/workspace_analysis_list/);
  assert.match(sql,/isg_workspace_analysis_list_v1/);
  assert.match(sql,/finding_count/);
  assert.match(sql,/highest_band/);
});

test('finding filing trusts server sources and verifies committed list visibility',()=>{
  assert.match(sql,/FROM public\.findings f JOIN public\.analyses a/);
  assert.match(sql,/FROM private_isg\.workspace_analysis_findings/);
  assert.match(sql,/workspace_analysis_filed_sources/);
  assert.match(sql,/COMMIT_VISIBILITY_FAILED/);
  assert.match(sql,/committed_and_visible/);
  assert.match(sql,/analysis_finding_filed/);
  assert.doesNotMatch(sql,/p_title|p_description|p_recommended_action/);
});

test('export pins immutable source, actor permission and output asset scope',()=>{
  for(const token of ['source_snapshot','permission_revision','AUTHORITY_REVOKED','ASSIGNMENT_REVOKED',
    'SELECTION_SCOPE_CONFLICT','ASSET_SCOPE_CONFLICT']) assert.ok(sql.includes(token),token);
  assert.match(sql,/workspace_export_start[\s\S]+TO service_role/);
  assert.match(sql,/workspace_analysis_commit[\s\S]+TO service_role/);
  assert.doesNotMatch(sql,/GRANT (SELECT|INSERT|UPDATE|DELETE) ON/);
});
