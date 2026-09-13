import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {verifyLocalSessionToken} from './auth_session_probe.mjs';
import {preparePersonnelDirectory} from '../../supabase/functions/_shared/personnel/directory-request.ts';
export const personnelAuthFiles=['workplace_fixture.sql','personnel_fixture.sql','personnel_mutation_fixture.sql','employee_intake_fixture.sql','employee_directory_fixture.sql','auth_personnel_fixture.sql'].map(f=>'scripts/isg/sql/'+f);
export function beginAuthPersonnelProbe({synthetic,sql,token,secret,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_PERSONNEL_SYNTHETIC_REQUIRED');
  const claims=verifyLocalSessionToken(token,secret);
  for(const file of personnelAuthFiles)sql(readFileSync(resolve(ROOT,file),'utf8'));
  const actor=claims.sub,company=randomUUID(),foreign=randomUUID(),other=randomUUID();
  sql(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES('${company}','${actor}','Auth personnel'),('${other}','${foreign}','Foreign');
    INSERT INTO isg_workplace_fixture.personnel_write_access VALUES('${actor}',true);`);
  const quote=v=>"'"+v.replaceAll("'","''")+"'";
  const context=(version=0)=>({schema_version:1,operation_id:randomUUID(),client_mutation_id:randomUUID(),platform:'ios',client_build:1,expected_version:version,scope:{kind:'company',company_id:company}});
  const create={action:'create',context:context(),full_name:'Ada Kaya',department:{kind:'new',name:'Bakım'}};
  const list={action:'employees',company_id:company,query:'',include_archived:false,cursor:null};
  const invoke=(request,jwt=claims)=>{
    const prepared=preparePersonnelDirectory(request);if(!prepared)throw Error('AUTH_RESTORE_PERSONNEL_BAD_REQUEST');
    return JSON.parse(sql(`BEGIN; SET LOCAL ROLE authenticated;
      SELECT set_config('request.jwt.claims',${quote(JSON.stringify(jwt))},true) IS NOT NULL;
      SELECT set_config('request.jwt.claim.sub','${foreign}',true) IS NOT NULL;
      SELECT isg_workplace_fixture.observe_personnel('${prepared.kind}',${quote(JSON.stringify(prepared.args))}::jsonb); COMMIT;`).split('\n').at(-1));
  };
  const snapshot=()=>sql(`SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(e)) FROM isg_workplace_fixture.employees e),
    (SELECT count(*) FROM isg_workplace_fixture.departments),(SELECT count(*) FROM isg_workplace_fixture.employee_create_receipts),
    (SELECT count(*) FROM isg_workplace_fixture.employee_edit_receipts),(SELECT count(*) FROM isg_workplace_fixture.employee_edit_audit),
    (SELECT count(*) FROM isg_workplace_fixture.employee_edit_outbox));`);
  const deny=(label,request,jwt,code)=>{const before=snapshot();pass('auth_personnel_'+label,invoke(request,jwt).error===code&&snapshot()===before);};
  pass('auth_personnel_acl_no_raw_domain_or_table_write',sql(`SELECT has_function_privilege('authenticated','isg_workplace_fixture.create_employee(uuid,uuid,uuid,text,uuid,text)','EXECUTE');
    SELECT has_function_privilege('anon','isg_workplace_fixture.personnel_verified(text,jsonb)','EXECUTE');
    SELECT has_function_privilege('service_role','isg_workplace_fixture.personnel_verified(text,jsonb)','EXECUTE');
    SELECT has_table_privilege('authenticated','isg_workplace_fixture.employees','UPDATE');`)==='f\nf\nf\nf');
  const committed=invoke(create).result;
  pass('auth_personnel_create_with_real_session',!!committed?.employee_id&&committed.version===0);
  pass('auth_personnel_fresh_owner_overrides_forged_legacy_sub',invoke(list).result?.rows?.[0]?.owner_id===actor);
  const before=snapshot();pass('auth_personnel_create_receipt_retry_one_employee',JSON.stringify(invoke(create).result)===JSON.stringify(committed)&&snapshot()===before);
  const employeeID=committed.employee_id;
  const edit={action:'edit',context:context(),employee_id:employeeID,full_name:'Ada Yeni',department:{kind:'keep'}};
  pass('auth_personnel_edit_with_real_session',invoke(edit).result?.version===1);
  deny('foreign_company', {...list,company_id:other},claims,'ACCESS_DENIED');
  deny('missing_session',list,{...claims,session_id:undefined},'AUTH_REQUIRED');
  deny('expired_token',list,{...claims,exp:Math.floor(Date.now()/1000)-1},'AUTH_REQUIRED');
  sql(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=false WHERE actor_id='${actor}';`);
  deny('revoked_create_retry',create,claims,'ACCESS_DENIED');deny('revoked_edit_retry',edit,claims,'ACCESS_DENIED');
  deny('metadata_cannot_grant_write',create,{...claims,user_metadata:{tier:'pro',can_mutate:true}},'ACCESS_DENIED');
  pass('auth_personnel_revoked_write_keeps_read_access',invoke(list).result?.rows?.[0]?.name==='Ada Yeni');
  sql(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=true WHERE actor_id='${actor}';`);
  const archive={action:'archive',context:context(1),employee_id:employeeID};
  pass('auth_personnel_archive_preserves_row',invoke(archive).result?.version===2&&invoke({...list,include_archived:true}).result?.rows?.[0]?.is_archived===true);
  return {afterLogout(){
    const signed=verifyLocalSessionToken(token,secret);
    deny('logout_denies_read',list,signed,'AUTH_REQUIRED');
    deny('logout_denies_create', {...create,context:context()},signed,'AUTH_REQUIRED');
    deny('logout_denies_archive_receipt',archive,signed,'AUTH_REQUIRED');
    return {synthetic:true,real_local_session:true,production_api:false,billing_integrated:false};
  }};
}
