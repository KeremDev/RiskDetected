-- Keep multi-photo feature rollout aligned with iOS build 67.
-- Production was updated first to unblock TestFlight/live QA; this migration
-- records the same idempotent flag change for future environments.

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_ios_builds}',
      (
        select jsonb_agg(build_number order by build_number::int)
        from (
          select distinct jsonb_array_elements_text(
            coalesce(value->'enabled_ios_builds', '[]'::jsonb)
          ) as build_number
          union
          select '67'
        ) builds
      ),
      true
    ),
    updated_at = now()
where key = 'multi_photo_analysis';
