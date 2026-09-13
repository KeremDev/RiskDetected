import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const billingLifecycleFiles=[
  'supabase/migrations/20260914090000_isg_billing_lifecycle.sql',
  'scripts/isg/billing_lifecycle_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,9,0,0)+seconds*1000).toISOString();

export async function beginBillingLifecycleProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_BILLING_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('AUTH_RESTORE_BILLING_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('billing_lifecycle_'+name,ok);
  sql(read(billingLifecycleFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='billing_lifecycle';")==='t');

  sql(["CREATE SCHEMA isg_billing_test;",
    "CREATE FUNCTION isg_billing_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; err_code text; BEGIN",
    "IF kind='evidence' THEN r:=private_isg.record_billing_evidence((a->>'owner')::uuid,a->>'environment',a->>'store',a->>'product',",
    "  a->>'purchase_ref',a->>'event_kind',a->>'lifecycle_state',(a->>'store_event_at')::timestamptz,(a->>'sequence')::bigint,",
    "  a->>'source',a->'payload',(a->>'now')::timestamptz);",
    "ELSIF kind='project' THEN r:=private_isg.project_billing_lifecycle((a->>'evidence')::uuid,(a->>'auto_renew')::boolean,",
    "  (a->>'expires_at')::timestamptz,(a->>'now')::timestamptz);",
    "ELSIF kind='access' THEN r:=private_isg.effective_billing_access((a->>'owner')::uuid,a->>'environment',(a->>'now')::timestamptz);",
    "ELSIF kind='grant' THEN r:=private_isg.grant_benefit((a->>'owner')::uuid,a->>'code',a->>'family',a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='advance' THEN r:=private_isg.advance_benefit((a->>'instance')::uuid,a->>'target',a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='activate' THEN r:=private_isg.activate_gift((a->>'instance')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='quote' THEN r:=private_isg.issue_discount_quote((a->>'instance')::uuid,(a->>'mapping')::uuid,a->>'currency',",
    "  (a->>'current')::bigint,(a->>'offer')::bigint,(a->>'observed')::timestamptz,(a->>'ttl')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='checkout' THEN r:=private_isg.open_checkout_intent((a->>'quote')::uuid,(a->>'installation')::uuid,",
    "  (a->>'timeout')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='timeout' THEN r:=private_isg.resolve_checkout_timeout((a->>'intent')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='settle' THEN r:=private_isg.settle_benefit((a->>'intent')::uuid,(a->>'evidence')::uuid,",
    "  daterange((a->>'period_from')::date,(a->>'period_to')::date),(a->>'now')::timestamptz);",
    "ELSIF kind='adjust' THEN r:=private_isg.adjust_settlement((a->>'settlement')::uuid,a->>'kind',a->>'reason',a->'evidence',(a->>'now')::timestamptz);",
    "ELSIF kind='reconcile' THEN r:=private_isg.reconcile_billing((a->>'for')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='force_paying_discount' THEN INSERT INTO private_isg.benefit_definitions(code,benefit_kind,grants_capability,",
    "  capability,duration_hours,discount_percent,funding_source,family_scope)",
    "  VALUES('bad_discount','discount_coupon',true,'pro_access',168,20,'store','none'); r:=to_jsonb('inserted'::text);",
    "ELSIF kind='force_quota_reset' THEN UPDATE private_isg.benefit_definitions SET resets_quota=true WHERE code='sponsor_gift_plus_7d'; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_store_trial' THEN UPDATE private_isg.benefit_definitions SET is_store_trial=true WHERE code='sponsor_gift_plus_7d'; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_signing_material' THEN UPDATE private_isg.store_offer_mappings SET signature_material_stored=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_default_offering' THEN UPDATE private_isg.store_offer_mappings SET excluded_from_default_offering=false; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_untokened_offer' THEN INSERT INTO private_isg.store_offer_mappings(definition_id,store,environment,",
    "  product_id,offer_id,offer_kind) SELECT definition_id,'google','production','rd_plus_monthly','no-token','developer_determined'",
    "  FROM private_isg.benefit_definitions WHERE code='monthly_discount_one_period'; r:=to_jsonb('inserted'::text);",
    "ELSIF kind='force_local_authority' THEN UPDATE private_isg.billing_lifecycle_projection SET access_authority='billing'; r:=to_jsonb('updated'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS err_code=MESSAGE_TEXT;",
    "IF err_code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','BENEFIT_STATE_INVALID',",
    "  'FAMILY_ALREADY_USED','PURCHASE_OWNED_ELSEWHERE','SETTLEMENT_CONFLICT','INTENT_ALREADY_OPEN','QUOTE_EXPIRED',",
    "  'NO_PAYMENT_EVIDENCE') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',err_code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_billing_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_BILLING_UNEXPECTED_'+r.error);return r.result;};
  // Real accounts: public.profiles references auth.users, so no invented owner.
  const otherOwner=sql("SELECT id FROM public.profiles WHERE id<>"+quote(ownerID)+" ORDER BY id LIMIT 1;");
  const thirdOwner=randomUUID();
  sql("INSERT INTO auth.users(id) VALUES("+quote(thirdOwner)+"); INSERT INTO public.profiles(id,tier) VALUES("+quote(thirdOwner)+",'free');");

  const purchase='GPA.0000-1111-2222-33333';
  const evidenceArgs=(over={})=>({owner:ownerID,environment:'production',store:'google',product:'rd_plus_monthly',
    purchase_ref:purchase,event_kind:'purchase',lifecycle_state:'active',store_event_at:now(0),sequence:10,
    source:'webhook',payload:{store:'google'},now:now(0),...over});
  mark('gate_blocks_the_ledger_while_rollout_off',call('evidence',evidenceArgs()).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('billing_gate','record_billing_evidence','project_billing_lifecycle','effective_billing_access','grant_benefit','advance_benefit','activate_gift','issue_discount_quote','open_checkout_intent','resolve_checkout_timeout','settle_benefit','adjust_settlement','reconcile_billing') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('billing_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  // The separation is structural: no row shape exists for a paying discount.
  mark('a_discount_definition_can_never_carry_a_capability',call('force_paying_discount',{}).error==='CHECK_VIOLATION');
  mark('a_gift_can_neither_reset_a_quota_nor_be_a_store_trial',
    call('force_quota_reset',{}).error==='CHECK_VIOLATION'&&call('force_store_trial',{}).error==='CHECK_VIOLATION');
  mark('the_seven_day_window_and_the_percentage_are_unapproved_numbers',
    sql("SELECT bool_and(NOT content_approved AND needs_review AND value_source='unapproved_fixture') FROM private_isg.benefit_definitions;")==='t');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='billing_lifecycle';");

  const first=ok('evidence',evidenceArgs());
  mark('a_purchase_is_recorded_once_and_reports_no_authority',first.replayed===false&&first.access_authority==='legacy');
  mark('a_duplicate_webhook_is_not_a_second_purchase',
    ok('evidence',evidenceArgs({now:now(5)})).replayed===true&&
    sql("SELECT count(*) FROM private_isg.billing_lifecycle_evidence WHERE purchase_ref="+quote(purchase)+";")==='1');
  mark('another_account_can_not_claim_the_same_purchase',
    call('evidence',evidenceArgs({owner:randomUUID(),event_kind:'renewal',sequence:11,now:now(6)})).error==='PURCHASE_OWNED_ELSEWHERE');

  const projected=ok('project',{evidence:first.evidence_id,auto_renew:true,expires_at:now(2592000),now:now(7)});
  mark('the_first_projection_reports_the_store_state',projected.applied===true&&projected.lifecycle_state==='active'&&projected.version===1);
  const late=ok('evidence',evidenceArgs({event_kind:'cancellation',lifecycle_state:'expired',sequence:4,
    store_event_at:now(-600),now:now(8)}));
  const lateApplied=ok('project',{evidence:late.evidence_id,auto_renew:false,expires_at:null,now:now(9)});
  mark('an_out_of_order_webhook_never_rewrites_a_newer_state',lateApplied.applied===false&&
    lateApplied.reason==='out_of_order'&&lateApplied.lifecycle_state==='active'&&
    sql("SELECT lifecycle_state||':'||version FROM private_isg.billing_lifecycle_projection WHERE owner_id="+quote(ownerID)+" AND store='google' AND environment='production';")==='active:1');
  const renewal=ok('evidence',evidenceArgs({event_kind:'renewal',sequence:20,store_event_at:now(600),now:now(10)}));
  const renewed=ok('project',{evidence:renewal.evidence_id,auto_renew:true,expires_at:now(5184000),now:now(11)});
  mark('a_newer_store_event_moves_the_projection_forward',renewed.applied===true&&renewed.version===2&&
    sql("SELECT applied_sequence_no FROM private_isg.billing_lifecycle_projection WHERE owner_id="+quote(ownerID)+" AND store='google';")==='20');
  mark('the_ledger_can_not_promote_itself_to_the_access_authority',
    call('force_local_authority',{}).error==='CHECK_VIOLATION'&&
    sql("SELECT bool_and(access_authority='legacy') FROM private_isg.billing_lifecycle_projection;")==='t');

  const unknown=ok('evidence',evidenceArgs({owner:otherOwner,purchase_ref:'GPA.9999-8888-7777-66666',
    event_kind:'sync',lifecycle_state:'unknown',sequence:1,source:'client_sync',now:now(12)}));
  ok('project',{evidence:unknown.evidence_id,auto_renew:null,expires_at:null,now:now(13)});
  const unknownAccess=ok('access',{owner:otherOwner,environment:'production',now:now(14)});
  // An account whose lifecycle could not be read is reviewed, never gifted as Free.
  mark('an_unreadable_lifecycle_is_reviewed_and_not_treated_as_free',unknown.needs_review===true&&
    unknownAccess.billing_tier.lifecycle_state==='unknown'&&unknownAccess.billing_tier.is_paid===false&&
    unknownAccess.billing_tier.needs_review===true);

  const sandbox=ok('evidence',evidenceArgs({owner:thirdOwner,environment:'sandbox',purchase_ref:'GPA.5555-4444-3333-22222',
    sequence:2,now:now(15)}));
  ok('project',{evidence:sandbox.evidence_id,auto_renew:true,expires_at:now(2592000),now:now(16)});
  mark('a_sandbox_purchase_is_never_a_paid_production_tier',
    ok('access',{owner:thirdOwner,environment:'production',now:now(17)}).billing_tier.is_paid===false&&
    sql("SELECT count(*) FROM private_isg.billing_lifecycle_projection WHERE owner_id="+quote(thirdOwner)+" AND environment='sandbox';")==='1');
  const paidAccess=ok('access',{owner:ownerID,environment:'production',now:now(18)});
  mark('the_report_separates_three_sources_and_decides_nothing',paidAccess.access_authority==='legacy'&&
    paidAccess.decides_access===false&&paidAccess.discount_grants_access===false&&
    paidAccess.billing_tier.is_paid===true&&paidAccess.gift_capability.active===false&&
    Object.prototype.hasOwnProperty.call(paidAccess,'capacity_floor'));

  const gift=ok('grant',{owner:ownerID,code:'sponsor_gift_plus_7d',family:'referral:'+companyID.slice(0,8),
    reason:'davet qualification',now:now(20)});
  mark('a_family_spends_its_gift_once',gift.state==='earned'&&gift.grants_capability===true&&
    call('grant',{owner:ownerID,code:'sponsor_gift_plus_7d',family:'referral:'+companyID.slice(0,8),
      reason:'ikinci deneme',now:now(21)}).error==='FAMILY_ALREADY_USED');
  mark('an_unlisted_state_move_does_not_exist',
    call('advance',{instance:gift.instance_id,target:'consumed',reason:'atlamayı dene',now:now(22)}).error==='BENEFIT_STATE_INVALID'&&
    sql("SELECT count(*) FROM private_isg.benefit_state_edges;")==='18');
  ok('advance',{instance:gift.instance_id,target:'available',reason:'qualification doğrulandı',now:now(23)});
  const activated=ok('activate',{instance:gift.instance_id,now:now(24)});
  mark('a_gift_runs_on_the_server_clock_without_touching_a_quota',activated.state==='active'&&
    activated.duration_hours===168&&activated.quota_reset===false&&activated.is_store_trial===false&&
    activated.funding_source==='sponsor'&&activated.duration_approved===false&&
    sql("SELECT expires_at=activated_at+interval '168 hours' FROM private_isg.benefit_instances WHERE instance_id="+quote(gift.instance_id)+";")==='t');
  mark('a_second_device_activating_the_same_gift_changes_nothing',
    ok('activate',{instance:gift.instance_id,now:now(25)}).replayed===true&&
    sql("SELECT version FROM private_isg.benefit_instances WHERE instance_id="+quote(gift.instance_id)+";")==='3');
  const giftAccess=ok('access',{owner:ownerID,environment:'production',now:now(26)});
  const atExpiry=ok('access',{owner:ownerID,environment:'production',now:now(24+168*3600)});
  mark('the_gift_is_over_at_its_expiry_instant',giftAccess.gift_capability.active===true&&
    giftAccess.gift_capability.capability==='plus_access'&&giftAccess.gift_capability.quota_reset===false&&
    atExpiry.gift_capability.active===false&&atExpiry.gift_capability.capability===null);
  mark('no_quota_reservation_was_created_by_a_gift',
    sql("SELECT count(*) FROM private_isg.quota_reservations WHERE owner_id="+quote(ownerID)+" AND funding_source='gift';")==='0');

  const mapping=sql("INSERT INTO private_isg.store_offer_mappings(definition_id,store,environment,product_id,offer_id,base_plan_id,offer_kind,replacement_mode,offer_token_required) SELECT definition_id,'google','production','rd_plus_monthly','winback-20','monthly-base','developer_determined','without_proration',true FROM private_isg.benefit_definitions WHERE code='monthly_discount_one_period' RETURNING mapping_id;").split('\n').at(-1);
  mark('a_google_offer_needs_its_token_and_replacement_mode',
    call('force_untokened_offer',{}).error==='CHECK_VIOLATION'&&
    sql("SELECT excluded_from_default_offering AND price_authority='store' AND NOT limit_approved FROM private_isg.store_offer_mappings WHERE mapping_id="+quote(mapping)+";")==='t');
  mark('no_offer_row_can_hold_signing_material_or_join_the_default_offering',
    call('force_signing_material',{}).error==='CHECK_VIOLATION'&&call('force_default_offering',{}).error==='CHECK_VIOLATION');

  const coupon=ok('grant',{owner:ownerID,code:'monthly_discount_one_period',family:'winback:'+ownerID.slice(0,8),
    reason:'winback kampanya adayı',now:now(30)});
  ok('advance',{instance:coupon.instance_id,target:'available',reason:'kampanya penceresi açıldı',now:now(31)});
  const expensive=ok('quote',{instance:coupon.instance_id,mapping,currency:'TRY',current:100000000,offer:120000000,
    observed:now(32),ttl:900,now:now(32)});
  // The legacy 100 / list 150 / offer 120 case: the store price decides, not a formula.
  mark('an_offer_that_costs_more_is_rejected_and_written_down',expensive.state==='rejected'&&
    expensive.advantage===false&&expensive.rejection_code==='NO_ADVANTAGE'&&
    sql("SELECT state FROM private_isg.benefit_instances WHERE instance_id="+quote(coupon.instance_id)+";")==='available');
  const good=ok('quote',{instance:coupon.instance_id,mapping,currency:'TRY',current:150000000,offer:120000000,
    observed:now(33),ttl:900,now:now(33)});
  mark('a_real_advantage_reserves_the_benefit_under_a_server_quote',good.state==='issued'&&good.advantage===true&&
    good.eligibility_authority==='server'&&good.price_authority==='store'&&good.percent_approved===false&&
    sql("SELECT state FROM private_isg.benefit_instances WHERE instance_id="+quote(coupon.instance_id)+";")==='reserved');
  const intent=ok('checkout',{quote:good.quote_id,installation:randomUUID(),timeout:120,now:now(34)});
  mark('one_quote_can_not_open_two_checkouts',intent.second_checkout_possible===false&&
    call('checkout',{quote:good.quote_id,installation:randomUUID(),timeout:120,now:now(35)}).error==='INTENT_ALREADY_OPEN'&&
    sql("SELECT count(*) FROM private_isg.checkout_intents WHERE quote_id="+quote(good.quote_id)+";")==='1');
  mark('a_timeout_waits_in_review_instead_of_returning_the_benefit',
    call('timeout',{intent:intent.intent_id,now:now(36)}).error==='VALIDATION_ERROR'&&
    ok('timeout',{intent:intent.intent_id,now:now(200)}).state==='review'&&
    sql("SELECT state FROM private_isg.benefit_instances WHERE instance_id="+quote(coupon.instance_id)+";")==='review');

  const otherEvidence=ok('evidence',evidenceArgs({owner:thirdOwner,environment:'production',
    purchase_ref:'GPA.1212-3434-5656-78787',sequence:3,now:now(201)}));
  mark('another_accounts_receipt_can_not_settle_this_benefit',
    call('settle',{intent:intent.intent_id,evidence:otherEvidence.evidence_id,period_from:'2026-10-01',
      period_to:'2026-11-01',now:now(202)}).error==='ACCESS_DENIED');
  const notPayment=ok('evidence',evidenceArgs({event_kind:'sync',lifecycle_state:'active',sequence:30,
    store_event_at:now(700),now:now(203)}));
  mark('a_sync_event_is_not_a_payment_proof',
    call('settle',{intent:intent.intent_id,evidence:notPayment.evidence_id,period_from:'2026-10-01',
      period_to:'2026-11-01',now:now(204)}).error==='NO_PAYMENT_EVIDENCE');
  const settled=ok('settle',{intent:intent.intent_id,evidence:renewal.evidence_id,period_from:'2026-10-01',
    period_to:'2026-11-01',now:now(205)});
  mark('the_payment_identity_is_read_from_the_store_evidence',settled.state==='consumed'&&
    settled.purchase_ref===purchase&&settled.store==='google'&&settled.environment==='production'&&
    settled.family_in_key===false&&
    sql("SELECT state FROM private_isg.benefit_instances WHERE instance_id="+quote(coupon.instance_id)+";")==='consumed');
  mark('settling_the_same_intent_twice_is_a_replay',
    ok('settle',{intent:intent.intent_id,evidence:renewal.evidence_id,period_from:'2026-10-01',
      period_to:'2026-11-01',now:now(206)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.benefit_settlements;")==='1');

  const second=ok('grant',{owner:ownerID,code:'monthly_discount_one_period',family:'referral:'+ownerID.slice(0,8),
    reason:'ikinci kampanya ailesi',now:now(210)});
  ok('advance',{instance:second.instance_id,target:'available',reason:'kampanya penceresi açıldı',now:now(211)});
  const secondQuote=ok('quote',{instance:second.instance_id,mapping,currency:'TRY',current:150000000,offer:120000000,
    observed:now(212),ttl:900,now:now(212)});
  const secondIntent=ok('checkout',{quote:secondQuote.quote_id,installation:randomUUID(),timeout:120,now:now(213)});
  // One payment, one economic settlement: a second campaign family cannot attach.
  mark('one_payment_settles_exactly_one_benefit',
    call('settle',{intent:secondIntent.intent_id,evidence:renewal.evidence_id,period_from:'2026-10-01',
      period_to:'2026-11-01',now:now(214)}).error==='SETTLEMENT_CONFLICT'&&
    sql("SELECT count(*) FROM private_isg.benefit_settlements WHERE purchase_ref="+quote(purchase)+";")==='1');
  const settlementID=sql("SELECT settlement_id FROM private_isg.benefit_settlements WHERE intent_id="+quote(intent.intent_id)+";");
  const adjusted=ok('adjust',{settlement:settlementID,kind:'refund',reason:'mağaza iade bildirdi',
    evidence:{store:'google'},now:now(220)});
  mark('a_refund_adjusts_the_settlement_without_freeing_the_period',adjusted.state==='adjusted'&&
    adjusted.period_released===false&&
    sql("SELECT state FROM private_isg.benefit_instances WHERE instance_id="+quote(coupon.instance_id)+";")==='adjusted'&&
    call('settle',{intent:secondIntent.intent_id,evidence:renewal.evidence_id,period_from:'2026-10-01',
      period_to:'2026-11-01',now:now(221)}).error==='SETTLEMENT_CONFLICT');
  // Far enough past the second checkout's timeout for it to be counted as waiting.
  const reconciled=ok('reconcile',{for:'2026-09-14',now:now(400)});
  mark('the_daily_reconciliation_counts_what_is_waiting',reconciled.projections_reviewed===1&&
    reconciled.benefits_in_review===0&&reconciled.timed_out_checkouts===1&&
    reconciled.evidence_seen>0&&ok('reconcile',{for:'2026-09-14',now:now(401)}).job_id===reconciled.job_id);

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='billing_lifecycle';");
  mark('kill_switch_stops_the_billing_ledger',
    call('evidence',evidenceArgs({purchase_ref:'GPA.0000-0000-0000-00000',sequence:99,now:now(240)})).error==='FEATURE_UNAVAILABLE'&&
    call('access',{owner:ownerID,environment:'production',now:now(240)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:billingLifecycleFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,access_authority:'legacy',legacy_paid_helper_touched:false,
      store_catalogue_changed:false,offer_generation_enabled:false,signing_material_stored:false,
      approved_commercial_numbers:false,store_sandbox_evidence:false,production_deployed:false};
  }};
}
