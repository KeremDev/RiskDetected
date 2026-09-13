import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {verifyLocalSessionToken} from './auth_session_probe.mjs';
export const directoryMigrationFiles=['supabase/migrations/20260913081536_isg_workplace_context_assignments.sql','scripts/isg/directory_migration_probe.mjs'];
const q=v=>"'"+String(v).replaceAll("'","''")+"'";

export async function beginDirectoryMigrationProbe({synthetic,sql,token,secret,companyID,request,waitReady,pass}) {
  if(synthetic!==true)throw Error('DIRECTORY_SYNTHETIC_REQUIRED');
  const claims=verifyLocalSessionToken(token,secret),company=companyID;
  let sequence=0;
  const mark=(name,ok)=>pass('directory_'+(++sequence)+'_'+name,ok);
  sql(readFileSync(resolve(ROOT,directoryMigrationFiles[0]),'utf8'));
  const readArgs=(kind,parent=null,after=null,archived=false)=>({p_company:company,p_kind:kind,p_parent:parent,p_after:after,p_archived:archived});
  const httpRead=(kind,parent=null)=>request('/rpc/isg_directory_read_v1',{method:'POST',body:readArgs(kind,parent)});
  await waitReady(()=>httpRead('workplaces').status===200);
  mark('http_owner_read',httpRead('workplaces').body.rows.length>0);
  sql(`CREATE FUNCTION isg_rpc_test.directory(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
  DECLARE r jsonb;state text;message text;BEGIN
  IF kind='read' THEN r:=public.isg_directory_read_v1((a->>'p_company')::uuid,a->>'p_kind',(a->>'p_parent')::uuid,(a->>'p_after')::uuid,(a->>'p_archived')::boolean);
  ELSIF kind='context' THEN r:=public.isg_context_at_v1((a->>'p_company')::uuid,(a->>'p_workplace')::uuid,(a->>'p_on')::date);
  ELSE r:=public.isg_directory_mutate_v1((a->>'p_company')::uuid,a->>'p_kind',(a->>'p_operation')::uuid,(a->>'p_mutation')::uuid,(a->>'p_id')::uuid,(a->>'p_expected')::bigint,a->'p_body');END IF;
  RETURN jsonb_build_object('result',r);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS state=RETURNED_SQLSTATE,message=MESSAGE_TEXT;RETURN jsonb_build_object('state',state,'error',message);END $$;
  REVOKE ALL ON FUNCTION isg_rpc_test.directory(text,jsonb) FROM PUBLIC;GRANT EXECUTE ON FUNCTION isg_rpc_test.directory(text,jsonb) TO authenticated;`);
  const invoke=(kind,args)=>JSON.parse(sql(`BEGIN;SET LOCAL ROLE authenticated;SELECT set_config('request.jwt.claims',${q(JSON.stringify(claims))},true) IS NOT NULL;SELECT isg_rpc_test.directory(${q(kind)},${q(JSON.stringify(args))}::jsonb);COMMIT;`).split('\n').at(-1));
  const write=(kind,body,id=null,version=0)=>({p_company:company,p_kind:kind,p_operation:randomUUID(),p_mutation:randomUUID(),p_id:id,p_expected:version,p_body:body});
  const create=(kind,body)=>{const args=write(kind,body);const out=invoke('write',args);assert.ok(out.result,`${kind}: ${JSON.stringify(out)}`);mark(kind+'_create',out.result.version===0);return {id:out.result.entity_id,args,result:out.result};};
  const snap=()=>sql("SELECT jsonb_build_array((SELECT count(*) FROM private_isg.personnel_receipts),(SELECT count(*) FROM private_isg.directory_events),(SELECT count(*) FROM private_isg.directory_outbox),(SELECT count(*) FROM private_isg.employee_assignments),(SELECT count(*) FROM private_isg.workplace_context_versions),(SELECT jsonb_agg(to_jsonb(w) ORDER BY id) FROM private_isg.workplaces w),(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM private_isg.departments d));");
  const deny=(name,args,error,kind='write')=>{const before=snap(),r=invoke(kind,args);if(r.error!==error&&r.state!==error)throw Error('AUTH_RESTORE_DIRECTORY_'+name+'_'+(r.state??'UNEXPECTED_SUCCESS'));mark(name,snap()===before);};
  mark('rls_all_tables',sql("SELECT count(*)=15 AND bool_and(rowsecurity) FROM pg_tables WHERE schemaname='private_isg';")==='t');
  mark('no_direct_client_grants',sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN('PUBLIC','anon','authenticated','service_role');")==='0');
  mark('five_checked_private_entries',sql("SELECT count(*)=5 AND bool_and(prosecdef AND proconfig @> ARRAY['search_path=\"\"']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('authenticated',p.oid,'EXECUTE');")==='t');
  mark('no_anon_or_service_entry',sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND(has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));")==='0');
  const w=create('workplaces',{name:'İkinci İşyeri',code:'001',address:null,is_archived:false});
  const dep=create('departments',{name:'Üretim',code:'01',workplace_id:w.id,parent_id:null,is_archived:false});
  const child=create('departments',{name:'Alt Bölüm',code:'02',workplace_id:w.id,parent_id:dep.id,is_archived:false});
  const job=create('jobs',{name:'Operatör',code:'J01',description:'İş tanımı',is_archived:false});
  const org=create('contractors',{name:'Dış Firma',code:'O01',relationship:'subcontractor',is_archived:false});
  const engagement=create('engagements',{organization_id:org.id,workplace_id:w.id,starts_on:'2026-01-01',ends_before:null,description:'Bakım'});
  for(const item of [w,dep,child,job,org,engagement]) {const before=snap();mark('replay_'+item.args.p_kind,JSON.stringify(invoke('write',item.args).result)===JSON.stringify(item.result)&&before===snap());}
  deny('hierarchy_cycle',write('departments',{...dep.args.p_body,parent_id:child.id},dep.id),'HIERARCHY_CYCLE');
  deny('cross_workplace_department',write('departments',{...child.args.p_body,workplace_id:httpRead('workplaces').body.rows.find(r=>r.id!==w.id).id},child.id),'DEPARTMENT_SCOPE_INVALID');
  deny('stale_job',write('jobs',job.args.p_body,job.id,9),'VERSION_CONFLICT');
  deny('duplicate_code',write('jobs',{...job.args.p_body,name:'Diğer'}),'23505');
  deny('numeric_name',write('jobs',{...job.args.p_body,name:12,code:'NUM'}),'VALIDATION_ERROR');
  deny('extra_health_field',write('jobs',{...job.args.p_body,diagnosis:'forbidden'}),'VALIDATION_ERROR');
  deny('foreign_read',{...readArgs('jobs'),p_company:randomUUID()},'ACCESS_DENIED','read');
  deny('foreign_write',{...w.args,p_company:randomUUID()},'ACCESS_DENIED');
  deny('overlap_engagement',write('engagements',{...engagement.args.p_body,starts_on:'2026-02-01'}),'23P01');
  deny('non_iso_date',write('engagements',{...engagement.args.p_body,starts_on:'today'}),'VALIDATION_ERROR');
  deny('invalid_date',write('engagements',{...engagement.args.p_body,starts_on:'2026-02-30'}),'22008');
  const employee=sql(`INSERT INTO private_isg.employees(company_id,owner_id,employee_code,full_name) VALUES(${q(company)},${q(claims.sub)},'DATED-ADA','Dated Ada') RETURNING id;`).trim();
  const employer=invoke('write',write('employers',{organization_id:org.id},employee));mark('employer_link',employer.result?.version===1);
  const assignBody={employee_id:employee,previous_id:null,workplace_id:w.id,department_id:dep.id,job_role_id:job.id,starts_on:'2026-01-01',reason:'İlk görevlendirme'};
  const assignment=invoke('write',write('assignments',assignBody));assert.ok(assignment.result,JSON.stringify(assignment));mark('assignment_created',assignment.result.version===1);
  deny('assignment_overlap',write('assignments',{...assignBody,starts_on:'2026-02-01'},null,1),'23P01');
  const rename=invoke('write',write('jobs',{...job.args.p_body,name:'Yeni Unvan'},job.id));mark('job_rename',rename.result?.version===1);
  mark('snapshot_preserved',httpRead('assignments',employee).body.rows[0].job_title_snapshot==='Operatör');
  const transfer=invoke('write',write('assignments',{...assignBody,previous_id:assignment.result.entity_id,starts_on:'2026-06-01'},null,1));assert.ok(transfer.result,JSON.stringify(transfer));
  mark('assignment_split',sql(`SELECT count(*)=2 AND count(*) FILTER(WHERE ends_before='2026-06-01')=1 FROM private_isg.employee_assignments WHERE employee_id=${q(employee)};`)==='t');
  mark('new_snapshot',httpRead('assignments',employee).body.rows.find(r=>r.id===transfer.result.entity_id).job_title_snapshot==='Yeni Unvan');
  const contextArgs=date=>({p_company:company,p_workplace:w.id,p_on:date});
  mark('unknown_context_no_default',invoke('context',contextArgs('2025-01-01')).result?.status==='needs_review');
  const body={workplace_id:w.id,previous_id:null,starts_on:'2026-01-01',timezone:'Europe/Istanbul',jurisdiction:'TR',hazard_class:'high',industry_code:'001',evidence_note:'Sentetik kayıt'};
  const context=invoke('write',write('contexts',body));assert.ok(context.result,JSON.stringify(context));mark('context_created',context.result.version===1);
  deny('context_overlap',write('contexts',{...body,starts_on:'2026-02-01'},null,1),'23P01');
  deny('context_bad_timezone',write('contexts',{...body,timezone:'Invented/Zone'},null,1),'TIMEZONE_INVALID');
  const split=invoke('write',write('contexts',{...body,previous_id:context.result.entity_id,starts_on:'2026-07-01',hazard_class:'low'},null,1));assert.ok(split.result,JSON.stringify(split));
  mark('context_historical',invoke('context',contextArgs('2026-06-30')).result?.context?.hazard_class==='high');
  mark('context_boundary',invoke('context',contextArgs('2026-07-01')).result?.context?.hazard_class==='low');
  mark('context_before_history_unknown',invoke('context',contextArgs('2025-12-31')).result?.status==='needs_review');
  mark('parent_version',httpRead('contexts',w.id).body.parent_version===2&&httpRead('assignments',employee).body.parent_version===2);
  for(const table of ['directory_events','directory_outbox','personnel_receipts']) {
    sql(`CREATE TRIGGER test_directory_tail BEFORE INSERT ON private_isg.${table} FOR EACH ROW EXECUTE FUNCTION isg_rpc_test.fail_write();`);
    deny('rollback_'+table,write('contexts',{...body,previous_id:split.result.entity_id,starts_on:'2026-09-01'},null,2),'TEST_FAULT');
    sql(`DROP TRIGGER test_directory_tail ON private_isg.${table};`);
  }
  const httpArgs=write('jobs',{name:'HTTP Unvan',code:'HTTP-J',description:'',is_archived:false});
  const httpWrite=()=>request('/rpc/isg_directory_mutate_v1',{method:'POST',body:httpArgs});
  mark('http_mutation',httpWrite().status===200);mark('http_replay',httpWrite().body.version===0);
  mark('http_no_token',request('/rpc/isg_directory_read_v1',{method:'POST',body:readArgs('jobs'),authorization:null}).status===401);
  const forged=token.split('.');forged[2]=(forged[2][0]==='A'?'B':'A')+forged[2].slice(1);
  mark('http_forged_token',request('/rpc/isg_directory_read_v1',{method:'POST',body:readArgs('jobs'),authorization:forged.join('.')}).status===401);
  mark('http_context_resolver',request('/rpc/isg_context_at_v1',{method:'POST',body:contextArgs('2026-07-01')}).body.context?.hazard_class==='low');
  sql('UPDATE private_isg.rollout SET write_enabled=false;');deny('rollout_off_replay',httpArgs,'FEATURE_UNAVAILABLE');sql('UPDATE private_isg.rollout SET write_enabled=true;');
  return {afterLogout(){mark('logout_read',httpRead('jobs').status===403);mark('logout_write_and_receipt',httpWrite().status===403);return {migration_applied:true,real_gotrue:true,real_postgrest:true,production_deployed:false,full_legacy_restore:false};}};
}
