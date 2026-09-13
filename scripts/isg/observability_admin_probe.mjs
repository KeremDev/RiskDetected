import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const observabilityAdminFiles=[
  'supabase/migrations/20260914130000_isg_observability_admin.sql',
  'scripts/isg/observability_admin_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,13,0,0)+seconds*1000).toISOString();

export async function beginObservabilityAdminProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_OBSERVABILITY_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('AUTH_RESTORE_OBSERVABILITY_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('observability_admin_'+name,ok);
  sql(read(observabilityAdminFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='observability';")==='t');

  sql(["CREATE SCHEMA isg_observability_test;",
    "CREATE FUNCTION isg_observability_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; err_code text; BEGIN",
    "IF kind='chain' THEN r:=private_isg.start_support_chain(a->>'support',(a->>'owner')::uuid,a->>'environment',",
    "  a->>'build',a->>'platform',(a->>'trace')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='event' THEN r:=private_isg.record_technical_event(a->>'support',a->>'stage',a->>'outcome',a->>'reason',",
    "  (a->>'request')::uuid,(a->>'operation')::uuid,(a->>'retry')::integer,(a->>'latency')::integer,a->'metadata',(a->>'now')::timestamptz);",
    "ELSIF kind='close' THEN r:=private_isg.close_support_chain(a->>'support',a->>'outcome',(a->>'now')::timestamptz);",
    "ELSIF kind='queue' THEN r:=private_isg.record_queue_report((a->>'owner')::uuid,(a->>'installation')::uuid,",
    "  (a->>'capacity')::integer,(a->>'dropped')::bigint,(a->>'oldest')::timestamptz,(a->>'transport')::boolean,(a->>'now')::timestamptz);",
    "ELSIF kind='attribution' THEN r:=private_isg.record_attribution((a->>'owner')::uuid,(a->>'authorized')::boolean,a->>'source',(a->>'now')::timestamptz);",
    "ELSIF kind='session' THEN r:=private_isg.open_admin_session((a->>'admin')::uuid,a->>'aal',",
    "  ARRAY(SELECT jsonb_array_elements_text(a->'scopes')),(a->>'expires')::timestamptz,(a->>'now')::timestamptz);",
    "ELSIF kind='simulate' THEN r:=private_isg.simulate_admin_action((a->>'session')::uuid,a->>'action_kind',a->>'scope',",
    "  a->>'target',a->'report',(a->>'now')::timestamptz);",
    "ELSIF kind='publish' THEN r:=private_isg.publish_admin_action((a->>'session')::uuid,(a->>'action')::uuid,a->'payload',(a->>'now')::timestamptz);",
    "ELSIF kind='export' THEN r:=private_isg.request_admin_export((a->>'session')::uuid,(a->>'action')::uuid,a->>'dataset',",
    "  ARRAY(SELECT jsonb_array_elements_text(a->'columns')),(a->>'rows')::bigint,(a->>'now')::timestamptz);",
    "ELSIF kind='pause' THEN r:=private_isg.set_admin_write_pause((a->>'paused')::boolean,a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='billing_still_works' THEN r:=private_isg.record_billing_evidence((a->>'owner')::uuid,'production','apple',",
    "  'rd_plus_monthly_ios',a->>'ref','renewal','active',(a->>'now')::timestamptz,(a->>'sequence')::bigint,'webhook',",
    "  '{\"store\":\"apple\"}'::jsonb,(a->>'now')::timestamptz);",
    "ELSIF kind='force_user_content' THEN UPDATE private_isg.technical_events SET carries_user_content=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_identifier' THEN UPDATE private_isg.attribution_records SET identifier_stored=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_third_party' THEN UPDATE private_isg.attribution_records SET third_party_sdk_called=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_blocking_queue' THEN UPDATE private_isg.telemetry_queue_reports SET blocks_domain=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_publish_without_audit' THEN UPDATE private_isg.admin_actions SET state='published',",
    "  published_at=(a->>'now')::timestamptz WHERE action_id=(a->>'action')::uuid; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_raw_pii' THEN UPDATE private_isg.admin_exports SET raw_pii_included=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_raw_audit' THEN UPDATE private_isg.admin_audit_entries SET carries_raw_payload=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_scope_without_mfa' THEN UPDATE private_isg.admin_scopes SET requires_aal2=false; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_audit_during_pause' THEN INSERT INTO private_isg.admin_audit_entries(session_id,admin_user_id,",
    "  action_kind,scope_key,target_ref,payload_digest,written_at) VALUES((a->>'session')::uuid,(a->>'admin')::uuid,",
    "  'benefit_review','billing.read','manual', sha256('x'::bytea),(a->>'now')::timestamptz); r:=to_jsonb('inserted'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS err_code=MESSAGE_TEXT;",
    "IF err_code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','METADATA_NOT_ALLOWED',",
    "  'REDACTION_VIOLATION','STAGE_OUT_OF_ORDER','CHAIN_CLOSED','MFA_REQUIRED','SCOPE_DENIED',",
    "  'ADMIN_WRITES_PAUSED','EXPORT_DENIED','SIMULATION_REQUIRED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',err_code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_observability_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_OBSERVABILITY_UNEXPECTED_'+r.error);return r.result;};

  const trace=randomUUID();
  const chainArgs=(over={})=>({support:'SUPPORT01AA',owner:ownerID,environment:'production',build:'1.4.0+214',
    platform:'ios',trace,now:now(0),...over});
  mark('gate_blocks_the_telemetry_ledger_while_rollout_off',call('chain',chainArgs()).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('observability_gate','start_support_chain','record_technical_event','close_support_chain','record_queue_report','record_attribution','open_admin_session','admin_authorize','simulate_admin_action','publish_admin_action','request_admin_export','set_admin_write_pause') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('observability_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  // The forbidden payloads have no column to travel in.
  mark('the_envelope_has_no_column_for_a_secret_or_a_body',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('technical_events','support_chains','funnel_progress','telemetry_queue_reports','attribution_records') AND column_name ~ '(email|password|otp|token|secret|signature|signed_url|body|photo|document|note_text|full_name)';")==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='observability';");

  const chain=ok('chain',chainArgs());
  mark('a_chain_starts_before_any_analysis_row_exists',chain.started_without_analysis===true&&
    chain.blocks_domain===false&&
    sql("SELECT analysis_row_created=false AND last_stage IS NULL FROM private_isg.support_chains WHERE support_id='SUPPORT01AA';")==='t');
  const evt=(over={})=>({support:'SUPPORT01AA',stage:'screen_open',outcome:'ok',reason:null,request:randomUUID(),
    operation:null,retry:0,latency:12,metadata:{entry_point:'home'},now:now(1),...over});
  mark('an_unlisted_metadata_key_is_refused',
    call('event',evt({metadata:{entry_point:'home',user_email:'a@b.co'}})).error==='METADATA_NOT_ALLOWED');
  mark('an_address_a_bearer_token_a_jwt_or_a_signed_url_is_refused',
    call('event',evt({metadata:{entry_point:'kerem.kayalar@example.com'}})).error==='REDACTION_VIOLATION'&&
    call('event',evt({metadata:{entry_point:'Bearer abc123def456'}})).error==='REDACTION_VIOLATION'&&
    call('event',evt({metadata:{entry_point:'eyJhbGciOiJIUzI1NiJ9.payload'}})).error==='REDACTION_VIOLATION'&&
    call('event',evt({metadata:{entry_point:'https://cdn.example.com/a.jpg?X-Amz-Signature=deadbeef'}})).error==='REDACTION_VIOLATION');
  mark('a_body_of_text_never_fits_in_the_envelope',
    call('event',evt({metadata:{entry_point:'x'.repeat(240)}})).error==='REDACTION_VIOLATION');
  const first=ok('event',evt());
  mark('an_allowlisted_event_is_recorded_without_user_content',first.stage_no===1&&
    first.carries_user_content===false&&first.blocks_domain===false&&
    call('force_user_content',{}).error==='CHECK_VIOLATION');
  ok('event',evt({stage:'photo_pick',metadata:{source_kind:'camera',picked_count:'1'},now:now(2)}));
  ok('event',evt({stage:'encode',metadata:{input_bytes:'4210000',output_bytes:'890000'},now:now(3)}));
  mark('a_stage_can_never_go_backwards',
    call('event',evt({stage:'screen_open',now:now(4)})).error==='STAGE_OUT_OF_ORDER');
  const failedEncode=ok('event',evt({stage:'upload',outcome:'failed',reason:'NETWORK_LOST',
    metadata:{bytes_sent:'12000',attempt_no:'3'},retry:3,now:now(5)}));
  mark('a_failure_before_submit_leaves_no_analysis_row',failedEncode.analysis_row_created===false);
  const closedEarly=ok('close',{support:'SUPPORT01AA',outcome:'failed_before_submit',now:now(6)});
  mark('a_failure_that_never_reached_the_server_is_counted_separately',
    closedEarly.analysis_row_created===false&&closedEarly.successful_user_outcome===false&&
    sql("SELECT count(*) FROM private_isg.funnel_progress WHERE support_id='SUPPORT01AA';")==='4');
  mark('a_closed_chain_accepts_no_further_event',
    call('event',evt({stage:'submit',metadata:{payload_bytes:'900'},now:now(7)})).error==='CHAIN_CLOSED');

  const second='SUPPORT02BB';
  ok('chain',chainArgs({support:second,platform:'android',now:now(10)}));
  const stage=(name,meta,offset,outcome)=>ok('event',{support:second,stage:name,outcome:outcome||'ok',reason:null,
    request:randomUUID(),operation:randomUUID(),retry:0,latency:40,metadata:meta,now:now(offset)});
  stage('screen_open',{entry_point:'home'},11); stage('photo_pick',{source_kind:'library'},12);
  stage('encode',{encoder_version:'3'},13); stage('upload_intent',{purpose:'analysis_input'},14);
  stage('upload',{transport:'https'},15); stage('submit',{idempotent:'true'},16);
  const queued=stage('job_queued',{queue_name:'analysis'},17);
  stage('provider',{provider_name:'primary',timeout_ms:'30000'},18);
  stage('result',{result_kind:'standard',parts_count:'4'},19);
  mark('the_analysis_row_appears_only_once_the_server_queued_the_job',queued.analysis_row_created===true&&
    sql("SELECT analysis_row_created FROM private_isg.support_chains WHERE support_id="+quote(second)+";")==='t');
  // A result that came back but was never drawn is not a successful outcome.
  mark('a_result_that_was_never_rendered_is_not_a_success',
    call('close',{support:second,outcome:'rendered',now:now(20)}).error==='VALIDATION_ERROR'&&
    call('close',{support:second,outcome:'failed_before_submit',now:now(20)}).error==='VALIDATION_ERROR');
  stage('ui_render',{screen_name:'result_hub',render_ms_bucket:'200_500'},21);
  const rendered=ok('close',{support:second,outcome:'rendered',now:now(22)});
  mark('only_a_rendered_chain_is_a_successful_user_outcome',rendered.successful_user_outcome===true&&
    ok('close',{support:second,outcome:'rendered',now:now(23)}).replayed===true);

  const dead=ok('queue',{owner:ownerID,installation:randomUUID(),capacity:500,dropped:1200,
    oldest:now(5),transport:false,now:now(30)});
  mark('a_full_or_dead_telemetry_queue_is_reported_not_escalated',dead.dropped_count===1200&&
    dead.blocks_domain===false&&dead.domain_operation_affected===false&&
    call('force_blocking_queue',{}).error==='CHECK_VIOLATION');
  const noTracking=ok('attribution',{owner:ownerID,authorized:false,source:'store_provided',now:now(31)});
  mark('without_a_tracking_authorization_the_attribution_is_unknown',noTracking.attribution_source==='unknown'&&
    noTracking.tracking_authorized===false&&noTracking.identifier_stored===false&&
    noTracking.third_party_sdk_called===false&&
    call('force_identifier',{}).error==='CHECK_VIOLATION'&&call('force_third_party',{}).error==='CHECK_VIOLATION');
  mark('an_authorized_account_may_record_a_real_source',
    ok('attribution',{owner:ownerID,authorized:true,source:'store_provided',now:now(32)}).attribution_source==='store_provided'&&
    sql("SELECT count(*) FROM private_isg.attribution_records WHERE owner_id="+quote(ownerID)+";")==='1');

  const adminUser=randomUUID();
  const weak=ok('session',{admin:adminUser,aal:'aal1',scopes:['campaign.publish','export.masked'],
    expires:now(3600),now:now(40)});
  const wrongScope=ok('session',{admin:adminUser,aal:'aal2',scopes:['telemetry.read'],expires:now(3600),now:now(41)});
  const good=ok('session',{admin:adminUser,aal:'aal2',scopes:['campaign.publish','export.masked','billing.read'],
    expires:now(3600),now:now(42)});
  mark('the_server_never_trusts_a_scope_claimed_by_the_client',good.scopes_verified_by==='server'&&
    call('session',{admin:adminUser,aal:'aal2',scopes:['campaign.invent'],expires:now(3600),now:now(43)}).error==='VALIDATION_ERROR');
  mark('an_admin_without_mfa_is_refused',
    call('simulate',{session:weak.session_id,action_kind:'campaign_pause',scope:'campaign.publish',
      target:'campaign:referral_v5',report:{would_pause:1},now:now(44)}).error==='MFA_REQUIRED');
  mark('an_admin_without_the_scope_is_refused',
    call('simulate',{session:wrongScope.session_id,action_kind:'campaign_pause',scope:'campaign.publish',
      target:'campaign:referral_v5',report:{would_pause:1},now:now(45)}).error==='SCOPE_DENIED');
  mark('an_expired_session_is_refused',
    call('simulate',{session:good.session_id,action_kind:'campaign_pause',scope:'campaign.publish',
      target:'campaign:referral_v5',report:{would_pause:1},now:now(99999)}).error==='ACCESS_DENIED');
  mark('every_admin_scope_demands_a_second_factor',call('force_scope_without_mfa',{}).error==='CHECK_VIOLATION');

  const pausedBefore=sql("SELECT count(*) FROM private_isg.campaign_versions WHERE status='paused';");
  const simulated=ok('simulate',{session:good.session_id,action_kind:'campaign_pause',scope:'campaign.publish',
    target:'campaign:referral_v5',report:{would_pause:1,affected_episodes:0},now:now(50)});
  // A dry run reports what would happen and leaves the campaign exactly as it was.
  mark('a_simulation_reports_without_changing_a_domain_row',simulated.state==='simulated'&&
    simulated.domain_changed===false&&
    sql("SELECT count(*) FROM private_isg.campaign_versions WHERE status='paused';")===pausedBefore);
  mark('a_published_action_without_its_audit_has_no_row_shape',
    call('force_publish_without_audit',{action:simulated.action_id,now:now(51)}).error==='CHECK_VIOLATION');
  const publishedAction=ok('publish',{session:good.session_id,action:simulated.action_id,
    payload:{reason:'budget review'},now:now(52)});
  mark('a_publish_writes_its_audit_before_it_publishes',publishedAction.audit_written_before_publish===true&&
    publishedAction.raw_payload_stored===false&&
    sql("SELECT a.written_at<=c.published_at FROM private_isg.admin_actions c JOIN private_isg.admin_audit_entries a ON a.audit_id=c.audit_id WHERE c.action_id="+quote(simulated.action_id)+";")==='t'&&
    call('force_raw_audit',{}).error==='CHECK_VIOLATION'&&
    ok('publish',{session:good.session_id,action:simulated.action_id,payload:{reason:'again'},now:now(53)}).replayed===true);
  const otherSession=ok('session',{admin:randomUUID(),aal:'aal2',scopes:['campaign.publish'],
    expires:now(3600),now:now(54)});
  mark('another_session_can_not_publish_this_action',
    call('publish',{session:otherSession.session_id,action:simulated.action_id,payload:{},now:now(55)}).error==='ACCESS_DENIED'&&
    call('publish',{session:good.session_id,action:randomUUID(),payload:{},now:now(56)}).error==='ACCESS_DENIED');

  const exportAction=ok('simulate',{session:good.session_id,action_kind:'export_request',scope:'export.masked',
    target:'dataset:support_chains',report:{estimated_rows:2},now:now(60)});
  mark('an_export_can_not_name_a_column_nobody_allowed',
    call('export',{session:good.session_id,action:exportAction.action_id,dataset:'support_chains',
      columns:['support_id','owner_email'],rows:2,now:now(61)}).error==='EXPORT_DENIED');
  const exported=ok('export',{session:good.session_id,action:exportAction.action_id,dataset:'support_chains',
    columns:['support_id','platform','owner_id'],rows:2,now:now(62)});
  mark('an_export_masks_what_must_be_masked_and_carries_no_raw_pii',
    JSON.stringify(exported.masked_columns)===JSON.stringify(['owner_id'])&&
    exported.raw_pii_included===false&&call('force_raw_pii',{}).error==='CHECK_VIOLATION');

  const pauseAction=ok('simulate',{session:good.session_id,action_kind:'budget_change',scope:'campaign.publish',
    target:'campaign:referral_v5',report:{new_cap:3},now:now(70)});
  const paused=ok('pause',{paused:true,reason:'ekonomik inceleme',now:now(71)});
  mark('pausing_admin_writes_stops_a_publish',paused.writes_paused===true&&
    call('publish',{session:good.session_id,action:pauseAction.action_id,payload:{new_cap:3},now:now(72)}).error==='ADMIN_WRITES_PAUSED');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='billing_lifecycle';");
  mark('the_audit_trail_and_the_billing_chain_keep_running_while_writes_are_paused',
    paused.audit_continues===true&&paused.settlement_continues===true&&
    ok('force_audit_during_pause',{session:good.session_id,admin:adminUser,now:now(73)})==='inserted'&&
    ok('billing_still_works',{owner:ownerID,ref:'2000000000000001',sequence:900,now:now(74)}).replayed===false&&
    ok('simulate',{session:good.session_id,action_kind:'benefit_review',scope:'billing.read',target:'benefit:any',
      report:{rows:1},now:now(75)}).state==='simulated');
  mark('resuming_lets_the_same_action_publish',
    ok('pause',{paused:false,reason:null,now:now(80)}).writes_paused===false&&
    ok('publish',{session:good.session_id,action:pauseAction.action_id,payload:{new_cap:3},now:now(81)}).state==='published');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('observability','billing_lifecycle');");
  mark('kill_switch_stops_the_observability_ledger',
    call('chain',chainArgs({support:'SUPPORT03CC',now:now(90)})).error==='FEATURE_UNAVAILABLE'&&
    call('simulate',{session:good.session_id,action_kind:'benefit_review',scope:'billing.read',target:'x',
      report:{},now:now(90)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:observabilityAdminFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,user_content_logged:false,identifier_stored:false,third_party_sdk_called:false,
      telemetry_blocks_domain:false,raw_pii_exported:false,publish_without_audit_possible:false,
      admin_panel_changed:false,production_deployed:false};
  }};
}
