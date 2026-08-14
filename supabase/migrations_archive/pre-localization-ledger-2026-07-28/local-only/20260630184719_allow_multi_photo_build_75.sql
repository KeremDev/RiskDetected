-- Keep build-gated multi-photo rollout aligned with iOS build 75 App Store submission.
-- Do not enable legacy flat flags or global rollout; build_allowlist remains the gate.

update public.app_feature_flags
set value = jsonb_set(
    value,
    '{enabled_ios_builds}',
    (
      select jsonb_agg(distinct build order by build)
      from jsonb_array_elements_text(
        coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["75"]'::jsonb
      ) as build
    ),
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(value, '{latest_build}', '75'::jsonb, true),
    '{policy_version}',
    to_jsonb('build-75-appstore'::text),
    true
  ),
  updated_at = now()
where key = 'ios_release_policy';

select pg_notify('pgrst', 'reload schema');
