-- Permit only the corrected App Review candidate build 80 to use the
-- existing build-gated multi-photo capability. Existing App Store builds,
-- plan limits, feature switches, kill switch, and release policy are not
-- changed by this migration.

do $allow_multi_photo_build_80$
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
    raise exception 'multi_photo_analysis kill switch must be false';
  end if;

  if v_flag ->> 'rollout_mode' is distinct from 'build_allowlist' then
    raise exception 'multi_photo_analysis rollout_mode must remain build_allowlist';
  end if;

  if coalesce((v_flag #>> '{features,multi_photo_analysis}')::boolean, false)
      is distinct from true
    or coalesce((v_flag #>> '{features,plus_pro_5_photo_limit}')::boolean, false)
      is distinct from true then
    raise exception 'paid multi-photo feature switches must remain enabled';
  end if;

  if coalesce((v_flag ->> 'max_photo_count_free')::integer, -1) <> 1
    or coalesce((v_flag ->> 'max_photo_count_plus')::integer, -1) <> 3
    or coalesce((v_flag ->> 'max_photo_count_pro')::integer, -1) <> 3 then
    raise exception 'expected photo limits are Free=1, Plus=3, Pro=3';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{enabled_ios_builds}',
        (
          select jsonb_agg(distinct build order by build)
          from jsonb_array_elements_text(
            coalesce(value -> 'enabled_ios_builds', '[]'::jsonb)
              || '["80"]'::jsonb
          ) as build
        ),
        true
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';
end
$allow_multi_photo_build_80$;

select pg_notify('pgrst', 'reload schema');
