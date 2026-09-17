import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const migration=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917110000_osgb_handover_memory.sql',import.meta.url),'utf8');
test('handover candidate is default-off and keeps storage private',()=>{
  assert.match(migration,/INSERT INTO private_isg\.workspace_rollout\(feature\) VALUES\('workspace_handover'\)/);
  assert.match(migration,/ENABLE ROW LEVEL SECURITY/g);
  assert.match(migration,/REVOKE ALL ON private_isg\.workspace_handovers/);
  assert.doesNotMatch(migration,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
});
test('handover snapshots and rechecks mutable authority',()=>{
  for(const token of ['source_membership_version','target_membership_version','source_assignment_version','company_version','preview_hash','VERSION_CONFLICT']) assert.ok(migration.includes(token),token);
  assert.match(migration,/FOR UPDATE/);
  assert.match(migration,/PRACTICING_MEMBERSHIP_REQUIRED/);
});
test('company execution is idempotent and writes deterministic redacted memory',()=>{
  assert.match(migration,/UNIQUE\(handover_id,company_id\)/);
  assert.match(migration,/item\.status='completed'/);
  assert.match(migration,/generator text NOT NULL DEFAULT 'deterministic_v1'/);
  assert.match(migration,/private_note/);
  assert.match(migration,/workspace_record_effect/);
});
test('unexecuted plans can cancel and completed plans compensate through a linked reverse handover',()=>{
  assert.match(migration,/workspace_handover_cancel/);
  assert.match(migration,/status NOT IN \('draft','scheduled'\)/);
  assert.match(migration,/compensation_for_item_id/);
  assert.match(migration,/workspace_handover_compensation_preview/);
  assert.match(migration,/Ters devir:/);
});
