import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runNotificationJob} from '../../supabase/functions/_shared/isg/notification-worker.ts';
import {preparePush} from '../../supabase/functions/_shared/isg/notification-transport.ts';
const job='11111111-1111-4111-8111-111111111111',owner='22222222-2222-4222-8222-222222222222',token='33333333-3333-4333-8333-333333333333';
const now=Date.parse('2026-09-13T15:00:00Z');
const snapshot=()=>({job_id:job,device:{owner_id:owner,app_build:120,category_enabled:true,os_authorized:true},provider:'fcm',token:'synthetic-token',title:'Bildirim',body:'Uygulamayı açın.'});
const claim=()=>({job_id:job,allowed:true,channel:'push',dispatch_token:token,expires_at:new Date(now+60000).toISOString(),resolved_route:'home'});
const accepted={state:'accepted',failure:null};
function fixture(){
  const calls={load:0,prepare:0,claim:0,send:0,complete:0};
  const ports={now:()=>now,enabled:async()=>true,
    repository:{load:async()=>{calls.load++;return snapshot();},claim:async()=>{calls.claim++;return claim();},complete:async()=>{calls.complete++;}},
    prepare:async()=>{calls.prepare++;return {send:async()=>{calls.send++;return accepted;}};}};
  return {ports,calls};
}
for(const mode of ['off','shadow'])test(`worker ${mode} cannot claim, prepare or send`,async()=>{
  const {ports,calls}=fixture();const r=await runNotificationJob(job,mode,ports);
  assert.equal(r.status,mode==='off'?'disabled':'shadow_no_send');
  assert.equal(calls.claim+calls.prepare+calls.send+calls.complete,0);
  if(mode==='off')assert.equal(calls.load,0);
});
test('live worker uses final route and token once then records exact outcome',async()=>{
  const {ports,calls}=fixture();let receipt;
  ports.prepare=async()=>({send:async(route,t)=>{calls.send++;assert.equal(route,'home');assert.equal(t,token);return accepted;}});
  ports.repository.complete=async r=>{receipt=r;calls.complete++;};
  const r=await runNotificationJob(job,'live',ports);
  assert.equal(r.status,'recorded');assert.deepEqual(receipt,r.receipt);assert.equal(receipt.dispatch_token,token);
  assert.equal(calls.load,2);assert.equal(calls.claim,1);assert.equal(calls.send,1);assert.equal(calls.complete,1);
});
for(const [label,change,status] of [
  ['disabled',p=>p.enabled=async()=>false,'disabled'],
  ['no snapshot',p=>p.repository.load=async()=>null,'unavailable'],
  ['foreign snapshot',p=>p.repository.load=async()=>({...snapshot(),job_id:owner}),'unavailable'],
  ['credential failure',p=>p.prepare=async()=>{throw Error('secret');},'preflight_failed'],
  ['claim refused',p=>p.repository.claim=async()=>({...claim(),allowed:false}),'not_claimed'],
  ['truthy malformed permission',p=>p.repository.claim=async()=>({...claim(),allowed:'true'}),'not_claimed'],
  ['claim exception',p=>p.repository.claim=async()=>{throw Error('secret');},'preflight_failed'],
  ['wrong claim job',p=>p.repository.claim=async()=>({...claim(),job_id:owner}),'invalid_claim_reconcile'],
  ['missing token',p=>p.repository.claim=async()=>({...claim(),dispatch_token:undefined}),'invalid_claim_reconcile'],
  ['email claim',p=>p.repository.claim=async()=>({...claim(),channel:'email'}),'invalid_claim_reconcile'],
  ['foreign route',p=>p.repository.claim=async()=>({...claim(),resolved_route:'https://bad.test'}),'invalid_claim_reconcile'],
  ['expired',p=>p.repository.claim=async()=>({...claim(),expires_at:new Date(now).toISOString()}),'expired_claim_reconcile'],
  ['insufficient budget',p=>p.repository.claim=async()=>({...claim(),expires_at:new Date(now+15000).toISOString()}),'expired_claim_reconcile'],
])test(`worker ${label} never invokes transport`,async()=>{
  const {ports,calls}=fixture();change(ports);const r=await runNotificationJob(job,'live',ports);
  assert.equal(r.status,status);assert.equal(calls.send,0);assert.equal(calls.complete,0);assert.ok(!JSON.stringify(r).includes('secret'));
});
for(const field of ['token','owner','category','build'])test(`credential refresh detects changed ${field}`,async()=>{
  const {ports,calls}=fixture();ports.repository.load=async()=>{calls.load++;const s=snapshot();if(calls.load===2){
    if(field==='token')s.token='new-token';if(field==='owner')s.device.owner_id=job;if(field==='category')s.device.category_enabled=false;if(field==='build')s.device.app_build=119;
  }return s;};
  assert.equal((await runNotificationJob(job,'live',ports)).status,'snapshot_changed');assert.equal(calls.claim,0);assert.equal(calls.send,0);
});
test('kill switch is re-read after credential preparation',async()=>{
  const {ports,calls}=fixture();let n=0;ports.enabled=async()=>++n===1;
  assert.equal((await runNotificationJob(job,'live',ports)).status,'disabled');assert.equal(calls.claim,0);
});
test('lost receipt response does not send twice or expose errors',async()=>{
  const {ports,calls}=fixture();ports.repository.complete=async()=>{throw Error('provider-secret');};
  const r=await runNotificationJob(job,'live',ports);
  assert.equal(r.status,'receipt_pending_reconcile');assert.equal(r.receipt.state,'accepted');assert.equal(calls.send,1);
  assert.ok(!JSON.stringify(r).includes('secret'));
});
for(const kind of ['throw','hang','malformed'])test(`provider ${kind} yields uncertain receipt without retry`,async()=>{
  const {ports,calls}=fixture();let signal;
  ports.prepare=async()=>({send:async(_r,_t,s)=>{calls.send++;signal=s;if(kind==='throw')throw Error('secret');if(kind==='hang')return new Promise(()=>{});return {state:'accepted',failure:'invalid'};}});
  const r=await runNotificationJob(job,'live',ports,10);
  assert.equal(r.receipt.state,'error');assert.equal(r.receipt.failure,'TRANSPORT_UNKNOWN');assert.equal(calls.send,1);assert.equal(signal.aborted,true);
});
test('eight orchestration callers obey repository single-winner claim',async()=>{
  const {ports,calls}=fixture();let taken=false;ports.repository.claim=async()=>{const allowed=!taken;taken=true;return {...claim(),allowed};};
  const results=await Promise.all(Array.from({length:8},()=>runNotificationJob(job,'live',ports)));
  assert.equal(results.filter(r=>r.status==='recorded').length,1);assert.equal(calls.send,1);
});
for(const provider of ['apns','fcm']){
  const credentials=provider==='apns'?{provider,bearer:'fake.jwt.value',topic:'com.synthetic.app',environment:'sandbox'}:{provider,bearer:'fake-access-token',project:'synthetic-project'};
  const snap=()=>({...snapshot(),provider,token:provider==='apns'?'a'.repeat(64):'synthetic-token'});
  for(const [status,state,failure] of [
    [200,'accepted',null],[201,'error','PROVIDER_RESULT_UNKNOWN'],[302,'error','PROVIDER_RESULT_UNKNOWN'],
    [400,'rejected','PROVIDER_REQUEST_REJECTED'],[401,'rejected','PROVIDER_AUTH_REQUIRED'],[403,'rejected','PROVIDER_AUTH_REQUIRED'],
    [404,'rejected','PROVIDER_REQUEST_REJECTED'],[410,'rejected',provider==='apns'?'TOKEN_INVALID':'PROVIDER_REQUEST_REJECTED'],
    [429,'rejected','RATE_LIMITED'],[500,'error','PROVIDER_RESULT_UNKNOWN'],[503,'error','PROVIDER_RESULT_UNKNOWN'],
  ])test(`${provider} ${status}: one request, ${state}/${failure}`,async()=>{
    let count=0;
    const transport=preparePush(snap(),credentials,async(url,init)=>{
      count++;assert.ok(url.startsWith(provider==='apns'?'https://api.sandbox.push.apple.com/3/device/':'https://fcm.googleapis.com/v1/projects/'));
      assert.equal(init.redirect,'error');assert.equal(init.method,'POST');
      const p=JSON.parse(init.body),data=provider==='apns'?p.data:p.message.data;
      assert.deepEqual(Object.keys(data).sort(),['job_id','route','schema_version']);assert.equal(data.route,'home');
      assert.ok(!init.body.includes(credentials.bearer));
      return new Response('not logged',{status});
    });
    assert.deepEqual(await transport.send('home',token,new AbortController().signal),{state,failure,...(status===429?{retry_after_seconds:60}:{})});
    await assert.rejects(transport.send('home',token,new AbortController().signal),/ALREADY_USED/);assert.equal(count,1);
  });
  test(`${provider} network loss never retries`,async()=>{
    let count=0;const t=preparePush(snap(),credentials,async()=>{count++;throw Error('device-token-secret');});
    assert.equal((await t.send('home',token,new AbortController().signal)).failure,'TRANSPORT_UNKNOWN');assert.equal(count,1);
  });
  test(`${provider} config and destination are validated before IO`,async()=>{
    const noIO=async()=>{assert.fail('unexpected IO');};
    assert.throws(()=>preparePush(snap(),{...credentials,bearer:'x\r\ninjected'},noIO));
    assert.throws(()=>preparePush({...snap(),token:'https://evil.test/'},credentials,noIO));
    const t=preparePush(snap(),credentials,noIO);await assert.rejects(t.send('https://evil.test',token,new AbortController().signal));
  });
}
test('new modules cannot start a server, read secrets or call legacy retry helpers',()=>{
  for(const path of ['notification-worker.ts','notification-transport.ts']){
    const source=readFileSync(new URL('../../supabase/functions/_shared/isg/'+path,import.meta.url),'utf8');
    assert.doesNotMatch(source,/Deno\.env|Deno\.serve|process\.env|deliverToAPNs|deliverToFcm|console\./);
    assert.doesNotMatch(source,/\bfetch\(/);
  }
});
