import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const notificationCoreFiles=[
  'supabase/migrations/20260914050000_isg_notification_core.sql',
  'scripts/isg/notification_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,5,0,0)+seconds*1000).toISOString();
// Europe/Istanbul is UTC+3: 09:00Z is 12:00 local, 19:00Z is 22:00 local.
const daytime=day=>`2026-10-${String(day).padStart(2,'0')}T09:00:00.000Z`;
const night=day=>`2026-10-${String(day).padStart(2,'0')}T19:00:00.000Z`;

export async function beginNotificationCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_NOTIFICATION_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_NOTIFICATION_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('notification_core_'+name,ok);
  sql(read(notificationCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='notifications';")==='t'&&
    sql("SELECT count(*)=4 AND count(*) FILTER (WHERE NOT caps_approved)=4 FROM private_isg.notification_purposes;")==='t');

  sql(["CREATE SCHEMA isg_notify_test;",
    "CREATE FUNCTION isg_notify_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='consent' THEN r:=private_isg.record_notification_consent((a->>'owner')::uuid,a->>'purpose',a->>'channel',(a->>'granted')::boolean,a->>'source',a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='ownership' THEN r:=private_isg.set_producer_ownership(a->>'purpose',a->>'kind',a->>'owner',a->>'mode',(a->>'now')::timestamptz);",
    "ELSIF kind='episode' THEN r:=private_isg.open_notification_episode((a->>'owner')::uuid,(a->>'company')::uuid,a->>'purpose',a->>'kind',a->>'source_ref',(a->>'schedule_version')::integer,(a->>'rule_version')::integer,a->>'producer',(a->>'explicit_alarm')::boolean,(a->>'now')::timestamptz);",
    "ELSIF kind='enqueue' THEN r:=private_isg.enqueue_notification((a->>'episode')::uuid,a->>'channel',a->>'route',a->>'fallback',(a->>'minimum_build')::integer,(a->>'scheduled_for')::timestamptz,a->>'timezone',(a->>'now')::timestamptz);",
    "ELSIF kind='dispatch' THEN r:=private_isg.dispatch_notification((a->>'job')::uuid,a->'device',(a->>'now')::timestamptz);",
    "ELSIF kind='attempt' THEN r:=private_isg.record_delivery_attempt((a->>'job')::uuid,a->>'provider',a->>'state',a->>'failure',(a->>'now')::timestamptz);",
    "ELSIF kind='force_delivered' THEN UPDATE private_isg.delivery_attempts SET delivery_confirmed=true WHERE attempt_id=(a->>'id')::uuid; r:=to_jsonb('updated'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','OS_PERMISSION_IS_NOT_CONSENT','LEGACY_OPT_OUT_PRESERVED','PRODUCER_NOT_REGISTERED','PRODUCER_NOT_OWNER','JOB_NOT_SENDABLE','SEND_TIME_CHECK_REQUIRED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_notify_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_NOTIFICATION_UNEXPECTED_'+r.error);return r.result;};

  mark('gate_blocks_the_backbone_while_rollout_off',call('consent',{owner:ownerID,purpose:'operational',channel:'push',
    granted:true,source:'onboarding',note:null,now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('notification_gate','record_notification_consent','set_producer_ownership','open_notification_episode','enqueue_notification','dispatch_notification','record_delivery_attempt') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('notification_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='notifications';");

  const consent=(over={})=>({owner:ownerID,purpose:'operational',channel:'push',granted:true,source:'onboarding',note:null,now:now(1),...over});
  mark('an_os_prompt_is_never_a_marketing_consent',
    call('consent',consent({purpose:'marketing',source:'os_permission'})).error==='OS_PERMISSION_IS_NOT_CONSENT'&&
    call('consent',consent({channel:'email',source:'os_permission'})).error==='OS_PERMISSION_IS_NOT_CONSENT');
  mark('push_and_email_consents_are_separate_records',!!ok('consent',consent())&&
    !!ok('consent',consent({channel:'email',granted:false,now:now(2)}))&&
    sql("SELECT count(*) FROM private_isg.notification_consents WHERE owner_id="+quote(ownerID)+" AND purpose='operational';")==='2'&&
    sql("SELECT granted FROM private_isg.notification_consents WHERE owner_id="+quote(ownerID)+" AND purpose='operational' AND channel='email';")==='f');
  ok('consent',consent({purpose:'marketing',granted:false,source:'settings',now:now(3)}));
  mark('a_migration_can_record_an_opt_out_but_never_overturn_one',
    call('consent',consent({purpose:'marketing',granted:true,source:'legacy_migration',now:now(4)})).error==='LEGACY_OPT_OUT_PRESERVED'&&
    sql("SELECT granted FROM private_isg.notification_consents WHERE owner_id="+quote(ownerID)+" AND purpose='marketing' AND channel='push';")==='f');
  mark('a_revoked_consent_records_when_it_was_revoked',
    sql("SELECT revoked_at IS NOT NULL FROM private_isg.notification_consents WHERE owner_id="+quote(ownerID)+" AND purpose='marketing' AND channel='push';")==='t');

  const kind='training.due_soon';
  mark('an_unregistered_episode_kind_produces_nothing',call('episode',{owner:ownerID,company:companyID,purpose:'obligation',
    kind,source_ref:'req-1',schedule_version:1,rule_version:2,producer:'isg_engine',explicit_alarm:false,now:now(10)}).error==='PRODUCER_NOT_REGISTERED');
  ok('ownership',{purpose:'obligation',kind,owner:'legacy',mode:'live',now:now(11)});
  mark('only_the_registered_owner_may_produce',call('episode',{owner:ownerID,company:companyID,purpose:'obligation',
    kind,source_ref:'req-1',schedule_version:1,rule_version:2,producer:'isg_engine',explicit_alarm:false,now:now(12)}).error==='PRODUCER_NOT_OWNER');
  const legacyEpisode=ok('episode',{owner:ownerID,company:companyID,purpose:'obligation',kind,source_ref:'req-1',
    schedule_version:1,rule_version:2,producer:'legacy',explicit_alarm:false,now:now(13)});
  const legacyJob=ok('enqueue',{episode:legacyEpisode.episode_id,channel:'push',route:'isg/requirement/req-1',
    fallback:'home',minimum_build:100,scheduled_for:daytime(1),timezone:'Europe/Istanbul',now:now(14)});
  mark('an_episode_and_a_job_are_created_once',ok('episode',{owner:ownerID,company:companyID,purpose:'obligation',kind,
    source_ref:'req-1',schedule_version:1,rule_version:2,producer:'legacy',explicit_alarm:false,now:now(15)}).replayed===true&&
    ok('enqueue',{episode:legacyEpisode.episode_id,channel:'push',route:'isg/requirement/req-1',fallback:'home',
      minimum_build:100,scheduled_for:daytime(1),timezone:'Europe/Istanbul',now:now(16)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.notification_jobs;")==='1');
  const handover=ok('ownership',{purpose:'obligation',kind,owner:'isg_engine',mode:'shadow',now:now(17)});
  mark('a_handover_cancels_what_the_previous_owner_left_pending',handover.cancelled_pending===1&&
    sql("SELECT state||':'||suppression_code FROM private_isg.notification_jobs WHERE job_id="+quote(legacyJob.job_id)+";")==='cancelled:PRODUCER_HANDOVER');
  const shadowEpisode=ok('episode',{owner:ownerID,company:companyID,purpose:'obligation',kind,source_ref:'req-2',
    schedule_version:1,rule_version:2,producer:'isg_engine',explicit_alarm:false,now:now(18)});
  const shadowJob=ok('enqueue',{episode:shadowEpisode.episode_id,channel:'push',route:'isg/requirement/req-2',
    fallback:'home',minimum_build:100,scheduled_for:daytime(2),timezone:'Europe/Istanbul',now:now(19)});
  const device={owner_id:ownerID,app_build:120,category_enabled:true};
  mark('a_shadow_producer_never_sends',ok('dispatch',{job:shadowJob.job_id,device,now:now(20)}).suppression_code==='SHADOW_MODE_NO_SEND'&&
    sql("SELECT count(*) FROM private_isg.delivery_attempts;")==='0');
  mark('a_suppressed_job_can_not_be_sent',call('attempt',{job:shadowJob.job_id,provider:'fcm',state:'accepted',failure:null,now:now(21)}).error==='JOB_NOT_SENDABLE');
  ok('ownership',{purpose:'obligation',kind,owner:'isg_engine',mode:'live',now:now(22)});

  const episodeFor=(ref,over={})=>ok('episode',{owner:ownerID,company:companyID,purpose:'obligation',kind,source_ref:ref,
    schedule_version:1,rule_version:2,producer:'isg_engine',explicit_alarm:false,now:now(30),...over});
  const jobFor=(episode,over={})=>ok('enqueue',{episode,channel:'push',route:'isg/requirement/new',fallback:'home',
    minimum_build:100,scheduled_for:daytime(3),timezone:'Europe/Istanbul',now:now(31),...over});
  const liveJob=jobFor(episodeFor('req-3').episode_id);
  mark('a_send_time_check_is_required_before_any_attempt',call('attempt',{job:liveJob.job_id,provider:'fcm',
    state:'accepted',failure:null,now:now(32)}).error==='SEND_TIME_CHECK_REQUIRED');
  const allowed=ok('dispatch',{job:liveJob.job_id,device,now:now(33)});
  mark('an_allowed_job_resolves_its_route',allowed.allowed===true&&allowed.resolved_route==='isg/requirement/new'&&
    allowed.route_downgraded===false&&allowed.delivered===false);
  const accepted=ok('attempt',{job:liveJob.job_id,provider:'fcm',state:'accepted',failure:null,now:now(34)});
  mark('provider_accepted_is_not_delivered_or_read',accepted.job_state==='sent'&&accepted.delivery_confirmed===false&&
    accepted.read_confirmed===false&&call('force_delivered',{id:accepted.attempt_id}).error==='CHECK_VIOLATION');
  const failing=jobFor(episodeFor('req-4').episode_id,{scheduled_for:daytime(4)});
  ok('dispatch',{job:failing.job_id,device,now:now(35)});
  const rejected=ok('attempt',{job:failing.job_id,provider:'fcm',state:'rejected',failure:'TOKEN_INVALID',now:now(36)});
  mark('a_rejected_attempt_leaves_the_job_failed_and_retryable',rejected.job_state==='failed'&&
    ok('attempt',{job:failing.job_id,provider:'fcm',state:'accepted',failure:null,now:now(37)}).attempt_no===2);

  const oldBuild=jobFor(episodeFor('req-5').episode_id,{scheduled_for:daytime(5),route:'isg/company/other/new-screen',fallback:'home'});
  const downgraded=ok('dispatch',{job:oldBuild.job_id,device:{...device,app_build:99},now:now(40)});
  mark('an_old_build_gets_the_safe_existing_screen',downgraded.route_downgraded===true&&downgraded.resolved_route==='home');
  const foreign=jobFor(episodeFor('req-6').episode_id,{scheduled_for:daytime(6)});
  mark('another_account_device_is_never_sent_to',ok('dispatch',{job:foreign.job_id,device:{...device,owner_id:randomUUID()},now:now(41)}).suppression_code==='DEVICE_OWNER_MISMATCH');
  const categoryOff=jobFor(episodeFor('req-7').episode_id,{scheduled_for:daytime(7)});
  mark('a_disabled_category_suppresses_the_job',ok('dispatch',{job:categoryOff.job_id,device:{...device,category_enabled:false},now:now(42)}).suppression_code==='CATEGORY_DISABLED');
  const quiet=jobFor(episodeFor('req-8').episode_id,{scheduled_for:night(8)});
  mark('quiet_hours_suppress_a_business_notification',ok('dispatch',{job:quiet.job_id,device,now:now(43)}).suppression_code==='QUIET_HOURS');

  ok('ownership',{purpose:'personal_reminder',kind:'note.reminder',owner:'isg_engine',mode:'live',now:now(50)});
  const alarmEpisode=ok('episode',{owner:ownerID,company:null,purpose:'personal_reminder',kind:'note.reminder',
    source_ref:'note-1',schedule_version:1,rule_version:null,producer:'isg_engine',explicit_alarm:true,now:now(51)});
  const alarmJob=ok('enqueue',{episode:alarmEpisode.episode_id,channel:'push',route:'notes/note-1',fallback:'home',
    minimum_build:100,scheduled_for:night(9),timezone:'Europe/Istanbul',now:now(52)});
  mark('an_explicit_personal_alarm_is_not_silenced_by_quiet_hours',ok('dispatch',{job:alarmJob.job_id,device,now:now(53)}).allowed===true);
  mark('an_explicit_alarm_belongs_only_to_a_personal_reminder',call('episode',{owner:ownerID,company:companyID,
    purpose:'obligation',kind,source_ref:'req-9',schedule_version:1,rule_version:2,producer:'isg_engine',
    explicit_alarm:true,now:now(54)}).error==='VALIDATION_ERROR');

  ok('ownership',{purpose:'operational',kind:'ops.daily',owner:'isg_engine',mode:'live',now:now(60)});
  const operational=(ref,day)=>{
    const episode=ok('episode',{owner:ownerID,company:companyID,purpose:'operational',kind:'ops.daily',source_ref:ref,
      schedule_version:1,rule_version:null,producer:'isg_engine',explicit_alarm:false,now:now(61)});
    return ok('enqueue',{episode:episode.episode_id,channel:'push',route:'ops/'+ref,fallback:'home',minimum_build:100,
      scheduled_for:daytime(day),timezone:'Europe/Istanbul',now:now(62)});
  };
  const first=operational('ops-1',12),second=operational('ops-2',12),third=operational('ops-3',12);
  ok('consent',consent({purpose:'operational',now:now(63)}));
  ok('dispatch',{job:first.job_id,device,now:now(64)}); ok('attempt',{job:first.job_id,provider:'fcm',state:'accepted',failure:null,now:now(65)});
  ok('dispatch',{job:second.job_id,device,now:now(66)}); ok('attempt',{job:second.job_id,provider:'fcm',state:'accepted',failure:null,now:now(67)});
  mark('a_daily_cap_suppresses_the_third_operational_message',ok('dispatch',{job:third.job_id,device,now:now(68)}).suppression_code==='FREQUENCY_CAP'&&
    sql("SELECT count(*) FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id) WHERE e.purpose='operational' AND j.state='sent';")==='2');
  const nextDay=operational('ops-4',13);
  mark('the_cap_window_is_the_local_day',ok('dispatch',{job:nextDay.job_id,device,now:now(69)}).allowed===true);

  ok('ownership',{purpose:'marketing',kind:'campaign.winback',owner:'isg_engine',mode:'live',now:now(70)});
  const marketingEpisode=ok('episode',{owner:ownerID,company:null,purpose:'marketing',kind:'campaign.winback',
    source_ref:'camp-1',schedule_version:1,rule_version:null,producer:'isg_engine',explicit_alarm:false,now:now(71)});
  const marketingJob=ok('enqueue',{episode:marketingEpisode.episode_id,channel:'push',route:'campaign/camp-1',
    fallback:'home',minimum_build:100,scheduled_for:daytime(14),timezone:'Europe/Istanbul',now:now(72)});
  mark('marketing_without_an_explicit_consent_is_suppressed',ok('dispatch',{job:marketingJob.job_id,device,now:now(73)}).suppression_code==='CONSENT_REVOKED');
  ok('consent',consent({purpose:'marketing',granted:true,source:'settings',now:now(74)}));
  const marketingSecond=ok('enqueue',{episode:ok('episode',{owner:ownerID,company:null,purpose:'marketing',
    kind:'campaign.winback',source_ref:'camp-2',schedule_version:1,rule_version:null,producer:'isg_engine',
    explicit_alarm:false,now:now(75)}).episode_id,channel:'push',route:'campaign/camp-2',fallback:'home',
    minimum_build:100,scheduled_for:daytime(15),timezone:'Europe/Istanbul',now:now(76)});
  ok('dispatch',{job:marketingSecond.job_id,device,now:now(77)});
  ok('attempt',{job:marketingSecond.job_id,provider:'fcm',state:'accepted',failure:null,now:now(78)});
  const marketingThird=ok('enqueue',{episode:ok('episode',{owner:ownerID,company:null,purpose:'marketing',
    kind:'campaign.winback',source_ref:'camp-3',schedule_version:1,rule_version:null,producer:'isg_engine',
    explicit_alarm:false,now:now(79)}).episode_id,channel:'push',route:'campaign/camp-3',fallback:'home',
    minimum_build:100,scheduled_for:daytime(16),timezone:'Europe/Istanbul',now:now(80)});
  mark('a_weekly_cap_holds_the_next_campaign',ok('dispatch',{job:marketingThird.job_id,device,now:now(81)}).suppression_code==='FREQUENCY_CAP');
  ok('consent',consent({purpose:'marketing',granted:false,source:'settings',now:now(82)}));
  const afterRevoke=ok('enqueue',{episode:ok('episode',{owner:ownerID,company:null,purpose:'marketing',
    kind:'campaign.winback',source_ref:'camp-4',schedule_version:1,rule_version:null,producer:'isg_engine',
    explicit_alarm:false,now:now(83)}).episode_id,channel:'push',route:'campaign/camp-4',fallback:'home',
    minimum_build:100,scheduled_for:daytime(30),timezone:'Europe/Istanbul',now:now(84)});
  mark('consent_revoked_after_enqueue_stops_the_send',ok('dispatch',{job:afterRevoke.job_id,device,now:now(85)}).suppression_code==='CONSENT_REVOKED');
  mark('the_legacy_notification_queue_is_untouched',sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('notification_jobs','notification_episodes') AND column_name IN ('legacy_notification_id','notification_type');")==='0');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='notifications';");
  mark('kill_switch_stops_the_backbone',call('dispatch',{job:afterRevoke.job_id,device,now:now(90)}).error==='FEATURE_UNAVAILABLE'&&
    call('consent',consent({now:now(91)})).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:notificationCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,legacy_queue_written:false,real_provider_connected:false,
      delivery_or_read_claimed:false,caps_approved:false,production_deployed:false};
  }};
}
