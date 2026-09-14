import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const nonconformityHTTPFiles=[
  'supabase/migrations/20260914170000_isg_nonconformity_owner_rpc.sql',
  'scripts/isg/nonconformity_http_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');

export async function beginNonconformityHTTPProbe({synthetic,sql,request,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_NONCONFORMITY_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID||typeof request!=='function')throw Error('AUTH_RESTORE_NONCONFORMITY_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('nonconformity_http_'+name,ok);
  sql(read(nonconformityHTTPFiles[0]));
  mark('migration_applied_without_opening_the_switch',
    sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='nonconformity';")==='t');

  const post=(path,body,options={})=>request('/rpc/'+path,{method:'POST',body,...options});
  const readCall=(args,options={})=>post('isg_nonconformity_read_v1',
    {p_company:companyID,p_kind:'list',p_query:null,p_state:null,p_after:null,p_id:null,...args},options);
  const mutate=(action,payload,ids={},options={})=>post('isg_nonconformity_mutate_v1',
    {p_company:companyID,p_action:action,p_operation:ids.operation??randomUUID(),
     p_mutation:ids.mutation??randomUUID(),p_payload:payload},options);

  mark('a_closed_switch_refuses_before_anything_else',
    readCall({}).body?.message==='FEATURE_UNAVAILABLE');
  mark('an_anonymous_caller_never_reaches_the_feature',readCall({},{authorization:null}).status===401);
  // Only the two wrappers and their two checked entries may be callable.
  const grants=sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname LIKE '%nonconformit%' AND has_function_privilege('authenticated',p.oid,'EXECUTE'); SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');").split('\n');
  mark('only_the_checked_entries_are_callable_and_no_table_is',grants[0]==='4'&&grants[1]==='0');

  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=false WHERE feature='nonconformity';");
  const places=readCall({p_kind:'workplaces'});
  const workplace=places.body?.rows?.[0]?.id;
  mark('read_only_lets_the_list_load_but_refuses_a_write',places.status===200&&Boolean(workplace)&&
    readCall({}).status===200&&
    mutate('open_manual',{workplace_id:workplace,title:'Salt okunur deneme',severity:'low'}).body?.message==='FEATURE_UNAVAILABLE');
  // The P09 core probe already left records on this company, so every count
  // below is measured against what was here before this probe wrote anything.
  const baseline=readCall({}).body.rows.length;
  const baselineDraft=readCall({p_state:'draft'}).body.rows.length;
  const baselineOpen=readCall({p_state:'open'}).body.rows.length;
  sql("UPDATE private_isg.rollout SET write_enabled=true WHERE feature='nonconformity';");

  mark('a_key_nobody_allowed_is_refused',
    mutate('open_manual',{workplace_id:workplace,title:'Kaçak alan',severity:'low',is_resolved:true})
      .body?.message==='PAYLOAD_NOT_ALLOWED');
  mark('an_unknown_risk_band_reaches_a_person_instead_of_becoming_low',
    mutate('open_from_finding',{workplace_id:workplace,title:'Bandı okunamayan bulgu',
      risk_band:'unknown',finding_id:randomUUID()}).body?.message==='SEVERITY_UNKNOWN');
  mark('another_owners_company_is_refused',
    post('isg_nonconformity_mutate_v1',{p_company:randomUUID(),p_action:'open_manual',
      p_operation:randomUUID(),p_mutation:randomUUID(),
      p_payload:{workplace_id:workplace,title:'Başka firma',severity:'low'}}).body?.message==='ACCESS_DENIED');

  const findingID=randomUUID();
  const fromFinding={workplace_id:workplace,title:'Korkuluk eksik',risk_band:'high',finding_id:findingID};
  const ids={operation:randomUUID(),mutation:randomUUID()};
  const opened=mutate('open_from_finding',fromFinding,ids);
  mark('a_live_finding_becomes_a_nonconformity_without_being_rewritten',opened.status===200&&
    opened.body.row.source_kind==='legacy_finding'&&opened.body.row.source_ref===findingID&&
    opened.body.row.severity==='high'&&opened.body.row.state==='draft'&&
    opened.body.legacy_finding_written===false&&opened.body.replayed===false);
  mark('the_same_request_returns_the_same_answer',
    JSON.stringify(mutate('open_from_finding',fromFinding,ids).body.row)===JSON.stringify(opened.body.row)&&
    mutate('open_from_finding',fromFinding,ids).body.replayed===true);
  mark('a_changed_payload_under_the_same_key_is_refused',
    mutate('open_from_finding',{...fromFinding,title:'Başka başlık'},ids).body?.message==='IDEMPOTENCY_CONFLICT');
  mark('the_same_finding_never_opens_a_second_nonconformity',(()=>{
    const again=mutate('open_from_finding',fromFinding);
    return again.status===200&&again.body.row.id===opened.body.row.id;})());

  const target=opened.body.row.id;
  mark('a_stale_version_can_not_move_the_state',
    mutate('transition',{nonconformity_id:target,expected_version:99,to_state:'open',
      reason:'eski sürümle dene'}).status===400);
  const moved=mutate('transition',{nonconformity_id:target,expected_version:opened.body.row.version,
    to_state:'open',reason:'uzman incelemesi tamam'});
  mark('the_state_machine_moves_the_record_forward',moved.status===200&&moved.body.row.state==='open'&&
    moved.body.row.version===opened.body.row.version+1);
  const withAction=mutate('add_action',{nonconformity_id:target,description:'Korkuluk montajı yapılacak',
    assignee:'Saha şefi'});
  mark('a_corrective_action_is_recorded_against_the_record',withAction.status===200&&
    withAction.body.row.actions.length===1);

  const manual=mutate('open_manual',{workplace_id:workplace,title:'Elle açılan uygunsuzluk',
    severity:'medium',assignee:'İşveren vekili'});
  mark('a_manual_record_carries_no_source_reference',manual.status===200&&
    manual.body.row.source_kind==='manual'&&manual.body.row.source_ref===null&&
    manual.body.row.severity==='medium');
  const list=readCall({});
  const detail=readCall({p_kind:'detail',p_id:target});
  mark('the_list_and_the_detail_read_back_what_was_written',list.status===200&&
    list.body.rows.length===baseline+2&&list.body.rows.some(r=>r.id===target)&&
    list.body.rows.some(r=>r.id===manual.body.row.id)&&
    list.body.legacy_findings_written===false&&
    detail.status===200&&detail.body.row.id===target&&detail.body.row.actions.length===1);
  mark('a_state_filter_narrows_the_list',(()=>{
    const drafts=readCall({p_state:'draft'}).body.rows;
    const opens=readCall({p_state:'open'}).body.rows;
    return drafts.length===baselineDraft+1&&drafts.some(r=>r.id===manual.body.row.id)&&
      opens.length===baselineOpen+1&&opens.some(r=>r.id===target)&&
      !drafts.some(r=>r.id===target);})());

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='nonconformity';");
  mark('kill_switch_stops_reading_and_writing',
    readCall({}).body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('open_manual',{workplace_id:workplace,title:'Kapalı',severity:'low'}).body?.message==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:nonconformityHTTPFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      legacy_findings_written:false,legacy_analyses_written:false,unknown_band_auto_mapped:false,
      native_screens_built:false,photo_pipeline_connected:false,production_deployed:false};
  }};
}
