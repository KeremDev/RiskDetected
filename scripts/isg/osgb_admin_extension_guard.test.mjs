import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917120000_osgb_admin_extension.sql',import.meta.url),'utf8');
test('OSGB admin commands reuse existing session, scope, simulation and publish authority',()=>{
  for(const name of ['admin_authorize','simulate_admin_action','publish_admin_action','admin_actions','admin_scopes']) assert.ok(sql.includes(name),name);
  assert.doesNotMatch(sql,/CREATE TABLE private_isg\.admin_(sessions|scopes|actions)/);
});
test('admin commands are allowlisted and service-only',()=>{
  for(const command of ['osgb_trial_grant','osgb_credit_grant','osgb_member_suspend','osgb_reconcile_request']) assert.ok(sql.includes(command),command);
  assert.match(sql,/TO service_role/);
  assert.doesNotMatch(sql,/TO authenticated/);
});
test('admin economic effects preserve provenance and audit-first ordering',()=>{
  assert.match(sql,/ACTIVE_STORE_ENTITLEMENT/);
  assert.match(sql,/source_kind='admin_trial'/);
  assert.match(sql,/workspace_credit_grant/);
  assert.match(sql,/publish_result:=private_isg\.publish_admin_action[\s\S]+IF command\.command_kind/);
});
