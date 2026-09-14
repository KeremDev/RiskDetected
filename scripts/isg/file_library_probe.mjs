import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const fileLibraryFiles=[
  'supabase/migrations/20260915010000_isg_file_library.sql',
  'scripts/isg/file_library_probe.mjs',
];
// The legacy storage migration, applied here for real so "the legacy buckets
// and policies are untouched" is compared against the actual shipped rows.
const LEGACY_STORAGE='supabase/migrations/20260503080033_07_storage_buckets.sql';

// The synthetic image has no Supabase Storage schema. These are the two tables
// and the one helper that both the legacy migration and this slice depend on,
// created with the column shapes Storage really uses so the policies compile
// and can be read back. It is a stand-in for the schema, not for the service:
// no object is ever uploaded here, and the probe's report says so.
const STORAGE_STAND_IN=`
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE IF NOT EXISTS storage.buckets(
  id text PRIMARY KEY, name text NOT NULL, public boolean NOT NULL DEFAULT false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS storage.objects(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text REFERENCES storage.buckets(id),
  name text, owner uuid, created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
DO $ensure$ BEGIN
  IF to_regprocedure('storage.foldername(text)') IS NULL THEN
    EXECUTE $create$CREATE FUNCTION storage.foldername(name text) RETURNS text[]
      LANGUAGE plpgsql IMMUTABLE AS $body$
      DECLARE parts text[];
      BEGIN parts:=string_to_array(name,'/'); RETURN parts[1:array_length(parts,1)-1]; END $body$;$create$;
  END IF;
  IF to_regprocedure('auth.uid()') IS NULL THEN
    EXECUTE $create$CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $body$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$body$;$create$;
  END IF;
END $ensure$;`;
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";

// The categories the client files under, and the company heading each one has
// to reach. Written out here by hand so a migration that silently re-points a
// heading is caught rather than confirmed by reading the table back.
const EXPECTED_SECTIONS={
  risk_assessment:'risk',emergency_plan:'emergency',training_material:'training',
  inspection_report:'inspections',measurement_report:'inspections',accident_record:'accidents',
  board_document:'board',handover_form:'handover',personnel_document:'personnel',
  contract:'files',permit_form:'files',contractor_document:'files',other:'files'};
// The page shows ten rows at a time, so the fixture has to carry more than ten.
const PAGE_SIZE=10,FILLER_ROWS=4;

