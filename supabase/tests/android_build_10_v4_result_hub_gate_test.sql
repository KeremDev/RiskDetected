begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(11);

select ok(
  (select value->'enabled_android_builds' ? '10' from public.app_feature_flags where key='analysis_engine_v4'),
  'Android versionCode 10 is admitted to V4'
);
select ok(
  (select value->'enabled_android_builds' ? '10' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'Android versionCode 10 is admitted to result hub'
);
select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9'] from public.app_feature_flags where key='analysis_engine_v4'),
  'V4 keeps Android builds 7, 8 and 9 admitted'
);
select ok(
  (select value->'enabled_android_builds' ?& array['7','8','9'] from public.app_feature_flags where key='analysis_result_hub_v1'),
  'result hub keeps Android builds 7, 8 and 9 admitted'
);
select ok(
  (select value->'enabled_ios_builds' ?& array['87','88'] from public.app_feature_flags where key='analysis_engine_v4'),
  'V4 keeps approved iOS builds admitted'
);
select ok(
  (select value->'enabled_ios_builds' ?& array['87','88'] from public.app_feature_flags where key='analysis_result_hub_v1'),
  'result hub keeps approved iOS builds admitted'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key='analysis_engine_v4'),
  'build_allowlist',
  'V4 remains build-allowlisted'
);
select is(
  (select value->>'rollout_mode' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'build_allowlist',
  'result hub remains build-allowlisted'
);
select ok(
  exists (
    select 1 from private.analysis_v4_configs
    where is_active and integrity_status='valid'
      and engine_version='vnext-v4'
      and provider_contract_version='visual-claim-candidate-v1'
      and domain_schema_version='safety-claim-v4.0'
  ),
  'the active analysis configuration is the released V4 contract'
);
select ok(
  exists (
    select 1
    from public.app_feature_flags
    where key='android_release_policy'
      -- Later builds advertise themselves through their own release-policy migration, so this
      -- guard tracks "build 10 or newer is live", not "build 10 exactly"; the exact state of the
      -- newest build is asserted by that build's own test.
      and (value->>'latest_build')::integer >= 10
      and (value->>'minimum_supported_build')::integer <= 10
      and coalesce((value->>'soft_update_enabled')::boolean, true) = false
      and coalesce((value->>'hard_update_enabled')::boolean, true) = false
      and value->>'app_store_url' = 'https://play.google.com/store/apps/details?id=com.riskdetectedan.app'
      and value->>'policy_version' like 'production-%-vc%'
  ),
  'build 10 or newer is advertised without forcing or nudging an update'
);
select ok(
  not exists (
    select 1
    from public.app_feature_flags
    where key in (
      'android_client_enabled',
      'android_auth_enabled',
      'android_analysis_submit_enabled',
      'android_payments_enabled',
      'android_notifications_enabled',
      'android_pdf_reports_enabled'
    )
      and (
        value->>'rollout_mode' not in ('min_version', 'min_build')
        or coalesce((value->>'kill_switch')::boolean, true)
        or coalesce((value->>'min_android_version_code')::integer, 2147483647) > 10
      )
  ),
  'all Android runtime gates admit build 10 through the minimum-version policy'
);

select * from extensions.finish();
rollback;
