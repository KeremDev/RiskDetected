#!/usr/bin/env node
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {chmodSync,readFileSync,writeFileSync} from 'node:fs';

const PROJECT_REF='qlymhrrlhklcudveknih';
const PRODUCTION_REF='ppcrzemgiztzcgddbins';
const URL=`https://${PROJECT_REF}.supabase.co`;
const CREDENTIALS='/tmp/isg-staging-qa-credentials.json';
const ACCESS_TOKEN=`${process.env.HOME}/.supabase/access-token`;

if(process.argv.includes(PRODUCTION_REF)||process.env.SUPABASE_PROJECT_REF===PRODUCTION_REF){
  throw new Error('PRODUCTION_TARGET_REFUSED');
}

const keys=JSON.parse(execFileSync('supabase',['projects','api-keys','--project-ref',PROJECT_REF,'-o','json'],
  {encoding:'utf8'}));
const anon=keys.find(row=>row.name==='anon')?.api_key;
const service=keys.find(row=>row.name==='service_role')?.api_key;
if(!anon||!service) throw new Error('STAGING_KEYS_UNAVAILABLE');
const managementToken=readFileSync(ACCESS_TOKEN,'utf8').trim();

const quote=value=>`'${String(value).replaceAll("'","''")}'`;
async function management(query){
  const response=await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`,{
    method:'POST',headers:{authorization:`Bearer ${managementToken}`,'content-type':'application/json'},
    body:JSON.stringify({query}),signal:AbortSignal.timeout(30_000),
  });
  const body=await response.json().catch(()=>null);
  if(!response.ok) throw new Error(`MANAGEMENT_SQL_${response.status}_${JSON.stringify(body)?.slice(0,300)}`);
  return body;
}
async function request(path,{method='GET',key=anon,bearer=key,body,headers={}}={}){
  const response=await fetch(`${URL}${path}`,{method,headers:{apikey:key,authorization:`Bearer ${bearer}`,
    ...(body instanceof Uint8Array?{}:{'content-type':'application/json'}),...headers},
    body:body===undefined?undefined:body instanceof Uint8Array?body:JSON.stringify(body),signal:AbortSignal.timeout(150_000)});
  const type=response.headers.get('content-type')??'';
  const payload=type.includes('json')?await response.json().catch(()=>null):new Uint8Array(await response.arrayBuffer());
  if(!response.ok) throw new Error(`HTTP_${response.status}_${path}_${JSON.stringify(payload)?.slice(0,500)}`);
  return payload;
}
const rpc=(name,args,access)=>request(`/rest/v1/rpc/${name}`,{method:'POST',bearer:access,body:args});
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const sleep=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
async function poll(label,read,accepted,attempts=24){
  let value;
  for(let attempt=0;attempt<attempts;attempt++){
    value=await read();
    if(accepted(value)) return value;
    await sleep(2500);
  }
  throw new Error(`${label}_TIMEOUT_${JSON.stringify(value)}`);
}

const report={project_ref:PROJECT_REF,production_touched:false,started_at:new Date().toISOString(),checks:{}};

// Staging-only switches. The production defaults remain dark and this script
// refuses the production project reference above.
const rollout=await management(`
  update private_isg.workspace_rollout set read_enabled=true,write_enabled=true,updated_at=clock_timestamp()
    where feature<>'workspace_admin';
  update private_isg.workspace_domain_rollout set read_enabled=true,write_enabled=true,updated_at=clock_timestamp();
  select (select count(*) from private_isg.workspace_rollout where read_enabled and write_enabled) as features,
    (select count(*) from private_isg.workspace_domain_rollout where read_enabled and write_enabled) as domains,
    (select count(*) from public.companies) as legacy_companies;`);
report.checks.staging_rollout=rollout.at(-1);

// The QA APK is versionCode 14. Keep staging closed to arbitrary builds, but
// admit that exact candidate to every Android runtime gate required by the
// end-to-end product smoke. Refuse to widen a killed or unexpected gate.
const androidRuntime=await management(`
  do $android_staging_qa$
  declare
    v_key text;
    v_value jsonb;
    v_keys constant text[] := array[
      'android_client_enabled','android_auth_enabled','android_analysis_submit_enabled',
      'android_payments_enabled','android_notifications_enabled','android_pdf_reports_enabled'
    ];
  begin
    foreach v_key in array v_keys loop
      select value into v_value from public.app_feature_flags where key=v_key for update;
      if v_value is null
        or coalesce((v_value->>'kill_switch')::boolean,true)
        or coalesce(v_value->>'rollout_mode','off') not in
          ('version_allowlist','build_allowlist','allowlist')
      then
        raise exception 'refusing Android QA rollout for %',v_key;
      end if;
      update public.app_feature_flags
      set value=jsonb_set(
        v_value,'{enabled_android_version_codes}',
        (select jsonb_agg(code order by code)
           from (select distinct value::integer as code
                   from jsonb_array_elements_text(
                     coalesce(v_value->'enabled_android_version_codes','[]'::jsonb)||'[14]'::jsonb
                   )) allowed),true
      ),updated_at=clock_timestamp()
      where key=v_key;
    end loop;
  end;
  $android_staging_qa$;
  select count(*) filter(where value->'enabled_android_version_codes' @> '[14]'::jsonb) as admitted,
    count(*) as total
  from public.app_feature_flags
  where key in ('android_client_enabled','android_auth_enabled','android_analysis_submit_enabled',
    'android_payments_enabled','android_notifications_enabled','android_pdf_reports_enabled');`);
report.checks.android_runtime=androidRuntime.at(-1);
if(Number(report.checks.android_runtime?.admitted)!==6||Number(report.checks.android_runtime?.total)!==6){
  throw new Error('ANDROID_QA_RUNTIME_GATES_NOT_READY');
}

const suffix=`${Date.now()}-${randomBytes(3).toString('hex')}`;
const email=`osgb-staging-qa+${suffix}@riskdetected.invalid`;
const password=`Qa!${randomBytes(18).toString('base64url')}`;
const user=await request('/auth/v1/admin/users',{method:'POST',key:service,bearer:service,
  body:{email,password,email_confirm:true,user_metadata:{full_name:'OSGB Staging QA'}}});
const session=await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
const access=session.access_token;
if(!user.id||!access) throw new Error('QA_AUTH_FAILED');
report.checks.auth={user_id:user.id,email,session:true};

const workspace=await rpc('isg_osgb_workspace_create_v1',{
  p_mutation:randomUUID(),p_name:`OSGB Staging Kabul ${suffix}`,p_timezone:'Europe/Istanbul',
},access);
const workspaceId=workspace.workspace_id;
if(!workspaceId) throw new Error('WORKSPACE_CREATE_FAILED');
await management(`
  update private_isg.workspaces set status='admin_trial',updated_at=clock_timestamp() where id=${quote(workspaceId)}::uuid;
  insert into private_isg.workspace_ai_pricing(feature,model_code,pricing_version,reserve_units,max_settle_units,active)
    values('staging_acceptance','gemini-2.5-flash','staging-v1',20,20,true)
    on conflict(feature,model_code,pricing_version) do update set reserve_units=excluded.reserve_units,
      max_settle_units=excluded.max_settle_units,active=true;
  select private_isg.workspace_credit_grant(gen_random_uuid(),${quote(workspaceId)}::uuid,'admin_support',
    ${quote(`staging-acceptance-${suffix}`)},500,${quote(user.id)}::uuid) as grant;`);

const company=await rpc('isg_workspace_company_create_v1',{
  p_mutation:randomUUID(),p_workspace:workspaceId,p_name:`Staging Kabul Firması ${suffix}`,p_hazard:'high',
},access);
const companyId=company.company_id;
if(!companyId) throw new Error('COMPANY_CREATE_FAILED');
report.checks.tenant={workspace_id:workspaceId,company_id:companyId,status:'admin_trial'};
writeFileSync(CREDENTIALS,JSON.stringify({project_ref:PROJECT_REF,url:URL,email,password,user_id:user.id,
  workspace_id:workspaceId,company_id:companyId,created_at:report.started_at},null,2)+'\n');
chmodSync(CREDENTIALS,0o600);

const list=await rpc('isg_workspace_list_v1',{},access);
const companies=await rpc('isg_workspace_company_list_v1',{p_workspace:workspaceId,p_after:null,p_limit:25},access);
const dashboard=await rpc('isg_workspace_dashboard_v1',{p_workspace:workspaceId,p_company:companyId},access);
if(!list.workspaces?.some(row=>row.workspace_id===workspaceId)||!companies.rows?.some(row=>row.company_id===companyId)||dashboard.measured!==true){
  throw new Error('TENANT_READBACK_FAILED');
}
report.checks.tenant_readback={workspace_list:true,company_list:true,dashboard:true};

const domainCalls=[
  ['personnel','isg_workspace_personnel_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'employees',p_query:'',p_archived:false,p_after:null,p_id:null,p_limit:25}],
  ['training','isg_workspace_training_read_v1',{p_workspace:workspaceId,p_company:companyId,p_id:null,p_after:null,p_limit:25}],
  ['risk','isg_workspace_risk_read_v1',{p_workspace:workspaceId,p_company:companyId,p_id:null,p_after:null,p_limit:25}],
  ['nonconformity','isg_workspace_nonconformity_read_v1',{p_workspace:workspaceId,p_company:companyId,p_id:null,p_state:null,p_after:null,p_limit:25}],
  ['checklist','isg_workspace_checklist_read_v1',{p_workspace:workspaceId,p_company:companyId,p_id:null,p_after:null,p_limit:25}],
  ['safety','isg_workspace_safety_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'plans',p_id:null,p_after:null,p_limit:25}],
  ['equipment','isg_workspace_equipment_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'inventory',p_id:null,p_query:'',p_state:null,p_type:null,p_after:null,p_limit:25}],
  ['operations','isg_workspace_operations_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'katip_contract',p_id:null,p_after:null,p_limit:25}],
  ['files','isg_workspace_file_read_v1',{p_workspace:workspaceId,p_company:companyId,p_id:null,p_query:'',p_category:null,p_include_archived:false,p_after:null,p_limit:25}],
  ['personnel_advanced','isg_workspace_personnel_advanced_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'job_roles',p_after:null,p_limit:25}],
  ['training_advanced','isg_workspace_training_advanced_read_v1',{p_workspace:workspaceId,p_company:companyId,p_kind:'curricula',p_after:null,p_limit:25}],
];
for(const [label,name,args] of domainCalls){
  const value=await rpc(name,args,access);
  if(value.schema_version!==1||value.workspace_id!==workspaceId||value.company_id!==companyId||!Array.isArray(value.rows)){
    throw new Error(`DOMAIN_${label.toUpperCase()}_INVALID`);
  }
  report.checks[`domain_${label}`]=true;
}

// Real Storage transport: authenticated upload to the server-selected private
// path, byte inspection/finalization, short-lived token download and hash match.
const fileBytes=new TextEncoder().encode('id,baslik,durum\n1,Staging kabul,Aktif\n');
const fileHash=sha(fileBytes);
const opened=await rpc('isg_workspace_upload_open_v1',{
  p_workspace:workspaceId,p_company:companyId,p_idempotency:randomUUID(),p_request_hash:`\\x${fileHash}`,
  p_purpose:'staging_acceptance',p_media_type:'text/csv',p_extension:'csv',p_expected_bytes:fileBytes.byteLength,
  p_expires_at:new Date(Date.now()+15*60_000).toISOString(),
},access);
const encodedPath=opened.object_path.split('/').map(encodeURIComponent).join('/');
await request(`/storage/v1/object/${encodeURIComponent(opened.bucket)}/${encodedPath}`,{method:'POST',bearer:access,
  body:fileBytes,headers:{'content-type':'text/csv','x-upsert':'false'}});
const finalized=await request('/functions/v1/isg-workspace-file-finalize',{method:'POST',bearer:access,
  body:{upload_token:opened.upload_token}});
const download=await rpc('isg_workspace_download_open_v1',{p_workspace:workspaceId,p_asset:finalized.asset_id,
  p_purpose:'staging_acceptance',p_expires_at:new Date(Date.now()+3*60_000).toISOString()},access);
const downloaded=await request('/functions/v1/isg-workspace-file-download',{method:'POST',bearer:access,
  body:{download_token:download.download_token}});
if(!(downloaded instanceof Uint8Array)||sha(downloaded)!==fileHash) throw new Error('STORAGE_ROUNDTRIP_HASH_MISMATCH');
report.checks.storage={upload:true,inspection:true,download:true,asset_id:finalized.asset_id,sha256_match:true};

// Actual Gemini call through the deployed queue worker.
const scenario='Atölyede koruyucusu sökülmüş taşlama makinesi kullanılıyor; çalışan gözlük takmıyor. Bulguları, uzman görüşünü ve eğitim önerisini üret.';
const ai=await rpc('isg_workspace_ai_submit_v1',{p_workspace:workspaceId,p_company:companyId,
  p_feature:'staging_acceptance',p_model:'gemini-2.5-flash',p_pricing_version:'staging-v1',
  p_idempotency:randomUUID(),p_request_hash:`\\x${sha(Buffer.from(scenario))}`,
  p_source_kind:'record_set',p_source_reference:scenario,p_source_version:1},access);
const secretRows=await management("select decrypted_secret from vault.decrypted_secrets where name='isg_workspace_jobs_secret' limit 1");
const workerSecret=secretRows?.[0]?.decrypted_secret;
if(!workerSecret) throw new Error('WORKER_SECRET_NOT_IN_VAULT');
const worker=await fetch(`${URL}/functions/v1/process-isg-workspace-jobs`,{method:'POST',
  headers:{'content-type':'application/json','x-isg-worker-secret':workerSecret},body:JSON.stringify({kinds:['ai'],limit:2}),
  signal:AbortSignal.timeout(150_000)}).then(async response=>({ok:response.ok,status:response.status,body:await response.json().catch(()=>null)}));
if(!worker.ok) throw new Error(`AI_WORKER_${worker.status}_${JSON.stringify(worker.body)}`);
const completedAi=await poll('AI_JOB',()=>rpc('isg_workspace_ai_get_v1',{p_workspace:workspaceId,p_job:ai.job_id},access),
  value=>['succeeded','failed','reconcile'].includes(value.status),12);
if(completedAi.status!=='succeeded') throw new Error(`REAL_PROVIDER_${completedAi.status}_${completedAi.error_code}`);
report.checks.gemini={real_call:true,status:'succeeded',job_id:ai.job_id};

const analyses=await rpc('isg_workspace_analysis_list_v1',{p_workspace:workspaceId,p_company:companyId,p_offset:0,p_limit:10},access);
const analysisId=analyses.rows?.[0]?.id;
if(!analysisId) throw new Error('ANALYSIS_COMMIT_MISSING');
const exportJobs=[];
for(const format of ['pdf','xlsx']){
  const created=await rpc('isg_workspace_export_create_v1',{p_mutation:randomUUID(),p_workspace:workspaceId,
    p_company:companyId,p_analysis:analysisId,p_format:format,p_selection:{}},access);
  exportJobs.push({format,id:created.row?.id});
}
const exportWorker=await fetch(`${URL}/functions/v1/process-isg-workspace-jobs`,{method:'POST',
  headers:{'content-type':'application/json','x-isg-worker-secret':workerSecret},body:JSON.stringify({kinds:['export'],limit:5}),
  signal:AbortSignal.timeout(150_000)}).then(async response=>({ok:response.ok,status:response.status,body:await response.json().catch(()=>null)}));
if(!exportWorker.ok) throw new Error(`EXPORT_WORKER_${exportWorker.status}_${JSON.stringify(exportWorker.body)}`);
for(const item of exportJobs){
  const value=await poll(`EXPORT_${item.format}`,()=>rpc('isg_workspace_export_get_v1',{
    p_workspace:workspaceId,p_company:companyId,p_job:item.id},access),value=>['succeeded','failed'].includes(value.row?.status),12);
  if(value.row?.status!=='succeeded'||!value.row.output_asset_id) throw new Error(`EXPORT_${item.format}_FAILED`);
  report.checks[`export_${item.format}`]={status:'succeeded',asset_id:value.row.output_asset_id};
}

const finalSql=await management(`
  select (select max(version) from supabase_migrations.schema_migrations) as max_migration,
    (select count(*) from private_isg.workspaces where id=${quote(workspaceId)}::uuid and kind='osgb' and status='admin_trial') as qa_workspace,
    (select count(*) from private_isg.workspace_companies where workspace_id=${quote(workspaceId)}::uuid and id=${quote(companyId)}::uuid) as qa_company,
    (select count(*) from private_isg.workspace_file_assets where workspace_id=${quote(workspaceId)}::uuid and lifecycle='active') as active_assets,
    (select count(*) from private_isg.workspace_ai_jobs where workspace_id=${quote(workspaceId)}::uuid and status='succeeded') as ai_succeeded,
    (select count(*) from private_isg.workspace_export_jobs where workspace_id=${quote(workspaceId)}::uuid and status='succeeded') as exports_succeeded,
    (select count(*) from cron.job where jobname='isg-workspace-jobs-staging') as cron_jobs,
    (select count(*) from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='isg-workspace-jobs-staging' and d.status='succeeded') as cron_successes;`);
report.checks.database=finalSql.at(-1);
report.completed_at=new Date().toISOString();
report.ok=true;
writeFileSync('/tmp/isg-staging-acceptance-report.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,credentials_path:CREDENTIALS},null,2));
