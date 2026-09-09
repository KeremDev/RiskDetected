begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(6);

select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9','10','11']
     from public.app_feature_flags where key = 'analysis_engine_v4'),
  'Android versionCode 11 joins the V4 allowlist without dropping earlier builds'
);
select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9','10','11']
     from public.app_feature_flags where key = 'analysis_result_hub_v1'),
  'Android versionCode 11 joins the result-hub allowlist without dropping earlier builds'
);
select ok(
  (select value->'enabled_ios_builds' ?& array['87','88']
     from public.app_feature_flags where key = 'analysis_engine_v4'),
  'iOS builds 87 and 88 stay on V4'
);
select ok(
  exists (
    select 1
    from public.app_feature_flags
    where key = 'android_release_policy'
      -- Newer builds advertise themselves through their own release-policy migration; this
      -- guard tracks "build 11 or newer is live", the newest build's exact state is asserted by
      -- its own test.
      and (value->>'latest_build')::integer >= 11
      and value->>'policy_version' like 'production-%-vc%'
      and coalesce((value->>'soft_update_enabled')::boolean, true) = false
      and coalesce((value->>'hard_update_enabled')::boolean, true) = false
  ),
  'build 11 or newer is advertised without forcing or nudging an update'
);
select ok(
  (select coalesce((value->>'min_android_version_code')::integer, 2147483647) <= 11
     from public.app_feature_flags where key = 'android_notifications_enabled'),
  'the notifications runtime gate admits build 11'
);
select ok(
  (select coalesce((value->>'kill_switch')::boolean, true) = false
     from public.app_feature_flags where key = 'android_client_enabled'),
  'the Android client master switch stays on'
);

select * from extensions.finish();
rollback;
