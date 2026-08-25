-- Activation follows the expand migration and Edge Function deployment. The
-- route remains doubly gated by this account allowlist and client capability.
update private.analysis_v4_configs set is_active=false,updated_at=now()
where is_active;

insert into private.analysis_v4_configs (
  engine_version,provider_contract_version,domain_schema_version,
  prompt_version,prompt_sha256,router_version,coverage_version,
  assurance_version,standards_version,quality_trace_version,
  report_projection_version,client_api_contract,config,integrity_status,is_active
)
select
  'vnext-v4','visual-claim-candidate-v1','safety-claim-v4.0',
  'v4-vision-core-v1',
  'f448cc63f18557d9e7df77afc903777b61c5f62584faedb6b918cae12860d7d6',
  'claim-routing-v1','critical-coverage-v1','assurance-topic-v1',
  'standards-registry-v1','quality-trace-v4','compatibility-report-v4',3,
  coalesce(c.config,'{}'::jsonb) || jsonb_build_object(
    'engine_version','vnext-v4',
    'provider_contract_version','visual-claim-candidate-v1',
    'domain_schema_version','safety-claim-v4.0',
    'prompt_version','v4-vision-core-v1',
    'prompt_sha256','f448cc63f18557d9e7df77afc903777b61c5f62584faedb6b918cae12860d7d6',
    'router_version','claim-routing-v1',
    'coverage_version','critical-coverage-v1',
    'assurance_version','assurance-topic-v1',
    'standards_version','standards-registry-v1',
    'quality_trace_version','quality-trace-v4',
    'report_projection_version','compatibility-report-v4',
    'primary_provider','gemini',
    'primary_model',coalesce(c.config->>'primary_model','gemini-2.5-flash'),
    'max_visible_items',8,
    'targeted_limit_premium',2,
    'targeted_limit_economy',1
  ),
  'valid',true
from lateral (
  select config from private.analysis_engine_configs
  where is_active order by updated_at desc limit 1
) c;

do $$
begin
  if not exists (select 1 from private.analysis_v4_configs where is_active) then
    raise exception 'v4 activation requires an active v3 compute configuration';
  end if;
end $$;

insert into private.analysis_v4_allowlist (user_id,enabled,note)
select id,true,'Routing-first v4 isolated owner pilot'
from public.profiles
where id='f3be34f9-6707-46d3-b827-a7dbcdfe1f66'::uuid
on conflict (user_id) do update set
  enabled=true,note=excluded.note,updated_at=now();

update public.app_feature_flags
set value=jsonb_build_object(
  'rollout_mode','user_allowlist',
  'kill_switch',false,
  'required_api_contract',3,
  'required_capability','safety_claim_v4_scoreless',
  'general_release_approved',false,
  'activated_at',now()
)
where key='analysis_engine_v4';
