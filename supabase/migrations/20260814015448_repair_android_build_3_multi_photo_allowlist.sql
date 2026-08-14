-- Repair the operational drift observed after the build-3 release migration: production retained
-- the paid plan limits (Plus/Pro=3) but lost the Android multi-photo build allowlist. This only
-- changes the Android-specific field; iOS allowlists and every shared capability remain intact.

do $repair_android_build_3_multi_photo_allowlist$
declare
  v_flag jsonb;
begin
  select value
  into v_flag
  from public.app_feature_flags
  where key = 'multi_photo_analysis'
  for update;

  if v_flag is null then
    raise exception 'multi_photo_analysis feature flag is missing';
  end if;

  if coalesce((v_flag ->> 'kill_switch')::boolean, true) then
    raise exception 'multi_photo_analysis kill switch must remain false';
  end if;

  if v_flag ->> 'rollout_mode' is distinct from 'build_allowlist' then
    raise exception 'multi_photo_analysis rollout_mode must remain build_allowlist';
  end if;

  if coalesce((v_flag #>> '{features,multi_photo_analysis}')::boolean, false)
      is distinct from true
    or coalesce((v_flag #>> '{features,plus_pro_5_photo_limit}')::boolean, false)
      is distinct from true
    or coalesce((v_flag ->> 'max_photo_count_free')::integer, -1) <> 1
    or coalesce((v_flag ->> 'max_photo_count_plus')::integer, -1) <> 3
    or coalesce((v_flag ->> 'max_photo_count_pro')::integer, -1) <> 3 then
    raise exception 'expected enabled multi-photo contract with Free=1, Plus=3, Pro=3';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{enabled_android_builds}',
        (
          select jsonb_agg(distinct build order by build)
          from jsonb_array_elements_text(
            coalesce(value -> 'enabled_android_builds', '[]'::jsonb) || '["3"]'::jsonb
          ) as build
        ),
        true
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';
end
$repair_android_build_3_multi_photo_allowlist$;

select pg_notify('pgrst', 'reload schema');
