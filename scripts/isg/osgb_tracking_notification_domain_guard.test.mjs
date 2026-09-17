import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917164500_osgb_tracking_notification_domain.sql',import.meta.url),'utf8');

test('dashboard, search and change feed are server scoped and omit personal notes',()=>{
  for(const token of ['workspace_dashboard','workspace_search','workspace_change_feed','workspace_change_read',
    'workspace_require_company','COMPANY_REQUIRED']) assert.ok(sql.includes(token),token);
  assert.doesNotMatch(sql,/FROM (private_isg\.)?(personal_notes|note_items|personal_reminders)/);
  assert.match(sql,/p_company IS NULL OR company_id=p_company/);
});

test('notification lease rechecks recipient revision and company assignment',()=>{
  for(const token of ['recipient_membership_id','permission_revision','AUTHORITY_REVOKED',
    'FOR UPDATE SKIP LOCKED','lease_token','lease_until','company_assignments']) assert.ok(sql.includes(token),token);
  assert.match(sql,/workspace_notification_claim[\s\S]+TO service_role/);
  assert.doesNotMatch(sql,/title text NOT NULL|body text NOT NULL/);
});

test('signed PPE uses an immutable company file reference and cleanup excludes uploads',()=>{
  assert.match(sql,/ppe_signed_evidence_shape/);
  assert.match(sql,/workspace_file_references/);
  assert.match(sql,/'signed_copy'/);
  assert.match(sql,/source_kind IN \('generated','derivative'\)/);
  assert.match(sql,/source_uploads_excluded/);
  assert.doesNotMatch(sql,/source_kind IN \('upload'/);
});
