import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';

const sql=readFileSync(`${ROOT}/supabase/pilot-release/candidates/20260917091500_osgb_personal_backfill.sql`,'utf8');
test('personal backfill is private, resumable and observation-only by default',()=>{
  assert.match(sql,/p_apply boolean DEFAULT false/);
  assert.match(sql,/workspace_backfill_checkpoints/);
  assert.match(sql,/source_fingerprint/);
  assert.match(sql,/ON CONFLICT DO NOTHING/);
  assert.match(sql,/ORDER BY p\.id LIMIT p_limit/);
  assert.match(sql,/REVOKE ALL ON FUNCTION private_isg\.workspace_backfill_personal_batch/);
  assert.doesNotMatch(sql,/GRANT EXECUTE/);
  assert.doesNotMatch(sql,/auth\.users/);
  assert.doesNotMatch(sql,/user_subscriptions|quota|balance|companies/);
});
