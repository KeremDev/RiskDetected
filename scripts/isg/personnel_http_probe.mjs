import {randomBytes,randomUUID} from 'node:crypto';
import {verifyLocalSessionToken} from './auth_session_probe.mjs';
import {preparePersonnelRPC} from '../../supabase/functions/_shared/personnel/rpc-request.ts';

// Dedicated allowlisted HTTP client in the same network=none namespace. No host ports.
const program=`const http=require('node:http');let raw='';process.stdin.on('data',c=>raw+=c);process.stdin.on('end',()=>{
const q=JSON.parse(raw);if(!['/','/employees','/rpc/read_personnel','/rpc/isg_personnel_read_v1','/rpc/isg_personnel_mutate_v1','/rpc/isg_directory_read_v1','/rpc/isg_directory_mutate_v1','/rpc/isg_context_at_v1','/rpc/isg_workspace_availability_v1'].includes(q.path)||!['GET','POST'].includes(q.method)||!['public','private_isg'].includes(q.schema))process.exit(2);
const req=http.request({host:'127.0.0.1',port:3000,path:q.path,method:q.method,headers:{'Content-Type':'application/json','Accept-Profile':q.schema,'Content-Profile':q.schema,...(q.token?{Authorization:'Bearer '+q.token}:{})}},res=>{
let body='';res.on('data',c=>{body+=c;if(body.length>1048576)req.destroy();});res.on('end',()=>{let value;try{value=JSON.parse(body)}catch{value=null;}process.stdout.write(JSON.stringify({status:res.statusCode,body:value}));});});
req.setTimeout(10000,()=>req.destroy());req.on('error',()=>process.exit(3));if(q.body)req.write(JSON.stringify(q.body));req.end();});`;

export async function beginPersonnelHTTPProbe({synthetic,token,secret,companyID,sql,start,guard,docker,names,waitReady,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_PERSONNEL_HTTP_SYNTHETIC_REQUIRED');
  const claims=verifyLocalSessionToken(token,secret);
  if(!/^[a-f0-9-]{36}$/.test(companyID??''))throw Error('AUTH_RESTORE_PERSONNEL_HTTP_SCOPE_INVALID');
  const password=randomBytes(32).toString('hex');
  // Authenticator is a gateway login, never a BYPASSRLS/domain write role.
  sql(`ALTER ROLE authenticator PASSWORD '${password}'; GRANT anon,authenticated TO authenticator;`);
  start('rest',{PGRST_DB_URI:`postgres://authenticator:${password}@127.0.0.1:5432/postgres?sslmode=disable`,
    PGRST_DB_SCHEMAS:'public',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:secret,
    PGRST_DB_CONFIG:'false',PGRST_SERVER_HOST:'127.0.0.1',PGRST_SERVER_PORT:'3000',PGRST_LOG_LEVEL:'crit'});
  const request=(path,{method='GET',body,authorization=token,schema='public'}={})=>{
    guard('rest');guard('client');
    const result=docker(['exec','-i',names.client,'node','-e',program],{input:JSON.stringify({path,method,body,token:authorization,schema}),maxBuffer:2*1024*1024});
    if(result.status!==0)throw Error('AUTH_RESTORE_PERSONNEL_HTTP_UNAVAILABLE');
    return JSON.parse(result.stdout);
  };
  const mark=(id,ok)=>pass('personnel_http_'+id,ok);
  await waitReady(()=>{try{return request('/',{authorization:null}).status===200;}catch{return false;}});
  const send=(body,options={})=>{const p=preparePersonnelRPC(body);if(!p)throw Error('AUTH_RESTORE_PERSONNEL_HTTP_CONTRACT_INVALID');return request('/rpc/'+p.functionName,{method:'POST',body:p.args,...options});};
  const context=(version=0)=>({schema_version:1,operation_id:randomUUID(),client_mutation_id:randomUUID(),platform:'android',client_build:1,expected_version:version,scope:{kind:'company',company_id:companyID}});
  const list={action:'employees',company_id:companyID,query:'',include_archived:false,cursor:null};
  const create={action:'create',context:context(),full_name:'HTTP Ada Kaya',department:{kind:'new',name:'HTTP Bakım'}};
  mark('no_token_denied',send(list,{authorization:null}).status===401);
  const parts=token.split('.');parts[2]=(parts[2][0]==='A'?'B':'A')+parts[2].slice(1);
  mark('forged_signature_denied',send(list,{authorization:parts.join('.')}).status===401);
  const first=send(create);mark('verified_login_creates_via_public_wrapper',first.status===200&&first.body.owner_id===claims.sub&&first.body.company_id===companyID&&first.body.version===0&&first.body.operation_id===create.context.operation_id);
  const replay=send(create);mark('retry_same_receipt',replay.status===200&&JSON.stringify(replay.body)===JSON.stringify(first.body));
  const conflict=send({...create,full_name:'Başka'});mark('changed_payload_conflict',conflict.status===400&&conflict.body.message==='IDEMPOTENCY_CONFLICT');
  const rows=send(list);mark('owner_list',rows.status===200&&rows.body.rows.some(r=>r.id===first.body.employee_id));
  const detail=send({action:'detail',company_id:companyID,employee_id:first.body.employee_id});mark('detail_includes_department',detail.status===200&&detail.body.department_name==='HTTP Bakım');
  const depts=send({...list,action:'departments',query:'HTTP'});mark('department_list',depts.status===200&&depts.body.rows.some(r=>r.id===detail.body.department_id));
  const edit={action:'edit',context:context(),employee_id:first.body.employee_id,full_name:'HTTP Ada Yeni',department:null};
  const updated=send(edit);mark('edit_removes_optional_department',updated.status===200&&updated.body.version===1&&send({action:'detail',company_id:companyID,employee_id:first.body.employee_id}).body.department_id===null);
  const stale=send({...edit,context:context()});mark('stale_version_denied',stale.status===400&&stale.body.message==='VERSION_CONFLICT');
  const archive={action:'archive',context:context(1),employee_id:first.body.employee_id};
  const archived=send(archive);mark('archive_retains_record',archived.status===200&&archived.body.version===2&&archived.body.is_archived&&send({action:'detail',company_id:companyID,employee_id:first.body.employee_id}).body.is_archived);
  const denied=send({...list,company_id:randomUUID()});mark('unknown_company_denied',denied.status===400&&denied.body.message==='ACCESS_DENIED');
  mark('private_schema_not_exposed',request('/employees',{schema:'private_isg'}).status===406);
  mark('private_rpc_not_exposed',request('/rpc/read_personnel',{method:'POST',body:preparePersonnelRPC(list).args}).status===404);
  mark('private_table_not_in_public',request('/employees').status===404);
  return {request,afterLogout(){
    const read=send(list),write=send(create),retry=send(archive);
    mark('revoked_session_read_denied',read.status===403&&read.body.message==='AUTH_REQUIRED');
    mark('revoked_session_write_denied',write.status===403&&write.body.message==='AUTH_REQUIRED');
    mark('revoked_session_receipt_denied',retry.status===403&&retry.body.message==='AUTH_REQUIRED');
    return {postgrest:true,verified_local_gotrue_token:true,public_schema_only:true,kong_gateway:false,mobile_sdk:false,production_deployed:false};
  }};
}
