import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917134500_osgb_workspace_operations.sql',import.meta.url),'utf8');
test('management writes are versioned, idempotent and scoped',()=>{
  for(const token of ['workspace_settings_update','workspace_archive','workspace_invitation_resend',
    'workspace_company_update','workspace_company_archive','workspace_receipt_replay','VERSION_CONFLICT'])assert.ok(sql.includes(token),token);
  assert.match(sql,/workspace_require_member\(p_workspace,ARRAY\['owner','admin'\]/);
});
test('resend rotates a hash-only token and returns plaintext once',()=>{
  assert.match(sql,/token_hash=sha256\(convert_to\(token,'UTF8'\)\)/);
  assert.match(sql,/token_returned',false/);
  assert.match(sql,/invitation_token',token/);
});
test('archives retain data and close current assignments with history',()=>{
  assert.match(sql,/data_deleted',false/);
  assert.match(sql,/company_assignment_events/);
  assert.match(sql,/ended_assignments/);
  assert.doesNotMatch(sql,/DELETE FROM/);
});
test('lists are server paginated and private tables remain ungranted',()=>{
  assert.match(sql,/LIMIT p_limit\+1/g);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});
