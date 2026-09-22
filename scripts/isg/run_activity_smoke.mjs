// Staging only. Credentials stay in memory; test note contents never enter logs.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const project = 'qlymhrrlhklcudveknih';
const credentials = JSON.parse(readFileSync(process.env.OSGB_DEVICE_CREDENTIALS ?? '/tmp/isgada-osgb-device-123-credentials.json'));
assert.equal(credentials.project_ref, project);
const keys = JSON.parse(execFileSync('supabase', ['projects','api-keys','--project-ref',project,'-o','json'], {encoding:'utf8'}));
const anon = keys.find(k=>k.name==='anon').api_key, service = keys.find(k=>k.name==='service_role').api_key;
async function request(path, token, body, method='POST', denied=false) {
 const r = await fetch(`https://${project}.supabase.co${path}`, {method,
  headers:{apikey:anon,authorization:`Bearer ${token}`,'content-type':'application/json'},
  body: body === undefined ? undefined : JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 const data=await r.json().catch(()=>null);
 if(denied) { assert.ok(r.status>=400, 'Unauthorized request accepted'); return data; }
 assert.ok(r.ok,`${path}: ${r.status} ${data?.message ?? data?.error ?? ''}`);
 return data;
}
const rpc=(token,name,args={})=>request('/rest/v1/rpc/'+name,token,args);
const login=async user=>(await request('/auth/v1/token?grant_type=password',anon,{email:user.email,password:user.password})).access_token;
let normalID;
const createdNotes=[];
try {
 const normal={email:`activity-qa-${randomUUID()}@riskdetected.invalid`,password:randomUUID()+'aA!9'};
 const account=await request('/auth/v1/admin/users',service,{...normal,email_confirm:true,user_metadata:{full_name:'Activity acceptance fixture'}});
 normalID=account.id;
 const tokens={normal:await login(normal),expert:await login(credentials.expert),manager:await login(credentials.owner)};
 for(const role of ['normal','expert','manager']) {
  const token=tokens[role];
  assert.equal((await rpc(token,'isg_notebook_rollout_v1')).enabled,true);
  const before=await rpc(token,'isg_activity_self_v1');
  assert.ok(before.summary.total_seconds>=0);
  await rpc(token,'isg_usage_presence_v1',{p_action:'start',p_workspace:role==='normal'?null:credentials.workspace.id});
  await rpc(token,'isg_usage_presence_v1',{p_action:'start',p_workspace:role==='normal'?null:credentials.workspace.id});
  await rpc(token,'isg_usage_presence_v1',{p_action:'stop',p_workspace:role==='normal'?null:credentials.workspace.id});
  console.log('PASS '+role+' activity and rollout');
 }
 for(const role of ['normal','expert']) {
  const token=tokens[role],note=randomUUID();
  createdNotes.push({token,note});
  const args={p_mutation:randomUUID(),p_note:note,p_action:'sync',p_expected:0,p_title:'Private QA title',p_body:'Private QA body',p_conflict:null};
  assert.equal((await rpc(token,'isg_notebook_mutate_v1',args)).state,'created');
  assert.equal((await rpc(token,'isg_notebook_mutate_v1',args)).replayed,true);
  const organized=await rpc(token,'isg_notebook_organize_v1',{p_mutation:randomUUID(),p_note:note,p_expected:1,
    p_items:[{item_id:randomUUID(),text:'Checklist QA item',done:true}],p_tags:['QA']});
  assert.equal(organized.version,2);
  const metadata=await rpc(token,'isg_notebook_organization_v1',{p_note:note});
  assert.equal(metadata.items[0].done,true);assert.deepEqual(metadata.tags,['QA']);
  const conflict=await rpc(token,'isg_notebook_mutate_v1',{...args,p_mutation:randomUUID(),p_expected:1,p_body:'Offline alternative'});
  assert.equal(conflict.state,'conflict');
  const read=await rpc(token,'isg_notebook_read_v1',{p_note:note,p_after:null});
  assert.equal(read.note.conflicts.length,1);
  const conflictID=read.note.conflicts[0].conflict_id;
  const resolved=await rpc(token,'isg_notebook_mutate_v1',{...args,p_mutation:randomUUID(),p_action:'resolve',p_expected:2,p_conflict:conflictID});
  assert.equal(resolved.state,'resolved');
  const events=await rpc(token,'isg_activity_self_v1');
  assert.ok(!JSON.stringify(events).includes('Private QA'));
  const personal=events.items.find(e=>e.entity_type==='personal_note');
  assert.ok(personal);
  const detail=await rpc(token,'isg_activity_event_detail_v1',{p_event:personal.id});
  assert.equal(detail.entity_id,null);assert.deepEqual(detail.changes,[]);
  await request('/rest/v1/rpc/isg_notebook_read_v1',tokens.manager,{p_note:note,p_after:null},'POST',true);
  if(role==='expert') {
   const manager=await rpc(tokens.manager,'isg_workspace_member_activity_v1',{p_workspace:credentials.workspace.id,p_user:credentials.expert.user_id});
   assert.ok(manager.items.every(e=>e.entity_type!=='personal_note'));
   await request('/rest/v1/rpc/isg_activity_event_detail_v1',tokens.manager,{p_event:personal.id,p_workspace:credentials.workspace.id},'POST',true);
  }
  console.log('PASS '+role+' note/checklist/tag/replay/conflict/resolve and private log');
 }
 await request('/rest/v1/rpc/isg_workspace_member_activity_v1',tokens.expert,{p_workspace:credentials.workspace.id,p_user:credentials.owner.user_id},'POST',true);
 await request('/rest/v1/rpc/isg_workspace_member_activity_v1',tokens.manager,{p_workspace:randomUUID(),p_user:credentials.expert.user_id},'POST',true);
 await request('/rest/v1/rpc/isg_notebook_delivery_claim_v1',tokens.expert,{p_limit:1},'POST',true);
 console.log('PASS manager scope, expert denial, worker service-only access');
 const unauth=await fetch(`https://${project}.supabase.co/functions/v1/process-notebook-reminders`,{method:'POST'});
 assert.equal(unauth.status,401);
 // The configured cron secret is deliberately not read by this client test.
 // Worker success is asserted independently through cron/net delivery evidence.
 console.log('PASS unauthenticated reminder worker denied');
} finally {
 for(const {token,note} of createdNotes) {
  try {
   const read=await rpc(token,'isg_notebook_read_v1',{p_note:note,p_after:null});
   await rpc(token,'isg_notebook_mutate_v1',{p_mutation:randomUUID(),p_note:note,p_action:'delete',p_expected:read.note.version,p_title:null,p_body:null,p_conflict:null});
  } catch { console.error('Test note cleanup requires inspection'); }
 }
 if(normalID) await request('/auth/v1/admin/users/'+normalID,service,undefined,'DELETE');
}
