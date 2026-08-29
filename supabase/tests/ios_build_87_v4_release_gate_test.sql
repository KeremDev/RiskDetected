begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(12);

select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key='analysis_engine_v4'),
  'build_allowlist',
  'V4 rollout is build-gated for the 2.0.0 review build'
);
select ok(
  (select value->'enabled_ios_builds' ? '87' from public.app_feature_flags where key='analysis_engine_v4'),
  'iOS build 87 is admitted to V4'
);
select is(
  (select value->>'general_release_approved' from public.app_feature_flags where key='analysis_engine_v4'),
  'true',
  'general V4 release is explicitly approved'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'build_allowlist',
  'result hub rollout is build-gated'
);
select ok(
  (select value->'enabled_ios_builds' ? '87' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'iOS build 87 is admitted to result hub'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)',
    'execute'
  ),
  'clients cannot directly resolve engine routes'
);

insert into auth.users (id,email,aud,role,created_at,updated_at)
values ('00000000-0000-4000-8000-000000008701','build87@example.invalid','authenticated','authenticated',now(),now());

insert into public.analyses (id,user_id,kind,status,photo_count,plan_at_creation)
values
 ('00000000-0000-4000-8000-000000008711','00000000-0000-4000-8000-000000008701','photo','pending',1,'free'),
 ('00000000-0000-4000-8000-000000008712','00000000-0000-4000-8000-000000008701','photo','pending',1,'plus'),
 ('00000000-0000-4000-8000-000000008713','00000000-0000-4000-8000-000000008701','photo','pending',1,'pro'),
 ('00000000-0000-4000-8000-000000008714','00000000-0000-4000-8000-000000008701','photo','pending',1,'free'),
 ('00000000-0000-4000-8000-000000008715','00000000-0000-4000-8000-000000008701','photo','pending',1,'free');

create temporary table build87_inputs as select
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","ai_execution_route":"paid_plan"}'::jsonb compute,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"ios","client_app_build":"87","safety_claim_v4_scoreless":true}'::jsonb ios87,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"ios","client_app_build":"86","safety_claim_v4_scoreless":true}'::jsonb ios86,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"android","client_app_build":"87","safety_claim_v4_scoreless":true}'::jsonb android87;

select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008711',compute,ios87
  )->>'engine_variant' from build87_inputs),
  'vnext-v4',
  'Free user on iOS build 87 is pinned to V4 without a user allowlist'
);
select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008712',compute,ios87
  )->>'engine_variant' from build87_inputs),
  'vnext-v4',
  'Plus user on iOS build 87 is pinned to V4'
);
select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008713',compute,ios87
  )->>'engine_variant' from build87_inputs),
  'vnext-v4',
  'Pro user on iOS build 87 is pinned to V4'
);
select isnt(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008714',compute,ios86
  )->>'engine_variant' from build87_inputs),
  'vnext-v4',
  'older iOS builds keep their existing resolver behaviour'
);
select isnt(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008715',compute,android87
  )->>'engine_variant' from build87_inputs),
  'vnext-v4',
  'Android is not changed by the iOS build-87 gate'
);

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','true'::jsonb,true)
where key='analysis_engine_v4';

insert into public.analyses (id,user_id,kind,status,photo_count,plan_at_creation)
values ('00000000-0000-4000-8000-000000008716','00000000-0000-4000-8000-000000008701','photo','pending',1,'free');

select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008701',
    '00000000-0000-4000-8000-000000008716',compute,ios87
  )->>'state' from build87_inputs),
  'v4_required_unavailable',
  'build 87 fails closed instead of falling back when V4 is unavailable'
);

select * from extensions.finish();
rollback;
