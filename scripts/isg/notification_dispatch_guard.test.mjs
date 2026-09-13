import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginNotificationDispatchProbe,notificationDispatchFiles} from './notification_dispatch_probe.mjs';
import {p05UpgradeFiles} from './p05_upgrade_probe.mjs';
const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const migration=read(notificationDispatchFiles[0]);

test('dispatch safety probe refuses non-synthetic or incomplete scope before SQL',async()=>{
  let touched=false;
  const sql=()=>{touched=true;};
  await assert.rejects(beginNotificationDispatchProbe({synthetic:false,sql}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNotificationDispatchProbe({synthetic:true,sql}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});
test('dispatch migration never enables rollout, grants clients or mutates legacy rows',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout|caps_approved\s*=\s*true/i);
  assert.doesNotMatch(migration,/\bGRANT\s+(EXECUTE|SELECT|ALL)/i);
  assert.doesNotMatch(migration,/(?:UPDATE|INSERT INTO|DELETE FROM)\s+(?:public|private)\./i);
  assert.match(migration,/FROM PUBLIC,anon,authenticated,service_role/);
  assert.equal([...migration.matchAll(/CREATE (?:OR REPLACE )?FUNCTION/g)].length,[...migration.matchAll(/SECURITY INVOKER SET search_path=''/g)].length);
});
test('send authorization uses current time, reserves capacity and fences receipts',()=>{
  assert.match(migration,/item\.scheduled_for>p_now OR item\.next_attempt_at>p_now/);
  assert.match(migration,/wall_time:=\(p_now AT TIME ZONE item\.timezone\)/);
  assert.match(migration,/state IN \('sent','dispatching','uncertain'\)/);
  assert.match(migration,/dispatch_token uuid UNIQUE/);
  assert.match(migration,/MESSAGE='DISPATCH_TOKEN_REQUIRED'/);
  assert.match(migration,/MESSAGE='LEASE_LOST'/);
  assert.match(migration,/MESSAGE='IDEMPOTENCY_CONFLICT'/);
});
test('unknown outcomes cannot auto retry; revoked consent and policy gate sending',()=>{
  assert.match(migration,/ELSIF p_state='error' THEN next_state:='uncertain'/);
  assert.match(migration,/item\.state NOT IN \('queued','failed'\)/);
  assert.match(migration,/reason','POLICY_UNAPPROVED'/);
  assert.match(migration,/captured_at=p_now AND NOT granted AND p_granted/);
  assert.match(migration,/FOREIGN KEY\(company_id,owner_id\) REFERENCES public\.companies\(id,user_id\)/);
  assert.match(migration,/pg_advisory_xact_lock\(hashtextextended\('isg.notification.producer:'/);
});
test('safety probe runs and hashes after predecessor, upgrade ordering and both CI paths are wired',()=>{
  const runner=read('scripts/isg/run_auth_restore.mjs');
  assert.match(runner,/beginNotificationDispatchProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? notificationDispatchFiles : \[\]\)/);
  assert.match(runner,/notificationDispatchProbe\.afterLogout\(\)/);
  const dispatchStage=runner.search(/stage\s*=\s*'notification-dispatch-safety'/);
  const notesStage=runner.search(/stage\s*=\s*'personal-notes'/);
  assert.ok(notesStage>=0&&dispatchStage>notesStage);
  assert.equal(p05UpgradeFiles.at(-1),notificationDispatchFiles[0]);
  assert.ok(p05UpgradeFiles.at(-2)<notificationDispatchFiles[0]);
  assert.equal(read('.github/workflows/isg-foundation.yml').split(notificationDispatchFiles[0]).length-1,2);
  assert.match(read('scripts/isg/run_suite.mjs'),/notification_dispatch_guard\.test\.mjs/);
});
