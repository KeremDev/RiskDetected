import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const riskCoreFiles=[
  'supabase/migrations/20260913190000_isg_risk_versioning.sql',
  'scripts/isg/risk_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,13,19,0,0)+seconds*1000).toISOString();
const hex=text=>createHash('sha256').update(text).digest('hex');

export async function beginRiskCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_RISK_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_RISK_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('risk_core_'+name,ok);
  sql(read(riskCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='risk';")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");

  sql(["CREATE SCHEMA isg_risk_test;",
    "CREATE FUNCTION isg_risk_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='open' THEN r:=private_isg.open_risk_assessment((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='draft' THEN r:=private_isg.draft_risk_version((a->>'assessment')::uuid,a->>'kind',(a->>'assessment_on')::date,(a->>'revision_on')::date,nullif(a->'scope','null'::jsonb),a->>'reason',(a->>'asset')::uuid,(a->>'expected')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='source' THEN r:=private_isg.attach_risk_source((a->>'assessment')::uuid,(a->>'version')::integer,(a->>'analysis')::uuid,(a->>'finding')::uuid,(a->>'source_version')::bigint,a->'fields',(a->>'now')::timestamptz);",
    "ELSIF kind='impact' THEN r:=private_isg.record_revision_impact((a->>'assessment')::uuid,(a->>'version')::integer,a->>'target_kind',a->>'target_ref',a->>'action',a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='variant' THEN r:=private_isg.attach_rescan_variant((a->>'assessment')::uuid,(a->>'version')::integer,(a->>'asset')::uuid,decode(a->>'sha256','hex'),(a->>'now')::timestamptz);",
    "ELSIF kind='finalize' THEN r:=private_isg.finalize_risk_version((a->>'assessment')::uuid,(a->>'version')::integer,(a->>'expected')::integer,(a->>'verified_by')::uuid,a->>'rule_code',(a->>'period_years')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='drift' THEN r:=private_isg.flag_source_drift((a->>'assessment')::uuid,(a->>'version')::integer,(a->>'analysis')::uuid,(a->>'current_source_version')::bigint,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='dispatch' THEN r:=private_isg.assert_current_risk_version((a->>'assessment')::uuid,(a->>'version')::integer);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','VERSION_CONFLICT','RULE_NEEDS_REVIEW','ASSESSMENT_DATE_IN_FUTURE','ASSESSMENT_DATE_IMMUTABLE','DRAFT_ALREADY_OPEN','VERSION_FINALIZED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_risk_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_RISK_UNEXPECTED_'+r.error);return r.result;};

  mark('gate_blocks_the_domain_while_rollout_off',call('open',{company:companyID,workplace,now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('risk_gate','open_risk_assessment','draft_risk_version','attach_risk_source','record_revision_impact','attach_rescan_variant','finalize_risk_version','flag_source_drift','assert_current_risk_version') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('risk_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('risk','rule_engine');");

  const assessment=ok('open',{company:companyID,workplace,now:now(1)});
  mark('an_assessment_opens_empty_and_replays',assessment.current_version===0&&
    ok('open',{company:companyID,workplace,now:now(2)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.risk_assessments;")==='1');
  mark('a_foreign_workplace_has_no_assessment',call('open',{company:companyID,workplace:randomUUID(),now:now(3)}).error==='ACCESS_DENIED');
  const draft=(over={})=>({assessment:assessment.assessment_id,kind:'full',assessment_on:'2026-06-01',revision_on:null,
    scope:null,reason:null,asset:null,expected:0,now:now(10),...over});
  mark('a_future_assessment_date_is_refused',call('draft',draft({assessment_on:'2027-01-01'})).error==='ASSESSMENT_DATE_IN_FUTURE');
  mark('a_full_assessment_needs_its_real_date',call('draft',draft({assessment_on:null})).error==='VALIDATION_ERROR');
  mark('a_revision_before_any_assessment_is_refused',call('draft',draft({kind:'metadata',assessment_on:null,reason:'Yanlış adres düzeltmesi yapıldı.'})).error==='VALIDATION_ERROR');
  mark('a_stale_expected_version_conflicts',call('draft',draft({expected:7})).error==='VERSION_CONFLICT');
  mark('an_unknown_document_can_not_back_a_version',call('draft',draft({asset:randomUUID()})).error==='ACCESS_DENIED');
  const first=ok('draft',draft({asset}));
  mark('a_full_draft_opens_at_version_one',first.version===1&&first.state==='draft'&&first.date_needs_review===false);
  mark('only_one_draft_at_a_time',call('draft',draft()).error==='DRAFT_ALREADY_OPEN');

  const analysis=randomUUID(),finding=randomUUID();
  const link=ok('source',{assessment:assessment.assessment_id,version:1,analysis,finding,source_version:3,
    fields:{hazard:'Yüksekte çalışma',severity:'high',photo_ref:'p1'},now:now(11)});
  mark('a_finding_enters_only_by_explicit_selection',link.legacy_analysis_written===false&&
    ok('source',{assessment:assessment.assessment_id,version:1,analysis,finding,source_version:3,fields:{hazard:'Yüksekte çalışma',severity:'high',photo_ref:'p1'},now:now(12)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.risk_source_links;")==='1');
  mark('an_impact_list_belongs_to_a_scoped_revision',call('impact',{assessment:assessment.assessment_id,version:1,
    target_kind:'requirement',target_ref:'training.basic_isg',action:'review',note:null,now:now(13)}).error==='VALIDATION_ERROR');
  mark('finalising_needs_a_named_verification',call('finalize',{assessment:assessment.assessment_id,version:1,expected:0,
    verified_by:null,rule_code:null,period_years:2,now:now(14)}).error==='VALIDATION_ERROR');
  mark('a_full_renewal_needs_an_explicit_period',call('finalize',{assessment:assessment.assessment_id,version:1,expected:0,verified_by:ownerID,rule_code:null,period_years:null,now:now(15)}).error==='VALIDATION_ERROR');
  const finalized=ok('finalize',{assessment:assessment.assessment_id,version:1,expected:0,verified_by:ownerID,rule_code:null,period_years:2,now:now(16)});
  mark('a_full_renewal_runs_its_period_from_the_assessment_date',finalized.valid_until==='2028-06-01'&&
    finalized.period_source==='unapproved_fixture'&&finalized.period_needs_review===true&&finalized.assessment_on==='2026-06-01');
  mark('finalising_replays_without_a_second_effect',ok('finalize',{assessment:assessment.assessment_id,version:1,expected:0,verified_by:ownerID,rule_code:null,period_years:2,now:now(17)}).replayed===true);
  mark('a_finalised_version_takes_no_more_sources',call('source',{assessment:assessment.assessment_id,version:1,
    analysis,finding:randomUUID(),source_version:3,fields:{hazard:'Sonradan'},now:now(18)}).error==='VERSION_FINALIZED');

  const beforeRescan=sql("SELECT base_assessment_on||':'||valid_until||':'||current_version FROM private_isg.risk_assessments WHERE assessment_id="+quote(assessment.assessment_id)+";");
  mark('a_rescan_can_not_move_the_legal_date',call('draft',draft({kind:'rescan',assessment_on:'2026-09-13',expected:1})).error==='ASSESSMENT_DATE_IMMUTABLE');
  const rescan=ok('draft',draft({kind:'rescan',assessment_on:null,expected:1}));
  mark('a_rescan_inherits_the_original_date',rescan.assessment_on==='2026-06-01'&&rescan.kind==='rescan');
  const variant=ok('variant',{assessment:assessment.assessment_id,version:rescan.version,asset,sha256:hex('better-scan'),now:now(20)});
  mark('a_better_scan_is_a_file_variant_not_a_renewal',variant.renews_period===false&&variant.base_version===1);
  mark('a_rescan_can_not_ask_for_a_new_period',call('finalize',{assessment:assessment.assessment_id,version:rescan.version,expected:1,verified_by:ownerID,rule_code:null,period_years:3,now:now(21)}).error==='VALIDATION_ERROR');
  const rescanFinal=ok('finalize',{assessment:assessment.assessment_id,version:rescan.version,expected:1,verified_by:ownerID,rule_code:null,period_years:null,now:now(22)});
  mark('an_upload_day_never_becomes_the_legal_date',rescanFinal.valid_until==='2028-06-01'&&rescanFinal.assessment_on==='2026-06-01'&&
    sql("SELECT base_assessment_on||':'||valid_until FROM private_isg.risk_assessments WHERE assessment_id="+quote(assessment.assessment_id)+";")==='2026-06-01:2028-06-01');
  mark('the_previous_final_is_superseded_but_unchanged',sql("SELECT state FROM private_isg.risk_assessment_versions WHERE assessment_id="+quote(assessment.assessment_id)+" AND version=1;")==='superseded'&&
    sql("SELECT assessment_on||':'||valid_until FROM private_isg.risk_assessment_versions WHERE assessment_id="+quote(assessment.assessment_id)+" AND version=1;")==='2026-06-01:2028-06-01');

  mark('a_metadata_correction_needs_a_reason',call('draft',draft({kind:'metadata',assessment_on:null,expected:2})).error==='VALIDATION_ERROR');
  const metadata=ok('draft',draft({kind:'metadata',assessment_on:null,reason:'İşyeri adresi yanlış yazılmıştı, düzeltildi.',expected:2}));
  const metadataFinal=ok('finalize',{assessment:assessment.assessment_id,version:metadata.version,expected:2,verified_by:ownerID,rule_code:null,period_years:null,now:now(30)});
  mark('a_metadata_correction_resets_no_period',metadataFinal.valid_until==='2028-06-01'&&
    sql("SELECT valid_until FROM private_isg.risk_assessments WHERE assessment_id="+quote(assessment.assessment_id)+";")==='2028-06-01');

  mark('a_partial_revision_needs_a_scope',call('draft',draft({kind:'partial',assessment_on:null,reason:'Kaynak makine değişti.',expected:3})).error==='VALIDATION_ERROR');
  const partial=ok('draft',draft({kind:'partial',assessment_on:null,scope:['kaynakhane'],reason:'Kaynak makinesi değişti, bölüm yeniden değerlendirildi.',expected:3}));
  const impact=ok('impact',{assessment:assessment.assessment_id,version:partial.version,target_kind:'curriculum_review',
    target_ref:'basic_isg/G4',action:'review',note:'G4 içeriği gözden geçirilecek.',now:now(40)});
  mark('a_scoped_revision_lists_what_it_touches',impact.action==='review'&&
    ok('impact',{assessment:assessment.assessment_id,version:partial.version,target_kind:'curriculum_review',target_ref:'basic_isg/G4',action:'review',note:null,now:now(41)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.revision_impacts;")==='1');
  const partialFinal=ok('finalize',{assessment:assessment.assessment_id,version:partial.version,expected:3,verified_by:ownerID,rule_code:null,period_years:null,now:now(42)});
  mark('a_scoped_revision_does_not_reset_the_whole_workplace',partialFinal.valid_until==='2028-06-01'&&beforeRescan.endsWith(':1'));

  const renewal=ok('draft',draft({kind:'full',assessment_on:'2026-09-01',expected:4,now:now(50)}));
  mark('a_full_renewal_can_use_a_published_rule_period',(()=>{
    const finalisedRenewal=ok('finalize',{assessment:assessment.assessment_id,version:renewal.version,expected:4,
      verified_by:ownerID,rule_code:'training.basic_isg',period_years:null,now:now(51)});
    return finalisedRenewal.period_source==='rule_version'&&finalisedRenewal.period_needs_review===false&&
      finalisedRenewal.valid_until==='2028-09-01'&&finalisedRenewal.assessment_on==='2026-09-01';})());
  mark('an_unpublished_rule_can_not_set_the_period',(()=>{
    const other=ok('draft',draft({kind:'full',assessment_on:'2026-09-05',expected:5,now:now(52)}));
    const refused=call('finalize',{assessment:assessment.assessment_id,version:other.version,expected:5,verified_by:ownerID,rule_code:'training.orientation',period_years:null,now:now(53)});
    ok('finalize',{assessment:assessment.assessment_id,version:other.version,expected:5,verified_by:ownerID,rule_code:null,period_years:2,now:now(54)});
    return refused.error==='RULE_NEEDS_REVIEW';})());

  const documentBefore=sql("SELECT md5(assessment_on::text||coalesce(valid_until::text,'-')||state) FROM private_isg.risk_assessment_versions WHERE assessment_id="+quote(assessment.assessment_id)+" AND version=1;");
  const quiet=ok('drift',{assessment:assessment.assessment_id,version:1,analysis,current_source_version:3,note:null,now:now(60)});
  mark('an_unchanged_source_raises_no_drift',quiet.source_drift===false);
  const drifted=ok('drift',{assessment:assessment.assessment_id,version:1,analysis,current_source_version:9,note:'Kaynak analiz yeniden çalıştırıldı.',now:now(61)});
  mark('a_drifting_source_only_suggests_a_review',drifted.source_drift===true&&drifted.action==='review_suggested'&&
    documentBefore===sql("SELECT md5(assessment_on::text||coalesce(valid_until::text,'-')||state) FROM private_isg.risk_assessment_versions WHERE assessment_id="+quote(assessment.assessment_id)+" AND version=1;"));
  mark('drift_needs_a_linked_source',call('drift',{assessment:assessment.assessment_id,version:1,analysis:randomUUID(),current_source_version:9,note:null,now:now(62)}).error==='ACCESS_DENIED');

  const current=Number(sql("SELECT current_version FROM private_isg.risk_assessments WHERE assessment_id="+quote(assessment.assessment_id)+";"));
  mark('a_stale_queued_document_is_stopped',call('dispatch',{assessment:assessment.assessment_id,version:1}).error==='VERSION_CONFLICT'&&
    ok('dispatch',{assessment:assessment.assessment_id,version:current}).dispatch_allowed===true);
  mark('a_very_old_date_is_flagged_for_review',ok('draft',draft({kind:'full',assessment_on:'2010-01-01',expected:current,now:now(71)})).date_needs_review===true);
  sql("DELETE FROM private_isg.risk_assessment_versions WHERE assessment_id="+quote(assessment.assessment_id)+" AND state='draft';");

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('risk','rule_engine');");
  mark('kill_switch_stops_the_risk_domain',call('draft',draft({expected:current,now:now(80)})).error==='FEATURE_UNAVAILABLE'&&
    call('dispatch',{assessment:assessment.assessment_id,version:current}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:riskCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,legacy_analysis_written:false,document_export_implemented:false,
      score_contribution_connected:false,production_deployed:false};
  }};
}
