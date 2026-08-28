begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(40);

select has_table('private','analysis_v4_configs','v4 config table exists');
select has_table('private','analysis_v4_allowlist','v4 allowlist exists');
select has_table('private','analysis_claim_candidates','raw candidates are isolated');
select has_table('private','analysis_items_v4','canonical v4 items exist');
select has_table('private','analysis_routing_ledger','routing ledger exists');
select has_table('private','analysis_hard_rejection_ledger','hard rejection ledger exists');
select has_table('private','analysis_quality_trace_v4','v4 quality trace exists');
select has_column(
  'private','analysis_quality_trace_v4','updated_at',
  'authoritative provider usage can timestamp the v4 quality trace'
);
select has_table('private','analysis_targeted_runs_v4','v4 targeted checkpoints exist');
select has_table('private','standards_registry','standards registry exists');
select has_table('private','assurance_topics','assurance registry exists');
select is(
  (select prompt_version from private.analysis_v4_configs where is_active),
  'v4-vision-core-v5','active v4 prompt version is pinned'
);
select is(
  (select router_version from private.analysis_v4_configs where is_active),
  'claim-routing-v15','active v4 router version is pinned'
);
select is(
  (select coverage_version from private.analysis_v4_configs where is_active),
  'critical-coverage-v3','active v4 coverage version is pinned'
);
select is(
  (select assurance_version from private.analysis_v4_configs where is_active),
  'assurance-topic-v2','active v4 assurance version is pinned'
);
select is(
  (select config #>> '{compute_profiles,premium,targeted_max_provider_output_tokens}'
   from private.analysis_v4_configs where is_active),
  '4096','premium targeted output budget has response headroom'
);
select is(
  (select config #>> '{compute_profiles,economy,targeted_max_provider_output_tokens}'
   from private.analysis_v4_configs where is_active),
  '3072','economy targeted output budget has bounded response headroom'
);

select has_function(
  'public','resolve_analysis_engine_route_v5',
  array['uuid','uuid','jsonb','jsonb'],
  'isolated route resolver exists'
);
select has_function(
  'public','begin_analysis_engine_run_v4',
  array['uuid','uuid','bigint','integer','uuid','text'],
  'v4 engine run begin RPC exists'
);
select has_function(
  'public','finalize_analysis_result_v4',
  array['uuid','uuid','bigint','integer','uuid','uuid','jsonb'],
  'atomic v4 finalizer exists'
);
select has_function(
  'public','admin_analysis_v4_pilot_report_v1',array['uuid'],
  'service-only pilot report exists'
);
select ok(
  not has_function_privilege(
    'authenticated','public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)','execute'
  ),
  'authenticated clients cannot choose their engine'
);
select ok(
  not has_function_privilege(
    'authenticated','public.finalize_analysis_result_v4(uuid,uuid,bigint,integer,uuid,uuid,jsonb)','execute'
  ),
  'authenticated clients cannot finalize v4'
);
select ok(
  has_function_privilege(
    'service_role','public.finalize_analysis_result_v4(uuid,uuid,bigint,integer,uuid,uuid,jsonb)','execute'
  ),
  'service role can finalize v4'
);

select has_column('public','findings','item_class','public projection has item class');
select has_column('public','findings','is_scored','public projection has score flag');
select col_default_is('public','findings','is_scored','true','v3 findings remain scored by default');
select ok(
  (select is_nullable='YES' from information_schema.columns
   where table_schema='public' and table_name='findings' and column_name='fk_probability'),
  'FK probability is nullable for scoreless records'
);
select ok(
  (select relrowsecurity from pg_class where oid='private.analysis_job_state'::regclass),
  'analysis job state has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid='private.support_request_rate_limits'::regclass),
  'support rate limit state has RLS enabled'
);
select is(
  (select count(distinct sector)::integer
   from private.assurance_topics t cross join lateral unnest(t.sectors) sector),
  15,
  'assurance topics cover every canonical sector'
);

insert into auth.users (id,email,aud,role,created_at,updated_at)
values
 ('00000000-0000-4000-8000-000000004001','v4-owner@example.invalid','authenticated','authenticated',now(),now()),
 ('00000000-0000-4000-8000-000000004002','v4-other@example.invalid','authenticated','authenticated',now(),now());

