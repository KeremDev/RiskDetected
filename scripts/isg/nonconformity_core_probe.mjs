import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const nonconformityCoreFiles=[
  'supabase/migrations/20260913210000_isg_nonconformity_core.sql',
  'scripts/isg/nonconformity_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,13,21,0,0)+seconds*1000).toISOString();

const STATES=['draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled'];
const ALLOWED=new Set(['draft>open','draft>cancelled','open>assigned','open>cancelled','assigned>in_progress',
  'assigned>open','assigned>cancelled','in_progress>pending_verification','in_progress>assigned','in_progress>cancelled',
  'pending_verification>closed','pending_verification>in_progress','closed>reopened','reopened>assigned',
  'reopened>in_progress','reopened>cancelled']);
// Shortest path from draft to every state, used to build a fresh record per edge.
const PATHS={draft:[],open:['open'],assigned:['open','assigned'],in_progress:['open','assigned','in_progress'],
  pending_verification:['open','assigned','in_progress','pending_verification'],
  closed:['open','assigned','in_progress','pending_verification','closed'],
  reopened:['open','assigned','in_progress','pending_verification','closed','reopened'],
  cancelled:['cancelled']};

export async function beginNonconformityCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_NONCONFORMITY_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_NONCONFORMITY_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('nonconformity_core_'+name,ok);
  sql(read(nonconformityCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='nonconformity';")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");

  sql(["CREATE SCHEMA isg_nc_test;",
    "CREATE FUNCTION isg_nc_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='open' THEN r:=private_isg.open_nonconformity((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'source_kind',a->>'source_ref',a->>'title',a->>'severity',(a->>'opened_on')::date,(a->>'due_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='move' THEN r:=private_isg.transition_nonconformity((a->>'nonconformity')::uuid,a->>'to_state',(a->>'expected')::bigint,a->>'reason',a->>'assignee',(a->>'actor')::uuid,(a->>'closed_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='action' THEN r:=private_isg.add_corrective_action((a->>'nonconformity')::uuid,a->>'description',a->>'assignee',(a->>'due_on')::date,a->>'external_ref',(a->>'now')::timestamptz);",
    "ELSIF kind='verify' THEN r:=private_isg.record_verification((a->>'nonconformity')::uuid,a->>'outcome',(a->>'verified_by')::uuid,(a->>'verified_on')::date,(a->>'asset')::uuid,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='publish' THEN r:=private_isg.publish_checklist_version(a->>'code',(a->>'version')::integer,(a->>'approver')::uuid,a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='run' THEN r:=private_isg.start_checklist_run((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'code',(a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='item' THEN r:=private_isg.record_run_item((a->>'run')::uuid,a->>'item',a->>'result',a->>'note',(a->>'asset')::uuid,(a->>'open_nonconformity')::boolean,a->>'severity',(a->>'due_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='submit' THEN r:=private_isg.submit_checklist_run((a->>'run')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='reconcile' THEN r:=private_isg.reconcile_nonconformities((a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','VERSION_CONFLICT','TRANSITION_NOT_ALLOWED','ASSIGNEE_REQUIRED','VERIFICATION_REQUIRED','IDEMPOTENCY_CONFLICT','RUN_SUBMITTED','RUN_INCOMPLETE') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_nc_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_NONCONFORMITY_UNEXPECTED_'+r.error);return r.result;};

  const fresh=(over={})=>({company:companyID,workplace,source_kind:'manual',source_ref:null,title:'Korkuluk eksik',
    severity:'high',opened_on:'2026-09-01',due_on:'2026-09-30',now:now(0),...over});
  mark('gate_blocks_the_domain_while_rollout_off',call('open',fresh()).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('nonconformity_gate','open_nonconformity','transition_nonconformity','add_corrective_action','record_verification','publish_checklist_version','start_checklist_run','record_run_item','submit_checklist_run','reconcile_nonconformities') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('nonconformity_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='nonconformity';");

  const move=(id,to,expected,over={})=>call('move',{nonconformity:id,to_state:to,expected,reason:'Gerekçe kaydı yazıldı.',
    assignee:null,actor:ownerID,closed_on:null,now:now(1),...over});
  // Walk a fresh record to a state, then try one edge out of it.
  const walkTo=(state,tick)=>{
    const created=ok('open',fresh({title:'Matris '+state+' '+tick,now:now(tick)}));
    let version=0;
    for(const step of PATHS[state]) {
      if(step==='assigned')  { move(created.nonconformity_id,step,version,{assignee:'Saha Şefi',now:now(tick)}); }
      else if(step==='closed') {
        ok('verify',{nonconformity:created.nonconformity_id,outcome:'accepted',verified_by:ownerID,verified_on:'2026-09-20',asset:null,note:null,now:now(tick)});
        move(created.nonconformity_id,step,version,{closed_on:'2026-09-20',now:now(tick)});
      } else move(created.nonconformity_id,step,version,{now:now(tick)});
      version+=1;
    }
    return {id:created.nonconformity_id,version};
  };
  let allowedOK=0,forbiddenOK=0,tick=10;
  for(const from of STATES) {
    tick+=1;
    // A refused edge changes nothing, so one record per from-state carries all
    // of them; each allowed edge gets its own fresh record.
    const shared=walkTo(from,tick);
    for(const to of STATES) {
      if(from===to){forbiddenOK+=1;continue;}
      const permitted=ALLOWED.has(from+'>'+to);
      const subject=permitted?walkTo(from,++tick):shared;
      if(permitted&&to==='closed')
        ok('verify',{nonconformity:subject.id,outcome:'accepted',verified_by:ownerID,verified_on:'2026-09-20',asset:null,note:null,now:now(tick)});
      const result=move(subject.id,to,subject.version,{assignee:'Saha Şefi',closed_on:to==='closed'?'2026-09-20':null,now:now(tick)});
      if(permitted) { if(result.result?.state===to) allowedOK+=1; }
      else if(result.error==='TRANSITION_NOT_ALLOWED') forbiddenOK+=1;
    }
  }
  mark('every_allowed_edge_moves_and_every_other_edge_is_refused',allowedOK===16&&forbiddenOK===48);
  mark('the_matrix_lives_in_the_database',sql("SELECT count(*) FROM private_isg.nonconformity_state_edges;")==='16');

  const subject=walkTo('in_progress',200);
  mark('a_stale_version_can_not_move_the_record',move(subject.id,'pending_verification',subject.version-1,{now:now(201)}).error==='VERSION_CONFLICT');
  mark('an_assignment_needs_a_contact',(()=>{
    const other=walkTo('open',202);
    return move(other.id,'assigned',other.version,{assignee:null,now:now(203)}).error==='ASSIGNEE_REQUIRED';})());
  mark('a_cancellation_needs_a_reason',(()=>{
    const other=walkTo('open',204);
    return move(other.id,'cancelled',other.version,{reason:null,now:now(205)}).error==='VALIDATION_ERROR';})());
  mark('closing_needs_an_accepted_expert_verification',(()=>{
    const other=walkTo('pending_verification',206);
    const refused=move(other.id,'closed',other.version,{closed_on:'2026-09-20',now:now(207)});
    ok('verify',{nonconformity:other.id,outcome:'rejected',verified_by:ownerID,verified_on:'2026-09-20',asset:null,note:'Kanıt yetersiz.',now:now(208)});
    const stillRefused=move(other.id,'closed',other.version,{closed_on:'2026-09-20',now:now(209)});
    return refused.error==='VERIFICATION_REQUIRED'&&stillRefused.error==='VERIFICATION_REQUIRED';})());
  mark('a_verification_is_recorded_once_per_cycle',(()=>{
    const other=walkTo('pending_verification',210);
    const first=ok('verify',{nonconformity:other.id,outcome:'accepted',verified_by:ownerID,verified_on:'2026-09-20',asset,note:null,now:now(211)});
    const again=ok('verify',{nonconformity:other.id,outcome:'accepted',verified_by:ownerID,verified_on:'2026-09-20',asset,note:null,now:now(212)});
    const flipped=call('verify',{nonconformity:other.id,outcome:'rejected',verified_by:ownerID,verified_on:'2026-09-20',asset:null,note:null,now:now(213)});
    return again.replayed===true&&again.verification_id===first.verification_id&&flipped.error==='IDEMPOTENCY_CONFLICT';})());
  mark('a_verification_needs_a_clean_document',(()=>{
    const other=walkTo('pending_verification',214);
    return call('verify',{nonconformity:other.id,outcome:'accepted',verified_by:ownerID,verified_on:'2026-09-20',asset:randomUUID(),note:null,now:now(215)}).error==='ACCESS_DENIED';})());
  mark('reopening_starts_a_new_verification_cycle',(()=>{
    const other=walkTo('closed',216);
    const reopened=move(other.id,'reopened',other.version,{now:now(217)});
    const back=move(other.id,'in_progress',reopened.result.version,{now:now(218)});
    const pending=move(other.id,'pending_verification',back.result.version,{now:now(219)});
    const refused=move(other.id,'closed',pending.result.version,{closed_on:'2026-09-25',now:now(220)});
    return reopened.result.state==='reopened'&&refused.error==='VERIFICATION_REQUIRED'&&
      sql("SELECT closed_on IS NULL FROM private_isg.nonconformities WHERE nonconformity_id="+quote(other.id)+";")==='t';})());
  mark('every_move_leaves_an_audit_row',sql("SELECT count(*)=count(DISTINCT (nonconformity_id,version)) FROM private_isg.nonconformity_transitions;")==='t'&&
    sql("SELECT count(*)>0 FROM private_isg.nonconformity_transitions WHERE actor_id="+quote(ownerID)+";")==='t');

  const actionSubject=walkTo('assigned',230);
  const action=ok('action',{nonconformity:actionSubject.id,description:'Korkuluk montajı yapılacak.',assignee:'Taşeron Ustabaşı',due_on:'2026-09-25',external_ref:'WO-1',now:now(231)});
  mark('an_action_assignee_is_not_an_application_user',action.assignee_is_application_user===false&&
    ok('action',{nonconformity:actionSubject.id,description:'Korkuluk montajı yapılacak.',assignee:'Taşeron Ustabaşı',due_on:'2026-09-25',external_ref:'WO-1',now:now(232)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.nonconformity_actions WHERE nonconformity_id="+quote(actionSubject.id)+";")==='1');
  mark('a_closed_record_takes_no_new_action',(()=>{
    const other=walkTo('closed',233);
    return call('action',{nonconformity:other.id,description:'Sonradan aksiyon',assignee:null,due_on:null,external_ref:null,now:now(234)}).error==='VALIDATION_ERROR';})());

  const legacy=ok('open',fresh({source_kind:'legacy_finding',source_ref:'legacy-finding-1',title:'Eski bulgudan açıldı',now:now(240)}));
  mark('a_legacy_finding_is_only_referenced_never_written',legacy.legacy_finding_written===false&&
    ok('open',fresh({source_kind:'legacy_finding',source_ref:'legacy-finding-1',title:'Tekrar tıklandı',now:now(241)})).replayed===true&&
    sql("SELECT count(*) FROM private_isg.nonconformities WHERE source_kind='legacy_finding';")==='1');
  mark('a_source_backed_record_needs_its_reference',call('open',fresh({source_kind:'risk_version',source_ref:null,now:now(242)})).error==='VALIDATION_ERROR');

  sql("INSERT INTO private_isg.checklist_templates(template_code,title) VALUES('site_walk','Saha Turu Kontrol Listesi');");
  const seedTemplate=version=>{
    sql("INSERT INTO private_isg.checklist_template_versions(template_code,version) VALUES('site_walk',"+version+");");
    sql("INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position) VALUES"+
      "('site_walk',"+version+",'guardrail','Korkuluklar tam mı?',false,1),('site_walk',"+version+",'ppe','KKD kullanımı uygun mu?',true,2);");
  };
  seedTemplate(1);
  sql("INSERT INTO private_isg.checklist_templates(template_code,title) VALUES('empty_list','Boş Liste');INSERT INTO private_isg.checklist_template_versions(template_code,version) VALUES('empty_list',1);");
  mark('an_empty_template_can_not_publish',call('publish',{code:'empty_list',version:1,approver:ownerID,note:'Onay',now:now(250)}).error==='VALIDATION_ERROR');
  const template=ok('publish',{code:'site_walk',version:1,approver:ownerID,note:'Saha turu listesi onaylandı.',now:now(251)});
  mark('a_published_template_carries_its_approval',template.items===2&&
    ok('publish',{code:'site_walk',version:1,approver:ownerID,note:'Tekrar',now:now(252)}).replayed===true);
  const run=ok('run',{company:companyID,workplace,code:'site_walk',on:'2026-09-10',now:now(253)});
  mark('a_run_pins_the_template_version',run.template_version===1&&run.state==='open');
  mark('an_unknown_item_or_a_forbidden_not_applicable_is_refused',
    call('item',{run:run.run_id,item:'missing_item',result:'conform',note:null,asset:null,open_nonconformity:false,severity:null,due_on:null,now:now(254)}).error==='VALIDATION_ERROR'&&
    call('item',{run:run.run_id,item:'guardrail',result:'not_applicable',note:null,asset:null,open_nonconformity:false,severity:null,due_on:null,now:now(255)}).error==='VALIDATION_ERROR');
  const failing=ok('item',{run:run.run_id,item:'guardrail',result:'nonconform',note:'Kuzey cephede korkuluk yok.',asset,open_nonconformity:true,severity:'critical',due_on:'2026-09-20',now:now(256)});
  mark('a_failing_item_opens_one_record_however_often_it_is_tapped',!!failing.nonconformity_id&&
    ok('item',{run:run.run_id,item:'guardrail',result:'nonconform',note:'Kuzey cephede korkuluk yok.',asset,open_nonconformity:true,severity:'critical',due_on:'2026-09-20',now:now(257)}).nonconformity_id===failing.nonconformity_id&&
    sql("SELECT count(*) FROM private_isg.nonconformities WHERE source_kind='checklist';")==='1');
  mark('an_incomplete_run_can_not_be_submitted',call('submit',{run:run.run_id,now:now(258)}).error==='RUN_INCOMPLETE');
  ok('item',{run:run.run_id,item:'ppe',result:'not_applicable',note:null,asset:null,open_nonconformity:false,severity:null,due_on:null,now:now(259)});
  mark('a_submitted_run_is_closed_for_edits',ok('submit',{run:run.run_id,now:now(260)}).state==='submitted'&&
    call('item',{run:run.run_id,item:'ppe',result:'conform',note:null,asset:null,open_nonconformity:false,severity:null,due_on:null,now:now(261)}).error==='RUN_SUBMITTED');
  const runSnapshot=sql("SELECT md5(string_agg(item_code||':'||result,',' ORDER BY item_code)) FROM private_isg.checklist_run_items WHERE run_id="+quote(run.run_id)+";");
  seedTemplate(2);
  ok('publish',{code:'site_walk',version:2,approver:ownerID,note:'İkinci sürüm yayını.',now:now(262)});
  mark('publishing_a_new_template_never_edits_an_old_run',
    sql("SELECT template_version FROM private_isg.checklist_runs WHERE run_id="+quote(run.run_id)+";")==='1'&&
    runSnapshot===sql("SELECT md5(string_agg(item_code||':'||result,',' ORDER BY item_code)) FROM private_isg.checklist_run_items WHERE run_id="+quote(run.run_id)+";"));

  const report=ok('reconcile',{on:'2026-10-01',now:now(270)});
  mark('reconciliation_counts_the_real_ledger',report.closed_without_verification===0&&report.critical_open>=1&&
    report.total===Number(sql("SELECT count(*) FROM private_isg.nonconformities;"))&&
    report.overdue===Number(sql("SELECT count(*) FROM private_isg.nonconformities WHERE state NOT IN ('closed','cancelled') AND due_on IS NOT NULL AND due_on<'2026-10-01';")));
  mark('reconciliation_keeps_one_row_per_day',!!ok('reconcile',{on:'2026-10-01',now:now(271)})&&sql("SELECT count(*) FROM private_isg.nonconformity_reconciliations;")==='1');

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='nonconformity';");
  mark('kill_switch_stops_the_nonconformity_domain',call('open',fresh({now:now(280)})).error==='FEATURE_UNAVAILABLE'&&
    call('submit',{run:run.run_id,now:now(280)}).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:nonconformityCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,legacy_findings_written:false,assignee_is_application_user:false,
      document_export_implemented:false,production_deployed:false};
  }};
}
