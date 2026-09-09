begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(5);

select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9','10','11','12','13','14']
     from public.app_feature_flags where key = 'analysis_engine_v4'),
  'Android versionCode 14 joins the V4 allowlist without dropping earlier builds'
);
select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9','10','11','12','13','14']
     from public.app_feature_flags where key = 'analysis_result_hub_v1'),
  'Android versionCode 14 joins the result-hub allowlist without dropping earlier builds'
);
select ok(
  (select value->'enabled_ios_builds' ?& array['87','88','89','90','91']
     from public.app_feature_flags where key = 'analysis_engine_v4'),
  'the current iOS V4 allowlist stays intact'
);
select ok(
  exists (
    select 1
    from public.app_feature_flags
    where key = 'android_release_policy'
      and (value->>'latest_build')::integer = 14
      and value->>'policy_version' = 'production-2.0.2-vc14'
      and coalesce((value->>'soft_update_enabled')::boolean, true) = false
      and coalesce((value->>'hard_update_enabled')::boolean, true) = false
  ),
  'live build 14 is advertised without enabling update prompts'
);
select ok(
  (select coalesce((value->>'kill_switch')::boolean, true) = false
     from public.app_feature_flags where key = 'android_client_enabled'),
  'the Android client master switch stays on'
);

select * from extensions.finish();
rollback;
