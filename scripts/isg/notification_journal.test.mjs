import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, chmod, readdir, readFile, writeFile, symlink, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { openNotificationJournal, reconcileNotificationJournal, runNotificationBatch } from '../../supabase/functions/_shared/isg/notification-journal.ts';
import { runNotificationJob } from '../../supabase/functions/_shared/isg/notification-worker.ts';

const job='11111111-1111-4111-8111-111111111111', owner='22222222-2222-4222-8222-222222222222', token='33333333-3333-4333-8333-333333333333';
const now=Date.parse('2026-09-13T15:00:00Z');
const receipt={job_id:job,dispatch_token:token,provider:'fcm',state:'accepted',failure:null,now:new Date(now).toISOString()};
async function setup(t) {
  const directory=await realpath(await mkdtemp(join(tmpdir(),'isg-journal-test-')));
  await chmod(directory,0o700);
  t.after(()=>rm(directory,{recursive:true,force:true})); // Only this test's freshly minted directory.
  const journal=await openNotificationJournal(directory), calls=[];
  const ports={journal,now:()=>now,enabled:async()=>true,
    repository:{load:async()=>({job_id:job,device:{owner_id:owner,app_build:120,category_enabled:true,os_authorized:true},provider:'fcm',token:'private-device-token',title:'private-title',body:'private-body'}),
      claim:async()=>({job_id:job,allowed:true,channel:'push',dispatch_token:token,expires_at:new Date(now+60000).toISOString(),resolved_route:'home'}),
      complete:async()=>calls.push('complete')},
    prepare:async()=>({send:async()=>{calls.push('send');return {state:'accepted',failure:null};}})};
  return {directory,journal,ports,calls};
}
test('durable immutable receipt survives reopening, acknowledgement removes from pending only',async t=>{
  const {directory,journal}=await setup(t);
  await journal.save(receipt);await journal.save(receipt);
  const reopened=await openNotificationJournal(directory);
  assert.deepEqual(await reopened.pending(100),[receipt]);
  await reopened.acknowledge(receipt);await reopened.acknowledge(receipt);
  assert.deepEqual(await reopened.pending(100),[]);
  assert.equal((await readdir(directory)).length,2);
});
test('conflicting outcome cannot replace durable receipt or acknowledgement',async t=>{
  const {journal}=await setup(t);await journal.save(receipt);
  const changed={...receipt,state:'error',failure:'TRANSPORT_UNKNOWN'};
  await assert.rejects(journal.save(changed),/CONFLICT/);
  await assert.rejects(journal.acknowledge(changed),/CONFLICT/);
  assert.deepEqual(await journal.pending(100),[receipt]);
});
test('concurrent identical journal saves retain one immutable receipt',async t=>{
  const {journal,directory}=await setup(t);
  await Promise.all(Array.from({length:8},()=>journal.save(receipt)));
  assert.equal((await readdir(directory)).length,1);
});
test('only receipt fields persist; title, device token and arbitrary secrets do not',async t=>{
  const {journal,directory}=await setup(t);
  await journal.save({...receipt,token:'SECRET',title:'SECRET',body:'SECRET'});
  assert.ok(!(await readFile(join(directory,token+'.receipt'),'utf8')).includes('SECRET'));
});
test('worker persists before SQL completion, then marks acknowledgement',async t=>{
  const {journal,ports,calls}=await setup(t);
  ports.repository.complete=async r=>{assert.deepEqual(await journal.pending(100),[r]);calls.push('complete');};
  assert.equal((await runNotificationJob(job,'live',ports)).status,'recorded');
  assert.deepEqual(calls,['send','complete']);assert.deepEqual(await journal.pending(100),[]);
});
test('lost SQL response is replayed without any provider invocation',async t=>{
  const {journal,ports,calls}=await setup(t);
  ports.repository.complete=async()=>{throw Error('SECRET');};
  assert.equal((await runNotificationJob(job,'live',ports)).status,'receipt_pending_reconcile');
  assert.deepEqual(calls,['send']);
  const completed=[];
  assert.deepEqual(await reconcileNotificationJournal(journal,{complete:async r=>completed.push(r)}),{status:'reconciled',reconciled:1});
  assert.deepEqual(completed,[receipt]);assert.deepEqual(calls,['send']);
});
test('failed durable write never claims recorded or invokes SQL completion',async t=>{
  const {ports,calls}=await setup(t);
  ports.journal.save=async()=>{throw Error('SECRET');};
  const result=await runNotificationJob(job,'live',ports);
  assert.equal(result.status,'journal_failed_reconcile');assert.deepEqual(calls,['send']);
  assert.ok(!JSON.stringify(result).includes('SECRET'));
});
test('ack write loss retains exact receipt for idempotent SQL replay',async t=>{
  const {ports,journal}=await setup(t);const acknowledge=journal.acknowledge;
  journal.acknowledge=async()=>{throw Error('SECRET');};
  assert.equal((await runNotificationJob(job,'live',ports)).status,'journal_ack_pending_reconcile');
  assert.deepEqual(await journal.pending(100),[receipt]);journal.acknowledge=acknowledge;
  assert.equal((await reconcileNotificationJournal(journal,ports.repository)).reconciled,1);
});
test('real child SIGKILL after fsync: a new journal instance recovers exact receipt',async t=>{
  const {directory,journal}=await setup(t);
  const moduleURL=new URL('../../supabase/functions/_shared/isg/notification-journal.ts',import.meta.url).href;
  const child=spawnSync(process.execPath,['--input-type=module','-e',
    `import {openNotificationJournal} from ${JSON.stringify(moduleURL)}; const j=await openNotificationJournal(${JSON.stringify(directory)}); await j.save(${JSON.stringify(receipt)}); process.kill(process.pid,'SIGKILL');`],{timeout:10000});
  assert.equal(child.signal,'SIGKILL');
  assert.deepEqual(await journal.pending(100),[receipt]);
  let completed=0;assert.equal((await reconcileNotificationJournal(journal,{complete:async()=>completed++})).status,'reconciled');assert.equal(completed,1);
});
for(const mode of ['off','shadow'])test(`${mode} batch does not touch journal or provider`,async t=>{
  const {ports,calls}=await setup(t);ports.journal.pending=async()=>assert.fail('journal read');
  assert.equal((await runNotificationBatch([job],mode,ports)).status,mode==='off'?'disabled':'batch_complete');assert.deepEqual(calls,[]);
});
test('batch deduplicates IDs and returns no receipt capability or content',async t=>{
  const {ports,calls}=await setup(t);const result=await runNotificationBatch([job,job],'live',ports);
  assert.deepEqual(result,{status:'batch_complete',processed:1});assert.deepEqual(calls,['send','complete']);
  assert.ok(!JSON.stringify(result).includes(token));
});
test('pending reconciliation blocks all fresh sends',async t=>{
  const {journal,ports,calls}=await setup(t);await journal.save(receipt);
  ports.repository.complete=async()=>{throw Error('SECRET');};
  assert.deepEqual(await runNotificationBatch([job],'live',ports),{status:'reconcile_pending',processed:0});assert.deepEqual(calls,[]);
});
for(const [outcome,status] of [[{state:'error',failure:'TRANSPORT_UNKNOWN'},'provider_uncertain'],[{state:'rejected',failure:'RATE_LIMITED',retry_after_seconds:120},'provider_rate_limited']])test(`batch stops on ${status}`,async t=>{
  const {ports,calls}=await setup(t);ports.prepare=async()=>({send:async()=>{calls.push('send');return outcome;}});
  assert.deepEqual(await runNotificationBatch([job,owner],'live',ports),{status,processed:1});assert.deepEqual(calls,['send','complete']);
});
test('batch rejects invalid IDs and oversized batches before any work',async t=>{
  const {ports,calls}=await setup(t);
  for(const jobs of [['bad'],Array(101).fill(job)])assert.equal((await runNotificationBatch(jobs,'live',ports)).status,'invalid_input');
  assert.deepEqual(calls,[]);
});
test('private directory, no symlink files, valid receipt size and schema are enforced',async t=>{
  const {journal,directory}=await setup(t);
  await chmod(directory,0o755);await assert.rejects(openNotificationJournal(directory),/PRIVATE/);await chmod(directory,0o700);
  await assert.rejects(journal.save({...receipt,dispatch_token:'../../bad'}),/INVALID/);
  await writeFile(join(directory,'source'),'{}',{mode:0o600});await symlink(join(directory,'source'),join(directory,token+'.receipt'));
  assert.equal((await reconcileNotificationJournal(journal,{complete:async()=>assert.fail('complete')})).status,'journal_unavailable');
});
test('corrupted acknowledgement is not silently treated as completed',async t=>{
  const {journal,directory}=await setup(t);await journal.save(receipt);
  await writeFile(join(directory,token+'.ack'),'{}',{mode:0o600});
  await assert.rejects(journal.pending(100),/CONFLICT/);
});
test('bounded replay reports more and never drops remaining receipts',async t=>{
  const {journal}=await setup(t);await journal.save(receipt);await journal.save({...receipt,dispatch_token:owner});
  assert.equal((await reconcileNotificationJournal(journal,{complete:async()=>{}},1)).status,'reconcile_more');
  assert.equal((await journal.pending(100)).length,1);
});
