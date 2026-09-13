import test from 'node:test';
import assert from 'node:assert/strict';
import {createNotificationRepository} from '../../supabase/functions/_shared/isg/notification-repository.ts';
import {parseProviderWait} from '../../supabase/functions/_shared/isg/notification-transport.ts';
import {validOutcome} from '../../supabase/functions/_shared/isg/notification-worker.ts';
const job='11111111-1111-4111-8111-111111111111',owner='22222222-2222-4222-8222-222222222222',token='33333333-3333-4333-8333-333333333333';
const now='2027-04-01T09:00:00.000Z';
const device={owner_id:owner,app_build:120,category_enabled:true,os_authorized:true};
const snapshot={job_id:job,device,provider:'fcm',token:'test-token',title:'Test',body:'Test'};
const receipt={job_id:job,dispatch_token:token,provider:'fcm',state:'rejected',failure:'RATE_LIMITED',retry_after_seconds:120,now};
const ack={schema_version:1,job_id:job,dispatch_token:token,attempt_id:owner,replayed:false,job_state:'failed',retry_after_seconds:120,delivery_confirmed:false,read_confirmed:false};
const claim={schema_version:1,job_id:job,allowed:true,channel:'push',dispatch_token:token,expires_at:'2027-04-01T09:01:00Z',resolved_route:'home'};
for(const [input,expected] of [[null,60],['0',60],['1',60],['120',120],['86400',86400],['86401',null],['-1',null],['1.2',null],['Infinity',null],['1e3',null],['',null],['Thu, 01 Apr 2027 09:03:00 GMT',180],['Thu, 01 Apr 2027 08:00:00 GMT',60],['tomorrow',null]])
  test(`provider wait ${String(input)} -> ${String(expected)}`,()=>assert.equal(parseProviderWait(input,Date.parse(now)),expected));
test('invalid clock cannot invent retry time',()=>assert.equal(parseProviderWait('120',NaN),null));
test('outcome wait is allowed only on known temporary rejections',()=>{
  assert.equal(validOutcome(receipt),true);
  for(const changed of [{retry_after_seconds:0},{retry_after_seconds:86401},{retry_after_seconds:1.5},{retry_after_seconds:NaN},{state:'accepted',failure:null},{state:'error'},{failure:'TOKEN_INVALID'}])assert.equal(validOutcome({...receipt,...changed}),false);
});
test('repository uses fixed SQL and bound values, detaches snapshots',async()=>{
  let statement,args;const repo=createNotificationRepository(async(s,a)=>{statement=s;args=a;return claim;},async()=>snapshot);
  const s=await repo.load(job);s.device.app_build=1;assert.equal(snapshot.device.app_build,120);
  assert.equal((await repo.claim(job,device,now)).allowed,true);
  assert.match(statement,/dispatch_notification\(\$1::uuid,\$2::jsonb,\$3::timestamptz\)/);
  assert.ok(!statement.includes(job));assert.deepEqual(args,[job,JSON.stringify(device),now]);
});
test('complete binds wait and validates SQL acknowledgement',async()=>{
  let args;const repo=createNotificationRepository(async(_s,a)=>{args=a;return ack;},async()=>snapshot);
  assert.deepEqual(await repo.complete(receipt),ack);assert.deepEqual(args,[job,token,'fcm','rejected','RATE_LIMITED',now,120]);
});
for(const [label,value]of [['null',null],['array',[]],['error',{error:'raw-secret'}],['rpc wrapper',{data:ack,error:null}],['version',{...ack,schema_version:2}],['wrong job',{...ack,job_id:owner}],['wrong token',{...ack,dispatch_token:owner}],['bad receipt id',{...ack,attempt_id:'bad'}],['claimed delivery',{...ack,delivery_confirmed:true}],['wrong wait',{...ack,retry_after_seconds:30}],['missing replay',{...ack,replayed:undefined}]])
  test(`invalid completion ${label} is not recorded as success`,async()=>{
    const repo=createNotificationRepository(async()=>value,async()=>snapshot);
    await assert.rejects(repo.complete(receipt),/NOTIFICATION_/);
  });
test('driver errors are redacted and do not trigger another query',async()=>{
  let calls=0;const repo=createNotificationRepository(async()=>{calls++;throw Error('SECRET_DATABASE_URL');},async()=>snapshot);
  await assert.rejects(repo.complete(receipt),e=>e.message==='NOTIFICATION_DATABASE_UNAVAILABLE');assert.equal(calls,1);
});
test('invalid scope or receipt is rejected before database IO',async()=>{
  const repo=createNotificationRepository(async()=>assert.fail('SQL called'),async()=>snapshot);
  await assert.rejects(repo.claim("';DROP TABLE",device,now));
  await assert.rejects(repo.complete({...receipt,retry_after_seconds:-1}));
  await assert.rejects(repo.load(owner));
});
