import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const notificationDispatchFiles=[
  'supabase/migrations/20260914070001_isg_notification_dispatch_safety.sql',
  'scripts/isg/notification_dispatch_probe.mjs',
];
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
const j=v=>q(JSON.stringify(v))+'::jsonb';
const at=(day=1,seconds=0)=>new Date(Date.UTC(2027,2,day,9,0,seconds)).toISOString();

export async function beginNotificationDispatchProbe({synthetic,sql,concurrentSql,ownerID,companyID,pass}) {
  if(synthetic!==true)throw Error('NOTIFICATION_DISPATCH_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID||!concurrentSql)throw Error('NOTIFICATION_DISPATCH_SCOPE_REQUIRED');
  const mark=(name,value)=>pass('notification_dispatch_'+name,value);
  sql(`CREATE SCHEMA isg_send_test;
    CREATE FUNCTION isg_send_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
    DECLARE answer jsonb;code text;BEGIN
      CASE kind
      WHEN 'consent' THEN answer:=private_isg.record_notification_consent((a->>'owner')::uuid,a->>'purpose',a->>'channel',(a->>'granted')::boolean,'settings',NULL,(a->>'now')::timestamptz);
      WHEN 'owner' THEN answer:=private_isg.set_producer_ownership(a->>'purpose',a->>'kind',a->>'producer',coalesce(a->>'mode','live'),(a->>'now')::timestamptz);
      WHEN 'episode' THEN answer:=private_isg.open_notification_episode((a->>'owner')::uuid,(a->>'company')::uuid,a->>'purpose',a->>'kind',a->>'ref',1,NULL,'isg_engine',coalesce((a->>'alarm')::boolean,false),(a->>'now')::timestamptz);
      WHEN 'enqueue' THEN answer:=private_isg.enqueue_notification((a->>'episode')::uuid,a->>'channel','isg/personnel','home',100,(a->>'due')::timestamptz,'Europe/Istanbul',(a->>'now')::timestamptz);
      WHEN 'claim' THEN answer:=private_isg.dispatch_notification((a->>'job')::uuid,a->'device',(a->>'now')::timestamptz);
      WHEN 'old_finish' THEN answer:=private_isg.record_delivery_attempt((a->>'job')::uuid,'fcm',a->>'state',a->>'failure',(a->>'now')::timestamptz);
      WHEN 'finish' THEN answer:=private_isg.complete_notification_delivery((a->>'job')::uuid,(a->>'token')::uuid,a->>'provider',a->>'state',a->>'failure',(a->>'now')::timestamptz);
      ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';END CASE;
      RETURN jsonb_build_object('result',answer);
      EXCEPTION WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;RETURN jsonb_build_object('error',code);
      WHEN foreign_key_violation THEN RETURN jsonb_build_object('error','FOREIGN_KEY_VIOLATION');
      END $$;`);
  const query=(kind,a)=>`SELECT isg_send_test.observe(${q(kind)},${j(a)});`;
  const call=(kind,a)=>JSON.parse(sql(query(kind,a)).split('\n').at(-1));
  const ok=(kind,a)=>{const r=call(kind,a);if(r.error)throw Error('NOTIFICATION_DISPATCH_UNEXPECTED_'+r.error);return r.result;};
  const device={owner_id:ownerID,app_build:120,category_enabled:true,os_authorized:true};
  const own=(purpose,kind,producer='isg_engine')=>ok('owner',{purpose,kind,producer,now:at()});
  const consent=(granted,purpose='obligation',channel='push',stamp=at())=>call('consent',{owner:ownerID,purpose,channel,granted,now:stamp});
  const make=(ref,{purpose='obligation',kind='safety.obligation',channel='push',due=at(),company=companyID,alarm=false}={})=>{
    const episode=ok('episode',{owner:ownerID,company,purpose,kind,ref,alarm,now:at()});
    return ok('enqueue',{episode:episode.episode_id,channel,due,now:at()}).job_id;
  };
  const claim=(job,stamp=at(),metadata=device)=>ok('claim',{job,device:metadata,now:stamp});
  const finish=(job,token,state='accepted',failure=null,stamp=at(1,1),provider='fcm')=>call('finish',{job,token,provider,state,failure,now:stamp});
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='notifications';");
  own('obligation','safety.obligation');consent(true);
  // Counterexamples execute the predecessor implementation, not a source regex.
  const tooEarly=make('before-future',{due:at(2)});
  mark('predecessor_reproduces_future_job_sent_early',claim(tooEarly).allowed===true);
  const delayed=make('before-night');
  mark('predecessor_reproduces_scheduled_time_instead_of_send_time',claim(delayed,at(1,36000)).allowed===true);
  const repeated=make('before-parallel');
  const before=await Promise.all(Array.from({length:4},()=>concurrentSql(query('claim',{job:repeated,device,now:at()}))));
  mark('predecessor_reproduces_duplicate_send_permission',before.every(r=>r.ok&&JSON.parse(r.output).result.allowed===true));
  const retry=make('before-revoked-retry');claim(retry);
  ok('old_finish',{job:retry,state:'error',failure:'TEMPORARY_FAILURE',now:at(1,1)});consent(false,'obligation','push',at(1,2));
  mark('predecessor_reproduces_retry_after_consent_revocation',ok('old_finish',{job:retry,state:'accepted',failure:null,now:at(1,3)}).job_state==='sent');

  sql(readFileSync(resolve(ROOT,notificationDispatchFiles[0]),'utf8'));
  mark('legacy_unfenced_entry_point_is_disabled',call('old_finish',{job:tooEarly,state:'accepted',failure:null,now:at()}).error==='DISPATCH_TOKEN_REQUIRED');
  consent(true,'obligation','push',at(2));
  mark('future_job_is_not_claimed',claim(tooEarly).reason==='NOT_DUE');
  const candidate=make('unapproved-policy',{due:at(3)});
  mark('unapproved_policy_cannot_send',claim(candidate,at(3)).reason==='POLICY_UNAPPROVED');
  sql('UPDATE private_isg.notification_purposes SET caps_approved=true;'); // isolated fixture approval ONLY
  mark('delayed_daytime_job_respects_current_quiet_hours',claim(delayed,at(3,36000)).suppression_code==='QUIET_HOURS');
  const missingOS=make('missing-os',{due:at(3)});
  mark('os_permission_is_separate_and_required',claim(missingOS,at(3),{...device,os_authorized:false}).suppression_code==='OS_PERMISSION_REQUIRED');
  const email=make('missing-email',{channel:'email',due:at(3)});
  mark('email_requires_its_own_consent',claim(email,at(3)).suppression_code==='CONSENT_MISSING');
  const noOwner=call('episode',{owner:ownerID,company:randomUUID(),purpose:'obligation',kind:'safety.obligation',ref:'foreign-company',now:at()});
  mark('company_owner_composite_is_enforced',noOwner.error==='FOREIGN_KEY_VIOLATION');
  const foreignCompany=sql(`SELECT id FROM public.companies WHERE user_id<>${q(ownerID)}::uuid ORDER BY id LIMIT 1;`);
  mark('existing_foreign_company_cannot_be_attached',!!foreignCompany&&call('episode',{owner:ownerID,company:foreignCompany,purpose:'obligation',kind:'safety.obligation',ref:'actual-foreign-company',now:at()}).error==='FOREIGN_KEY_VIOLATION');
  const single=make('one-winner',{due:at(4)});
  const raced=await Promise.all(Array.from({length:8},()=>concurrentSql(query('claim',{job:single,device,now:at(4)}))));
  const claims=raced.filter(r=>r.ok).map(r=>JSON.parse(r.output).result);
  const winner=claims.find(r=>r.allowed);
  mark('eight_workers_get_one_token',raced.every(r=>r.ok)&&claims.filter(r=>r.allowed).length===1&&!!winner.dispatch_token);
  mark('wrong_token_is_fenced',finish(single,randomUUID(),'accepted',null,at(4,1)).error==='LEASE_LOST');
  mark('provider_must_match_channel',finish(single,winner.dispatch_token,'accepted',null,at(4,1),'email').error==='VALIDATION_ERROR');
  const accepted=finish(single,winner.dispatch_token,'accepted',null,at(4,2)).result;
  const replay=finish(single,winner.dispatch_token,'accepted',null,at(4,3)).result;
  mark('accepted_ack_is_idempotent_not_delivery',accepted.job_state==='sent'&&replay.replayed&&accepted.attempt_id===replay.attempt_id&&!accepted.delivery_confirmed&&!accepted.read_confirmed);
  mark('changed_ack_is_rejected',finish(single,winner.dispatch_token,'rejected','TOKEN_INVALID',at(4,4)).error==='IDEMPOTENCY_CONFLICT');
  mark('sent_job_is_never_reclaimed',claim(single,at(5)).allowed===false);
  const unknown=make('unknown-outcome',{due:at(5)}),unknownClaim=claim(unknown,at(5));
  mark('transport_error_is_uncertain_not_retryable',finish(unknown,unknownClaim.dispatch_token,'error','TRANSPORT_UNKNOWN',at(5,1)).result.job_state==='uncertain'&&claim(unknown,at(6)).allowed===false);
  const expired=make('expired-claim',{due:at(5)}),expiredClaim=claim(expired,at(5));
  mark('expired_claim_never_auto_resends',claim(expired,at(5,61)).state==='uncertain');
  mark('late_known_result_can_reconcile_without_resend',finish(expired,expiredClaim.dispatch_token,'accepted',null,at(5,62)).result.job_state==='sent');
  const backoff=make('retry-consent',{due:at(6)}),attempt=claim(backoff,at(6));
  mark('definitive_retryable_rejection_has_backoff',finish(backoff,attempt.dispatch_token,'rejected','RATE_LIMITED',at(6,1)).result.job_state==='failed'&&claim(backoff,at(6,2)).reason==='NOT_DUE');
  consent(false,'obligation','push',at(6,2));
  mark('retry_rechecks_current_consent',claim(backoff,at(6,31)).suppression_code==='CONSENT_REVOKED');
  mark('stale_consent_cannot_restore_permission',consent(true,'obligation','push',at(6,1)).error==='STALE_CONSENT');
  mark('equal_timestamp_opt_out_wins',consent(true,'obligation','push',at(6,2)).error==='STALE_CONSENT');
  consent(true,'obligation','push',at(7));
  const terminal=make('invalid-token',{due:at(7)}),terminalClaim=claim(terminal,at(7));
  mark('permanent_rejection_is_terminal',finish(terminal,terminalClaim.dispatch_token,'rejected','TOKEN_INVALID',at(7,1)).result.job_state==='dead'&&claim(terminal,at(8)).allowed===false);
  own('operational','safety.cap');consent(true,'operational','push',at(8));
  sql("UPDATE private_isg.notification_purposes SET daily_cap=1 WHERE purpose='operational';");
  const capped=[make('cap-first',{purpose:'operational',kind:'safety.cap',due:at(8)}),make('cap-second',{purpose:'operational',kind:'safety.cap',due:at(8)})];
  const capRace=await Promise.all(capped.map(job=>concurrentSql(query('claim',{job,device,now:at(8)}))));
  const capResults=capRace.filter(r=>r.ok).map(r=>JSON.parse(r.output).result);
  mark('parallel_jobs_reserve_one_frequency_slot',capRace.every(r=>r.ok)&&capResults.filter(r=>r.allowed).length===1&&capResults.filter(r=>r.suppression_code==='FREQUENCY_CAP').length===1);
  own('obligation','safety.handover');
  const held=make('handover',{kind:'safety.handover',due:at(8)});claim(held,at(8));
  mark('handover_refuses_an_inflight_send',call('owner',{purpose:'obligation',kind:'safety.handover',producer:'legacy',now:at(8,1)}).error==='DISPATCH_IN_FLIGHT');
  // The missing-row path must hold the same keyed lock for the whole transaction.
  // Both possible ordering outcomes are safe: legacy wins before creation, or
  // ISG owns an inflight job and the competing handover must be refused.
  const registrationKind='safety.first_registration';
  const firstRegistration=`DO $$ DECLARE ep jsonb;jb jsonb;BEGIN
    PERFORM private_isg.set_producer_ownership('obligation',${q(registrationKind)},'isg_engine','live',${q(at(8))}::timestamptz);
    ep:=private_isg.open_notification_episode(${q(ownerID)}::uuid,${q(companyID)}::uuid,'obligation',${q(registrationKind)},'registration-race',1,NULL,'isg_engine',false,${q(at(8))}::timestamptz);
    jb:=private_isg.enqueue_notification((ep->>'episode_id')::uuid,'push','isg/personnel','home',100,${q(at(8))}::timestamptz,'Europe/Istanbul',${q(at(8))}::timestamptz);
    PERFORM private_isg.dispatch_notification((jb->>'job_id')::uuid,${j(device)},${q(at(8))}::timestamptz);
    PERFORM pg_sleep(0.1);
  END $$;`;
  const registrationRace=await Promise.all([
    concurrentSql(firstRegistration),
    concurrentSql(query('owner',{purpose:'obligation',kind:registrationKind,producer:'legacy',now:at(8,1)})),
  ]);
  mark('first_registration_and_handover_preserve_inflight_owner',registrationRace.every(r=>r.ok)&&sql(`SELECT NOT EXISTS(SELECT 1 FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id) JOIN private_isg.producer_ownership p ON p.purpose=e.purpose AND p.episode_kind=e.episode_kind WHERE e.episode_kind=${q(registrationKind)} AND j.state='dispatching' AND e.produced_by<>p.owner);`)==='t');
  // Re-run the inherited contract on the FINAL implementation, not just v1.
  mark('final_device_owner_gate',claim(make('wrong-device',{due:at(10)}),at(10),{...device,owner_id:randomUUID()}).suppression_code==='DEVICE_OWNER_MISMATCH');
  mark('final_category_gate',claim(make('category-off',{due:at(10)}),at(10),{...device,category_enabled:false}).suppression_code==='CATEGORY_DISABLED');
  mark('final_old_build_falls_back',claim(make('old-build',{due:at(10)}),at(10),{...device,app_build:99}).resolved_route==='home');
  ok('owner',{purpose:'obligation',kind:'safety.shadow',producer:'isg_engine',mode:'shadow',now:at(10)});
  mark('final_shadow_never_sends',claim(make('shadow',{kind:'safety.shadow',due:at(10)}),at(10)).suppression_code==='SHADOW_MODE_NO_SEND');
  own('personal_reminder','safety.alarm');
  mark('final_explicit_personal_alarm_survives_quiet_hours',claim(make('personal-alarm',{purpose:'personal_reminder',kind:'safety.alarm',due:at(10),alarm:true}),at(10,36000)).allowed===true);
  const quietStart=make('quiet-start',{due:at(10)}),quietEnd=make('quiet-end',{due:at(10)});
  mark('quiet_start_inclusive_end_exclusive',claim(quietStart,at(10,32400)).suppression_code==='QUIET_HOURS'&&claim(quietEnd,at(11,-14400)).allowed===true);
  const recovered=make('retry-success',{due:at(12)}),firstClaim=claim(recovered,at(12));
  const firstAck=finish(recovered,firstClaim.dispatch_token,'rejected','TEMPORARY_FAILURE',at(12,1)).result;
  const secondClaim=claim(recovered,at(12,31));
  const oldAck=finish(recovered,firstClaim.dispatch_token,'rejected','TEMPORARY_FAILURE',at(12,32)).result;
  const secondAck=finish(recovered,secondClaim.dispatch_token,'accepted',null,at(12,33)).result;
  mark('definitive_retry_gets_new_token_and_old_ack_does_not_reset_job',firstAck.job_state==='failed'&&secondClaim.allowed&&secondClaim.dispatch_token!==firstClaim.dispatch_token&&oldAck.replayed&&oldAck.job_state==='dispatching'&&secondAck.attempt_no===2&&secondAck.job_state==='sent');
  mark('new_functions_are_not_client_executable',sql("SELECT NOT has_function_privilege('authenticated','private_isg.complete_notification_delivery(uuid,uuid,text,text,text,timestamptz)','EXECUTE') AND NOT has_function_privilege('service_role','private_isg.complete_notification_delivery(uuid,uuid,text,text,text,timestamptz)','EXECUTE');")==='t');
  sql("UPDATE private_isg.notification_purposes SET caps_approved=false;UPDATE private_isg.notification_purposes SET daily_cap=2 WHERE purpose='operational';UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='notifications';");
  mark('rollout_kill_switch_blocks_dispatch_and_completion',call('claim',{job:held,device,now:at(9)}).error==='FEATURE_UNAVAILABLE'&&finish(single,winner.dispatch_token,'accepted',null,at(9)).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){return {migration_file:notificationDispatchFiles[0],predecessor_counterexamples:4,parallel_same_job_workers:8,parallel_cap_jobs:2,provider_called:false,production_changed:false,rollout_left_disabled:true,unknown_result_auto_retry:false};}};
}
