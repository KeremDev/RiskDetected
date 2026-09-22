#!/usr/bin/env node

import {readFileSync} from 'node:fs';

const PROJECT_REF = 'qlymhrrlhklcudveknih';
const EMAIL = process.argv[2] ?? 'kayalar.kerem21@gmail.com';
const ACCESS_TOKEN_PATH = '/Users/keremkayalar/.supabase/access-token';
const accessToken = readFileSync(ACCESS_TOKEN_PATH, 'utf8').trim();

const quote = value => `'${String(value).replaceAll("'", "''")}'`;

async function management(query) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: {authorization: `Bearer ${accessToken}`, 'content-type': 'application/json'},
    body: JSON.stringify({query}),
    signal: AbortSignal.timeout(120_000),
  });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`MANAGEMENT_SQL_${response.status}_${JSON.stringify(body)?.slice(0, 800)}`);
  return body;
}

const probes = [
  ['workspace', `select to_jsonb(public.isg_workspace_availability_v1(null))`],
  ['company_workspace', `select to_jsonb(public.isg_workspace_availability_v1((select id from public.companies where user_id=auth.uid() order by created_at limit 1)))`],
  ['analyses', `select jsonb_build_object('completed',count(*)) from public.analyses where status='completed'`],
  ['overview', `select to_jsonb(public.isg_pilot_overview_v2(null))`],
  ['appointments', `select to_jsonb(public.isg_appointments_read_v1(null,'list','',null,null,null,null,10,0))`],
  ['checklists', `select to_jsonb(public.isg_checklists_read_v1(null,'list','',null,null,null,null,10,0))`],
  ['directory', `select to_jsonb(public.isg_directory_read_v1((select id from public.companies where user_id=auth.uid() order by created_at limit 1),'workplaces',null,null,false))`],
  ['documents', `select to_jsonb(public.isg_document_portfolio_v1('',null,null,null,10,0))`],
  ['drills', `select to_jsonb(public.isg_drills_read_v1(null,'list','',null,null,null,10,0))`],
  ['emergency_plans', `select to_jsonb(public.isg_emergency_plans_read_v1(null,'list','',null,null,null,10,0))`],
  ['equipment', `select to_jsonb(public.isg_equipment_checks_read_v1(null,'list','',null,null,null,null,10,0))`],
  ['nonconformities', `select to_jsonb(public.isg_nonconformity_read_v1((select id from public.companies where user_id=auth.uid() order by created_at limit 1),'list','',null,null,null))`],
  ['personnel', `select to_jsonb(public.isg_personnel_read_v1((select id from public.companies where user_id=auth.uid() order by created_at limit 1),'employees','',false,null,null))`],
  ['file_library', `select to_jsonb(public.isg_pilot_file_library_read_v2(null,'list','',null,null,null,10,0))`],
  ['notices', `select to_jsonb(public.isg_pilot_notice_feed_v1(null,'active',50))`],
  ['training', `select to_jsonb(public.isg_pilot_training_sessions_v2(null,null))`],
  ['ppe', `select to_jsonb(public.isg_ppe_read_v1(null,'list','',null,null,null,10,0))`],
  ['risk', `select to_jsonb(public.isg_risk_versions_read_v1(null,'list','',null,null,null,10,0))`],
  ['statistics', `select to_jsonb(public.isg_statistics_v1(null,6))`],
  ['annual_plans', `select to_jsonb(public.isg_pilot_process_read_v1('annual_work_plan',null,null,null,'',0))`],
  ['boards', `select to_jsonb(public.isg_pilot_process_read_v1('board',null,null,null,'',0))`],
  ['visits', `select to_jsonb(public.isg_pilot_process_read_v1('site_visit',null,null,null,'',0))`],
  ['work_permits', `select to_jsonb(public.isg_pilot_process_read_v1('work_permit',null,null,null,'',0))`],
  ['contractors', `select to_jsonb(public.isg_pilot_process_read_v1('contractor',null,null,null,'',0))`],
  ['katip', `select to_jsonb(public.isg_pilot_process_read_v1('katip_contract',null,null,null,'',0))`],
];

const values = probes.map(([name, sql]) => `(${quote(name)},${quote(sql)})`).join(',\n');
const rows = await management(`
  begin;
  create or replace function pg_temp.isg_probe(p_name text,p_sql text) returns jsonb
  language plpgsql as $$
  declare value jsonb;
  begin
    execute p_sql into value;
    return jsonb_build_object('name',p_name,'ok',true,'value',value);
  exception when others then
    return jsonb_build_object('name',p_name,'ok',false,'sqlstate',sqlstate,'error',sqlerrm);
  end $$;
  select set_config('request.jwt.claims',jsonb_build_object(
    'sub',u.id,'role','authenticated','session_id',s.id,'exp',extract(epoch from clock_timestamp()+interval '10 minutes')::bigint
  )::text,true)
  from auth.users u
  join lateral (select id from auth.sessions where user_id=u.id order by created_at desc limit 1) s on true
  where lower(u.email)=lower(${quote(EMAIL)});
  set local role authenticated;
  select pg_temp.isg_probe(name,statement) result
  from (values ${values}) checks(name,statement);
  rollback;`);

const results = rows.map(row => row.result);
const failed = results.filter(result => !result.ok);
const companyWorkspace = results.find(result => result.name === 'company_workspace');
if (companyWorkspace?.value?.can_read !== true || companyWorkspace?.value?.can_write !== true) {
  failed.push({name: 'company_workspace_authority', ok: false, error: 'READ_WRITE_CAPABILITY_REQUIRED'});
}
const analyses = results.find(result => result.name === 'analyses');
if (!Number.isInteger(analyses?.value?.completed) || analyses.value.completed < 1) {
  failed.push({name: 'analysis_visibility', ok: false, error: 'COMPLETED_ANALYSES_NOT_VISIBLE'});
}
console.log(JSON.stringify({email: EMAIL, passed: results.length - failed.length,
  failed: failed.length, failures: failed, results}, null, 2));
if (failed.length) process.exitCode = 1;
