import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const ruleCoreFiles=[
  'supabase/migrations/20260913150000_isg_rule_core.sql',
  'scripts/isg/rule_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const at=seconds=>new Date(Date.UTC(2026,8,13,15,0,0)+seconds*1000).toISOString();
const digest=text=>createHash('sha256').update(text).digest('hex');

export async function beginRuleCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_RULE_CORE_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_RULE_CORE_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('rule_core_'+name,ok);
  sql(read(ruleCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='rule_engine';")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");

  sql(["CREATE SCHEMA isg_rule_test;",
    "CREATE FUNCTION isg_rule_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='evaluate' THEN r:=private_isg.evaluate_applicability(a->'expression',a->'facts');",
    "ELSIF kind='due' THEN r:=to_jsonb(private_isg.next_due_on((a->>'from')::date,a->>'kind',(a->>'length')::integer));",
    "ELSIF kind='source' THEN r:=private_isg.register_legal_source(a->>'jurisdiction',a->>'citation',a->>'url',decode(a->>'sha256','hex'),(a->>'retrieved_at')::timestamptz,(a->>'from')::date,(a->>'to')::date,(a->>'verified_by')::uuid,a->>'evidence',(a->>'now')::timestamptz);",
    "ELSIF kind='rule' THEN r:=private_isg.add_rule_version(a->>'code',(a->>'source')::uuid,a->'expression',a->>'action',a->>'period_kind',(a->>'period_length')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='simulate' THEN r:=private_isg.simulate_rule_version(a->>'code',(a->>'version')::integer,a->'samples',(a->>'now')::timestamptz);",
    "ELSIF kind='publish' THEN r:=private_isg.publish_rule_version(a->>'code',(a->>'version')::integer,(a->>'approver')::uuid,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='decide' THEN r:=private_isg.decide_applicability((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'code',(a->>'on')::date,a->'facts',(a->>'now')::timestamptz);",
    "ELSIF kind='open' THEN r:=private_isg.open_requirement((a->>'decision')::uuid,(a->>'period_start')::date,a->>'timezone',(a->>'now')::timestamptz);",
    "ELSIF kind='reschedule' THEN r:=private_isg.reschedule_requirement((a->>'requirement')::uuid,(a->>'due')::date,a->>'timezone',a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='close' THEN r:=private_isg.close_requirement((a->>'requirement')::uuid,a->>'status',a->>'reason',(a->>'now')::timestamptz);",
    "ELSIF kind='reconcile' THEN r:=private_isg.reconcile_rules((a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','RULE_NEEDS_REVIEW') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_rule_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_RULE_CORE_UNEXPECTED_'+r.error);return r.result;};

  const highRisk={all:[{fact:'jurisdiction',eq:'TR'},{fact:'hazard_class',in:['high','medium']},{fact:'employee_count',gte:50}]};
  // Evaluation is a pure expression function; only the write path is gated.
  mark('gate_blocks_the_registry_and_the_decision_while_rollout_off',
    call('source',{jurisdiction:'TR',citation:'x',url:'https://example.invalid/a',sha256:digest('a'),retrieved_at:at(-10),from:'2026-01-01',to:null,verified_by:null,evidence:null,now:at(0)}).error==='FEATURE_UNAVAILABLE'&&
    call('decide',{company:companyID,workplace,code:'training.basic_isg',on:'2026-09-13',facts:{jurisdiction:'TR'},now:at(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('rule_gate','validate_rule_expression','evaluate_applicability','next_due_on','register_legal_source','add_rule_version','simulate_rule_version','publish_rule_version','decide_applicability','open_requirement','reschedule_requirement','close_requirement','reconcile_rules') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('rule_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='rule_engine';");

  const bad=[{},{all:[],any:[]},{maybe:[{fact:'hazard_class',eq:'high'}]},{all:[]},
    {all:[{fact:'unknown_fact',eq:'x'}]},{all:[{fact:'hazard_class',matches:'x'}]},
    {all:[{fact:'hazard_class',in:[1]}]},{all:[{fact:'hazard_class',gte:5}]},
    {all:[{fact:'hazard_class',eq:'high',extra:1}]},{all:Array.from({length:9},()=>({fact:'hazard_class',eq:'high'}))}];
  mark('the_expression_grammar_is_bounded',bad.every(expression=>call('evaluate',{expression,facts:{hazard_class:'high'}}).error==='VALIDATION_ERROR'));
  const evaluate=(expression,facts)=>ok('evaluate',{expression,facts});
  const full={jurisdiction:'TR',hazard_class:'high',employee_count:120,industry_code:'41.20'};
  mark('all_requires_every_clause',evaluate(highRisk,full).state==='required'&&
    evaluate(highRisk,{...full,employee_count:10}).state==='not_required'&&
    evaluate(highRisk,{...full,hazard_class:'low'}).reason==='CLAUSE_NOT_MATCHED');
  const missing=evaluate(highRisk,{jurisdiction:'TR',hazard_class:'high'});
  mark('a_missing_fact_is_review_not_a_denial',missing.state==='needs_review'&&missing.reason==='FACT_UNKNOWN'&&
    JSON.stringify(missing.missing_facts)===JSON.stringify(['employee_count']));
  mark('a_definite_mismatch_outranks_an_unknown_fact',evaluate(highRisk,{jurisdiction:'TR',hazard_class:'low'}).state==='not_required');
  mark('a_fact_of_the_wrong_type_is_unknown_not_false',evaluate(highRisk,{...full,employee_count:'çok'}).state==='needs_review');
  const anyOf={any:[{fact:'hazard_class',in:['high']},{fact:'industry_code',in:['41.20']}]};
  mark('any_needs_one_clause_and_keeps_unknowns_in_review',evaluate(anyOf,{hazard_class:'low',industry_code:'41.20'}).state==='required'&&
    evaluate(anyOf,{hazard_class:'low',industry_code:'10.10'}).state==='not_required'&&
    evaluate(anyOf,{hazard_class:'low'}).state==='needs_review');
  mark('not_in_and_lte_close_the_operator_set',evaluate({all:[{fact:'hazard_class',not_in:['low']}]},{hazard_class:'high'}).state==='required'&&
    evaluate({all:[{fact:'employee_count',lte:10}]},{employee_count:11}).state==='not_required');

  const due=(from,kind,length)=>ok('due',{from,kind,length});
  mark('a_month_lands_on_the_last_valid_day',due('2026-01-31','months',1)==='2026-02-28'&&due('2028-01-31','months',1)==='2028-02-29');
  mark('a_year_is_a_calendar_year_not_365_days',due('2027-03-01','years',1)==='2028-03-01'&&due('2028-02-29','years',1)==='2029-02-28');
  mark('twelve_months_and_one_year_agree',due('2026-09-13','months',12)===due('2026-09-13','years',1));
  mark('a_once_rule_is_due_on_its_start_and_rejects_a_length',due('2026-09-13','once',null)==='2026-09-13'&&
    call('due',{from:'2026-09-13',kind:'once',length:12}).error==='VALIDATION_ERROR'&&
    call('due',{from:'2026-09-13',kind:'years',length:null}).error==='VALIDATION_ERROR');

  const sourceArgs=(over={})=>({jurisdiction:'TR',citation:'6331 sayılı Kanun m.17',url:'https://www.resmigazete.gov.tr/eskiler/2026/04/20260402-2.htm',
    sha256:digest('official-text'),retrieved_at:at(-60),from:'2026-04-02',to:null,verified_by:null,evidence:null,now:at(0),...over});
  const unverified=ok('source',sourceArgs({url:'https://example.invalid/only-a-link',sha256:digest('only-a-link')}));
  mark('a_url_alone_never_clears_review',unverified.needs_review===true);
  mark('a_reviewer_without_a_written_note_stays_in_review',ok('source',sourceArgs({url:'https://example.invalid/no-note',sha256:digest('no-note'),verified_by:ownerID})).needs_review===true);
  const verified=ok('source',sourceArgs({verified_by:ownerID,evidence:'Resmî Gazete metni indirildi, madde 17 ve yürürlük tarihi elle karşılaştırıldı.'}));
  mark('a_checksummed_reviewed_source_leaves_review',verified.needs_review===false);
  mark('the_same_document_is_registered_once',ok('source',sourceArgs({verified_by:ownerID,evidence:'Tekrar kayıt denemesi, aynı belge ve aynı özet.'})).replayed===true);
  mark('a_retrieval_from_the_future_is_refused',call('source',sourceArgs({url:'https://example.invalid/future',sha256:digest('future'),retrieved_at:at(600)})).error==='VALIDATION_ERROR');

  const code='training.basic_isg';
  const draft=ok('rule',{code,source:verified.source_id,expression:highRisk,action:'training',period_kind:'years',period_length:1,now:at(10)});
  mark('a_new_rule_starts_as_a_draft',draft.version===1&&draft.status==='draft'&&draft.jurisdiction==='TR');
  mark('an_invalid_action_or_period_never_creates_a_version',
    call('rule',{code,source:verified.source_id,expression:highRisk,action:'sacrifice',period_kind:'years',period_length:1,now:at(11)}).error==='VALIDATION_ERROR'&&
    call('rule',{code,source:verified.source_id,expression:highRisk,action:'training',period_kind:'days',period_length:365,now:at(11)}).error==='VALIDATION_ERROR'&&
    sql("SELECT count(*) FROM private_isg.rule_versions WHERE rule_code="+quote(code)+";")==='1');
  mark('a_draft_can_not_be_published',call('publish',{code,version:1,approver:ownerID,note:'Onay',now:at(12)}).error==='RULE_NEEDS_REVIEW');
  const samples=[full,{...full,employee_count:10},{jurisdiction:'TR',hazard_class:'high'}];
  const simulated=ok('simulate',{code,version:1,samples,now:at(13)});
  mark('simulation_reports_the_three_outcomes',simulated.required===1&&simulated.not_required===1&&simulated.needs_review===1&&simulated.status==='simulated');
  const unverifiedRule=ok('rule',{code:'training.orientation',source:unverified.source_id,expression:highRisk,action:'training',period_kind:'once',period_length:null,now:at(14)});
  ok('simulate',{code:'training.orientation',version:unverifiedRule.version,samples,now:at(15)});
  mark('a_source_in_review_can_not_be_published',call('publish',{code:'training.orientation',version:1,approver:ownerID,note:'Onay',now:at(16)}).error==='RULE_NEEDS_REVIEW');
  mark('publishing_requires_a_named_approval_note',call('publish',{code,version:1,approver:ownerID,note:null,now:at(17)}).error==='VALIDATION_ERROR'&&
    call('publish',{code,version:1,approver:null,note:'Onay',now:at(17)}).error==='VALIDATION_ERROR');
  const published=ok('publish',{code,version:1,approver:ownerID,note:'İçerik incelemesi 13 Eylül 2026 tarihinde tamamlandı.',now:at(18)});
  mark('a_verified_simulated_rule_publishes_with_its_approver',published.status==='published'&&
    sql("SELECT approved_by="+quote(ownerID)+" AND published_at IS NOT NULL FROM private_isg.rule_versions WHERE rule_code="+quote(code)+" AND version=1;")==='t');
  mark('publishing_replays_without_a_second_effect',ok('publish',{code,version:1,approver:ownerID,note:'Tekrar',now:at(19)}).replayed===true);

  const decide=(over={})=>({company:companyID,workplace,code,on:'2026-09-13',facts:full,now:at(20),...over});
  mark('an_unpublished_rule_makes_no_decision',call('decide',decide({code:'training.orientation'})).error==='RULE_NEEDS_REVIEW');
  mark('a_foreign_workplace_is_denied',call('decide',decide({workplace:randomUUID()})).error==='ACCESS_DENIED');
  const abroad=ok('decide',decide({facts:{...full,jurisdiction:'DE'},on:'2026-09-10'}));
  mark('a_turkish_rule_is_not_applied_abroad',abroad.state==='not_required'&&abroad.reason==='JURISDICTION_MISMATCH');
  const unknownJurisdiction=ok('decide',decide({facts:{hazard_class:'high',employee_count:120},on:'2026-09-11'}));
  mark('an_unknown_jurisdiction_is_review',unknownJurisdiction.state==='needs_review'&&unknownJurisdiction.reason==='JURISDICTION_UNKNOWN');
  const decision=ok('decide',decide());
  mark('a_matching_context_becomes_a_required_decision',decision.state==='required'&&decision.rule_version===1);
  mark('the_same_context_and_day_decides_once',ok('decide',decide()).replayed===true&&
    sql("SELECT count(*) FROM private_isg.applicability_decisions WHERE decided_on='2026-09-13' AND company_id="+quote(companyID)+";")==='1');
  sql("UPDATE private_isg.workplaces SET context_version=context_version+1 WHERE id="+quote(workplace)+";");
  mark('a_changed_context_version_is_decided_again',ok('decide',decide({now:at(21)})).replayed===false&&
    sql("SELECT count(*) FROM private_isg.applicability_decisions WHERE decided_on='2026-09-13' AND company_id="+quote(companyID)+";")==='2');

  mark('only_a_required_decision_opens_an_obligation',call('open',{decision:unknownJurisdiction.decision_id,period_start:'2026-09-13',timezone:'Europe/Istanbul',now:at(22)}).error==='RULE_NEEDS_REVIEW');
  mark('an_unknown_timezone_is_refused',call('open',{decision:decision.decision_id,period_start:'2026-09-13',timezone:'Mars/Olympus',now:at(22)}).error==='VALIDATION_ERROR');
  const requirement=ok('open',{decision:decision.decision_id,period_start:'2026-09-13',timezone:'Europe/Istanbul',now:at(23)});
  mark('an_obligation_carries_a_dated_schedule',requirement.status==='open'&&requirement.due_on==='2027-09-13'&&requirement.schedule_version===1&&requirement.period_key==='2026-09-13');
  mark('one_obligation_per_rule_action_and_period',ok('open',{decision:decision.decision_id,period_start:'2026-09-13',timezone:'Europe/Istanbul',now:at(24)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.requirement_instances WHERE company_id="+quote(companyID)+";")==='1');
  const rescheduled=ok('reschedule',{requirement:requirement.requirement_id,due:'2027-06-30',timezone:'Europe/Istanbul',reason:'CONTEXT_CHANGED',now:at(30)});
  mark('a_new_schedule_invalidates_the_old_one_instead_of_editing_it',rescheduled.schedule_version===2&&
    sql("SELECT state||':'||coalesce(invalidated_reason,'-') FROM private_isg.requirement_schedules WHERE requirement_id="+quote(requirement.requirement_id)+" AND version=1;")==='invalidated:CONTEXT_CHANGED'&&
    sql("SELECT count(*) FROM private_isg.requirement_schedules WHERE requirement_id="+quote(requirement.requirement_id)+" AND state='active';")==='1');
  mark('an_unchanged_reschedule_is_a_replay',ok('reschedule',{requirement:requirement.requirement_id,due:'2027-06-30',timezone:'Europe/Istanbul',reason:'CONTEXT_CHANGED',now:at(31)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.requirement_schedules WHERE requirement_id="+quote(requirement.requirement_id)+";")==='2');
  mark('a_cancelled_obligation_needs_a_reason',call('close',{requirement:requirement.requirement_id,status:'cancelled',reason:null,now:at(32)}).error==='VALIDATION_ERROR'&&
    call('close',{requirement:requirement.requirement_id,status:'satisfied',reason:'WHY',now:at(32)}).error==='VALIDATION_ERROR');

  const report=ok('reconcile',{on:'2026-09-14',now:at(40)});
  mark('reconciliation_sees_review_and_missing_obligations',report.sources_in_review>=1&&report.decisions_in_review>=1&&
    report.required_without_requirement>=1&&report.open_requirements===1&&report.published_rules===1);
  mark('reconciliation_keeps_one_row_per_day',!!ok('reconcile',{on:'2026-09-14',now:at(41)})&&sql("SELECT count(*) FROM private_isg.rule_reconciliations;")==='1');
  const closed=ok('close',{requirement:requirement.requirement_id,status:'satisfied',reason:null,now:at(50)});
  mark('a_satisfied_obligation_completes_its_schedule',closed.status==='satisfied'&&
    sql("SELECT count(*) FROM private_isg.requirement_schedules WHERE requirement_id="+quote(requirement.requirement_id)+" AND state='completed';")==='1'&&
    ok('close',{requirement:requirement.requirement_id,status:'satisfied',reason:null,now:at(51)}).replayed===true);
  const second=ok('rule',{code,source:verified.source_id,expression:anyOf,action:'training',period_kind:'years',period_length:2,now:at(60)});
  ok('simulate',{code,version:second.version,samples,now:at(61)});
  const republished=ok('publish',{code,version:second.version,approver:ownerID,note:'İkinci sürüm içerik onayı.',now:at(62)});
  mark('a_new_published_version_supersedes_the_previous_one',republished.superseded_version===1&&
    sql("SELECT count(*) FROM private_isg.rule_versions WHERE rule_code="+quote(code)+" AND status='published';")==='1'&&
    sql("SELECT status FROM private_isg.rule_versions WHERE rule_code="+quote(code)+" AND version=1;")==='superseded');
  mark('a_closed_obligation_is_not_flagged_on_a_superseded_rule',ok('reconcile',{on:'2026-09-15',now:at(63)}).requirements_on_superseded_rules===0);

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='rule_engine';");
  mark('kill_switch_stops_the_rule_engine',call('decide',decide({now:at(70)})).error==='FEATURE_UNAVAILABLE'&&
    call('reconcile',{on:'2026-09-16',now:at(70)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:ruleCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,official_2026_content_verified:false,real_legal_catalogue_loaded:false,
      task_or_notification_consumer_connected:false,production_deployed:false};
  }};
}
