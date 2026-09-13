import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const campaignCoreFiles=[
  'supabase/migrations/20260914110000_isg_campaign_core.sql',
  'scripts/isg/campaign_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const base=Date.UTC(2026,8,14,11,0,0);
const now=seconds=>new Date(base+seconds*1000).toISOString();
const hours=n=>n*3600;
const days=n=>n*86400;

export async function beginCampaignCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_CAMPAIGN_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('AUTH_RESTORE_CAMPAIGN_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('campaign_core_'+name,ok);
  sql(read(campaignCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='campaigns';")==='t');

  sql(["CREATE SCHEMA isg_campaign_test;",
    "CREATE FUNCTION isg_campaign_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; err_code text; BEGIN",
    "IF kind='publish' THEN r:=private_isg.publish_campaign_version((a->>'version')::uuid,(a->>'approver')::uuid,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='pause' THEN r:=private_isg.pause_campaign_version((a->>'version')::uuid,a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='code' THEN r:=private_isg.issue_referral_code((a->>'owner')::uuid,(a->>'campaign')::uuid,a->>'code',(a->>'now')::timestamptz);",
    "ELSIF kind='claim' THEN r:=private_isg.claim_referral(a->>'code',(a->>'invitee')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='event' THEN r:=private_isg.record_qualification_event((a->>'owner')::uuid,a->>'event_kind',(a->>'operation')::uuid,",
    "  (a->>'occurred_on')::date,a->>'timezone',(a->>'now')::timestamptz);",
    "ELSIF kind='evaluate' THEN r:=private_isg.evaluate_referral_qualification((a->>'claim')::uuid,(a->>'version')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='award' THEN r:=private_isg.award_referral_reward((a->>'claim')::uuid,(a->>'version')::uuid,a->>'period',a->>'plan_period',(a->>'now')::timestamptz);",
    "ELSIF kind='budget' THEN r:=private_isg.reserve_campaign_budget((a->>'version')::uuid,a->>'period',(a->>'owner')::uuid,(a->>'amount')::bigint,(a->>'now')::timestamptz);",
    "ELSIF kind='eligibility' THEN r:=private_isg.winback_eligibility((a->>'owner')::uuid,(a->>'campaign')::uuid,a->>'plan_period',(a->>'now')::timestamptz);",
    "ELSIF kind='episode' THEN r:=private_isg.open_winback_episode((a->>'owner')::uuid,(a->>'version')::uuid,a->>'plan_period',(a->>'now')::timestamptz);",
    "ELSIF kind='contact' THEN r:=private_isg.record_winback_contact((a->>'episode')::uuid,a->>'channel',(a->>'now')::timestamptz);",
    "ELSIF kind='resolve' THEN r:=private_isg.resolve_winback_episode((a->>'episode')::uuid,a->>'outcome',a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='force_forbidden_event' THEN INSERT INTO private_isg.qualification_events(owner_id,event_kind,operation_id,",
    "  occurred_on,account_timezone) VALUES((a->>'owner')::uuid,'screen_view',gen_random_uuid(),'2026-09-14','Europe/Istanbul'); r:=to_jsonb('inserted'::text);",
    "ELSIF kind='force_client_proof' THEN UPDATE private_isg.qualification_events SET proof_source='client_report'; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_delivery_claim' THEN UPDATE private_isg.winback_contacts SET delivery_claimed=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_ttl_reset' THEN UPDATE private_isg.suppression_records SET ttl_reset=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_approved_cap' THEN UPDATE private_isg.campaign_budgets SET cap_approved=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_publish_without_approval' THEN UPDATE private_isg.campaign_versions SET status='published',published_at=(a->>'now')::timestamptz",
    "  WHERE version_id=(a->>'version')::uuid; r:=to_jsonb('updated'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS err_code=MESSAGE_TEXT;",
    "IF err_code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','SELF_REFERRAL','CYCLE_DETECTED',",
    "  'ALREADY_CLAIMED','NOT_QUALIFIED','CAMPAIGN_UNAVAILABLE','CAMPAIGN_PAUSED','BUDGET_EXHAUSTED','EPISODE_EXISTS',",
    "  'NOT_ELIGIBLE','TOO_EARLY','SUPPRESSED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',err_code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_campaign_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_CAMPAIGN_UNEXPECTED_'+r.error);return r.result;};

  // Own accounts, so nothing here depends on what an earlier probe left behind.
  const invitee=randomUUID(), leaver=randomUUID(), latecomer=randomUUID();
  sql("INSERT INTO auth.users(id) VALUES("+quote(invitee)+"),("+quote(leaver)+"),("+quote(latecomer)+");"+
    "INSERT INTO public.profiles(id,tier) VALUES("+quote(invitee)+",'free'),("+quote(leaver)+",'free'),("+quote(latecomer)+",'free');");
  // The P14 slice left exactly one account whose store lifecycle is unreadable.
  const unreadableOwner=sql("SELECT owner_id FROM private_isg.billing_lifecycle_projection WHERE lifecycle_state='unknown' LIMIT 1;");
  const referralID=randomUUID(), winbackID=randomUUID(), referralVersion=randomUUID(), winbackVersion=randomUUID();
  sql(["INSERT INTO private_isg.campaign_definitions(campaign_id,code,family) VALUES("+quote(referralID)+",'referral_v5','referral'),("+quote(winbackID)+",'winback_v5','winback');",
    "INSERT INTO private_isg.campaign_versions(version_id,campaign_id,revision,qualification_days,qualification_window_days,inviter_reward_code,invitee_reward_code)",
    "  VALUES("+quote(referralVersion)+","+quote(referralID)+",1,2,30,'monthly_discount_one_period','sponsor_gift_plus_7d');",
    "INSERT INTO private_isg.campaign_versions(version_id,campaign_id,revision,qualification_days,qualification_window_days,wait_hours,accept_days,max_contacts,second_contact_gap_days,winback_reward_code)",
    "  VALUES("+quote(winbackVersion)+","+quote(winbackID)+",1,2,30,72,14,2,7,'monthly_discount_one_period');"].join('\n'));
  mark('gate_blocks_the_campaign_ledger_while_rollout_off',
    call('code',{owner:ownerID,campaign:referralID,code:'ABC123',now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('campaign_gate','publish_campaign_version','pause_campaign_version','issue_referral_code','claim_referral','record_qualification_event','evaluate_referral_qualification','reserve_campaign_budget','settle_campaign_budget','award_referral_reward','winback_eligibility','open_winback_episode','record_winback_contact','resolve_winback_episode') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('campaign_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  // Abuse evidence has no row shape: no address, network or device is stored.
  mark('no_address_network_or_device_column_exists',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('referral_codes','referral_claims','qualification_events','winback_episodes','winback_contacts','suppression_records','eligibility_checks') AND column_name ~ '(email|ip_|_ip|address|device|fingerprint|relay|user_agent)';")==='0');
  mark('a_campaign_version_can_not_publish_itself_without_a_human',
    call('force_publish_without_approval',{version:referralVersion,now:now(1)}).error==='CHECK_VIOLATION');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('campaigns','billing_lifecycle');");

  const approver=randomUUID();
  const published=ok('publish',{version:referralVersion,approver,note:'ticari onay kaydı',now:now(3)});
  ok('publish',{version:winbackVersion,approver,note:'ticari onay kaydı',now:now(3)});
  mark('publication_records_the_human_and_keeps_the_values_unapproved',published.status==='published'&&
    published.values_approved===false&&published.needs_review===true&&
    ok('publish',{version:referralVersion,approver,note:'tekrar',now:now(4)}).replayed===true&&
    sql("SELECT approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL FROM private_isg.campaign_versions WHERE version_id="+quote(referralVersion)+";")==='t');

  const code=ok('code',{owner:ownerID,campaign:referralID,code:'ABC123',now:now(5)});
  mark('a_code_belongs_to_one_canonical_account',code.code==='ABC123'&&
    ok('code',{owner:ownerID,campaign:referralID,code:'ZZZ999',now:now(6)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.referral_codes WHERE owner_id="+quote(ownerID)+";")==='1');
  mark('nobody_invites_themselves',call('claim',{code:'ABC123',invitee:ownerID,now:now(7)}).error==='SELF_REFERRAL');
  const claim=ok('claim',{code:'ABC123',invitee,now:now(8)});
  mark('one_invitee_belongs_to_one_family_once',claim.state==='claimed'&&
    call('claim',{code:'ABC123',invitee,now:now(9)}).error==='ALREADY_CLAIMED');
  const inviteeCode=ok('code',{owner:invitee,campaign:referralID,code:'BBB222',now:now(10)});
  mark('an_invited_account_can_not_invite_its_own_inviter_back',inviteeCode.code==='BBB222'&&
    call('claim',{code:'BBB222',invitee:ownerID,now:now(11)}).error==='CYCLE_DETECTED');

  // Only a completed server mutation qualifies, and only on distinct days.
  mark('a_screen_view_has_no_row_shape_and_a_client_claim_is_refused',
    call('force_forbidden_event',{owner:invitee}).error==='CHECK_VIOLATION');
  const firstOperation=randomUUID();
  const day=(d,kind,offset,operation)=>ok('event',{owner:invitee,event_kind:kind,operation:operation||randomUUID(),
    occurred_on:d,timezone:'Europe/Istanbul',now:now(offset)});
  day('2026-09-14','employee_created',hours(1),firstOperation);
  mark('one_day_of_work_is_not_enough',
    ok('evaluate',{claim:claim.claim_id,version:referralVersion,now:now(hours(2))}).qualified===false);
  mark('the_same_operation_is_never_counted_twice',
    day('2026-09-15','employee_created',hours(3),firstOperation).replayed===true&&
    sql("SELECT count(*) FROM private_isg.qualification_events WHERE owner_id="+quote(invitee)+";")==='1');
  // A draft revision of the same campaign qualifies nobody.
  const draftVersion=randomUUID();
  sql("INSERT INTO private_isg.campaign_versions(version_id,campaign_id,revision,qualification_days,qualification_window_days) VALUES("+quote(draftVersion)+","+quote(referralID)+",2,2,30);");
  mark('an_unpublished_revision_qualifies_nobody',
    call('evaluate',{claim:claim.claim_id,version:draftVersion,now:now(hours(4))}).error==='CAMPAIGN_UNAVAILABLE');
  day('2026-09-16','workplace_created',days(2));
  const qualified=ok('evaluate',{claim:claim.claim_id,version:referralVersion,now:now(days(2)+hours(1))});
  mark('two_distinct_days_of_real_work_qualify_without_marketing_consent',qualified.qualified===true&&
    qualified.distinct_days===2&&qualified.marketing_consent_required===false&&
    ok('evaluate',{claim:claim.claim_id,version:referralVersion,now:now(days(2)+hours(2))}).replayed===true);
  mark('a_client_can_not_relabel_its_own_proof',call('force_client_proof',{}).error==='CHECK_VIOLATION');

  mark('no_reward_without_a_budget_row',
    call('award',{claim:claim.claim_id,version:referralVersion,period:'2026-09',plan_period:'monthly',
      now:now(days(2)+hours(3))}).error==='VALIDATION_ERROR');
  sql("INSERT INTO private_isg.campaign_budgets(version_id,period_key,cap_amount) VALUES("+quote(referralVersion)+",'2026-09',2);");
  mark('an_approved_looking_cap_is_impossible',call('force_approved_cap',{}).error==='CHECK_VIOLATION');
  // The inviter has an active production subscription from the P14 slice.
  const monthly=ok('award',{claim:claim.claim_id,version:referralVersion,period:'2026-09',plan_period:'monthly',
    now:now(days(2)+hours(4))});
  mark('a_paid_monthly_inviter_gets_a_discount_and_the_invitee_a_gift',monthly.state==='rewarded'&&
    monthly.inviter_branch==='paid_monthly'&&monthly.inviter_reward_kind==='discount_coupon'&&
    monthly.capability_opened===false&&monthly.needs_review===true&&
    sql("SELECT benefit_kind FROM private_isg.benefit_definitions d JOIN private_isg.benefit_instances i ON i.definition_id=d.definition_id WHERE i.owner_id="+quote(invitee)+" AND i.family_key LIKE 'referral-invitee:%';")==='gift_access');
  mark('the_reward_is_committed_against_the_budget',
    sql("SELECT state||':'||amount FROM private_isg.budget_reservations WHERE version_id="+quote(referralVersion)+";")==='committed:1'&&
    ok('award',{claim:claim.claim_id,version:referralVersion,period:'2026-09',plan_period:'monthly',
      now:now(days(2)+hours(5))}).replayed===true);

  const annualInvitee=leaver;
  const annualClaim=ok('claim',{code:'ABC123',invitee:annualInvitee,now:now(days(3))});
  day2(sql,quote,randomUUID,ok,annualInvitee,now,days);
  ok('evaluate',{claim:annualClaim.claim_id,version:referralVersion,now:now(days(6))});
  const annual=ok('award',{claim:annualClaim.claim_id,version:referralVersion,period:'2026-09',plan_period:'annual',
    now:now(days(6)+hours(1))});
  // An annual inviter is never converted to monthly and never read as Free.
  mark('an_annual_inviter_takes_no_branch_and_is_not_treated_as_free',annual.state==='rejected'&&
    annual.reject_code==='UNSUPPORTED_BRANCH'&&annual.auto_plan_conversion===false&&annual.treated_as_free===false&&
    sql("SELECT count(*) FROM private_isg.suppression_records WHERE decided_at_stage='reward' AND reason='not_eligible';")==='1');

  // Winback: never subscribed, unreadable, still paying, and really left.
  const never=ok('eligibility',{owner:latecomer,campaign:winbackID,plan_period:'monthly',now:now(days(7))});
  const unreadable=ok('eligibility',{owner:unreadableOwner,campaign:winbackID,plan_period:'monthly',now:now(days(7))});
  mark('an_account_that_never_paid_or_can_not_be_read_is_no_candidate',never.eligible===false&&
    never.reason_code==='NEVER_SUBSCRIBED'&&unreadable.eligible===false&&
    unreadable.reason_code==='UNKNOWN_LIFECYCLE');
  const stillPaying=ok('eligibility',{owner:ownerID,campaign:winbackID,plan_period:'monthly',now:now(days(7))});
  mark('an_active_subscriber_is_not_a_winback_candidate',stillPaying.eligible===false&&
    stillPaying.reason_code==='OTHER_STORE_ACTIVE');
  const ref='GPA.7777-6666-5555-44444';
  const bought=ok2(sql,quote,leaver,ref,'purchase','active',now(days(8)),100);
  ok2(sql,quote,leaver,ref,'expiration','expired',now(days(9)),110);
  const leftFor=ok('eligibility',{owner:leaver,campaign:winbackID,plan_period:'monthly',now:now(days(10))});
  mark('a_real_expired_monthly_payer_is_eligible',leftFor.eligible===true&&leftFor.reason_code==='ELIGIBLE'&&
    leftFor.positive_payment===true&&bought===true);
  mark('an_annual_or_unknown_plan_period_is_refused_with_its_own_reason',
    ok('eligibility',{owner:leaver,campaign:winbackID,plan_period:'annual',now:now(days(10))}).reason_code==='ANNUAL_PLAN'&&
    ok('eligibility',{owner:leaver,campaign:winbackID,plan_period:'unknown',now:now(days(10))}).reason_code==='UNKNOWN_PLAN_PERIOD');

  const refused=ok('episode',{owner:latecomer,version:winbackVersion,plan_period:'monthly',now:now(days(10))});
  mark('a_refused_episode_is_written_down_instead_of_disappearing',refused.opened===false&&
    refused.reason_code==='NEVER_SUBSCRIBED'&&
    sql("SELECT count(*) FROM private_isg.suppression_records WHERE decided_at_stage='open' AND owner_id="+quote(latecomer)+";")==='1');
  const episode=ok('episode',{owner:leaver,version:winbackVersion,plan_period:'monthly',now:now(days(10))});
  mark('an_episode_waits_the_candidate_seventy_two_hours',episode.opened===true&&episode.timing_approved===false&&
    sql("SELECT contactable_from=became_eligible_at+interval '72 hours' AND accept_until=contactable_from+interval '14 days' FROM private_isg.winback_episodes WHERE episode_id="+quote(episode.episode_id)+";")==='t');
  mark('a_family_opens_one_episode_for_a_lifetime',
    call('episode',{owner:leaver,version:winbackVersion,plan_period:'monthly',now:now(days(11))}).error==='EPISODE_EXISTS');
  mark('nothing_is_sent_before_the_waiting_time',
    call('contact',{episode:episode.episode_id,channel:'push',now:now(days(10)+hours(71))}).error==='TOO_EARLY');
  const noConsent=ok('contact',{episode:episode.episode_id,channel:'push',now:now(days(13)+hours(1))});
  mark('an_os_permission_is_not_a_marketing_consent',noConsent.contacted===false&&
    noConsent.reason==='consent_missing'&&noConsent.ttl_reset===false&&noConsent.episode_closed===false&&
    sql("SELECT count(*) FROM private_isg.winback_contacts;")==='0'&&
    sql("SELECT state FROM private_isg.winback_episodes WHERE episode_id="+quote(episode.episode_id)+";")==='waiting');
  sql("INSERT INTO private_isg.notification_consents(owner_id,purpose,channel,granted,source,captured_at) VALUES("+quote(leaver)+",'marketing','push',true,'onboarding',"+quote(now(days(12)))+");");
  const contacted=ok('contact',{episode:episode.episode_id,channel:'push',now:now(days(13)+hours(2))});
  mark('a_consented_contact_is_an_attempt_and_not_a_delivery',contacted.contacted===true&&
    contacted.ordinal===1&&contacted.delivery_claimed===false&&
    call('force_delivery_claim',{}).error==='CHECK_VIOLATION');
  mark('a_second_contact_waits_its_own_gap',
    call('contact',{episode:episode.episode_id,channel:'push',now:now(days(14))}).error==='TOO_EARLY');

  const acceptUntil=sql("SELECT accept_until FROM private_isg.winback_episodes WHERE episode_id="+quote(episode.episode_id)+";");
  ok2(sql,quote,leaver,ref,'purchase','active',now(days(20)),200);
  const resubscribed=ok('contact',{episode:episode.episode_id,channel:'push',now:now(days(21))});
  mark('resubscribing_during_the_send_suppresses_without_resetting_the_clock',resubscribed.contacted===false&&
    resubscribed.reason==='resubscribed'&&resubscribed.ttl_reset===false&&
    sql("SELECT accept_until FROM private_isg.winback_episodes WHERE episode_id="+quote(episode.episode_id)+";")===acceptUntil&&
    call('force_ttl_reset',{}).error==='CHECK_VIOLATION');
  mark('a_suppressed_episode_accepts_no_further_contact',
    call('contact',{episode:episode.episode_id,channel:'push',now:now(days(22))}).error==='SUPPRESSED'&&
    call('resolve',{episode:episode.episode_id,outcome:'accepted',reason:'geç kabul',now:now(days(22))}).error==='SUPPRESSED');

  const lateClaim=ok('claim',{code:'ABC123',invitee:latecomer,now:now(days(22))});
  ok('event',{owner:latecomer,event_kind:'employee_created',operation:randomUUID(),occurred_on:'2026-09-20',
    timezone:'Europe/Istanbul',now:now(days(22))});
  ok('event',{owner:latecomer,event_kind:'risk_assessment_created',operation:randomUUID(),occurred_on:'2026-09-21',
    timezone:'Europe/Istanbul',now:now(days(22)+hours(1))});
  ok('evaluate',{claim:lateClaim.claim_id,version:referralVersion,now:now(days(22)+hours(2))});
  const paused=ok('pause',{version:referralVersion,reason:'bütçe incelemesi',now:now(days(23))});
  mark('a_pause_stops_new_production_and_keeps_what_was_earned',paused.rewarded_claims_kept===1&&
    paused.earned_benefits_revoked===false&&paused.settlements_revoked===false&&
    sql("SELECT count(*) FROM private_isg.benefit_instances WHERE family_key LIKE 'referral-%';")==='2'&&
    ok('pause',{version:referralVersion,reason:'tekrar',now:now(days(24))}).replayed===true);
  mark('a_paused_campaign_rewards_nobody_new_even_when_qualified',
    sql("SELECT state FROM private_isg.referral_claims WHERE claim_id="+quote(lateClaim.claim_id)+";")==='qualified'&&
    call('award',{claim:lateClaim.claim_id,version:referralVersion,period:'2026-09',plan_period:'monthly',
      now:now(days(25))}).error==='CAMPAIGN_PAUSED');
  mark('the_budget_refuses_the_third_reward_of_a_two_reward_period',
    ok('budget',{version:referralVersion,period:'2026-09',owner:ownerID,amount:1,now:now(days(26))}).state==='reserved'&&
    call('budget',{version:referralVersion,period:'2026-09',owner:ownerID,amount:1,now:now(days(26))}).error==='BUDGET_EXHAUSTED');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('campaigns','billing_lifecycle');");
  mark('kill_switch_stops_every_campaign_producer',
    call('claim',{code:'ABC123',invitee:randomUUID(),now:now(days(30))}).error==='FEATURE_UNAVAILABLE'&&
    call('eligibility',{owner:leaver,campaign:winbackID,plan_period:'monthly',now:now(days(30))}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:campaignCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,commercial_values_approved:false,marketing_sent:false,
      delivery_claimed:false,ttl_reset_possible:false,store_offer_created:false,
      abuse_signal_from_network_or_address:false,production_deployed:false};
  }};
}
// Two distinct qualifying days for a second invitee.
function day2(sql,quote,uuid,ok,owner,now,days){
  ok('event',{owner,event_kind:'employee_created',operation:uuid(),occurred_on:'2026-09-17',
    timezone:'Europe/Istanbul',now:now(days(4))});
  ok('event',{owner,event_kind:'department_created',operation:uuid(),occurred_on:'2026-09-18',
    timezone:'Europe/Istanbul',now:now(days(5))});
}
// One raw store evidence row plus its projection, written through P14.
function ok2(sql,quote,owner,ref,kind,state,at,sequence){
  sql("SELECT private_isg.record_billing_evidence("+quote(owner)+",'production','google','rd_plus_monthly',"+
    quote(ref)+","+quote(kind)+","+quote(state)+","+quote(at)+","+sequence+",'webhook','{\"store\":\"google\"}'::jsonb,"+quote(at)+");");
  sql("SELECT private_isg.project_billing_lifecycle((SELECT evidence_id FROM private_isg.billing_lifecycle_evidence WHERE purchase_ref="+
    quote(ref)+" AND sequence_no="+sequence+"),true,NULL,"+quote(at)+");");
  return true;
}
