import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginNotificationCoreProbe,notificationCoreFiles} from './notification_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,notificationCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginNotificationCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNotificationCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the backbone ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('notifications'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,6);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('four purposes stay separate and their caps are unapproved',()=>{
  assert.match(migration,/CHECK\(purpose IN \('obligation','personal_reminder','operational','marketing'\)\)/);
  assert.match(migration,/caps_approved boolean NOT NULL DEFAULT false/);
  assert.doesNotMatch(migration,/caps_approved\) VALUES[\s\S]*true/);
});

test('an OS prompt is never a marketing consent and an opt-out survives',()=>{
  assert.match(migration,/CHECK\(source<>'os_permission' OR purpose<>'marketing'\)/);
  assert.match(migration,/MESSAGE='OS_PERMISSION_IS_NOT_CONSENT'/);
  assert.match(migration,/MESSAGE='LEGACY_OPT_OUT_PRESERVED'/);
  assert.match(migration,/channel text NOT NULL CHECK\(channel IN \('push','email'\)\)/);
});

test('one owner per episode kind, shadow never sends, handover cancels pending',()=>{
  assert.match(migration,/MESSAGE='PRODUCER_NOT_OWNER'/);
  assert.match(migration,/code:='SHADOW_MODE_NO_SEND'/);
  assert.match(migration,/suppression_code='PRODUCER_HANDOVER'/);
});

test('everything is re-checked at send time and delivery is never claimed',()=>{
  assert.match(migration,/MESSAGE='SEND_TIME_CHECK_REQUIRED'/);
  assert.match(migration,/code:='CONSENT_REVOKED'/);
  assert.match(migration,/code:='QUIET_HOURS'/);
  assert.match(migration,/code:='FREQUENCY_CAP'/);
  assert.match(migration,/delivery_confirmed boolean NOT NULL DEFAULT false CHECK\(NOT delivery_confirmed\)/);
  assert.match(migration,/read_confirmed boolean NOT NULL DEFAULT false CHECK\(NOT read_confirmed\)/);
});

test('an explicit personal alarm is not silenced and an old build is downgraded',()=>{
  assert.match(migration,/NOT episode\.explicit_alarm AND\n\s*\(local_time>=policy\.quiet_start/);
  assert.match(migration,/CHECK\(NOT explicit_alarm OR purpose='personal_reminder'\)/);
  assert.match(migration,/resolved:=CASE WHEN device_build<job\.minimum_build THEN job\.fallback_route ELSE job\.route END/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginNotificationCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? notificationCoreFiles : \[\]\)/);
  assert.match(runner,/notificationProbe\.afterLogout\(\)/);
});