insert into public.analyses (id,user_id,kind,status,photo_count,plan_at_creation)
values
 ('00000000-0000-4000-8000-000000004101','00000000-0000-4000-8000-000000004001','photo','pending',1,'plus'),
 ('00000000-0000-4000-8000-000000004102','00000000-0000-4000-8000-000000004001','photo','pending',1,'plus'),
 ('00000000-0000-4000-8000-000000004103','00000000-0000-4000-8000-000000004002','photo','pending',1,'plus'),
 ('00000000-0000-4000-8000-000000004104','00000000-0000-4000-8000-000000004001','photo','pending',1,'plus'),
 ('00000000-0000-4000-8000-000000004105','00000000-0000-4000-8000-000000004001','photo','pending',1,'plus');

insert into private.analysis_v4_allowlist(user_id,enabled,note)
values ('00000000-0000-4000-8000-000000004001',true,'pgtap')
on conflict(user_id) do update set enabled=true;

update public.app_feature_flags set value=jsonb_build_object(
  'rollout_mode','user_allowlist','kill_switch',false,
  'required_api_contract',3,'required_capability','safety_claim_v4_scoreless',
  'general_release_approved',false
) where key='analysis_engine_v4';

create temporary table route_inputs as select
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","ai_execution_route":"paid_plan"}'::jsonb compute,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"ios","client_app_build":"test","safety_claim_v4_scoreless":true}'::jsonb compatible,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":2,"client_platform":"ios","client_app_build":"old","safety_claim_v4_scoreless":false}'::jsonb incompatible;

create temporary table owner_v4 as
select public.resolve_analysis_engine_route_v5(
  '00000000-0000-4000-8000-000000004001',
  '00000000-0000-4000-8000-000000004101',compute,compatible
) response from route_inputs;
select is((select response->>'engine_variant' from owner_v4),'vnext-v4',
  'allowlisted compatible owner routes to v4');

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','true'::jsonb,true)
where key='analysis_engine_v4';
select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000004001',
    '00000000-0000-4000-8000-000000004101',compute,incompatible
  )->>'engine_variant' from route_inputs),
  'vnext-v4','pinned v4 route survives later flag/client changes'
);

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','false'::jsonb,true)
where key='analysis_engine_v4';
create temporary table old_client as
select public.resolve_analysis_engine_route_v5(
  '00000000-0000-4000-8000-000000004001',
  '00000000-0000-4000-8000-000000004102',compute,incompatible
) response from route_inputs;
select isnt((select response->>'engine_variant' from old_client),'vnext-v4',
  'old owner build cannot enter v4');
select is((select response->>'v4_fallback_reason' from old_client),'v4_client_incompatible',
  'old build fallback is observable');

create temporary table other_user as
select public.resolve_analysis_engine_route_v5(
  '00000000-0000-4000-8000-000000004002',
  '00000000-0000-4000-8000-000000004103',compute,compatible
) response from route_inputs;
select isnt((select response->>'engine_variant' from other_user),'vnext-v4',
  'capability cannot bypass private allowlist');
select is((select response->>'v4_fallback_reason' from other_user),'v4_user_not_allowlisted',
  'non-allowlisted fallback is observable');

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','true'::jsonb,true)
where key='analysis_engine_v4';
select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000004001',
    '00000000-0000-4000-8000-000000004104',compute,compatible
  )->>'v4_fallback_reason' from route_inputs),
  'v4_kill_switch','kill switch sends new work to the unchanged resolver'
);

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','false'::jsonb,true)
where key='analysis_engine_v4';
update private.analysis_v4_configs set integrity_status='invalid' where is_active;
select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000004001',
    '00000000-0000-4000-8000-000000004105',compute,compatible
  )->>'v4_fallback_reason' from route_inputs),
  'v4_config_missing_or_invalid','invalid config fails safely to v3/legacy'
);

select is(
  public.admin_analysis_v4_pilot_report_v1(
    '00000000-0000-4000-8000-000000000000'
  )->>'state',
  'v4_run_not_found','pilot report fails closed for unknown run'
);

select * from extensions.finish();
rollback;
