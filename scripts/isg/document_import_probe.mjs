import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const documentImportFiles=[
  'supabase/migrations/20260914030000_isg_document_import_core.sql',
  'scripts/isg/document_import_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,3,0,0)+seconds*1000).toISOString();
const hex=text=>createHash('sha256').update(text).digest('hex');

export async function beginDocumentImportProbe({synthetic,sql,concurrentSql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_DOCUMENT_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_DOCUMENT_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('document_import_'+name,ok);
  sql(read(documentImportFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT count(*)=2 AND bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.rollout WHERE feature IN ('documents','imports');")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");

  sql(["CREATE SCHEMA isg_doc_test;",
    "CREATE FUNCTION isg_doc_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='cell' THEN r:=private_isg.import_cell_value(a->>'kind',a->>'raw',a->>'date_system',a->>'decimal');",
    "ELSIF kind='column' THEN r:=to_jsonb(private_isg.import_column_allowed(a->>'column'));",
    "ELSIF kind='number' THEN r:=to_jsonb(private_isg.allocate_document_number((a->>'company')::uuid,a->>'scope',(a->>'year')::integer));",
    "ELSIF kind='document' THEN r:=private_isg.register_document((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'domain',a->>'source_ref',a->>'template',(a->>'now')::timestamptz);",
    "ELSIF kind='finalize' THEN r:=private_isg.finalize_document_version((a->>'document')::uuid,(a->>'mutation')::uuid,a->'snapshot',a->>'source_kind',a->>'scope',(a->>'year')::integer,(a->>'finalized_by')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='export' THEN r:=private_isg.request_export((a->>'document')::uuid,(a->>'version')::integer,a->>'format',(a->>'now')::timestamptz);",
    "ELSIF kind='export_settle' THEN r:=private_isg.settle_export((a->>'job')::uuid,a->>'state',(a->>'asset')::uuid,a->>'error',(a->>'now')::timestamptz);",
    "ELSIF kind='batch' THEN r:=private_isg.open_import_batch((a->>'company')::uuid,a->>'target',(a->>'asset')::uuid,decode(a->>'file_sha256','hex'),(a->>'mapping_version')::integer,(a->>'mutation')::uuid,a->>'date_system',a->>'decimal',a->'columns',(a->>'now')::timestamptz);",
    "ELSIF kind='row' THEN r:=private_isg.stage_import_row((a->>'batch')::uuid,(a->>'row_no')::integer,a->'raw',(a->>'now')::timestamptz);",
    "ELSIF kind='preview' THEN r:=private_isg.preview_import_batch((a->>'batch')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='commit' THEN r:=private_isg.commit_import_batch((a->>'batch')::uuid,decode(a->>'preview','hex'),(a->>'allow_partial')::boolean,(a->>'now')::timestamptz);",
    "ELSIF kind='compensate' THEN r:=private_isg.compensate_import_batch((a->>'batch')::uuid,(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','TEMPLATE_NOT_PUBLISHED','IDEMPOTENCY_CONFLICT','HEALTH_COLUMN_REFUSED','BATCH_COMMITTED','PREVIEW_REQUIRED','PREVIEW_STALE','PARTIAL_COMMIT_NOT_ALLOWED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_doc_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_DOCUMENT_UNEXPECTED_'+r.error);return r.result;};

  mark('gate_blocks_documents_and_imports_while_rollout_off',
    call('document',{company:companyID,workplace,domain:'training',source_ref:'x',template:'training_certificate',now:now(0)}).error==='FEATURE_UNAVAILABLE'&&
    call('batch',{company:companyID,target:'employee',asset,file_sha256:hex('f'),mapping_version:1,mutation:randomUUID(),date_system:'1900',decimal:',',columns:['full_name'],now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('document_gate','import_gate','sanitise_cell','import_column_allowed','import_cell_value','allocate_document_number','register_document','finalize_document_version','request_export','settle_export','open_import_batch','stage_import_row','preview_import_batch','commit_import_batch','compensate_import_batch') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('document_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('documents','imports');");

  const cell=(kind,raw,over={})=>ok('cell',{kind,raw,date_system:'1900',decimal:',',...over});
  mark('a_formula_prefix_is_neutralised_not_executed',
    cell('text','=SUM(A1:A9)').value==='SUM(A1:A9)'&&cell('text','=SUM(A1:A9)').sanitised===true&&
    cell('text','@cmd').value==='cmd'&&cell('text','+1+1').value==='1+1'&&cell('text','-oops').value==='oops'&&
    cell('text','Normal metin').sanitised===false);
  mark('a_turkish_decimal_is_read_and_an_ambiguous_one_is_reviewed',
    cell('number','1.234,56').value===1234.56&&cell('number','12,5').value===12.5&&cell('number','1234').value===1234&&
    cell('number','1.234').state==='review'&&cell('number','1.234').reason==='AMBIGUOUS_DECIMAL'&&
    cell('number','1,234.56',{decimal:'.'}).value===1234.56);
  mark('a_code_keeps_its_leading_zeros',cell('code','007').value==='007'&&cell('code','007').state==='ok'&&
    cell('code','çğü!').state==='error');
  // The two systems differ by exactly 1462 days; assert the relation, not a
  // hand-computed date.
  mark('both_excel_date_systems_are_supported',cell('date','45000').value==='2023-03-15'&&
    cell('date','45000',{date_system:'1904'}).value===cell('date','46462').value&&
    cell('date','2026-09-14').value==='2026-09-14');
  mark('the_1900_leap_bug_is_refused',cell('date','60').reason==='EXCEL_1900_LEAP_BUG'&&
    cell('date','59').value==='1900-02-28'&&cell('date','61').value==='1900-03-01');
  mark('an_empty_cell_is_not_an_invalid_one',cell('date','').state==='empty'&&cell('date','  ').state==='empty'&&
    cell('date','abc').reason==='DATE_INVALID');
  mark('a_health_column_is_refused_at_the_door',ok('column',{column:'full_name'})===true&&
    ok('column',{column:'saglik_raporu'})===false&&ok('column',{column:'Blood_Type'})===false&&
    ok('column',{column:'asi_tarihi'})===false);

  sql("INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES('training_certificate','training','Eğitim Katılım Belgesi');"+
    "INSERT INTO private_isg.document_template_versions(template_code,version,status,approved_by,approval_note,published_at) VALUES('training_certificate',1,'published',"+quote(ownerID)+",'Şablon onaylandı.',now());"+
    "INSERT INTO private_isg.document_templates(template_code,source_domain,title) VALUES('draft_only','training','Yayımlanmamış');"+
    "INSERT INTO private_isg.document_template_versions(template_code,version) VALUES('draft_only',1);");
  mark('an_unpublished_template_produces_no_document',call('document',{company:companyID,workplace,domain:'training',
    source_ref:'enrolment-1',template:'draft_only',now:now(10)}).error==='TEMPLATE_NOT_PUBLISHED');
  const document=ok('document',{company:companyID,workplace,domain:'training',source_ref:'enrolment-1',template:'training_certificate',now:now(11)});
  mark('a_document_is_registered_once_per_source',document.current_version===0&&
    ok('document',{company:companyID,workplace,domain:'training',source_ref:'enrolment-1',template:'training_certificate',now:now(12)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.documents;")==='1');
  const snapshot={company_name:'Firma A',employee_name:'Ada Kaya',employee_role:'Operatör',completed_on:'2026-10-01',rule_version:2};
  const mutation=randomUUID();
  const finalized=ok('finalize',{document:document.document_id,mutation,snapshot,source_kind:'structured',
    scope:'egitim',year:2026,finalized_by:ownerID,now:now(13)});
  mark('finalising_allocates_a_number_and_a_snapshot_hash',finalized.version===1&&finalized.document_no==='EGITIM-2026-1'&&
    /^[a-f0-9]{64}$/.test(finalized.snapshot_sha256)&&finalized.template_version===1);
  mark('a_retry_does_not_duplicate_the_logical_document',ok('finalize',{document:document.document_id,mutation,
    snapshot,source_kind:'structured',scope:'egitim',year:2026,finalized_by:ownerID,now:now(14)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.document_versions;")==='1');
  sql("UPDATE public.companies SET name='Firma A Yeni Unvan' WHERE id="+quote(companyID)+";");
  mark('a_finalised_snapshot_never_follows_its_source',
    sql("SELECT snapshot->>'company_name' FROM private_isg.document_versions WHERE document_id="+quote(document.document_id)+" AND version=1;")==='Firma A'&&
    sql("SELECT encode(snapshot_sha256,'hex') FROM private_isg.document_versions WHERE document_id="+quote(document.document_id)+" AND version=1;")===finalized.snapshot_sha256);

  const races=await Promise.all(Array.from({length:20},()=>concurrentSql("SELECT isg_doc_test.observe('number',"+
    json({company:companyID,scope:'rapor',year:2026})+");")));
  const numbers=races.filter(r=>r.ok).map(r=>JSON.parse(r.output.split('\n').at(-1)).result);
  mark('twenty_concurrent_allocations_produce_twenty_unique_numbers',numbers.length===20&&new Set(numbers).size===20&&
    numbers.every(value=>/^RAPOR-2026-\d+$/.test(value)));

  const pdf=ok('export',{document:document.document_id,version:1,format:'pdf',now:now(20)});
  const xlsx=ok('export',{document:document.document_id,version:1,format:'xlsx',now:now(21)});
  mark('both_formats_render_the_same_snapshot',pdf.snapshot_sha256===xlsx.snapshot_sha256&&
    pdf.content_kind==='structured'&&xlsx.content_kind==='structured'&&
    ok('export',{document:document.document_id,version:1,format:'pdf',now:now(22)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.export_jobs;")==='2');
  const scanned=ok('document',{company:companyID,workplace,domain:'training',source_ref:'scanned-record-1',template:'training_certificate',now:now(23)});
  ok('finalize',{document:scanned.document_id,mutation:randomUUID(),snapshot:{source:'taranmış pdf'},source_kind:'scanned',
    scope:'risk',year:2026,finalized_by:ownerID,now:now(24)});
  mark('a_scanned_original_never_becomes_a_structured_spreadsheet',
    ok('export',{document:scanned.document_id,version:1,format:'xlsx',now:now(25)}).content_kind==='metadata_index'&&
    ok('export',{document:scanned.document_id,version:1,format:'pdf',now:now(26)}).content_kind==='structured');
  mark('a_render_failure_is_separate_from_a_ready_document',
    ok('export_settle',{job:pdf.job_id,state:'ready',asset,error:null,now:now(27)}).state==='ready'&&
    ok('export_settle',{job:xlsx.job_id,state:'failed',asset:null,error:'RENDER_FAILED',now:now(28)}).state==='failed'&&
    sql("SELECT count(*) FROM private_isg.document_versions WHERE document_id="+quote(document.document_id)+";")==='1');
  mark('a_ready_export_is_not_overwritten',call('export_settle',{job:pdf.job_id,state:'failed',asset:null,
    error:'RENDER_FAILED',now:now(29)}).error==='VALIDATION_ERROR');

  const batchArgs=(over={})=>({company:companyID,target:'employee',asset,file_sha256:hex('personel.xlsx'),
    mapping_version:1,mutation:randomUUID(),date_system:'1900',decimal:',',
    columns:['employee_code','full_name','hired_on'],now:now(40),...over});
  mark('a_health_column_stops_the_batch_before_it_opens',call('batch',batchArgs({columns:['full_name','saglik_raporu']})).error==='HEALTH_COLUMN_REFUSED');
  const batchMutation=randomUUID();
  const batch=ok('batch',batchArgs({mutation:batchMutation}));
  mark('a_batch_is_idempotent_per_company_and_mutation',ok('batch',batchArgs({mutation:batchMutation})).replayed===true&&
    sql("SELECT count(*) FROM private_isg.import_batches;")==='1');
  mark('the_same_file_for_another_purpose_is_an_explicit_conflict',
    call('batch',batchArgs({mutation:batchMutation,mapping_version:2})).error==='IDEMPOTENCY_CONFLICT');
  const existingCode=sql("SELECT employee_code FROM private_isg.employees WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const rows=[
    [1,{employee_code:'IMP-001',full_name:'İthal Personel A',hired_on:'2026-01-15'}],
    [2,{employee_code:'IMP-002',full_name:'İthal Personel B',hired_on:'45000'}],
    [3,{employee_code:'',full_name:'Kodsuz Kişi',hired_on:''}],
    [4,{employee_code:existingCode,full_name:'Zaten Var',hired_on:''}],
    [5,{employee_code:'IMP-005',full_name:'',hired_on:''}],
    [6,{employee_code:'IMP-006',full_name:'Tarihi Bozuk',hired_on:'60'}]];
  const staged=rows.map(([row_no,raw])=>ok('row',{batch:batch.batch_id,row_no,raw,now:now(41)}));
  mark('identity_is_never_derived_from_a_name',staged[2].status==='review'&&staged[2].error_code==='IDENTITY_NOT_DERIVABLE');
  mark('a_known_code_is_a_duplicate_not_a_second_person',staged[3].status==='duplicate'&&staged[3].error_code==='EMPLOYEE_CODE_EXISTS');
  mark('a_missing_name_and_a_leap_bug_date_are_errors',staged[4].status==='error'&&staged[4].error_code==='NAME_REQUIRED'&&
    staged[5].status==='error'&&staged[5].error_code==='EXCEL_1900_LEAP_BUG');
  mark('a_serial_date_is_normalised_on_the_row',staged[0].status==='ok'&&staged[1].status==='ok'&&
    staged[1].normalised.hired_on==='2023-03-15');
  mark('a_health_column_in_a_row_is_refused_too',call('row',{batch:batch.batch_id,row_no:7,
    raw:{employee_code:'IMP-007',full_name:'X',kan_grubu:'A'},now:now(42)}).error==='HEALTH_COLUMN_REFUSED');
  mark('a_commit_without_a_preview_is_refused',call('commit',{batch:batch.batch_id,preview:hex('none'),allow_partial:false,now:now(43)}).error==='PREVIEW_REQUIRED');
  const preview=ok('preview',{batch:batch.batch_id,now:now(44)});
  mark('the_preview_lists_every_outcome',preview.summary.rows===6&&preview.summary.ok===2&&preview.summary.error===2&&
    preview.summary.duplicate===1&&preview.summary.review===1);
  mark('a_stale_preview_hash_can_not_commit',call('commit',{batch:batch.batch_id,preview:hex('other'),allow_partial:true,now:now(45)}).error==='PREVIEW_STALE');
  mark('a_partial_commit_needs_an_explicit_policy',call('commit',{batch:batch.batch_id,preview:preview.preview_sha256,allow_partial:false,now:now(46)}).error==='PARTIAL_COMMIT_NOT_ALLOWED');
  sql("UPDATE private_isg.employees SET record_version=record_version+1 WHERE company_id="+quote(companyID)+" AND employee_code="+quote(existingCode)+";");
  mark('a_target_that_moved_after_the_preview_conflicts',call('commit',{batch:batch.batch_id,preview:preview.preview_sha256,allow_partial:true,now:now(47)}).error==='PREVIEW_STALE');
  const restaged=ok('row',{batch:batch.batch_id,row_no:4,raw:{employee_code:existingCode,full_name:'Zaten Var',hired_on:''},now:now(48)});
  const preview2=ok('preview',{batch:batch.batch_id,now:now(49)});
  const committed=ok('commit',{batch:batch.batch_id,preview:preview2.preview_sha256,allow_partial:true,now:now(50)});
  mark('only_clean_rows_are_written_and_the_rest_are_reported',committed.created===2&&committed.skipped===4&&
    committed.partial===true&&restaged.status==='duplicate'&&
    sql("SELECT count(*) FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND employee_code LIKE 'IMP-%';")==='2');
  mark('a_commit_replay_writes_nothing_new',ok('commit',{batch:batch.batch_id,preview:preview2.preview_sha256,allow_partial:true,now:now(51)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND employee_code LIKE 'IMP-%';")==='2');
  mark('a_committed_batch_takes_no_new_row',call('row',{batch:batch.batch_id,row_no:8,raw:{employee_code:'IMP-008',full_name:'Y'},now:now(52)}).error==='BATCH_COMMITTED'&&
    sql("SELECT count(*) FROM private_isg.import_checkpoints WHERE batch_id="+quote(batch.batch_id)+";")==='2');
  sql("UPDATE private_isg.employees SET record_version=record_version+1 WHERE company_id="+quote(companyID)+" AND employee_code='IMP-001';");
  const compensated=ok('compensate',{batch:batch.batch_id,now:now(60)});
  mark('compensation_removes_only_what_it_created_and_did_not_change',compensated.removed===1&&
    compensated.kept_because_changed===1&&
    sql("SELECT count(*) FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND employee_code='IMP-001';")==='1'&&
    sql("SELECT count(*) FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND employee_code='IMP-002';")==='0');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('documents','imports');");
  mark('kill_switch_stops_documents_and_imports',call('export',{document:document.document_id,version:1,format:'pdf',now:now(70)}).error==='FEATURE_UNAVAILABLE'&&
    call('preview',{batch:batch.batch_id,now:now(70)}).error==='FEATURE_UNAVAILABLE');
  sql("DELETE FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND employee_code LIKE 'IMP-%';");
  sql("UPDATE public.companies SET name='Firma A' WHERE id="+quote(companyID)+";");
  return {afterLogout(){
    return {migration_file:documentImportFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,renderer_implemented:false,parser_implemented:false,
      native_or_http_surface:false,production_deployed:false};
  }};
}
