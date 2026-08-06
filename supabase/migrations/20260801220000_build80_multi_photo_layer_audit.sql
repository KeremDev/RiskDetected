-- Keep the global multi-photo layer audit flag off for live App Store builds,
-- but enable the 12-layer audit and higher thinking budget for iOS build 80
-- and later review candidates. Existing production build 77 stays on the
-- existing allowlist and must continue to receive the previous behavior.

do $build80_multi_photo_layer_audit$
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

  if coalesce((v_flag ->> 'multi_photo_layer_audit_enabled')::boolean, false) then
    raise exception 'global multi_photo_layer_audit_enabled must remain false';
  end if;

  if coalesce((v_flag #>> '{features,multi_photo_analysis}')::boolean, false)
      is distinct from true
    or coalesce((v_flag #>> '{features,multi_photo_coverage_v2}')::boolean, false)
      is distinct from true
    or coalesce((v_flag #>> '{features,plus_pro_5_photo_limit}')::boolean, false)
      is distinct from true then
    raise exception 'paid multi-photo feature switches must remain enabled';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
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
              '{min_ios_build}',
              '80'::jsonb,
              true
            ),
            '{multi_photo_layer_audit_enabled_ios_builds}',
            (
              select jsonb_agg(distinct build order by build)
              from jsonb_array_elements_text(
                coalesce(value -> 'multi_photo_layer_audit_enabled_ios_builds', '[]'::jsonb)
                  || '["80"]'::jsonb
              ) as build
            ),
            true
          ),
          '{multi_photo_layer_audit_min_ios_build}',
          '80'::jsonb,
          true
        ),
        '{multi_photo_thinking_budget_min_ios_build}',
        '80'::jsonb,
        true
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';

  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{multi_photo_thinking_budget_min_ios_build_value}',
        '6144'::jsonb,
        true
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';
end
$build80_multi_photo_layer_audit$;

select pg_notify('pgrst', 'reload schema');
