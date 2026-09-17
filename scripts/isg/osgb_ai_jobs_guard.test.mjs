import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917123000_osgb_ai_jobs.sql',import.meta.url),'utf8');
test('AI jobs pin actor, membership revision, workspace, company, source and pricing',()=>{
  for(const token of ['actor_user_id','membership_id','permission_revision','workspace_id','company_id','source_reference','source_version','pricing_version']) assert.ok(sql.includes(token),token);
  assert.match(sql,/workspace_ai_pricing/);
});
test('AI worker rechecks authority before provider and settles the canonical wallet',()=>{
  assert.match(sql,/AUTHORITY_REVOKED/); assert.match(sql,/ASSIGNMENT_REVOKED/);
  assert.match(sql,/workspace_credit_release/); assert.match(sql,/workspace_credit_settle/);
  assert.match(sql,/SETTLEMENT_EXCEEDS_RESERVATION/);
});
test('worker mutations are service-only while scoped submit and get are authenticated',()=>{
  assert.match(sql,/workspace_ai_complete[\s\S]+TO service_role/);
  assert.match(sql,/public\.isg_workspace_ai_submit_v1[\s\S]+TO authenticated/);
  assert.doesNotMatch(sql,/GRANT (SELECT|INSERT|UPDATE|DELETE) ON/);
});
