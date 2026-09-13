import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const dispatchQuotaFiles=[
  'supabase/migrations/20260913110000_isg_event_dispatch.sql',
  'supabase/migrations/20260913113000_isg_quota_reservations.sql',
  'scripts/isg/dispatch_quota_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';

// Deterministic test clock. Lease, backoff and period windows are asserted in
// seconds, so a wall clock would make the expectations unfalsifiable.
const T0=Date.UTC(2026,8,13,9,0,0);
const at=seconds=>new Date(T0+seconds*1000).toISOString();

export async function beginDispatchQuotaProbe({synthetic,sql,concurrentSql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_DISPATCH_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_DISPATCH_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('dispatch_quota_'+name,ok);
  const legacyBefore=sql("SELECT md5(string_agg(p.prosrc,'|' ORDER BY p.oid::text)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('user_plan_tier','company_limit_for_user','enforce_company_write_rules'); SELECT count(*) FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND NOT tgisinternal; SELECT count(*) FROM public.companies;");
  sql(read(dispatchQuotaFiles[0]));
  sql(read(dispatchQuotaFiles[1]));
  mark('migrations_applied',sql("SELECT count(*) FROM private_isg.rollout;")==='3');
  mark('legacy_helpers_triggers_and_rows_unchanged',legacyBefore===sql("SELECT md5(string_agg(p.prosrc,'|' ORDER BY p.oid::text)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('user_plan_tier','company_limit_for_user','enforce_company_write_rules'); SELECT count(*) FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND NOT tgisinternal; SELECT count(*) FROM public.companies;"));
  mark('rollout_defaults_off',sql("SELECT bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.rollout WHERE feature IN ('event_dispatch','quota_ledger');")==='t');

  // Fixed dispatch of the new entry points; no dynamic SQL, no client grant.
  sql(["CREATE SCHEMA isg_worker_test;",
    "CREATE FUNCTION isg_worker_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='fanout' THEN r:=private_isg.dispatch_fanout((a->>'limit')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='claim' THEN r:=private_isg.claim_event(a->>'consumer',(a->>'now')::timestamptz);",
    "ELSIF kind='complete' THEN r:=to_jsonb(private_isg.complete_event(a->>'consumer',(a->>'event')::uuid,(a->>'token')::uuid,(a->>'now')::timestamptz));",
    "ELSIF kind='fail' THEN r:=private_isg.fail_event(a->>'consumer',(a->>'event')::uuid,(a->>'token')::uuid,a->>'error',(a->>'now')::timestamptz);",
    "ELSIF kind='replay' THEN r:=private_isg.replay_dead_event(a->>'consumer',(a->>'event')::uuid,a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='reconcile' THEN r:=private_isg.reconcile_dispatch((a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='period' THEN r:=to_jsonb(private_isg.quota_period_key(a->>'quota_kind',(a->>'now')::timestamptz,a->>'timezone'));",
    "ELSIF kind='reserve' THEN r:=private_isg.reserve_quota((a->>'owner')::uuid,(a->>'company')::uuid,a->>'quota_kind',a->>'period',(a->>'amount')::bigint,a->>'funding',(a->>'operation')::uuid,(a->>'mutation')::uuid,(a->>'limit')::bigint,(a->>'unlimited')::boolean,(a->>'ttl')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='settle' THEN r:=private_isg.settle_quota((a->>'reservation')::uuid,a->'evidence',(a->>'now')::timestamptz);",
    "ELSIF kind='release' THEN r:=private_isg.release_quota((a->>'reservation')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='expire' THEN r:=to_jsonb(private_isg.expire_quota_reservations((a->>'now')::timestamptz));",
    "ELSIF kind='shadow' THEN r:=private_isg.record_quota_shadow((a->>'owner')::uuid,a->>'quota_kind',a->>'period',(a->>'legacy')::bigint,a->'detail',(a->>'now')::timestamptz);",
    "ELSIF kind='floor' THEN r:=private_isg.effective_floor((a->>'owner')::uuid,a->>'capability');",
    "ELSIF kind='floor_insert' THEN INSERT INTO private_isg.legacy_entitlement_floors(owner_id,capability,is_unlimited,floor_value,source,needs_review)",
    " VALUES((a->>'owner')::uuid,a->>'capability',(a->>'unlimited')::boolean,(a->>'value')::bigint,a->>'source',(a->>'needs_review')::boolean); r:=to_jsonb('inserted'::text);",
    "ELSIF kind='live_authority' THEN INSERT INTO private_isg.quota_reservations(owner_id,quota_kind,period_key,amount,funding_source,authority,operation_id,mutation_id,request_hash,expires_at)",
    " VALUES((a->>'owner')::uuid,'company_slot','lifetime',1,'plan','live',gen_random_uuid(),gen_random_uuid(),'\\x00'::bytea,now()); r:=to_jsonb('inserted'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','LEASE_LOST','CAPACITY_EXCEEDED','IDEMPOTENCY_CONFLICT','TEST_FAULT') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_worker_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_DISPATCH_UNEXPECTED_'+r.error);return r.result;};

  mark('gate_blocks_fanout_while_rollout_off',call('fanout',{limit:10,now:at(0)}).error==='FEATURE_UNAVAILABLE');
  mark('gate_blocks_claim_while_rollout_off',call('claim',{consumer:'training_requirements_v1',now:at(0)}).error==='FEATURE_UNAVAILABLE');
  mark('gate_blocks_reconcile_while_rollout_off',call('reconcile',{on:'2026-09-13',now:at(0)}).error==='FEATURE_UNAVAILABLE');
  mark('gate_blocks_reserve_while_rollout_off',call('reserve',{owner:ownerID,company:companyID,quota_kind:'company_slot',period:'lifetime',amount:1,funding:'plan',operation:randomUUID(),mutation:randomUUID(),limit:5,unlimited:false,ttl:300,now:at(0)}).error==='FEATURE_UNAVAILABLE');
  mark('gate_blocks_floor_read_while_rollout_off',call('floor',{owner:ownerID,capability:'company_slot'}).error==='FEATURE_UNAVAILABLE');

  const grants=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('dispatch_gate','domain_events','dispatch_fanout','claim_event','complete_event','fail_event','replay_dead_event','reconcile_dispatch','quota_gate','quota_period_key','quota_used','expire_quota_reservations','reserve_quota','settle_quota','release_quota','record_quota_shadow','effective_floor') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE')); SELECT string_agg(p.proname,',' ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('authenticated',p.oid,'EXECUTE'); SELECT bool_and(p.proconfig @> ARRAY['search_path=\"\"']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg';").split('\n');
  mark('new_tables_have_rls_and_no_client_table_grant',grants[0]==='0'&&grants[1]==='0');
  mark('worker_and_ledger_functions_have_no_client_execute',grants[2]==='0');
  mark('existing_client_rpc_grants_unchanged',grants[3]==='context_at,directory_mutate,directory_read,mutate_personnel,read_personnel,workspace_availability');
  mark('every_private_function_pins_search_path',grants[4]==='t');

  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('event_dispatch','quota_ledger');");

  // Distinct synthetic entity kind: the probe asserts on its own aggregate while
  // the real P05 producers keep emitting into the same tables.
  const aggregate=randomUUID(),other=randomUUID();
  const seed=(kind,entity,version)=>sql("WITH e AS(INSERT INTO private_isg.directory_events(company_id,owner_id,operation_id,entity_kind,entity_id,version,created_at) VALUES("+quote(companyID)+","+quote(ownerID)+",gen_random_uuid(),"+quote(kind)+","+quote(entity)+","+version+",timestamptz "+quote(at(-3600+version))+") RETURNING event_id) INSERT INTO private_isg.directory_outbox(event_id) SELECT event_id FROM e RETURNING event_id;");
  const events=[seed('dispatch_probe',aggregate,0),seed('dispatch_probe',aggregate,1),seed('dispatch_probe',aggregate,2)];
  seed('dispatch_probe_other',other,0);
  const consumers=[['training_requirements_v1','P07',"ARRAY['directory.dispatch_probe.changed']",true,3],
    ['score_projection_v1','P17',"ARRAY['directory.dispatch_probe.changed']",true,5],
    ['disabled_consumer_v1','P12',"ARRAY['directory.dispatch_probe.changed']",false,5],
    ['other_kind_consumer_v1','P10',"ARRAY['directory.dispatch_probe_other.changed']",true,5],
    ['personnel_projection_v1','P06',"ARRAY['employee.created','employee.updated','employee.archived','employee.restored']",true,5]];
  for(const [name,pkg,types,enabled,attempts] of consumers)
    sql("INSERT INTO private_isg.consumer_registry(consumer,event_source,event_types,owner_package,is_enabled,max_attempts) VALUES("+quote(name)+","+(name==='personnel_projection_v1'?"'personnel'":"'directory'")+","+types+","+quote(pkg)+","+enabled+","+attempts+");");
  const mine=consumer=>sql("SELECT coalesce(string_agg(state||':'||aggregate_version,',' ORDER BY aggregate_version),'') FROM private_isg.event_deliveries WHERE consumer="+quote(consumer)+" AND aggregate_id="+quote(aggregate)+";");

  ok('fanout',{limit:5000,now:at(0)});
  mark('fanout_creates_one_delivery_per_subscribed_consumer',mine('training_requirements_v1')==='pending:0,pending:1,pending:2'&&mine('score_projection_v1')==='pending:0,pending:1,pending:2');
  mark('fanout_skips_disabled_consumer',mine('disabled_consumer_v1')==='');
  mark('fanout_respects_event_type_subscription',sql("SELECT count(*) FROM private_isg.event_deliveries WHERE consumer='other_kind_consumer_v1';")==='1'&&sql("SELECT count(*) FROM private_isg.event_deliveries WHERE consumer='other_kind_consumer_v1' AND aggregate_id="+quote(aggregate)+";")==='0');
  mark('fanout_reads_the_real_personnel_producer',sql("SELECT (SELECT count(*) FROM private_isg.event_deliveries WHERE consumer='personnel_projection_v1')=(SELECT count(*) FROM private_isg.personnel_outbox);")==='t');
  mark('fanout_is_idempotent',ok('fanout',{limit:5000,now:at(1)}).created===0);

  const first=ok('claim',{consumer:'training_requirements_v1',now:at(10)});
  mark('claim_returns_lowest_aggregate_version',first?.aggregate_version===0&&first.attempts===1&&!!first.lease_token);
  mark('claim_blocks_successor_until_prior_is_done',ok('claim',{consumer:'training_requirements_v1',now:at(11)})===null);
  const parallel=ok('claim',{consumer:'score_projection_v1',now:at(11)});
  mark('consumers_progress_independently',parallel?.event_id===first.event_id&&parallel.aggregate_version===0);
  ok('complete',{consumer:'score_projection_v1',event:parallel.event_id,token:parallel.lease_token,now:at(12)});
  mark('complete_writes_receipt_and_marks_done',ok('complete',{consumer:'training_requirements_v1',event:first.event_id,token:first.lease_token,now:at(12)})===true&&sql("SELECT count(*) FROM private_isg.consumer_receipts WHERE event_id="+quote(first.event_id)+" AND consumer='training_requirements_v1';")==='1');
  mark('lost_acknowledgement_replay_has_no_second_effect',ok('complete',{consumer:'training_requirements_v1',event:first.event_id,token:first.lease_token,now:at(13)})===false&&sql("SELECT count(*) FROM private_isg.consumer_receipts WHERE event_id="+quote(first.event_id)+" AND consumer='training_requirements_v1';")==='1');
  const second=ok('claim',{consumer:'training_requirements_v1',now:at(14)});
  mark('successor_is_claimable_after_prior_is_done',second?.aggregate_version===1);
  mark('wrong_lease_token_cannot_complete',call('complete',{consumer:'training_requirements_v1',event:second.event_id,token:randomUUID(),now:at(15)}).error==='LEASE_LOST');

  const failed=ok('fail',{consumer:'training_requirements_v1',event:second.event_id,token:second.lease_token,error:'RETRYABLE_FAILURE',now:at(20)});
  mark('failure_returns_event_to_pending_with_backoff',failed.state==='pending'&&failed.attempts===1&&failed.retry_in_seconds===5);
  mark('event_is_not_claimable_before_its_backoff_window',ok('claim',{consumer:'training_requirements_v1',now:at(22)})===null);
  const retry=ok('claim',{consumer:'training_requirements_v1',now:at(25)});
  const failedAgain=ok('fail',{consumer:'training_requirements_v1',event:retry.event_id,token:retry.lease_token,error:'RETRYABLE_FAILURE',now:at(26)});
  mark('backoff_grows_exponentially',retry.event_id===second.event_id&&retry.attempts===2&&failedAgain.retry_in_seconds===10);
  const last=ok('claim',{consumer:'training_requirements_v1',now:at(40)});
  const dead=ok('fail',{consumer:'training_requirements_v1',event:last.event_id,token:last.lease_token,error:'RULE_NEEDS_REVIEW',now:at(41)});
  mark('attempt_budget_exhaustion_creates_a_dead_letter',dead.state==='dead'&&dead.attempts===3&&dead.retry_in_seconds===null&&sql("SELECT count(*) FROM private_isg.dispatch_dead_letters WHERE event_id="+quote(second.event_id)+" AND consumer='training_requirements_v1' AND replayed_at IS NULL;")==='1');
  mark('dead_event_holds_its_successor_instead_of_skipping',ok('claim',{consumer:'training_requirements_v1',now:at(4000)})===null&&mine('training_requirements_v1')==='done:0,dead:1,pending:2');
  mark('replay_requires_a_dead_delivery',call('replay',{consumer:'training_requirements_v1',event:events[2],reason:'inceleme',now:at(4001)}).error==='VALIDATION_ERROR');
  mark('replay_requires_a_reason',call('replay',{consumer:'training_requirements_v1',event:second.event_id,reason:'   ',now:at(4001)}).error==='VALIDATION_ERROR');
  const replayed=ok('replay',{consumer:'training_requirements_v1',event:second.event_id,reason:'Kural sürümü düzeltildi',now:at(4002)});
  mark('replay_resets_attempts_and_keeps_dead_letter_history',replayed.state==='pending'&&replayed.attempts===0&&sql("SELECT count(*) FROM private_isg.dispatch_dead_letters WHERE event_id="+quote(second.event_id)+" AND replayed_at IS NOT NULL AND replay_reason='Kural sürümü düzeltildi';")==='1');
  const afterReplay=ok('claim',{consumer:'training_requirements_v1',now:at(4003)});
  mark('replay_unblocks_the_aggregate',afterReplay?.event_id===second.event_id&&afterReplay.attempts===1);
  const reclaimed=ok('claim',{consumer:'training_requirements_v1',now:at(4040)});
  mark('expired_lease_is_reclaimed_and_keeps_the_spent_attempt',reclaimed?.event_id===second.event_id&&reclaimed.attempts===2);
  mark('expired_lease_cannot_complete',call('complete',{consumer:'training_requirements_v1',event:second.event_id,token:afterReplay.lease_token,now:at(4041)}).error==='LEASE_LOST');
  mark('unregistered_consumer_is_denied',call('claim',{consumer:'unknown_consumer_v1',now:at(4042)}).error==='ACCESS_DENIED');
  mark('disabled_consumer_is_denied',call('claim',{consumer:'disabled_consumer_v1',now:at(4042)}).error==='ACCESS_DENIED');

  sql("CREATE FUNCTION isg_worker_test.fail_tail() RETURNS trigger LANGUAGE plpgsql AS $fault$ BEGIN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEST_FAULT'; END $fault$;");
  sql("CREATE TRIGGER receipt_fault BEFORE INSERT ON private_isg.consumer_receipts FOR EACH ROW EXECUTE FUNCTION isg_worker_test.fail_tail();");
  const before=mine('training_requirements_v1');
  mark('consumer_effect_and_receipt_commit_together',call('complete',{consumer:'training_requirements_v1',event:second.event_id,token:reclaimed.lease_token,now:at(4043)}).error==='TEST_FAULT'&&mine('training_requirements_v1')===before);
  sql("DROP TRIGGER receipt_fault ON private_isg.consumer_receipts;");
  ok('complete',{consumer:'training_requirements_v1',event:second.event_id,token:reclaimed.lease_token,now:at(4044)});

  const report=ok('reconcile',{on:'2026-09-13',now:at(4100)});
  mark('reconcile_reports_the_real_ledger',report.undelivered===0&&report.done_without_receipt===0&&report.open_dead_letters===0&&report.stale_leases===0&&report.deliveries===Number(sql("SELECT count(*) FROM private_isg.event_deliveries;"))&&report.receipts===Number(sql("SELECT count(*) FROM private_isg.consumer_receipts;")));
  mark('reconcile_keeps_one_row_per_day',!!ok('reconcile',{on:'2026-09-13',now:at(4200)})&&sql("SELECT count(*) FROM private_isg.dispatch_reconciliations;")==='1');

  mark('period_key_requires_a_known_timezone',call('period',{quota_kind:'ai_analysis',now:at(0),timezone:'Mars/Olympus'}).error==='VALIDATION_ERROR');
  mark('period_keys_follow_the_declared_window',ok('period',{quota_kind:'ai_analysis',now:at(0),timezone:'Europe/Istanbul'})==='2026-09-13'&&ok('period',{quota_kind:'report_export',now:at(0),timezone:'Europe/Istanbul'})==='2026-09'&&ok('period',{quota_kind:'company_slot',now:at(0),timezone:null})==='lifetime');
  mark('period_key_shape_must_match_the_kind',call('reserve',{owner:ownerID,company:companyID,quota_kind:'ai_analysis',period:'lifetime',amount:1,funding:'plan',operation:randomUUID(),mutation:randomUUID(),limit:5,unlimited:false,ttl:300,now:at(0)}).error==='VALIDATION_ERROR');
  const reserve=(over={})=>({owner:ownerID,company:companyID,quota_kind:'company_slot',period:'lifetime',amount:1,funding:'plan',operation:randomUUID(),mutation:randomUUID(),limit:2,unlimited:false,ttl:300,now:at(0),...over});
  const slotA=reserve(),slotB=reserve();
  const firstSlot=ok('reserve',slotA);
  mark('reservation_is_shadow_only',firstSlot.authority==='shadow'&&firstSlot.used_after===1&&call('live_authority',{owner:ownerID}).error==='CHECK_VIOLATION');
  ok('reserve',slotB);
  const slotCount=()=>sql("SELECT count(*) FROM private_isg.quota_reservations WHERE owner_id="+quote(ownerID)+" AND quota_kind='company_slot' AND period_key='lifetime';");
  const beforeDenied=slotCount();
  mark('reserve_denies_beyond_the_supplied_limit',call('reserve',reserve()).error==='CAPACITY_EXCEEDED'&&slotCount()===beforeDenied);
  const replay=ok('reserve',slotA);
  mark('reserve_replays_the_same_mutation',replay.replayed===true&&replay.reservation_id===firstSlot.reservation_id&&slotCount()===beforeDenied);
  mark('reserve_conflicts_on_a_changed_body',call('reserve',{...slotA,amount:2}).error==='IDEMPOTENCY_CONFLICT');
  mark('unlimited_is_an_explicit_flag_not_a_large_number',!!ok('reserve',reserve({quota_kind:'ai_analysis',period:'2026-09-13',limit:null,unlimited:true,amount:1000})));
  ok('floor_insert',{owner:ownerID,capability:'report_export',unlimited:false,value:5,source:'contract',needs_review:false});
  mark('a_recorded_floor_creates_no_capacity',ok('floor',{owner:ownerID,capability:'report_export'}).floor_value===5&&call('reserve',reserve({quota_kind:'report_export',period:'2026-09',limit:0})).error==='CAPACITY_EXCEEDED');

  const settled=ok('settle',{reservation:firstSlot.reservation_id,evidence:{source:'probe'},now:at(10)});
  mark('settlement_records_the_consumption_once',settled.state==='settled'&&sql("SELECT count(*) FROM private_isg.quota_settlements WHERE reservation_id="+quote(firstSlot.reservation_id)+";")==='1');
  mark('settlement_is_idempotent',ok('settle',{reservation:firstSlot.reservation_id,evidence:{source:'probe'},now:at(11)}).replayed===true&&sql("SELECT count(*) FROM private_isg.quota_settlements WHERE reservation_id="+quote(firstSlot.reservation_id)+";")==='1');
  mark('a_settled_consumption_is_never_released',call('release',{reservation:firstSlot.reservation_id,now:at(12)}).error==='VALIDATION_ERROR');
  const secondSlot=sql("SELECT reservation_id FROM private_isg.quota_reservations WHERE owner_id="+quote(ownerID)+" AND mutation_id="+quote(slotB.mutation)+";");
  ok('release',{reservation:secondSlot,now:at(13)});
  mark('release_frees_the_slot_again',!!ok('reserve',reserve({mutation:randomUUID()})));
  const shortTtl=ok('reserve',reserve({quota_kind:'storage_bytes',amount:100,limit:100,ttl:10,now:at(0)}));
  mark('an_expired_reservation_frees_capacity',ok('expire',{now:at(60)})>=1&&!!ok('reserve',reserve({quota_kind:'storage_bytes',amount:100,limit:100,now:at(61)}))&&sql("SELECT state FROM private_isg.quota_reservations WHERE reservation_id="+quote(shortTtl.reservation_id)+";")==='expired');
  mark('periods_and_owners_are_separate_windows',!!ok('reserve',reserve({quota_kind:'ai_analysis',period:'2026-09-14',limit:1,amount:1})));

  const contention='2026-09-20',lockKind='ai_analysis';
  const races=await Promise.all(Array.from({length:20},()=>concurrentSql("SELECT isg_worker_test.observe('reserve',"+json(reserve({quota_kind:lockKind,period:contention,limit:1,amount:1,mutation:randomUUID(),operation:randomUUID()}))+");")));
  const outcomes=races.filter(r=>r.ok).map(r=>JSON.parse(r.output.split('\n').at(-1)));
  mark('twenty_parallel_reservations_sell_one_slot',outcomes.length===20&&outcomes.filter(r=>r.result?.state==='reserved').length===1&&outcomes.filter(r=>r.error==='CAPACITY_EXCEEDED').length===19&&sql("SELECT count(*) FROM private_isg.quota_reservations WHERE quota_kind="+quote(lockKind)+" AND period_key="+quote(contention)+";")==='1');

  mark('unknown_floor_source_must_stay_in_review',call('floor_insert',{owner:ownerID,capability:'ai_analysis',unlimited:false,value:3,source:'unknown',needs_review:false}).error==='CHECK_VIOLATION');
  mark('unlimited_and_numeric_floor_are_mutually_exclusive',call('floor_insert',{owner:ownerID,capability:'ai_analysis',unlimited:true,value:5,source:'contract',needs_review:false}).error==='CHECK_VIOLATION');
  ok('floor_insert',{owner:ownerID,capability:'company_slot',unlimited:false,value:5,source:'contract',needs_review:false});
  const floor=ok('floor',{owner:ownerID,capability:'company_slot'});
  mark('floor_reports_measurement_without_granting_access',floor.recorded===true&&floor.floor_value===5&&floor.grants_access===false);
  const missing=ok('floor',{owner:ownerID,capability:'storage_bytes'});
  mark('an_unrecorded_floor_is_review_not_zero',missing.recorded===false&&missing.floor_value===null&&missing.needs_review===true);

  const legacyState=sql("SELECT count(*) FROM public.companies WHERE user_id="+quote(ownerID)+"; SELECT private.company_limit_for_user("+quote(ownerID)+");");
  const shadow=ok('shadow',{owner:ownerID,quota_kind:'company_slot',period:'lifetime',legacy:99,detail:{probe:'company_slot'},now:at(100)});
  mark('shadow_comparison_records_disagreement_without_changing_legacy',shadow.agreed===false&&shadow.authority==='legacy'&&legacyState===sql("SELECT count(*) FROM public.companies WHERE user_id="+quote(ownerID)+"; SELECT private.company_limit_for_user("+quote(ownerID)+");"));

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('event_dispatch','quota_ledger');");
  mark('kill_switch_stops_the_worker_and_the_ledger',call('claim',{consumer:'training_requirements_v1',now:at(5000)}).error==='FEATURE_UNAVAILABLE'&&call('reserve',reserve({mutation:randomUUID()})).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_files:dispatchQuotaFiles.slice(0,2),exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,worker_identity_bound:false,legacy_quota_authority_replaced:false,
      production_deployed:false,consumer_runtime_implemented:false};
  }};
}
