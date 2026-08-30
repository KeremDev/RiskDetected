begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(17);

select ok(
  position(
    'training_recommendations' in (
      select pg_get_constraintdef(oid)
      from pg_constraint
      where conname = 'paywall_events_result_section_check'
    )
  ) > 0,
  'paywall attribution accepts the training result section'
);

select ok(
  position(
    'training_card' in (
      select pg_get_constraintdef(oid)
      from pg_constraint
      where conname = 'analysis_item_feedback_target_kind_check'
    )
  ) > 0,
  'result feedback accepts training-card targets'
);

select ok(
  position(
    'training_recommendations' in (
      select pg_get_constraintdef(oid)
      from pg_constraint
      where conname = 'analysis_item_feedback_section_check'
    )
  ) > 0,
  'result feedback accepts the training section'
);

select ok(
  position(
    'training_card' in (
      select pg_get_constraintdef(oid)
      from pg_constraint
      where conname = 'analysis_item_feedback_target_reference_check'
    )
  ) > 0,
  'training feedback does not require a finding or notebook UUID'
);

select ok(
  (select value->'enabled_android_builds' ? '7' from public.app_feature_flags where key='analysis_engine_v4'),
  'Android versionCode 7 is admitted to V4'
);
select ok(
  (select value->'enabled_android_builds' ? '7' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'Android versionCode 7 is admitted to result hub'
);
select ok(
  (select value->'enabled_ios_builds' ? '87' from public.app_feature_flags where key='analysis_engine_v4'),
  'V4 keeps iOS build 87 admitted'
);
select ok(
  (select value->'enabled_ios_builds' ? '88' from public.app_feature_flags where key='analysis_engine_v4'),
  'V4 keeps iOS build 88 admitted'
);
select ok(
  (select value->'enabled_ios_builds' ? '87' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'result hub keeps iOS build 87 admitted'
);
select ok(
  (select value->'enabled_ios_builds' ? '88' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'result hub keeps iOS build 88 admitted'
);
select is(
  (select (value->>'latest_build')::int from public.app_feature_flags where key='android_release_policy'),
  6,
  'closed-test gate does not advertise build 7 before Play upload'
);
select ok(
  (select not (value->>'hard_update_enabled')::boolean and not (value->>'soft_update_enabled')::boolean
   from public.app_feature_flags where key='android_release_policy'),
  'closed-test gate does not enable Android update prompts'
);

insert into auth.users (id,email,aud,role,created_at,updated_at)
values ('00000000-0000-4000-8000-000000000701','android7@example.invalid','authenticated','authenticated',now(),now());

insert into public.analyses (id,user_id,kind,status,photo_count,plan_at_creation)
values
 ('00000000-0000-4000-8000-000000000711','00000000-0000-4000-8000-000000000701','photo','pending',1,'free'),
 ('00000000-0000-4000-8000-000000000712','00000000-0000-4000-8000-000000000701','photo','pending',1,'free'),
 ('00000000-0000-4000-8000-000000000713','00000000-0000-4000-8000-000000000701','photo','pending',1,'free');

select is(
  public.result_hub_upsert_feedback(
    '00000000-0000-4000-8000-000000000701',
    '00000000-0000-4000-8000-000000000711',
    'training_card',
    'training-00000000-0000-4000-8000-000000000711-fire-safety',
    null,
    null,
    'training_recommendations',
    'training',
    -1,
    'other',
    'Kapalı test geri bildirimi',
    '{}'::jsonb,
    '{}'::jsonb
  )->>'reaction',
  'dislike',
  'training-card feedback is persisted by the shared result-hub RPC'
);

create temporary table android7_inputs as select
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","ai_execution_route":"free_plan"}'::jsonb compute,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"android","client_app_build":"7","safety_claim_v4_scoreless":true}'::jsonb android7,
  '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"android","client_app_build":"6","safety_claim_v4_scoreless":true}'::jsonb android6;

select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000000701',
    '00000000-0000-4000-8000-000000000711',compute,android7
  )->>'engine_variant' from android7_inputs),
  'vnext-v4',
  'Android build 7 resolves to V4'
);
select isnt(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000000701',
    '00000000-0000-4000-8000-000000000712',compute,android6
  )->>'engine_variant' from android7_inputs),
  'vnext-v4',
  'Android build 6 keeps its existing engine route'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'build_allowlist',
  'result hub remains build-allowlisted'
);

update public.app_feature_flags
set value=jsonb_set(value,'{kill_switch}','true'::jsonb,true)
where key='analysis_engine_v4';

select is(
  (select public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000000701',
    '00000000-0000-4000-8000-000000000713',compute,android7
  )->>'v4_fallback_reason' from android7_inputs),
  'v4_kill_switch',
  'Android build 7 leaves V4 through the observable safe fallback when its kill switch is active'
);

select * from extensions.finish();
rollback;
