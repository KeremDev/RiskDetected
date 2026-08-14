update public.app_feature_flags
set value = jsonb_set(
    value,
    '{enabled_ios_builds}',
    (
      select jsonb_agg(distinct build order by build)
      from jsonb_array_elements_text(
        coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["69"]'::jsonb
      ) as build
    ),
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(value, '{latest_build}', '69'::jsonb, true),
    '{policy_version}',
    to_jsonb('build-69-testflight'::text),
    true
  ),
  updated_at = now()
where key = 'ios_release_policy';
