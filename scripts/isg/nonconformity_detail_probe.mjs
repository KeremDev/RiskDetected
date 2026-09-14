import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const nonconformityDetailFiles=[
  'supabase/migrations/20260914190000_isg_nonconformity_detail.sql',
  'scripts/isg/nonconformity_detail_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');

// Hand-computed, not a second call into the production expression.
// Fine-Kinney 6 x 3 x 15 = 270, and 270 falls in (200,400] which is 'high'.
const FK_SCORE=270,FK_BAND='high';
// 5x5 matrix 4 x 5 = 20, and 20 is above 19, which is 'critical'.
const M5_SCORE=20,M5_BAND='critical';

export async function beginNonconformityDetailProbe({synthetic,sql,request,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_NONCONFORMITY_DETAIL_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID||typeof request!=='function')throw Error('AUTH_RESTORE_NONCONFORMITY_DETAIL_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('nonconformity_detail_'+name,ok);
  sql(read(nonconformityDetailFiles[0]));
  mark('migration_applied_without_opening_the_switch',
    sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='nonconformity';")==='t');
  mark('the_detail_table_is_private_and_row_secured',
    sql("SELECT rowsecurity FROM pg_tables WHERE schemaname='private_isg' AND tablename='nonconformity_details';")==='t'&&
    sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');")==='0');
  // The score and the band are generated columns, so no statement anywhere can
  // write them — not this server's own code, and not a client.
  mark('the_score_and_the_band_can_not_be_written_by_anyone',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name='nonconformity_details' AND column_name IN ('risk_score','risk_band') AND is_generated='ALWAYS';")==='2');
  mark('opening_the_boundary_added_no_new_callable_function',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname LIKE '%nonconformit%' AND has_function_privilege('authenticated',p.oid,'EXECUTE');")==='4');

  const post=(path,body,options={})=>request('/rpc/'+path,{method:'POST',body,...options});
  const readCall=(args,options={})=>post('isg_nonconformity_read_v1',
    {p_company:companyID,p_kind:'list',p_query:null,p_state:null,p_after:null,p_id:null,...args},options);
  const mutate=(action,payload,ids={},options={})=>post('isg_nonconformity_mutate_v1',
    {p_company:companyID,p_action:action,p_operation:ids.operation??randomUUID(),
     p_mutation:ids.mutation??randomUUID(),p_payload:payload},options);

  mark('a_closed_switch_refuses_the_new_actions_too',
    mutate('open_detailed',{workplace_id:randomUUID(),title:'Kapalı',severity:'low'}).body?.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='nonconformity';");
  const workplace=readCall({p_kind:'workplaces'}).body?.rows?.[0]?.id;
  if(!workplace)throw Error('AUTH_RESTORE_NONCONFORMITY_DETAIL_WORKPLACE_MISSING');
  const baseline=readCall({}).body.rows.length;

  const detailed=mutate('open_detailed',{workplace_id:workplace,title:'Merdiven sabitlenmemiş',severity:'high',
    description:'Seyyar merdiven zemine sabitlenmemiş ve üst destek yok.',
    control_measure:'Merdiven tabanına kaymaz pabuç takılacak, üst nokta bağlanacak.',
    legislation_ref:'6331 sayılı Kanun md.4 · Yapı İşlerinde İSG Yönetmeliği',
    responsible_contact:'Saha şefi',risk_method:'fine_kinney',
    fk_probability:6,fk_frequency:3,fk_severity:15});
  mark('the_expert_fields_are_stored_with_the_record',detailed.status===200&&
    detailed.body.row.detail?.description==='Seyyar merdiven zemine sabitlenmemiş ve üst destek yok.'&&
    detailed.body.row.detail?.control_measure?.startsWith('Merdiven tabanına')&&
    detailed.body.row.detail?.legislation_ref?.startsWith('6331')&&
    detailed.body.row.detail?.responsible_contact==='Saha şefi'&&
    detailed.body.row.record_kind==='nonconformity'&&detailed.body.row.source_kind==='manual');
  mark('the_server_computes_the_fine_kinney_score_and_band',
    Number(detailed.body.row.detail?.risk_score)===FK_SCORE&&
    detailed.body.row.detail?.risk_band===FK_BAND&&
    detailed.body.row.detail?.score_authority==='generated_column');
  mark('a_client_supplied_score_has_no_key_to_arrive_in',
    mutate('open_detailed',{workplace_id:workplace,title:'Uydurma skor',severity:'low',
      risk_method:'fine_kinney',fk_probability:1,fk_frequency:1,fk_severity:1,
      risk_score:999}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    mutate('open_detailed',{workplace_id:workplace,title:'Uydurma bant',severity:'low',
      risk_band:'critical'}).body?.message==='PAYLOAD_NOT_ALLOWED');
  mark('a_method_without_its_own_inputs_is_refused',
    mutate('open_detailed',{workplace_id:workplace,title:'Eksik skor',severity:'low',
      risk_method:'fine_kinney'}).body?.message==='RISK_INPUT_INCOMPLETE'&&
    mutate('open_detailed',{workplace_id:workplace,title:'Eksik matris',severity:'low',
      risk_method:'matrix_5x5',m5_probability:3}).body?.message==='RISK_INPUT_INCOMPLETE');
  mark('inputs_from_the_other_method_can_not_be_mixed_in',
    mutate('open_detailed',{workplace_id:workplace,title:'Karışık metot',severity:'low',
      risk_method:'fine_kinney',fk_probability:1,fk_frequency:1,fk_severity:1,
      m5_probability:3,m5_severity:3}).body?.message==='RISK_INPUT_INCOMPLETE');
  mark('an_input_without_a_method_is_refused',
    mutate('open_detailed',{workplace_id:workplace,title:'Metotsuz girdi',severity:'low',
      fk_probability:1}).body?.message==='RISK_INPUT_INCOMPLETE');
  mark('a_value_outside_the_published_scale_is_refused',
    mutate('open_detailed',{workplace_id:workplace,title:'Ölçek dışı',severity:'low',
      risk_method:'fine_kinney',fk_probability:4,fk_frequency:1,fk_severity:1}).status===400&&
    mutate('open_detailed',{workplace_id:workplace,title:'Matris dışı',severity:'low',
      risk_method:'matrix_5x5',m5_probability:9,m5_severity:1}).status===400);

  const matrix=mutate('open_detailed',{workplace_id:workplace,title:'Pano önü kapalı',severity:'critical',
    risk_method:'matrix_5x5',m5_probability:4,m5_severity:5});
  mark('the_matrix_method_scores_with_its_own_thresholds',matrix.status===200&&
    Number(matrix.body.row.detail?.risk_score)===M5_SCORE&&matrix.body.row.detail?.risk_band===M5_BAND);

  // An expert-opinion item arrives unscored. There is no band to map, so the
  // action has no key for one and the person has to say how severe it is.
  const itemID=randomUUID();
  const improvement={workplace_id:workplace,title:'Saha turu sıklığı artırılmalı',severity:'low',
    record_kind:'improvement',item_id:itemID,description:'Uzman görüşü maddesinden geldi.'};
  mark('an_expert_item_has_no_key_for_a_risk_band',
    mutate('open_from_expert_item',{...improvement,risk_band:'high'}).body?.message==='PAYLOAD_NOT_ALLOWED');
  const opened=mutate('open_from_expert_item',improvement);
  mark('an_unscored_expert_item_can_be_filed_as_an_improvement',opened.status===200&&
    opened.body.row.record_kind==='improvement'&&opened.body.row.source_kind==='legacy_expert_item'&&
    opened.body.row.source_ref===itemID&&opened.body.legacy_finding_written===false&&
    opened.body.row.detail?.risk_method===null&&opened.body.row.detail?.risk_band===null);
  mark('the_same_expert_item_never_opens_a_second_record',(()=>{
    const again=mutate('open_from_expert_item',improvement);
    return again.status===200&&again.body.row.id===opened.body.row.id;})());
  const asNonconformity=mutate('open_from_expert_item',{workplace_id:workplace,
    title:'Uzman görüşü · acil çıkış işareti yok',severity:'medium',record_kind:'nonconformity',
    item_id:randomUUID()});
  mark('the_same_expert_item_screen_can_also_file_a_nonconformity',asNonconformity.status===200&&
    asNonconformity.body.row.record_kind==='nonconformity');
  mark('the_older_actions_still_can_not_file_an_improvement',
    mutate('open_manual',{workplace_id:workplace,title:'Gizli öneri',severity:'low',
      record_kind:'improvement'}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    mutate('open_from_finding',{workplace_id:workplace,title:'Gizli öneri 2',risk_band:'high',
      finding_id:randomUUID(),record_kind:'improvement'}).body?.message==='PAYLOAD_NOT_ALLOWED');

  const target=detailed.body.row.id;
  const edited=mutate('set_detail',{nonconformity_id:target,
    description:'Merdiven değiştirildi, yeni merdiven sabitlenmedi.',
    control_measure:'Sabitleme aparatı temin edilecek.',
    risk_method:'matrix_5x5',m5_probability:4,m5_severity:5});
  mark('editing_the_detail_replaces_exactly_what_the_screen_shows',edited.status===200&&
    edited.body.row.detail?.description==='Merdiven değiştirildi, yeni merdiven sabitlenmedi.'&&
    // The screen no longer carried a legislation reference or a responsible
    // person, so the record no longer claims one.
    edited.body.row.detail?.legislation_ref===null&&edited.body.row.detail?.responsible_contact===null&&
    edited.body.row.detail?.risk_method==='matrix_5x5'&&
    Number(edited.body.row.detail?.risk_score)===M5_SCORE&&edited.body.row.detail?.risk_band===M5_BAND&&
    edited.body.row.detail?.fk_probability===null);
  mark('another_owners_record_can_not_be_edited',
    post('isg_nonconformity_mutate_v1',{p_company:randomUUID(),p_action:'set_detail',
      p_operation:randomUUID(),p_mutation:randomUUID(),
      p_payload:{nonconformity_id:target,description:'Başka firma'}}).body?.message==='ACCESS_DENIED');

  const list=readCall({});
  mark('the_list_separates_improvements_from_nonconformities',list.status===200&&
    list.body.rows.length===baseline+4&&
    list.body.rows.find(r=>r.id===opened.body.row.id)?.record_kind==='improvement'&&
    list.body.rows.filter(r=>r.record_kind==='improvement').length===1&&
    list.body.rows.find(r=>r.id===target)?.risk_band===M5_BAND&&
    list.body.rows.find(r=>r.id===asNonconformity.body.row.id)?.risk_band===null);
  // Every record written before this slice keeps meaning what it meant.
  mark('records_written_before_this_slice_stay_nonconformities',
    sql("SELECT bool_and(record_kind='nonconformity') FROM private_isg.nonconformities WHERE source_kind IN ('legacy_finding','manual');")==='t');

  const replayIDs={operation:randomUUID(),mutation:randomUUID()};
  const first=mutate('set_detail',{nonconformity_id:target,description:'Tekrar denemesi'},replayIDs);
  const second=mutate('set_detail',{nonconformity_id:target,description:'Tekrar denemesi'},replayIDs);
  mark('a_retry_returns_the_first_answer_instead_of_writing_again',first.status===200&&
    second.body.replayed===true&&JSON.stringify(second.body.row)===JSON.stringify(first.body.row));

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='nonconformity';");
  mark('kill_switch_stops_the_new_actions_as_well',
    mutate('set_detail',{nonconformity_id:target,description:'Kapalı'}).body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('open_from_expert_item',{workplace_id:workplace,title:'Kapalı',severity:'low',
      item_id:randomUUID()}).body?.message==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:nonconformityDetailFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      score_is_a_generated_column:true,client_supplied_score_accepted:false,
      expert_item_band_mapped:false,legacy_findings_written:false,legacy_analyses_written:false,
      native_screens_built:false,production_deployed:false};
  }};
}
