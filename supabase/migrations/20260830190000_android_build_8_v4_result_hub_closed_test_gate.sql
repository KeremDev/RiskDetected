-- RiskDetected Android 2.0.0 (versionCode 8) closed-test gate.
--
-- Runtime gates have used min_version since 20260819235131, so build 8 does not
-- need to be copied into the old per-version allowlists. The V4 engine and the
-- result hub intentionally remain build allowlists; admit build 8 there while
-- preserving build 7 and every approved iOS build. Do not advertise build 8 as
-- latest until Google Play has processed the closed-test artifact.

do $preflight$
declare
  v_key text;
  v_value jsonb;
  v_runtime_keys constant text[] := array[
    'android_client_enabled',
    'android_auth_enabled',
    'android_analysis_submit_enabled',
    'android_payments_enabled',
    'android_notifications_enabled',
    'android_pdf_reports_enabled'
  ];
begin
  foreach v_key in array v_runtime_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value is null
      or v_value->>'rollout_mode' not in ('min_version', 'min_build')
      or coalesce((v_value->>'min_android_version_code')::integer, 2147483647) > 8
      or coalesce((v_value->>'kill_switch')::boolean, true)
    then
      raise exception 'Android build 8 runtime gate preflight failed for %', v_key;
    end if;
  end loop;

  select value into v_value
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  if v_value is null
    or v_value->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_value->>'kill_switch', 'true') <> 'false'
    or coalesce(v_value->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_value->>'required_api_contract', '') <> '3'
    or coalesce(v_value->>'required_capability', '') <> 'safety_claim_v4_scoreless'
    or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ? '7')
  then
    raise exception 'Android build 8 V4 preflight state mismatch';
  end if;

  select value into v_value
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if v_value is null
    or v_value->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_value->>'kill_switch', 'true') <> 'false'
    or coalesce(v_value->>'required_capability', '') <> 'analysis_result_hub_v1'
    or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ? '7')
  then
    raise exception 'Android build 8 result-hub preflight state mismatch';
  end if;
end;
$preflight$;

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_android_builds}',
      (
        select jsonb_agg(distinct build order by build)
        from jsonb_array_elements_text(
          coalesce(value->'enabled_android_builds', '[]'::jsonb) || '["8"]'::jsonb
        ) as build
      ),
      true
    ),
    updated_at = now()
where key in ('analysis_engine_v4', 'analysis_result_hub_v1');

do $verification$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
  v_policy jsonb;
begin
  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  select value into v_policy
  from public.app_feature_flags
  where key = 'android_release_policy';

  if not (coalesce(v_engine_flag->'enabled_android_builds', '[]'::jsonb) ? '7')
    or not (coalesce(v_engine_flag->'enabled_android_builds', '[]'::jsonb) ? '8')
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 8 V4 gate verification failed';
  end if;

  if not (coalesce(v_hub_flag->'enabled_android_builds', '[]'::jsonb) ? '7')
    or not (coalesce(v_hub_flag->'enabled_android_builds', '[]'::jsonb) ? '8')
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 8 result-hub gate verification failed';
  end if;

  if coalesce((v_policy->>'latest_build')::integer, 0) >= 8 then
    raise exception 'Android build 8 must not be advertised before Play processing completes';
  end if;
end;
$verification$;
