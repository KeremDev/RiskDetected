import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const documentTrackingFiles=[
  'supabase/migrations/20260914210000_isg_document_tracking.sql',
  'scripts/isg/document_tracking_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');

// Hand-computed, never a second call into the production expression.
// The tracker warns 30 days ahead, so with a copy that runs out in 10 days the
// answer is 'due_soon', with one that ran out yesterday it is 'expired', and
// with one that lasts another 200 days it is 'valid'.
const NOTICE_DAYS=30,DUE_SOON_IN=10,EXPIRED_BY=1,STILL_VALID_IN=200;
// A drill record is good for a year, so a copy issued today runs out 365 days
// later. 365 is added here by hand rather than read back from the server.
const DRILL_VALIDITY_DAYS=365;
const day=(anchor,offset)=>{
  const value=new Date(Date.UTC(anchor.y,anchor.m-1,anchor.d));
  value.setUTCDate(value.getUTCDate()+offset);
  return value.toISOString().slice(0,10);
};

export async function beginDocumentTrackingProbe({synthetic,sql,request,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_DOCUMENT_TRACKING_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID||typeof request!=='function')throw Error('AUTH_RESTORE_DOCUMENT_TRACKING_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('document_tracking_'+name,ok);
  sql(read(documentTrackingFiles[0]));

  mark('migration_applied_without_opening_the_switch',
    sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='document_tracking';")==='t');
  mark('every_new_table_is_private_and_row_secured',
    sql("SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND rowsecurity AND tablename IN ('document_obligation_kinds','document_obligations','document_obligation_records','document_tracking_receipts');")==='4'&&
    sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');")==='0');
  // A health record has no code to arrive under: the allowed set is a CHECK on
  // the catalogue, so no later insert can add one without a new migration.
  mark('a_health_record_has_no_kind_to_arrive_under',
    sql("SELECT count(*) FROM private_isg.document_obligation_kinds WHERE kind_code ~ '(health|medical|saglik|muayene|rapor_sagl)';")==='0'&&
    sql("SELECT count(*) FROM pg_constraint WHERE conrelid='private_isg.document_obligation_kinds'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%kind_code%';")!=='0');
  // The insert is attempted for real. The exception block swallows the refusal
  // so the session survives, and the row count afterwards says what happened.
  sql(`DO $$ BEGIN
    INSERT INTO private_isg.document_obligation_kinds(kind_code,ordinal) VALUES('health_report',900);
  EXCEPTION WHEN check_violation THEN NULL; END $$;`);
  mark('the_schema_itself_refuses_a_health_kind',
    sql("SELECT count(*) FROM private_isg.document_obligation_kinds WHERE kind_code='health_report';")==='0');
  // Missing, due soon and expired are worked out at read time, so no row can
  // carry yesterday's answer.
  mark('no_table_stores_a_status_a_stale_row_could_claim',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('document_obligations','document_obligation_records') AND column_name IN ('status','state','is_valid','is_expired','is_compliant');")==='0');
  // There is no asset column at all, so the tracker cannot claim a stored file.
  mark('no_column_can_claim_a_stored_file',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('document_obligations','document_obligation_records') AND column_name IN ('asset_id','storage_path','file_sha256','derivative_id');")==='0');
  mark('the_boundary_exposes_exactly_two_callable_functions',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'isg_document_tracking%' AND has_function_privilege('authenticated',p.oid,'EXECUTE');")==='2');

  const post=(path,body,options={})=>request('/rpc/'+path,{method:'POST',body,...options});
  const readCall=(args,options={})=>post('isg_document_tracking_read_v1',
    {p_company:companyID,p_kind:'list',p_query:null,p_status:null,p_workplace:null,p_id:null,...args},options);
  const mutate=(action,payload,ids={},options={})=>post('isg_document_tracking_mutate_v1',
    {p_company:companyID,p_action:action,p_operation:ids.operation??randomUUID(),
     p_mutation:ids.mutation??randomUUID(),p_payload:payload},options);

  // The boundary was created by the migration above, so the gateway may still
  // be reloading its schema when the first call lands. A dropped connection is
  // not an answer: wait for a real one instead of reading the failure as a result.
  const settle=ms=>Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,ms);
  let closed=null;
  for(let attempt=0;attempt<20;attempt++){
    try{ closed=readCall({}); break; }catch{ settle(500); }
  }
  if(closed===null)throw Error('AUTH_RESTORE_DOCUMENT_TRACKING_BOUNDARY_UNREACHABLE');
  mark('a_closed_switch_refuses_both_directions',
    closed.body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('add_obligation',{kind_code:'risk_assessment',title:'Kapalı'}).body?.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='document_tracking';");

  const catalogue=readCall({p_kind:'kinds'});
  mark('the_catalogue_says_plainly_that_health_records_are_not_tracked',
    catalogue.status===200&&catalogue.body.health_records_tracked===false&&
    catalogue.body.rows.length===16&&
    catalogue.body.rows.every(entry=>!/health|medical/.test(entry.code)));

  const workplace=readCall({p_kind:'workplaces'}).body?.rows?.[0]?.id;
  if(!workplace)throw Error('AUTH_RESTORE_DOCUMENT_TRACKING_WORKPLACE_MISSING');
  // Today is an input to the rule, not the rule: it is read once and every
  // expected date below is computed from it here.
  const stamp=sql('SELECT to_char((clock_timestamp() AT TIME ZONE \'UTC\')::date,\'YYYY-MM-DD\');');
  const anchor={y:Number(stamp.slice(0,4)),m:Number(stamp.slice(5,7)),d:Number(stamp.slice(8,10))};

  const missing=mutate('add_obligation',{kind_code:'risk_assessment',title:'Risk değerlendirmesi',
    notice_days:NOTICE_DAYS,responsible_contact:'İşveren vekili'});
  mark('an_obligation_is_the_experts_own_declaration_by_default',missing.status===200&&
    missing.body.row.basis==='expert'&&missing.body.row.legal_ref===null&&
    missing.body.row.status==='missing'&&missing.body.row.status_authority==='computed_at_read'&&
    missing.body.file_stored===false);
  mark('calling_an_obligation_legal_demands_the_reference_relied_upon',
    mutate('add_obligation',{kind_code:'emergency_plan',title:'Dayanaksız',basis:'legal'}).status===400||
    mutate('add_obligation',{kind_code:'emergency_plan',title:'Dayanaksız 2',basis:'legal'}).status>=400);
  const legal=mutate('add_obligation',{kind_code:'emergency_plan',title:'Acil durum planı',basis:'legal',
    legal_ref:'6331 sayılı Kanun md.11',notice_days:NOTICE_DAYS,workplace_id:workplace});
  mark('a_legal_basis_carries_the_experts_own_reference',legal.status===200&&
    legal.body.row.basis==='legal'&&legal.body.row.legal_ref==='6331 sayılı Kanun md.11'&&
    legal.body.row.workplace_id===workplace);

  const drill=mutate('add_obligation',{kind_code:'drill_record',title:'Tatbikat kaydı',
    validity_days:DRILL_VALIDITY_DAYS,notice_days:NOTICE_DAYS});
  const derived=mutate('record_copy',{obligation_id:drill.body.row.id,issued_on:day(anchor,0)});
  mark('the_end_date_follows_the_obligations_own_period',derived.status===200&&
    derived.body.row.latest_valid_until===day(anchor,DRILL_VALIDITY_DAYS)&&
    derived.body.row.status==='valid');
  const explicit=mutate('record_copy',{obligation_id:drill.body.row.id,issued_on:day(anchor,0),
    valid_until:day(anchor,STILL_VALID_IN),document_no:'TAT-2026-004',
    location_note:'İşveren dosyası · klasör 3'});
  mark('an_explicit_end_date_wins_over_the_period',explicit.status===200&&
    explicit.body.row.latest_valid_until===day(anchor,STILL_VALID_IN)&&
    explicit.body.row.status==='valid'&&explicit.body.row.records[0].document_no==='TAT-2026-004');

  const expired=mutate('add_obligation',{kind_code:'equipment_inspection',title:'Periyodik kontrol',
    notice_days:NOTICE_DAYS});
  mutate('record_copy',{obligation_id:expired.body.row.id,issued_on:day(anchor,-400),
    valid_until:day(anchor,-EXPIRED_BY)});
  const dueSoon=mutate('add_obligation',{kind_code:'annual_work_plan',title:'Yıllık çalışma planı',
    notice_days:NOTICE_DAYS});
  mutate('record_copy',{obligation_id:dueSoon.body.row.id,issued_on:day(anchor,-10),
    valid_until:day(anchor,DUE_SOON_IN)});
  const openEnded=mutate('add_obligation',{kind_code:'board_minutes',title:'Kurul tutanağı',
    notice_days:NOTICE_DAYS});
  mutate('record_copy',{obligation_id:openEnded.body.row.id,issued_on:day(anchor,-5)});

  const list=readCall({});
  const byID=id=>list.body.rows.find(entry=>entry.id===id);
  mark('a_copy_that_ran_out_reads_as_expired',byID(expired.body.row.id)?.status==='expired');
  mark('a_copy_inside_the_notice_window_reads_as_due_soon',byID(dueSoon.body.row.id)?.status==='due_soon');
  mark('a_copy_outside_the_notice_window_reads_as_valid',byID(drill.body.row.id)?.status==='valid');
  mark('an_obligation_with_no_period_never_runs_out',
    byID(openEnded.body.row.id)?.status==='valid'&&byID(openEnded.body.row.id)?.latest_valid_until===null);
  mark('an_obligation_with_no_copy_still_reads_as_missing',byID(missing.body.row.id)?.status==='missing');
  // The counts are a tally of tracked documents. They are not a statement that
  // the company or any person is compliant, and there is no field to say so.
  mark('the_answer_is_a_tally_and_never_a_compliance_verdict',
    list.status===200&&list.body.compliance_verdict===null&&
    list.body.file_storage_available===false&&
    Number(list.body.counts.missing)>=1&&Number(list.body.counts.expired)>=1&&
    Number(list.body.counts.due_soon)>=1&&Number(list.body.counts.valid)>=1&&
    Object.values(list.body.counts).reduce((total,value)=>total+Number(value),0)===list.body.rows.length);
  mark('a_status_filter_returns_only_that_status',
    readCall({p_status:'expired'}).body.rows.every(entry=>entry.status==='expired')&&
    readCall({p_status:'expired'}).body.rows.length===Number(list.body.counts.expired));
  mark('a_workplace_filter_returns_only_that_workplaces_obligations',
    readCall({p_workplace:workplace}).body.rows.every(entry=>entry.workplace_id===workplace));

  const replayIDs={operation:randomUUID(),mutation:randomUUID()};
  const first=mutate('record_copy',{obligation_id:openEnded.body.row.id,issued_on:day(anchor,0)},replayIDs);
  const second=mutate('record_copy',{obligation_id:openEnded.body.row.id,issued_on:day(anchor,0)},replayIDs);
  mark('a_retry_returns_the_first_answer_instead_of_filing_a_second_copy',first.status===200&&
    second.body.replayed===true&&JSON.stringify(second.body.row.records)===JSON.stringify(first.body.row.records));

  const renamed=mutate('update_obligation',{obligation_id:missing.body.row.id,
    expected_version:missing.body.row.version,title:'Risk değerlendirmesi · 2026',note:'Yenileme planlandı'});
  mark('an_update_moves_the_version_and_keeps_the_rest',renamed.status===200&&
    renamed.body.row.title==='Risk değerlendirmesi · 2026'&&renamed.body.row.note==='Yenileme planlandı'&&
    renamed.body.row.version===missing.body.row.version+1&&
    renamed.body.row.responsible_contact==='İşveren vekili');
  mark('a_stale_version_is_refused_instead_of_overwriting',
    mutate('update_obligation',{obligation_id:missing.body.row.id,
      expected_version:missing.body.row.version,title:'Eski sürüm'}).body?.message==='VERSION_CONFLICT');
  mark('a_field_the_server_never_agreed_to_read_is_refused',
    mutate('add_obligation',{kind_code:'other',title:'Uydurma',status:'valid'}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    mutate('record_copy',{obligation_id:drill.body.row.id,issued_on:day(anchor,0),
      asset_id:randomUUID()}).body?.message==='PAYLOAD_NOT_ALLOWED');
  mark('another_owners_company_is_refused',
    post('isg_document_tracking_read_v1',{p_company:randomUUID(),p_kind:'list',p_query:null,
      p_status:null,p_workplace:null,p_id:null}).body?.message==='ACCESS_DENIED'&&
    post('isg_document_tracking_mutate_v1',{p_company:randomUUID(),p_action:'add_obligation',
      p_operation:randomUUID(),p_mutation:randomUUID(),
      p_payload:{kind_code:'other',title:'Başka firma'}}).body?.message==='ACCESS_DENIED');

  const archived=mutate('archive_obligation',{obligation_id:expired.body.row.id,
    expected_version:expired.body.row.version});
  mark('archiving_takes_it_out_of_the_list_without_deleting_its_copies',archived.status===200&&
    archived.body.row.is_archived===true&&archived.body.row.records.length===1&&
    readCall({}).body.rows.find(entry=>entry.id===expired.body.row.id)===undefined);
  mark('an_archived_obligation_accepts_no_new_copy',
    mutate('record_copy',{obligation_id:expired.body.row.id,
      issued_on:day(anchor,0)}).body?.message==='OBLIGATION_ARCHIVED');

  const removal=mutate('remove_copy',{obligation_id:drill.body.row.id,
    record_id:explicit.body.row.records[0].id});
  mark('removing_the_newest_copy_falls_back_to_the_one_before_it',removal.status===200&&
    removal.body.row.latest_valid_until===day(anchor,DRILL_VALIDITY_DAYS));

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='document_tracking';");
  mark('the_kill_switch_stops_the_tracker_in_both_directions',
    readCall({}).body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('record_copy',{obligation_id:drill.body.row.id,
      issued_on:day(anchor,0)}).body?.message==='FEATURE_UNAVAILABLE');

  return {afterLogout(){
    return {migration_file:documentTrackingFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      health_records_trackable:false,status_stored:false,file_stored:false,
      compliance_verdict_returned:false,legacy_tables_written:false,production_deployed:false};
  }};
}
