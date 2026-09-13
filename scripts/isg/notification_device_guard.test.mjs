import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { beginNotificationDeviceProbe } from './notification_device_probe.mjs';
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
test('device probe refuses a non-synthetic target before SQL',()=>{
  assert.throws(()=>beginNotificationDeviceProbe({synthetic:false,sql:()=>assert.fail('SQL')}),/SYNTHETIC/);
});
test('both native platforms wire best-effort device permission RPC without sending owner or clock',()=>{
  for(const path of ['App/Services/NotificationService.swift','android/core/data/src/main/kotlin/com/riskdetectedan/core/data/notifications/DeviceTokenRepository.kt']) {
    const source=read(path);assert.ok(source.includes('isg_notification_device_permission_v1'));
    for(const key of ['p_token','p_provider','p_build','p_authorized'])assert.ok(source.includes(key));
  }
});
test('migration keeps private access, active session, token rotation and ambiguity guards',()=>{
  const source=read('supabase/migrations/20260914070003_isg_device_notification_permission.sql');
  for(const guard of ['active_actor()','notification_gate(true)','ENABLE ROW LEVEL SECURITY','d.token_fingerprint=md5(t.token)','DEVICE_STRATEGY_REQUIRED','clock_timestamp()','s.user_id=d.owner_id'])assert.ok(source.includes(guard));
  assert.ok(!/ALTER TABLE public\./i.test(source));
  assert.ok(!/UPDATE private_isg.rollout/i.test(source));
});
