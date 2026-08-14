-- Permit App Store build 77 to use the existing build-gated multi-photo
-- capability. The user-facing limits remain Free=1 and Plus/Pro=3.
--
-- ios_release_policy.latest_build intentionally remains 76 until version
-- 1.2.4 is available on the App Store, preventing premature update prompts.

update public.app_feature_flags
set value = jsonb_set(
    value,
    '{enabled_ios_builds}',
    (
      select jsonb_agg(distinct build order by build)
      from jsonb_array_elements_text(
        coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["77"]'::jsonb
      ) as build
    ),
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';

select pg_notify('pgrst', 'reload schema');
