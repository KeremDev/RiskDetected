-- Covers the current Android closed-test release-gate state. The original ADR-005 migration
-- creates every flag closed; later closed-test migrations opened the six Android capabilities
-- for explicitly admitted Play builds, then 20260819235131 switched all six to a min_version
-- floor of 2 so a new build no longer has to be hand-added to an allowlist before it can run
-- (see that migration for the versionCode 6 incident it fixes). `enabled_android_version_codes`
-- is left in place as the rollback path and is asserted separately below.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(8);

select ok(
  exists (select 1 from public.app_feature_flags where key = 'android_client_enabled'),
  'android_client_enabled flag row exists'
);

select ok(
  coalesce((
    select bool_and(
      coalesce((value->>'kill_switch')::boolean, true) = false
      and value->>'rollout_mode' = 'min_version'
      and (value->>'min_android_version_code')::int = 2
    )
    from public.app_feature_flags
    where key in (
      'android_client_enabled',
      'android_auth_enabled',
      'android_analysis_submit_enabled',
      'android_payments_enabled',
      'android_notifications_enabled',
      'android_pdf_reports_enabled'
    )
  ), false),
  'all six Android capabilities are open for versionCode 2 and above (min_version floor)'
);

select is(
  (select count(*)::int from public.app_feature_flags where key like 'android_%enabled'),
  6,
  'exactly the 6 expected android_*_enabled flags exist (no typo/duplicate)'
);

select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'android_release_policy'
      and (value->>'hard_update_enabled')::boolean = false
      and (value->>'soft_update_enabled')::boolean = false
  ),
  'android_release_policy starts fully closed (cannot force or soft-nudge an update)'
);

-- Regression: these must never overwrite the live ios_release_policy row (on conflict do nothing
-- + distinct key names already guarantee this, but assert explicitly since this is exactly the
-- kind of accidental cross-platform collision the whole Android effort must not cause).
select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'ios_release_policy'
      and (value->>'latest_build')::int >= 77
  ),
  'ios_release_policy is untouched by this migration (still has its real, non-Android latest_build)'
);

select ok(
  (select count(*)::int from public.app_feature_flags where key = 'ios_release_policy') = 1,
  'still exactly one ios_release_policy row (no accidental duplicate/collision)'
);

select ok(
  not exists (
    select 1 from public.app_feature_flags
    where key = 'android_client_enabled' and value ? 'enabled_ios_builds'
  ),
  'android flags do not carry an ios-shaped enabled_ios_builds key by copy-paste mistake'
);

select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'android_client_enabled' and value ? 'enabled_android_version_codes'
  ),
  'android_client_enabled carries the android-shaped allowlist key instead'
);

select * from finish();
rollback;