export async function beginFileLibraryProbe({synthetic,sql,request,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_FILE_LIBRARY_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID||typeof request!=='function')throw Error('AUTH_RESTORE_FILE_LIBRARY_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('file_library_'+name,ok);
  sql(STORAGE_STAND_IN);
  sql(read(LEGACY_STORAGE));
  // Exactly what the legacy product owns in storage, before this slice runs.
  // The count travels with the digest, so a fingerprint taken over nothing at
  // all can never match one taken over the real rows.
  const legacyStorage=()=>sql(`SELECT
    (SELECT count(*) FROM pg_policies p WHERE p.schemaname='storage' AND p.tablename='objects'
       AND p.policyname LIKE ANY(ARRAY['photos%','reports%','logos%']))||':'||
    (SELECT count(*) FROM storage.buckets b WHERE b.id IN ('photos','reports','logos'))||':'||
    md5(coalesce(string_agg(part,'|' ORDER BY part),'')) FROM (
      SELECT 'buckets:'||coalesce(string_agg(b.id||b.public::text||coalesce(b.file_size_limit,0)::text,',' ORDER BY b.id),'') AS part
        FROM storage.buckets b WHERE b.id IN ('photos','reports','logos')
      UNION ALL SELECT 'policies:'||coalesce(string_agg(p.policyname||p.cmd||coalesce(p.qual,'')||coalesce(p.with_check,''),',' ORDER BY p.policyname),'')
        FROM pg_policies p WHERE p.schemaname='storage' AND p.tablename='objects'
          AND p.policyname LIKE ANY(ARRAY['photos%','reports%','logos%'])
    ) parts;`);
  const legacyBefore=legacyStorage();
  let legacyAfter=null;
  sql(read(fileLibraryFiles[0]));

  mark('migration_applied_without_opening_the_switch',
    sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='file_library';")==='t');
  mark('every_new_table_is_private_and_row_secured',
    sql("SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND rowsecurity AND tablename IN ('file_scanners','file_library_categories','file_library_entries','file_library_receipts');")==='4'&&
    sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');")==='0');

  // Both buckets are private, and the client's reach into them is one policy
  // each: write-only into quarantine, read-only out of the final bucket.
  mark('neither_new_bucket_is_public',
    sql("SELECT count(*) FROM storage.buckets WHERE id IN ('isg-quarantine','isg-documents') AND NOT public;")==='2');
  mark('the_client_can_only_put_into_quarantine_never_read_or_replace_it',
    sql("SELECT coalesce(string_agg(DISTINCT cmd,',' ORDER BY cmd),'') FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND coalesce(qual,'')||coalesce(with_check,'') LIKE '%isg-quarantine%';")==='INSERT');
  mark('the_client_can_only_read_out_of_the_final_bucket',
    sql("SELECT coalesce(string_agg(DISTINCT cmd,',' ORDER BY cmd),'') FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND coalesce(qual,'')||coalesce(with_check,'') LIKE '%isg-documents%';")==='SELECT');
  // The legacy buckets and their policies are untouched by this slice: the
  // fingerprint taken before the migration ran has to still match.
  legacyAfter=legacyStorage();
  mark('the_legacy_storage_rows_and_policies_are_byte_identical_afterwards',
    legacyAfter===legacyBefore&&/^11:3:[a-f0-9]{32}$/.test(legacyBefore));
  mark('the_three_legacy_buckets_are_still_there',
    sql("SELECT count(*) FROM storage.buckets WHERE id IN ('photos','reports','logos');")==='3');
  // Four for photos, four for logos, three for reports: what the 2026-05-03
  // migration actually ships, counted rather than assumed.
  mark('the_eleven_legacy_storage_policies_are_still_there',
    sql("SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE ANY(ARRAY['photos%','reports%','logos%']);")==='11');

  // A verdict must not be assertable by the account that uploaded the file.
  mark('the_inspection_entry_is_out_of_reach_of_a_signed_in_account',
    sql("SELECT has_function_privilege('authenticated','public.isg_file_inspection_v1(uuid,text,jsonb)','EXECUTE');")==='f'&&
    sql("SELECT has_function_privilege('service_role','public.isg_file_inspection_v1(uuid,text,jsonb)','EXECUTE');")==='t');
  mark('the_worker_identity_reaches_the_inspector_and_nothing_else',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'isg_file%' AND has_function_privilege('service_role',p.oid,'EXECUTE');")==='1');
  mark('the_boundary_exposes_exactly_two_functions_to_a_signed_in_account',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'isg_file%' AND has_function_privilege('authenticated',p.oid,'EXECUTE');")==='2');

  const post=(path,body,options={})=>request('/rpc/'+path,{method:'POST',body,...options});
  const readCall=(args={},options={})=>post('isg_file_library_read_v1',
    {p_company:companyID,p_kind:'list',p_query:null,p_category:null,p_state:null,p_id:null,
     p_limit:PAGE_SIZE,p_offset:0,...args},options);
  const mutate=(action,payload,ids={},options={})=>post('isg_file_library_mutate_v1',
    {p_company:companyID,p_action:action,p_operation:ids.operation??randomUUID(),
     p_mutation:ids.mutation??randomUUID(),p_payload:payload},options);

  // The boundary was created a moment ago, so the gateway may still be reloading
  // its schema. A dropped connection is not an answer.
  const settle=ms=>Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,ms);
  let closed=null;
  for(let attempt=0;attempt<20;attempt++){
    try{ closed=readCall(); break; }catch{ settle(500); }
  }
  if(closed===null)throw Error('AUTH_RESTORE_FILE_LIBRARY_BOUNDARY_UNREACHABLE');
  mark('a_closed_switch_refuses_both_directions',
    closed.body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('open_upload',{title:'Kapalı',category:'other',file_name:'a.pdf',extension:'pdf',
      bytes:10,sha256:'0'.repeat(64)}).body?.message==='FEATURE_UNAVAILABLE');

  // The library rides on the P04 quarantine machine, so opening the library on
  // its own is deliberately not enough to accept a single byte.
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='file_library';");
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='file_core';");
  mark('the_library_cannot_accept_an_upload_while_the_file_core_switch_is_closed',
    readCall({p_kind:'catalog'}).status===200&&
    mutate('open_upload',{title:'Çekirdek kapalı',category:'other',file_name:'a.pdf',extension:'pdf',
      bytes:10,sha256:'0'.repeat(64)}).body?.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='file_core';");

  const catalogue=readCall({p_kind:'catalog'});
  mark('the_catalogue_never_claims_a_malware_scan_ran',catalogue.status===200&&
    catalogue.body.malware_scanning_available===false&&
    catalogue.body.scanners.length===1&&catalogue.body.scanners[0].detects_malware===false&&
    catalogue.body.scanners[0].assurance==='format_inspection');
  mark('every_category_reaches_the_company_heading_it_belongs_under',
    catalogue.body.categories.length===Object.keys(EXPECTED_SECTIONS).length&&
    catalogue.body.categories.every(entry=>EXPECTED_SECTIONS[entry.code]===entry.section));
  // The picker is a convenience; this is the authority for what may be sent.
  const accepts=Object.fromEntries(catalogue.body.accepts.map(entry=>[entry.purpose,entry]));
  mark('the_server_declares_what_it_will_accept_and_says_the_limits_are_unapproved',
    accepts.company_document.extensions.join(',')==='pdf,doc,docx,xls,xlsx'&&
    accepts.evidence_photo.extensions.join(',')==='jpg,jpeg,png,heic,heif,webp,avif'&&
    accepts.company_document.limit_approved===false&&accepts.evidence_photo.limit_approved===false);

  const digest=value=>sql(`SELECT encode(sha256(convert_to(${quote(value)},'UTF8')),'hex');`);
  const sizeOf=value=>Number(sql(`SELECT octet_length(convert_to(${quote(value)},'UTF8'));`));
  const openUpload=(body,overrides={},ids={})=>mutate('open_upload',
    {title:'Belge',category:'other',file_name:'belge.pdf',extension:'pdf',
     bytes:sizeOf(body),sha256:digest(body),...overrides},ids);

  const reportBody='%PDF-1.7 risk degerlendirmesi';
  const report=openUpload(reportBody,{title:'Risk değerlendirmesi 2026',category:'risk_assessment',
    file_name:'risk-2026.pdf'});
  mark('an_opened_upload_hands_back_a_path_under_the_callers_own_prefix',report.status===200&&
    report.body.row.state==='pending'&&report.body.row.upload_bucket==='isg-quarantine'&&
    report.body.row.upload_path.startsWith('quarantine/'+ownerID+'/')&&
    // Nothing is downloadable yet, and no column exists that could say otherwise.
    report.body.row.download_path===null&&report.body.row.malware_scanned===false);
  mark('the_purpose_is_chosen_by_the_server_from_the_real_extension',
    report.body.row.purpose==='company_document'&&
    openUpload('binary',{extension:'png',file_name:'k.png'}).body.row.purpose==='evidence_photo');
  mark('an_extension_the_product_never_accepts_is_refused_before_an_intent_exists',
    openUpload('x',{extension:'exe',file_name:'a.exe'}).body?.message==='UNSUPPORTED_FORMAT'&&
    sql("SELECT count(*) FROM private_isg.upload_intents WHERE declared_extension='exe';")==='0');
  mark('a_category_the_company_page_has_no_heading_for_is_refused',
    openUpload('x',{category:'saglik_raporu'}).body?.message==='VALIDATION_ERROR');

  // There is no action through which a signed-in account can call its own file
  // clean: the allowlist is the whole set of things a client may ask for.
  mark('no_client_action_can_declare_a_verdict',
    mutate('record_scan',{entry_id:report.body.entry_id}).body?.message==='VALIDATION_ERROR'&&
    mutate('promote',{entry_id:report.body.entry_id}).body?.message==='VALIDATION_ERROR'&&
    mutate('open_upload',{title:'x',category:'other',file_name:'a.pdf',extension:'pdf',bytes:1,
      sha256:digest('x'),verdict:'clean'}).body?.message==='PAYLOAD_NOT_ALLOWED');

  // The inspection is driven the way the worker drives it, through the one
  // entry the worker identity holds.
  const intentOf=entry=>sql(`SELECT intent_id FROM private_isg.file_library_entries WHERE entry_id=${quote(entry)};`);
  const stage=(intent,name,payload)=>JSON.parse(sql(
    `SELECT private_isg.inspect_file_upload(${quote(intent)},${quote(name)},${quote(JSON.stringify(payload))}::jsonb);`));
  const reportIntent=intentOf(report.body.entry_id);
  const claim=stage(reportIntent,'claim',{});
  mark('the_inspector_is_handed_the_owner_by_the_row_and_never_by_its_caller',
    claim.owner_id===ownerID&&claim.declared_sha256===digest(reportBody)&&
    claim.quarantine_path===report.body.row.upload_path);

  // Bytes that disagree with the intent never reach a verdict at all.
  const tamperedEntry=openUpload(reportBody,{title:'Değiştirilmiş',file_name:'t.pdf'});
  const tamperedIntent=intentOf(tamperedEntry.body.entry_id);
  const tampered=stage(tamperedIntent,'received',
    {bytes:sizeOf('baska icerik'),sha256:digest('baska icerik'),detected_type:'application/pdf'});
  mark('bytes_that_are_not_the_bytes_announced_are_refused_not_scanned',
    tampered.state==='rejected'&&tampered.row.state==='rejected'&&
    tampered.row.rejection_code==='HASH_MISMATCH'&&tampered.row.download_path===null);

  stage(reportIntent,'received',{bytes:sizeOf(reportBody),sha256:digest(reportBody),
    detected_type:'application/pdf'});
  const scanned=stage(reportIntent,'scanned',{scanner:'isg_format_inspector',scan_version:'1',
    verdict:'clean',finding_code:'',sha256:digest(reportBody),evidence:{inspector:'isg_format_inspector'}});
  mark('a_cleared_file_is_still_not_a_file_until_it_is_promoted',
    scanned.state==='clean'&&scanned.row.download_path===null);
  // Anti-TOCTOU: the bytes promoted have to be the bytes that were inspected.
  const swapped=stage(reportIntent,'promoted',{sha256:digest('swapped'),bytes:sizeOf('swapped')});
  mark('promoting_different_bytes_than_the_ones_inspected_is_refused',
    swapped.row.state==='rejected'&&swapped.row.rejection_code==='HASH_MISMATCH'&&
    sql("SELECT count(*) FROM private_isg.file_assets WHERE source_intent_id="+quote(reportIntent)+";")==='0');

  // A clean run, end to end.
  const goodBody='%PDF-1.7 acil durum plani';
  const plan=openUpload(goodBody,{title:'Acil durum planı',category:'emergency_plan',
    file_name:'acil-durum.pdf'});
  const planIntent=intentOf(plan.body.entry_id);
  stage(planIntent,'received',{bytes:sizeOf(goodBody),sha256:digest(goodBody),detected_type:'application/pdf'});
  stage(planIntent,'scanned',{scanner:'isg_format_inspector',scan_version:'1',verdict:'clean',
    finding_code:'',sha256:digest(goodBody),evidence:{checks:'encryption,embedded,active_content'}});
  const promoted=stage(planIntent,'promoted',{sha256:digest(goodBody),bytes:sizeOf(goodBody)});
  mark('a_cleared_upload_becomes_a_file_at_a_path_named_by_its_own_digest',
    promoted.row.state==='promoted'&&promoted.row.download_bucket==='isg-documents'&&
    promoted.row.download_path==='assets/'+ownerID+'/'+digest(goodBody));
  mark('the_promoted_row_says_what_cleared_it_and_does_not_claim_more',
    promoted.row.scanner==='isg_format_inspector'&&promoted.row.assurance==='format_inspection'&&
    promoted.row.malware_scanned===false);

  // Filing the same document again cannot write over the object already there.
  const again=openUpload(goodBody,{title:'Acil durum planı · kopya',category:'contract',
    file_name:'acil-durum-2.pdf'});
  const againIntent=intentOf(again.body.entry_id);
  stage(againIntent,'received',{bytes:sizeOf(goodBody),sha256:digest(goodBody),detected_type:'application/pdf'});
  stage(againIntent,'scanned',{scanner:'isg_format_inspector',scan_version:'1',verdict:'clean',
    finding_code:'',sha256:digest(goodBody),evidence:{}});
  const duplicate=stage(againIntent,'promoted',{sha256:digest(goodBody),bytes:sizeOf(goodBody)});
  mark('filing_the_same_document_twice_links_to_one_object_instead_of_overwriting_it',
    duplicate.duplicate_of_existing_asset===true&&
    duplicate.row.download_path===promoted.row.download_path&&
    sql("SELECT count(*) FROM private_isg.file_assets WHERE immutable_path="+quote(promoted.row.download_path)+";")==='1');

  // A refusal and a scanner failure are each their own answer, and neither is clean.
  const badBody='%PDF-1.7 /JavaScript';
  const macro=openUpload(badBody,{title:'Makro taşıyan belge',file_name:'makro.docx',extension:'docx'});
  const macroIntent=intentOf(macro.body.entry_id);
  stage(macroIntent,'received',{bytes:sizeOf(badBody),sha256:digest(badBody),detected_type:'application/zip'});
  const refused=stage(macroIntent,'scanned',{scanner:'isg_format_inspector',scan_version:'1',
    verdict:'rejected',finding_code:'MACRO_PRESENT',sha256:digest(badBody),evidence:{entry:'word/vbaProject.bin'}});
  mark('a_refused_file_never_becomes_a_file',refused.row.state==='rejected'&&
    refused.row.rejection_code==='SCAN_REJECTED'&&refused.row.scan_finding==='MACRO_PRESENT'&&
    refused.row.download_path===null);
  const brokenBody='%PDF-1.7 tarayici arizasi';
  const broken=openUpload(brokenBody,{title:'Denetim yapılamadı',file_name:'ariza.pdf'});
  const brokenIntent=intentOf(broken.body.entry_id);
  stage(brokenIntent,'received',{bytes:sizeOf(brokenBody),sha256:digest(brokenBody),detected_type:'application/pdf'});
  const failure=stage(brokenIntent,'scanned',{scanner:'isg_format_inspector',scan_version:'1',
    verdict:'failed',finding_code:'INSPECTOR_TIMEOUT',sha256:digest(brokenBody),evidence:{}});
  mark('an_inspection_that_could_not_finish_is_never_read_as_clean',
    failure.row.state==='scan_failed'&&failure.row.rejection_code==='SCAN_UNAVAILABLE'&&
    failure.row.download_path===null);

  // A scanner nobody registered is not evidence of anything.
  const strangeBody='%PDF-1.7 bilinmeyen tarayici';
  const strange=openUpload(strangeBody,{title:'Bilinmeyen tarayıcı',file_name:'bilinmeyen.pdf'});
  const strangeIntent=intentOf(strange.body.entry_id);
  stage(strangeIntent,'received',{bytes:sizeOf(strangeBody),sha256:digest(strangeBody),
    detected_type:'application/pdf'});
  stage(strangeIntent,'scanned',{scanner:'kesin_temiz_tarayici',scan_version:'9',verdict:'clean',
    finding_code:'',sha256:digest(strangeBody),evidence:{}});
  const strangePromoted=stage(strangeIntent,'promoted',{sha256:digest(strangeBody),bytes:sizeOf(strangeBody)});
  mark('an_unregistered_scanner_is_never_reported_as_a_malware_scan',
    strangePromoted.row.state==='promoted'&&strangePromoted.row.scanner==='kesin_temiz_tarayici'&&
    strangePromoted.row.assurance===null&&strangePromoted.row.malware_scanned===false&&
    sql("SELECT (evidence->>'scanner_registered')::text FROM private_isg.file_scan_results WHERE intent_id="+quote(strangeIntent)+";")==='false');

  // The list.
  for(let index=0;index<FILLER_ROWS;index++){
    openUpload('dolgu-'+index,{title:'Dolgu belgesi '+index,category:'contract',
      file_name:'dolgu-'+index+'.pdf'});
  }
  const page=readCall();
  mark('the_page_is_bounded_and_the_tally_counts_the_same_rows_it_pages',
    page.status===200&&page.body.rows.length===PAGE_SIZE&&page.body.limit===PAGE_SIZE&&
    page.body.has_more===true&&page.body.total>PAGE_SIZE&&
    Object.values(page.body.counts).reduce((sum,value)=>sum+Number(value),0)===page.body.total);
  mark('the_page_puts_what_needs_attention_first',
    page.body.rows[0].state==='rejected'&&
    page.body.rows.findIndex(row=>row.state==='promoted')>
      page.body.rows.findIndex(row=>row.state==='pending'));
  mark('the_answer_is_a_tally_and_never_a_compliance_verdict',
    page.body.compliance_verdict===null&&page.body.malware_scanning_available===false&&
    page.body.rows.every(row=>row.malware_scanned===false&&row.state_authority==='computed_at_read'));
  mark('a_state_filter_returns_only_that_state',
    readCall({p_state:'promoted'}).body.rows.every(row=>row.state==='promoted')&&
    readCall({p_state:'promoted'}).body.rows.length===Number(page.body.counts.promoted));
  // A counter and the filter it carries have to be the same set of rows.
  const grouped={filed:['promoted'],working:['pending','uploaded','scanning','clean'],
    unchecked:['scan_failed','expired']};
  mark('tapping_a_counter_filters_exactly_what_that_counter_counted',
    Object.entries(grouped).every(([word,states])=>{
      const answer=readCall({p_state:word,p_limit:100});
      const expected=states.reduce((sum,state)=>sum+Number(page.body.counts[state]??0),0);
      return answer.body.total===expected&&answer.body.rows.every(row=>states.includes(row.state));
    }));
  mark('a_state_word_the_server_never_agreed_to_is_refused',
    readCall({p_state:'temiz'}).body?.message==='VALIDATION_ERROR');
  mark('a_category_filter_answers_one_heading_of_the_company_page',
    readCall({p_category:'emergency_plan'}).body.rows.every(row=>row.category==='emergency_plan')&&
    readCall({p_category:'emergency_plan'}).body.rows.every(row=>row.section==='emergency'));
  const sum=states=>Object.values(states).reduce((running,value)=>running+Number(value),0);
  mark('the_per_category_tally_answers_every_heading_in_one_call',
    typeof page.body.category_counts==='object'&&
    Object.values(page.body.category_counts).reduce((running,states)=>running+sum(states),0)===
      sum(page.body.counts));
  mark('the_whole_account_reads_in_one_call_without_naming_a_company',
    post('isg_file_library_read_v1',{p_company:null,p_kind:'list',p_query:null,p_category:null,
      p_state:null,p_id:null,p_limit:PAGE_SIZE,p_offset:0}).body.companies
      .every(entry=>entry.id===companyID));
  mark('a_search_narrows_the_page_without_changing_the_account_tally',
    readCall({p_query:'Acil durum'}).body.rows.every(row=>/Acil durum/.test(row.title))&&
    JSON.stringify(readCall({p_query:'Acil durum'}).body.counts)===JSON.stringify(page.body.counts));

  // Naming and filing are the expert's, and a stale version cannot overwrite.
  const renamed=mutate('rename_entry',{entry_id:plan.body.entry_id,
    expected_version:promoted.row.version,title:'Acil durum planı · 2026',category:'emergency_plan',
    note:'İşveren nüshası imzalı'});
  mark('renaming_and_refiling_move_the_version_and_keep_the_file',renamed.status===200&&
    renamed.body.row.title==='Acil durum planı · 2026'&&renamed.body.row.note==='İşveren nüshası imzalı'&&
    renamed.body.row.version===promoted.row.version+1&&
    renamed.body.row.download_path===promoted.row.download_path);
  mark('a_stale_version_is_refused_instead_of_overwriting',
    mutate('rename_entry',{entry_id:plan.body.entry_id,expected_version:promoted.row.version,
      title:'Eski sürüm'}).body?.message==='VERSION_CONFLICT');
  // One upload that never started, and one document that is already on file.
  const abandoned=openUpload('vazgecilen',{title:'Vazgeçilen yükleme',file_name:'vazgecilen.pdf'});
  mark('cancelling_only_abandons_an_upload_that_never_became_a_file',
    // A promoted document is not cancelled; it is archived.
    mutate('cancel_upload',{entry_id:plan.body.entry_id,
      expected_version:renamed.body.row.version}).body?.message==='UPLOAD_NOT_CANCELLABLE'&&
    // Neither is one whose upload already ended in a refusal.
    mutate('cancel_upload',{entry_id:report.body.entry_id,
      expected_version:report.body.row.version}).body?.message==='UPLOAD_NOT_CANCELLABLE'&&
    mutate('cancel_upload',{entry_id:abandoned.body.entry_id,
      expected_version:abandoned.body.row.version}).status===200&&
    // The object it would have been is not in the archive, and never was.
    sql("SELECT count(*) FROM private_isg.file_assets a JOIN private_isg.file_library_entries e ON e.asset_id=a.asset_id WHERE e.entry_id="+quote(abandoned.body.entry_id)+";")==='0');

  const replayIDs={operation:randomUUID(),mutation:randomUUID()};
  const firstOpen=openUpload('tekrar',{title:'Tekrar',file_name:'tekrar.pdf'},replayIDs);
  const secondOpen=openUpload('tekrar',{title:'Tekrar',file_name:'tekrar.pdf'},replayIDs);
  mark('a_retry_returns_the_first_answer_instead_of_opening_a_second_upload',
    firstOpen.status===200&&secondOpen.body.replayed===true&&
    secondOpen.body.entry_id===firstOpen.body.entry_id&&
    sql("SELECT count(*) FROM private_isg.file_library_entries WHERE title='Tekrar';")==='1');
  mark('another_owners_company_is_refused',
    post('isg_file_library_mutate_v1',{p_company:randomUUID(),p_action:'open_upload',
      p_operation:randomUUID(),p_mutation:randomUUID(),
      p_payload:{title:'Yabancı',category:'other',file_name:'a.pdf',extension:'pdf',bytes:5,
        sha256:digest('x')}}).body?.message==='ACCESS_DENIED');

  mark('the_legacy_analysis_and_report_tables_were_never_written',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('analyses','findings','reports') AND column_name IN ('file_library_entry_id','isg_asset_id');")==='0');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='file_library';");
  mark('the_kill_switch_stops_the_library_and_the_inspector_together',
    readCall().body?.message==='FEATURE_UNAVAILABLE'&&
    mutate('rename_entry',{entry_id:plan.body.entry_id,expected_version:renamed.body.row.version,
      title:'x'}).body?.message==='FEATURE_UNAVAILABLE'&&
    (()=>{try{stage(planIntent,'claim',{});return false;}catch{return true;}})());

  return {afterLogout(){
    return {migration_file:fileLibraryFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      buckets_private:true,client_can_read_quarantine:false,client_can_declare_a_verdict:false,
      // The schema is real and applied; the Storage service itself is not run
      // here, so no object was ever uploaded, scanned or promoted for real.
      storage_schema:'synthetic_stand_in',storage_service_exercised:false,
      legacy_storage_fingerprint_before:legacyBefore,legacy_storage_fingerprint_after:legacyAfter,
      bytes_uploaded_or_promoted:false,
      malware_scanning_available:false,assurance:'format_inspection',
      promoted_path_is_content_addressed:true,legacy_storage_paths_touched:false,
      production_deployed:false};
  }};
}
