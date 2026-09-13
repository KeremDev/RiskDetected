import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const scorePortfolioFiles=[
  'supabase/migrations/20260914150000_isg_score_portfolio.sql',
  'scripts/isg/score_portfolio_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,15,0,0)+seconds*1000).toISOString();

// Candidate V5 weights 25/25/15/15/10/10 with one deliberately tighter cap.
const PROCESSES=[['risk_assessment',25,25],['training',25,25],['health_surveillance_followup',15,5],
  ['nonconformity',15,15],['emergency_readiness',10,10],['records_and_documents',10,10]];

export async function beginScorePortfolioProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_SCORE_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('AUTH_RESTORE_SCORE_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('score_portfolio_'+name,ok);
  sql(read(scorePortfolioFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='score';")==='t');

  sql(["CREATE SCHEMA isg_score_test;",
    "CREATE FUNCTION isg_score_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; err_code text; BEGIN",
    "IF kind='publish' THEN r:=private_isg.publish_score_policy((a->>'policy')::uuid,(a->>'approver')::uuid,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='declare' THEN r:=private_isg.declare_subject_state((a->>'company')::uuid,a->>'process',a->>'applicability',",
    "  (a->>'completed')::bigint,(a->>'required')::bigint,a->>'justification',(a->>'verified_by')::uuid,",
    "  (a->>'verified_on')::date,a->>'context',(a->>'now')::timestamptz);",
    "ELSIF kind='compute' THEN r:=private_isg.compute_score_snapshot((a->>'company')::uuid,(a->>'policy')::uuid,",
    "  (a->>'for')::date,a->'context',(a->>'now')::timestamptz);",
    "ELSIF kind='explain' THEN r:=private_isg.explain_score((a->>'snapshot')::uuid);",
    "ELSIF kind='critical' THEN r:=private_isg.raise_score_critical_finding((a->>'snapshot')::uuid,a->>'code',a->>'process',a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='oracle' THEN r:=private_isg.verify_against_oracle(a->>'fixture',(a->>'snapshot')::uuid);",
    "ELSIF kind='simulate' THEN r:=private_isg.simulate_policy_change((a->>'from')::uuid,(a->>'to')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='portfolio' THEN r:=private_isg.build_portfolio_projection((a->>'owner')::uuid,(a->>'policy')::uuid,",
    "  (a->>'for')::date,a->'companies',(a->>'now')::timestamptz);",
    "ELSIF kind='force_publish_without_approval' THEN UPDATE private_isg.score_policy_versions SET status='published',",
    "  published_at=(a->>'now')::timestamptz WHERE policy_version_id=(a->>'policy')::uuid; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_approved_weights' THEN UPDATE private_isg.score_policy_versions SET weights_approved=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_official_certificate' THEN UPDATE private_isg.score_policy_versions SET is_official_compliance_certificate=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_snapshot_certificate' THEN UPDATE private_isg.score_snapshots SET is_official_certificate=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_approved_cap' THEN UPDATE private_isg.score_processes SET cap_approved=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_cap_over_weight' THEN UPDATE private_isg.score_processes SET contribution_cap=99 WHERE process_key='training'; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_unverified_exemption' THEN INSERT INTO private_isg.score_subject_states(company_id,process_key,",
    "  applicability,source_context,recorded_at) VALUES((a->>'company')::uuid,'nonconformity','not_required','probe',(a->>'now')::timestamptz); r:=to_jsonb('inserted'::text);",
    "ELSIF kind='force_hidden_warning' THEN UPDATE private_isg.score_critical_findings SET hidden_by_total_score=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_oracle_from_function' THEN UPDATE private_isg.score_oracle_fixtures SET computed_by_production_function=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_headcount_weight' THEN UPDATE private_isg.portfolio_projections SET headcount_used_as_weight=true; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_entry_weight' THEN UPDATE private_isg.portfolio_entries SET portfolio_weight=0.5; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_history_rewritten' THEN UPDATE private_isg.score_simulations SET history_rewritten=true; r:=to_jsonb('updated'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS err_code=MESSAGE_TEXT;",
    "IF err_code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','POLICY_INCOMPLETE',",
    "  'POLICY_NOT_PUBLISHED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',err_code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_score_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_SCORE_UNEXPECTED_'+r.error);return r.result;};

  const policy1=randomUUID(), policy2=randomUUID(), emptyPolicy=randomUUID();
  const expert=randomUUID(), approver=randomUUID();
  const rows=(id,caps)=>PROCESSES.map(([key,weight,cap],i)=>"("+quote(id)+","+quote(key)+","+weight+","+(caps?caps[i]:cap)+")").join(',');
  sql(["INSERT INTO private_isg.score_policy_versions(policy_version_id,revision) VALUES("+quote(policy1)+",1),("+quote(policy2)+",2),("+quote(emptyPolicy)+",3);",
    "INSERT INTO private_isg.score_processes(policy_version_id,process_key,weight,contribution_cap) VALUES "+rows(policy1)+";",
    // Revision 2 differs in one number only: the tight cap is lifted to its weight.
    "INSERT INTO private_isg.score_processes(policy_version_id,process_key,weight,contribution_cap) VALUES "+rows(policy2,[25,25,15,15,10,10])+";"].join('\n'));
  mark('gate_blocks_the_score_while_rollout_off',
    call('publish',{policy:policy1,approver,note:'onay',now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('score_gate','publish_score_policy','declare_subject_state','score_preview','compute_score_snapshot','explain_score','raise_score_critical_finding','verify_against_oracle','simulate_policy_change','build_portfolio_projection') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('score_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  mark('a_policy_can_not_publish_itself_without_a_human',
    call('force_publish_without_approval',{policy:policy1,now:now(1)}).error==='CHECK_VIOLATION');
  mark('the_score_can_never_call_itself_an_official_certificate',
    call('force_official_certificate',{}).error==='CHECK_VIOLATION'&&
    call('force_approved_weights',{}).error==='CHECK_VIOLATION'&&
    call('force_approved_cap',{}).error==='CHECK_VIOLATION');
  mark('a_cap_can_never_exceed_its_own_weight',call('force_cap_over_weight',{}).error==='CHECK_VIOLATION');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='score';");

  mark('a_policy_without_a_single_process_can_not_publish',
    call('publish',{policy:emptyPolicy,approver,note:'boş politika',now:now(2)}).error==='POLICY_INCOMPLETE');
  const published=ok('publish',{policy:policy1,approver,note:'uzman ve işveren kararı kaydı',now:now(3)});
  ok('publish',{policy:policy2,approver,note:'ikinci revizyon kararı',now:now(3)});
  mark('publication_records_the_human_and_keeps_the_weights_unapproved',published.status==='published'&&
    published.process_count===6&&Number(published.weight_sum)===100&&published.weights_approved===false&&
    published.is_official_compliance_certificate===false&&
    ok('publish',{policy:policy1,approver,note:'tekrar',now:now(4)}).replayed===true);

  const goldenCompany=companyID, emptyCompany=randomUUID(), voluntaryCompany=randomUUID();
  const declare=(company,process,over={})=>ok('declare',{company,process,applicability:'required',completed:null,
    required:null,justification:null,verified_by:null,verified_on:null,context:'probe fixture',now:now(10),...over});
  mark('an_unpublished_policy_computes_nothing',
    call('compute',{company:goldenCompany,policy:emptyPolicy,for:'2026-09-14',context:{},now:now(11)}).error==='POLICY_NOT_PUBLISHED');
  mark('leaving_a_process_out_of_the_score_needs_a_verified_reason',
    call('force_unverified_exemption',{company:goldenCompany,now:now(12)}).error==='CHECK_VIOLATION');

  // Hand worked out: 0.5*25=12.5, 1*25=25, 1*15 capped to 5, exemption out,
  // unknown keeps its 10 in the denominator, voluntary is neutral.
  // total weight 75, earned 42.5, score 100*42.5/75 = 56.67
  declare(goldenCompany,'risk_assessment',{completed:4,required:8});
  declare(goldenCompany,'training',{completed:8,required:8});
  declare(goldenCompany,'health_surveillance_followup',{completed:10,required:10});
  declare(goldenCompany,'nonconformity',{applicability:'not_required',justification:'işyeri kapsam dışı, uzman doğruladı',
    verified_by:expert,verified_on:'2026-09-10'});
  declare(goldenCompany,'emergency_readiness',{applicability:'needs_review'});
  const neutral=declare(goldenCompany,'records_and_documents',{applicability:'voluntary'});
  mark('a_voluntary_record_never_enters_the_main_score',neutral.counts_in_main_score===false);
  sql(["INSERT INTO private_isg.score_oracle_fixtures(fixture_key,expected_main_score,expected_provisional,",
    "  expected_total_weight,expected_earned_points,verified_by,verified_on,note) VALUES",
    "('golden_mixed_company',56.67,true,75.000,42.500,"+quote(expert)+",'2026-09-14','elle: 12.5+25+5(cap)+0 / 75'),",
    "('golden_empty_company',NULL,true,100.000,0.000,"+quote(expert)+",'2026-09-14','elle: veri yok, sayı yok'),",
    "('golden_all_voluntary',NULL,true,0.000,0.000,"+quote(expert)+",'2026-09-14','elle: gönüllü kayıt nötr');"].join('\n'));
  const golden=ok('compute',{company:goldenCompany,policy:policy1,for:'2026-09-14',
    context:{source:'probe'},now:now(20)});
  const goldenCheck=ok('oracle',{fixture:'golden_mixed_company',snapshot:golden.snapshot_id});
  mark('the_production_number_matches_a_hand_computed_oracle',goldenCheck.matched===true&&
    Number(goldenCheck.actual_main_score)===56.67&&Number(goldenCheck.actual_total_weight)===75&&
    Number(goldenCheck.actual_earned_points)===42.5&&goldenCheck.hand_computed===true&&
    goldenCheck.computed_by_production_function===false);
  mark('the_oracle_can_not_be_relabelled_as_a_second_call',
    call('force_oracle_from_function',{}).error==='CHECK_VIOLATION');
  const explained=ok('explain',{snapshot:golden.snapshot_id});
  const line=key=>explained.contributions.find(c=>c.process_key===key);
  mark('every_number_on_screen_traces_back_to_one_process',explained.contributions.length===6&&
    Number(line('risk_assessment').capped_points)===12.5&&
    Number(line('training').capped_points)===25);
  mark('a_contribution_cap_really_limits_one_process',line('health_surveillance_followup').cap_applied===true&&
    Number(line('health_surveillance_followup').capped_points)===5&&
    Number(line('health_surveillance_followup').raw_ratio)===1);
  mark('a_verified_exemption_leaves_the_denominator_entirely',
    line('nonconformity').counted_in_total_weight===false&&
    line('nonconformity').exclusion_reason==='verified_not_required');
  mark('an_unknown_process_stays_in_the_denominator_and_marks_the_answer_provisional',
    line('emergency_readiness').applicability==='needs_review'&&
    line('emergency_readiness').counted_in_total_weight===true&&
    Number(line('emergency_readiness').capped_points)===0&&golden.provisional===true&&
    golden.needs_review_count===1);
  mark('a_voluntary_process_is_neutral_on_both_sides',
    line('records_and_documents').counted_in_total_weight===false&&
    line('records_and_documents').exclusion_reason==='voluntary'&&
    Number(line('records_and_documents').capped_points)===0&&golden.voluntary_count===1);

  const empty=ok('compute',{company:emptyCompany,policy:policy1,for:'2026-09-14',context:{source:'probe'},now:now(21)});
  mark('a_company_with_no_data_is_never_a_hundred',empty.main_score===null&&empty.provisional===true&&
    empty.has_any_data===false&&empty.needs_review_count===6&&
    ok('oracle',{fixture:'golden_empty_company',snapshot:empty.snapshot_id}).matched===true);
  mark('a_missing_row_is_unknown_and_never_an_exemption',
    sql("SELECT count(*) FROM private_isg.score_contributions c JOIN private_isg.score_snapshots s ON s.snapshot_id=c.snapshot_id WHERE s.snapshot_id="+quote(empty.snapshot_id)+" AND c.exclusion_reason IS NOT NULL;")==='0');
  for(const [key] of PROCESSES) declare(voluntaryCompany,key,{applicability:'voluntary',now:now(22)});
  const allVoluntary=ok('compute',{company:voluntaryCompany,policy:policy1,for:'2026-09-14',
    context:{source:'probe'},now:now(23)});
  mark('a_company_that_only_volunteers_has_no_number_either',allVoluntary.main_score===null&&
    Number(allVoluntary.total_weight)===0&&allVoluntary.provisional===true&&
    ok('oracle',{fixture:'golden_all_voluntary',snapshot:allVoluntary.snapshot_id}).matched===true);

  const warned=ok('critical',{snapshot:golden.snapshot_id,code:'RISK_ASSESSMENT_EXPIRED',process:'risk_assessment',
    note:'geçerli risk değerlendirmesi yok',now:now(30)});
  const explainedAgain=ok('explain',{snapshot:golden.snapshot_id});
  mark('a_critical_warning_stands_beside_the_number_not_inside_it',warned.critical_count===1&&
    warned.hidden_by_total_score===false&&explainedAgain.critical_findings.length===1&&
    explainedAgain.critical_findings_hidden===false&&
    Number(explainedAgain.main_score)===56.67&&
    call('force_hidden_warning',{}).error==='CHECK_VIOLATION');
  mark('recomputing_the_same_day_is_a_replay',
    ok('compute',{company:goldenCompany,policy:policy1,for:'2026-09-14',context:{source:'probe'},now:now(31)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.score_snapshots WHERE company_id="+quote(goldenCompany)+";")==='1');

  // The second revision lifts the tight cap: 12.5+25+15+0 = 52.5 / 75 = 70.00
  const simulation=ok('simulate',{from:policy1,to:policy2,now:now(40)});
  mark('a_simulation_writes_no_snapshot_and_rewrites_no_history',simulation.history_rewritten===false&&
    simulation.snapshots_written===0&&simulation.companies_compared===3&&
    sql("SELECT count(*) FROM private_isg.score_snapshots;")==='3'&&
    call('force_history_rewritten',{}).error==='CHECK_VIOLATION');
  mark('the_simulated_delta_matches_the_hand_computed_change',Number(simulation.max_absolute_delta)===13.33);
  const newSnapshot=ok('compute',{company:goldenCompany,policy:policy2,for:'2026-09-14',
    context:{source:'probe'},now:now(41)});
  mark('a_new_policy_adds_a_snapshot_and_never_rewrites_the_old_one',Number(newSnapshot.main_score)===70&&
    sql("SELECT main_score FROM private_isg.score_snapshots WHERE snapshot_id="+quote(golden.snapshot_id)+";")==='56.67'&&
    sql("SELECT count(*) FROM private_isg.score_snapshots WHERE company_id="+quote(goldenCompany)+";")==='2');

  const portfolio=ok('portfolio',{owner:ownerID,policy:policy1,for:'2026-09-14',now:now(50),
    companies:[{company_id:goldenCompany,employee_count:1200},{company_id:emptyCompany,employee_count:3},
      {company_id:voluntaryCompany,employee_count:7}]});
  // 1200 employees and 3 employees weigh exactly the same: one company, one vote.
  mark('a_big_company_never_takes_over_the_portfolio',portfolio.weighting==='equal_per_company'&&
    portfolio.headcount_used_as_weight===false&&portfolio.companies_total===3&&
    portfolio.companies_scored===1&&portfolio.companies_provisional===3&&
    Number(portfolio.average_main_score)===56.67&&
    sql("SELECT bool_and(portfolio_weight=1) FROM private_isg.portfolio_entries;")==='t');
  mark('a_headcount_can_never_become_a_weight',call('force_headcount_weight',{}).error==='CHECK_VIOLATION'&&
    call('force_entry_weight',{}).error==='CHECK_VIOLATION');
  const emptyPortfolio=ok('portfolio',{owner:ownerID,policy:policy2,for:'2026-09-15',now:now(51),
    companies:[{company_id:emptyCompany,employee_count:3}]});
  mark('a_portfolio_with_nothing_scored_has_no_average',emptyPortfolio.average_main_score===null&&
    emptyPortfolio.companies_scored===0&&emptyPortfolio.companies_provisional===1&&
    ok('portfolio',{owner:ownerID,policy:policy1,for:'2026-09-14',now:now(52),companies:[]}).replayed===true);
  mark('no_snapshot_can_be_relabelled_as_a_certificate',
    call('force_snapshot_certificate',{}).error==='CHECK_VIOLATION');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='score';");
  mark('kill_switch_stops_the_score_ledger',
    call('compute',{company:goldenCompany,policy:policy1,for:'2026-09-16',context:{},now:now(60)}).error==='FEATURE_UNAVAILABLE'&&
    call('explain',{snapshot:golden.snapshot_id}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:scorePortfolioFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,weights_approved:false,official_certificate_claimed:false,
      hundred_shown_without_data:false,history_rewritten:false,headcount_used_as_weight:false,
      oracle_is_hand_computed:true,client_surface_built:false,production_deployed:false};
  }};
}
