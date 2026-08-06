-- Extend the production Build 80 release gates to the App Review candidate
-- Build 81 without changing rollout modes, kill switches, reviewer cohorts,
-- plan limits, or the live iOS release policy.

do $allow_build_81_localization$
declare
  v_keys constant text[] := array[
    'localization_v2',
    'english_product_enabled',
    'global_localization_wave1',
    'safety_profile_en_intl_enabled',
    'safety_profile_en_gb_enabled',
    'safety_profile_en_us_enabled',
    'safety_profile_en_au_enabled',
    'safety_profile_en_ca_enabled',
    'localization_queue_payload_v1',
    'ai_language_guard_enabled',
    'ai_country_term_guard_enabled',
    'english_report_enabled',
    'english_notifications_enabled'
  ];
  v_flag_count integer;
begin
  select count(*)
  into v_flag_count
  from public.app_feature_flags
  where key = any(v_keys);

  if v_flag_count <> cardinality(v_keys) then
    raise exception 'expected % localization flags, found %',
      cardinality(v_keys),
      v_flag_count;
  end if;

  if exists (
    select 1
    from public.app_feature_flags
    where key = any(v_keys)
      and (
        coalesce((value ->> 'kill_switch')::boolean, true)
        or value ->> 'rollout_mode' is distinct from 'allowlist'
      )
  ) then
    raise exception 'localization release flags must remain allowlist-scoped with kill switches off';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{enabled_ios_builds}',
        (
          select jsonb_agg(distinct build order by build)
          from jsonb_array_elements_text(
            coalesce(value -> 'enabled_ios_builds', '[]'::jsonb)
              || '["81"]'::jsonb
          ) as build
        ),
        true
      ),
      updated_at = now()
  where key = any(v_keys);
end
$allow_build_81_localization$;

do $allow_build_81_multi_photo$
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
    or coalesce((v_flag #>> '{features,multi_photo_coverage_v2}')::boolean, false)
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

  if coalesce((v_flag ->> 'multi_photo_layer_audit_enabled')::boolean, false) then
    raise exception 'global multi_photo_layer_audit_enabled must remain false';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        jsonb_set(
          value,
          '{enabled_ios_builds}',
          (
            select jsonb_agg(distinct build order by build)
            from jsonb_array_elements_text(
              coalesce(value -> 'enabled_ios_builds', '[]'::jsonb)
                || '["81"]'::jsonb
            ) as build
          ),
          true
        ),
        '{multi_photo_layer_audit_enabled_ios_builds}',
        (
          select jsonb_agg(distinct build order by build)
          from jsonb_array_elements_text(
            coalesce(
              value -> 'multi_photo_layer_audit_enabled_ios_builds',
              '[]'::jsonb
            ) || '["81"]'::jsonb
          ) as build
        ),
        true
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';
end
$allow_build_81_multi_photo$;

select pg_notify('pgrst', 'reload schema');
