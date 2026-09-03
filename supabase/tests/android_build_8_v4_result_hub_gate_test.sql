begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(7);

select ok(
  (select value->'enabled_android_builds' ? '8' from public.app_feature_flags where key='analysis_engine_v4'),
  'Android versionCode 8 is admitted to V4'
);
select ok(
  (select value->'enabled_android_builds' ? '8' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'Android versionCode 8 is admitted to result hub'
);
select ok(
  (select value->'enabled_android_builds' ? '7' from public.app_feature_flags where key='analysis_engine_v4'),
  'V4 keeps Android versionCode 7 admitted'
);
select ok(
  (select value->'enabled_android_builds' ? '7' from public.app_feature_flags where key='analysis_result_hub_v1'),
  'result hub keeps Android versionCode 7 admitted'
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
        or coalesce((value->>'min_android_version_code')::integer, 2147483647) > 8
      )
  ),
  'all Android runtime gates admit build 8 through the minimum-version policy'
);

select * from extensions.finish();
rollback;
