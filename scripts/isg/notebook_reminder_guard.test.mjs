import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { p05UpgradeFiles } from './p05_upgrade_probe.mjs';

const migration='supabase/migrations/20260914070005_isg_notebook_reminder_api.sql';
const read=path=>readFileSync(path,'utf8');

test('reminder API is owner-only, idempotent and server-push bound',()=>{
  const sql=read(migration);
  for(const value of ['active_actor()','notes_gate(true)','notification_gate(false)','IDEMPOTENCY_CONFLICT',
    "'server_push'",'DEVICE_UNAVAILABLE','LIMIT 21','dispatch_bound_notification','REMINDER_TIME_STALE',
    'notification_job_snapshot','provider_called\',false','p.enabled AND p.app_reminders',
    '(p_starts_on+p_local_time) AT TIME ZONE p_timezone<=stamp']) assert.ok(sql.includes(value),value);
  assert.doesNotMatch(sql,/user_plan_tier|user_subscriptions|company_id/);
  assert.match(sql,/REVOKE ALL ON FUNCTION[\s\S]+FROM PUBLIC,anon,authenticated,service_role/);
  assert.ok(p05UpgradeFiles.includes(migration));
});

test('notification repository claims through the reminder-aware database gate',()=>{
  const source=read('supabase/functions/_shared/isg/notification-repository.ts');
  assert.match(source,/dispatch_bound_notification\(\$1::uuid,\$2::jsonb,\$3::timestamptz\)/);
  assert.match(source,/installation_id/);
});

test('native reminder entry stays behind the notebook release gate',()=>{
  const swift=read('App/Views/Components/NotebookDestination.swift');
  const kotlin=read('android/feature/profile/src/main/kotlin/com/riskdetectedan/feature/profile/NotebookScreen.kt');
  for(const source of [swift,kotlin]) {
    assert.match(source,/enabled = false/);
    assert.match(source,/Hatırlatıcı/);
    assert.match(source,/server.push|server_push|Sunucu bildirimi/i);
    assert.doesNotMatch(source,/Analytics|Logger|println\(/);
  }
  const iosToken=read('App/Services/NotificationService.swift');
  const androidToken=read('android/core/data/src/main/kotlin/com/riskdetectedan/core/data/notifications/DeviceTokenRepository.kt');
  for(const source of [iosToken,androidToken]) {
    assert.match(source,/installation[_I]?[dD]|installationID/);
    assert.match(source,/serverPush|ServerPush/);
  }
});
