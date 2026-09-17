import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917150000_osgb_training_domain.sql',import.meta.url),'utf8');

test('training session, record, participant and revision share workspace scope',()=>{
  for(const table of ['pilot_training_sessions','pilot_training_records','pilot_training_participants',
    'pilot_training_session_revisions']){
    assert.match(sql,new RegExp(`ALTER TABLE private_isg\\.${table} ADD COLUMN workspace_id uuid`));
  }
  assert.match(sql,/pilot_training_records_workspace_company_fk/);
  assert.match(sql,/pilot_training_records_workspace_session_fk/);
  assert.match(sql,/pilot_training_participants_workspace_employee_fk/);
  assert.match(sql,/PARTICIPANT_SCOPE_CONFLICT/);
  assert.match(sql,/IMMUTABLE_SCOPE/);
});

test('OSGB training uses real authors without opening legacy owner access',()=>{
  assert.match(sql,/pilot_training_sessions ALTER COLUMN owner_id DROP NOT NULL/);
  assert.match(sql,/pilot_training_records ALTER COLUMN owner_id DROP NOT NULL/);
  assert.match(sql,/VALUES\(p_workspace,NULL,clean_title,clean_trainer/);
  assert.match(sql,/created_by_user_id,updated_by_user_id/);
  assert.match(sql,/LEGACY_OWNER_FORBIDDEN/);
});

test('training endpoints are assignment scoped, idempotent and table-private',()=>{
  for(const token of ['workspace_domain_gate(\'training\'','workspace_require_company',
    'workspace_receipt_replay','workspace_record_effect','isg_workspace_training_read_v1',
    'isg_workspace_training_mutate_v1','isg_workspace_training_metrics_v1']) assert.ok(sql.includes(token),token);
  assert.doesNotMatch(sql,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON/i);
  assert.match(sql,/PARTICIPANT_UNAVAILABLE/);
  assert.match(sql,/TRAINING_NOT_ENDED/);
  assert.match(sql,/ATTENDANCE_REQUIRED/);
});

test('training metrics expose measured totals, people, minutes and missing coverage',()=>{
  for(const token of ['completed_minutes','trained_people','person_minutes','people_without_completed_training',
    "'measured',true"]) assert.ok(sql.includes(token),token);
});
