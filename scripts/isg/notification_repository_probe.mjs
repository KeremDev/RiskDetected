import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ROOT} from './lib.mjs';
import {createNotificationRepository} from '../../supabase/functions/_shared/isg/notification-repository.ts';
import {runNotificationJob} from '../../supabase/functions/_shared/isg/notification-worker.ts';
import {preparePush} from '../../supabase/functions/_shared/isg/notification-transport.ts';
export const notificationRepositoryFiles=[
  'supabase/migrations/20260914070002_isg_notification_provider_wait.sql',
  'scripts/isg/notification_repository_probe.mjs',
  'supabase/functions/_shared/isg/notification-repository.ts',
  'supabase/functions/_shared/isg/notification-worker.ts',
  'supabase/functions/_shared/isg/notification-transport.ts',
];
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
export async function beginNotificationRepositoryProbe({synthetic,sql,ownerID,companyID,pass}){
  if(synthetic!==true)throw Error('NOTIFICATION_REPOSITORY_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('NOTIFICATION_REPOSITORY_SCOPE_REQUIRED');
  const mark=(id,ok)=>pass('notification_repository_'+id,ok);
  sql(readFileSync(resolve(ROOT,notificationRepositoryFiles[0]),'utf8'));
  mark('migration_keeps_rollout_closed',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='notifications';")==='t');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='notifications';UPDATE private_isg.notification_purposes SET caps_approved=true;");
  let now=Date.parse('2027-04-01T09:00:00Z'),calls=0,status=429,loseAck=false,networkError=false;
  const stamp=()=>new Date(now).toISOString();
  sql(`SELECT private_isg.set_producer_ownership('obligation','repository.test','isg_engine','live',${q(stamp())});SELECT private_isg.record_notification_consent(${q(ownerID)},'obligation','push',true,'settings',NULL,${q(stamp())});`);
  const make=()=>JSON.parse(sql(`SELECT private_isg.enqueue_notification((e.value->>'episode_id')::uuid,'push','isg/personnel','home',100,${q(stamp())},'Europe/Istanbul',${q(stamp())}) FROM (SELECT private_isg.open_notification_episode(${q(ownerID)},${q(companyID)},'obligation','repository.test',${q(randomUUID())},1,NULL,'isg_engine',false,${q(stamp())}) value) e;`)).job_id;
  // psql PREPARE/EXECUTE exercises real parameter binding; no client/production
  // driver or credentials. Every statement targets the guarded disposable DB.
  const query=async(statement,values)=>{
    const args=values.map(v=>v===null?'NULL':q(v)).join(',');
    const result=JSON.parse(sql(`PREPARE isg_repository_statement AS ${statement};EXECUTE isg_repository_statement(${args});`).split('\n').at(-1));
    if(loseAck&&statement.includes('complete_notification')){loseAck=false;throw Error('SIMULATED_RESPONSE_LOSS');}
    return result;
  };
  const device={owner_id:ownerID,app_build:120,category_enabled:true,os_authorized:true};
  const repository=createNotificationRepository(query,async job=>({job_id:job,device,provider:'fcm',token:'synthetic-token',title:'Sentetik',body:'Gerçek alıcı yok'}));
  const ports={repository,enabled:async()=>sql("SELECT read_enabled AND write_enabled FROM private_isg.rollout WHERE feature='notifications';")==='t',now:()=>now,
    prepare:async snapshot=>preparePush(snapshot,{provider:'fcm',bearer:'synthetic-bearer',project:'synthetic-project'},async()=>{
      calls++;if(networkError)throw Error('SYNTHETIC_CONNECTION_LOSS');return new Response('',{status,headers:{'retry-after':'120'}});
    },()=>now)};
  const job=make();
  const first=await runNotificationJob(job,'live',ports);
  mark('real_sql_claim_provider_stub_and_receipt_compose',first.status==='recorded'&&first.receipt.state==='rejected'&&first.receipt.retry_after_seconds===120&&calls===1);
  mark('provider_wait_persisted_atomically',sql(`SELECT j.state='failed' AND j.next_attempt_at=${q(stamp())}::timestamptz+interval '120 seconds' AND a.retry_after_seconds=120 FROM private_isg.notification_jobs j JOIN private_isg.delivery_attempts a USING(job_id) WHERE j.job_id=${q(job)};`)==='t');
  const replay=await repository.complete(first.receipt);
  mark('same_receipt_replay_preserves_wait',replay.replayed===true&&sql(`SELECT count(*) FROM private_isg.delivery_attempts WHERE job_id=${q(job)};`)==='1');
  let conflict=false;try{await repository.complete({...first.receipt,retry_after_seconds:121});}catch{conflict=true;}
  mark('changed_wait_conflicts_without_mutation',conflict&&sql(`SELECT retry_after_seconds FROM private_isg.delivery_attempts WHERE job_id=${q(job)};`)==='120');
  now+=119000;
  mark('before_provider_wait_no_new_send',(await runNotificationJob(job,'live',ports)).status==='not_claimed'&&calls===1);
  now+=1000;status=200;
  const second=await runNotificationJob(job,'live',ports);
  mark('at_wait_boundary_new_claim_and_one_send',second.status==='recorded'&&second.receipt.dispatch_token!==first.receipt.dispatch_token&&calls===2&&sql(`SELECT state FROM private_isg.notification_jobs WHERE job_id=${q(job)};`)==='sent');
  const lost=make();loseAck=true;
  const pending=await runNotificationJob(lost,'live',ports),countAtLoss=calls;
  mark('committed_receipt_lost_response_returns_pending',pending.status==='receipt_pending_reconcile'&&pending.receipt.state==='accepted');
  mark('restart_does_not_resend_committed_job',(await runNotificationJob(lost,'live',ports)).status==='not_claimed'&&calls===countAtLoss);
  mark('pending_receipt_reconciles_idempotently',(await repository.complete(pending.receipt)).replayed===true&&calls===countAtLoss);
  const unknown=make();networkError=true;
  const ambiguous=await runNotificationJob(unknown,'live',ports),countAtUnknown=calls;
  mark('unknown_transport_persisted_without_retry',ambiguous.receipt.state==='error'&&sql(`SELECT state FROM private_isg.notification_jobs WHERE job_id=${q(unknown)};`)==='uncertain'&&(await runNotificationJob(unknown,'live',ports)).status==='not_claimed'&&calls===countAtUnknown);
  networkError=false;
  const concurrent=make(),countAtRace=calls;
  const raced=await Promise.all(Array.from({length:8},()=>runNotificationJob(concurrent,'live',ports)));
  mark('eight_worker_invocations_one_real_sql_winner',raced.filter(r=>r.status==='recorded').length===1&&calls===countAtRace+1);
  mark('completion_api_has_no_client_grants',sql("SELECT NOT has_function_privilege('authenticated','private_isg.complete_notification_delivery_with_retry(uuid,uuid,text,text,text,timestamptz,integer)','EXECUTE') AND NOT has_function_privilege('service_role','private_isg.complete_notification_delivery_with_retry(uuid,uuid,text,text,text,timestamptz,integer)','EXECUTE');")==='t');
  sql("UPDATE private_isg.notification_purposes SET caps_approved=false;UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='notifications';");
  mark('disabled_worker_makes_no_provider_request',(await runNotificationJob(makeDisabledJob(),'live',ports)).status==='disabled'&&calls===countAtRace+1);
  function makeDisabledJob(){return randomUUID();}
  return {afterLogout(){return {real_postgres_prepared_calls:true,worker_repository_transport_composed:true,provider_stub_only:true,trusted_device_source:'synthetic fixture',external_egress:false,production_changed:false,rollout_left_disabled:true,receipt_response_loss_replayed:true};}};
}
