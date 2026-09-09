// Explicit production canary: synthetic image and a newly created QA-only user.
// Credentials stay in memory. Retains QA rows for server-side trace inspection.
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
const project = 'ppcrzemgiztzcgddbins';
if (process.env.RD_CONFIRM_HOSTED_CANARY !== project) throw new Error('Production opt-in required');
const cohort = process.env.RD_CANARY_COHORT ?? 'repeat_free';
if (!['repeat_free', 'cancelled_plus_trial'].includes(cohort)) throw new Error('Unknown canary cohort');
const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '-o', 'json'], {encoding:'utf8'}));
const service = keys.find(k => k.name === 'service_role')?.api_key;
const anon = keys.find(k => k.name === 'anon')?.api_key;
if (!service || !anon) throw new Error('Server credentials unavailable');
const url = `https://${project}.supabase.co`;
async function request(endpoint, {token=service, method='GET', json, bytes, headers={}}={}) {
  const r = await fetch(url+endpoint, {method, headers:{apikey:anon, Authorization:`Bearer ${token}`, ...(json ? {'Content-Type':'application/json'} : {}), ...headers}, body: json ? JSON.stringify(json) : bytes});
  const text = await r.text();
  let data; try {data=JSON.parse(text);} catch {data=null;}
  if (!r.ok) throw new Error(`${endpoint}: ${r.status} ${JSON.stringify(data).slice(0,700)}`);
  return data;
}
const stamp = crypto.randomUUID();
const email = `rd-free-canary-${stamp}@example.invalid`;
const password = crypto.randomUUID()+crypto.randomUUID();
const user = await request('/auth/v1/admin/users', {method:'POST', json:{email,password,email_confirm:true,user_metadata:{full_name:'QA Synthetic Free Repeat',qa_canary:true,app_language:'tr',preferred_content_locale:'tr-TR',work_jurisdiction_country:'TR'}}});
const userID=user.id;
console.log(JSON.stringify({phase:'user_created',user_id:userID}));
// These are synthetic eligibility fixtures, not actual purchases or prior calls.
const priorID=cohort === 'repeat_free' ? crypto.randomUUID() : null;
if (priorID) {
await request('/rest/v1/analyses',{method:'POST',json:{id:priorID,user_id:userID,kind:'photo',canvas:'general',title:'QA synthetic prior-completed eligibility fixture',status:'completed',created_at:new Date(Date.now()-86400000).toISOString()}});
} else {
  const start = new Date(Date.now()-86400000).toISOString();
  const end = new Date(Date.parse(start)+7*86400000).toISOString();
  await request('/rest/v1/user_subscriptions?on_conflict=user_id',{method:'POST',headers:{Prefer:'resolution=merge-duplicates'},json:{user_id:userID,tier:'plus',status:'active',source:'qa_synthetic_fixture',environment:'SANDBOX',store:'APP_STORE',product_id:'riskdetected_plus_yearly',trial_product_id:'riskdetected_plus_yearly',period_type:'TRIAL',will_renew:false,trial_started_at:start,trial_ends_at:end,current_period_ends_at:end,last_event_id:`QA-FIXTURE-${stamp}`}});
  await request(`/rest/v1/profiles?id=eq.${userID}`,{method:'PATCH',json:{tier:'plus',full_name:'QA Cancelled PLUS Trial'}});
}
const auth=await request('/auth/v1/token?grant_type=password',{method:'POST',json:{email,password}});
const token=auth.access_token;
if (!token) throw new Error('QA authentication failed');
const analysisID=crypto.randomUUID();
const storagePath=`${userID}/${analysisID}/synthetic.png`;
const bytes=await readFile('/tmp/rd-free-synthetic-scene.png');
await request('/rest/v1/analyses',{method:'POST',token,json:{id:analysisID,user_id:userID,kind:'photo',canvas:'general',title:`QA hosted ${cohort} synthetic canary`,status:'pending',analysis_sector:'general',analysis_sector_source:'user_selected',analysis_sector_prompt_version:'active-sector-v1',primary_method:'fine_kinney'}});
await request(`/storage/v1/object/photos/${storagePath}`,{method:'POST',token,bytes,headers:{'Content-Type':'image/png'}});
await request('/rest/v1/photos',{method:'POST',token,json:{analysis_id:analysisID,user_id:userID,storage_path:storagePath,width:800,height:600,size_bytes:bytes.length,byte_size:bytes.length,mime_type:'image/png',sequence_index:1,client_photo_id:crypto.randomUUID(),is_primary:true,upload_payload_version:'photo-batch-storage-v1'}});
console.log(JSON.stringify({phase:'prepared',user_id:userID,analysis_id:analysisID,prior_fixture_id:priorID,storage_path:storagePath}));
await request('/functions/v1/analyze',{method:'POST',token,json:{analysis_id:analysisID,canvas:'general',canvases:['general'],analysis_mode:'standard',request_id:crypto.randomUUID(),support_id:`QA-FREE-${stamp}`,analysis_sector:'general',analysis_sector_source:'user_selected',analysis_sector_prompt_version:'active-sector-v1',app_language:'tr',output_language:'tr',output_locale:'tr-TR',work_jurisdiction_country:'TR',safety_profile_id:'tr-tr-current-v1',safety_profile_version:1,method:'fine_kinney',photo_paths:[storagePath],photo_base64_parts:[],client_app_version:'1.3.1',client_app_build:'88',client_platform:'ios',api_contract_version:3,client_capabilities:{multi_photo_analysis:true,multi_photo_coverage_v2:true,editable_findings:true,report_snapshot_v2:true,safety_claim_v4_scoreless:true}}});
console.log(JSON.stringify({phase:'queued',analysis_id:analysisID}));
const deadline=Date.now()+240000;
while(Date.now()<deadline){
  const [row]=await request(`/rest/v1/analyses?id=eq.${analysisID}&select=id,status,failure_code,finding_count`);
  if(['completed','failed'].includes(row?.status)) {
    console.log(JSON.stringify({phase:'terminal',...row,user_id:userID}));
    if(row.status!=='completed') process.exitCode=1;
    break;
  }
  await new Promise(r=>setTimeout(r,3000));
  if(Date.now()>=deadline) throw new Error(`Canary timeout: ${analysisID}`);
}
