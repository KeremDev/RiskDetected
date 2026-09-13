import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {beginNotificationRepositoryProbe,notificationRepositoryFiles} from './notification_repository_probe.mjs';
import {p05UpgradeFiles} from './p05_upgrade_probe.mjs';
test('repository SQL probe rejects unsafe mode and missing scope before SQL',async()=>{
  let touched=false;const sql=()=>{touched=true;};
  await assert.rejects(beginNotificationRepositoryProbe({synthetic:false,sql}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNotificationRepositoryProbe({synthetic:true,sql}),/SCOPE_REQUIRED/);assert.equal(touched,false);
});
test('provider wait is private, replay fenced and never shortens backoff',()=>{
  const m=readFileSync(notificationRepositoryFiles[0],'utf8');
  assert.doesNotMatch(m,/GRANT\s+|UPDATE private_isg\.rollout|SECURITY DEFINER/);
  assert.match(m,/SECURITY INVOKER SET search_path=''/);
  assert.match(m,/prior_wait IS DISTINCT FROM p_retry_after_seconds/);
  assert.match(m,/greatest\(next_attempt_at,p_now\+make_interval/);
  assert.ok(p05UpgradeFiles.indexOf(notificationRepositoryFiles[0]) > p05UpgradeFiles.indexOf('supabase/migrations/20260914070001_isg_notification_dispatch_safety.sql'));
});
