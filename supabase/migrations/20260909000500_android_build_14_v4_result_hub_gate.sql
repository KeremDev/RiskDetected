-- RiskDetected Android 2.0.2 (versionCode 14) pre-release analysis gate.
-- Admit the candidate to V4 and the result hub while keeping build 13 advertised until
-- Google Play confirms build 14 is publicly available.
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
      or coalesce((v_value->>'min_android_version_code')::integer, 2147483647) > 14
      or coalesce((v_value->>'kill_switch')::boolean, true)
    then
      raise exception 'Android build 14 runtime gate preflight failed for %', v_key;
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
    or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12','13'])
    or not (coalesce(v_value->'enabled_ios_builds', '[]'::jsonb) ?& array['87','88','89','90','91'])
  then
    raise exception 'Android build 14 V4 preflight state mismatch';
  end if;

  select value into v_value
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if v_value is null
    or v_value->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_value->>'kill_switch', 'true') <> 'false'
    or coalesce(v_value->>'required_capability', '') <> 'analysis_result_hub_v1'
    or not (coalesce(v_value->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12','13'])
    or not (coalesce(v_value->'enabled_ios_builds', '[]'::jsonb) ?& array['87','88','89','90','91'])
  then
    raise exception 'Android build 14 result-hub preflight state mismatch';
  end if;

  if not exists (
    select 1
    from private.analysis_v4_configs
    where is_active
      and integrity_status = 'valid'
      and engine_version = 'vnext-v4'
      and provider_contract_version = 'visual-claim-candidate-v1'
      and domain_schema_version = 'safety-claim-v4.0'
      and prompt_sha256 ~ '^[a-f0-9]{64}$'
  ) then
    raise exception 'Android build 14 active V4 configuration preflight failed';
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
          coalesce(value->'enabled_android_builds', '[]'::jsonb) || '["14"]'::jsonb
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

  if not (coalesce(v_engine_flag->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12','13','14'])
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 14 V4 gate verification failed';
  end if;

  if not (coalesce(v_hub_flag->'enabled_android_builds', '[]'::jsonb) ?& array['7','8','9','10','11','12','13','14'])
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 14 result-hub gate verification failed';
  end if;

  if coalesce((v_policy->>'latest_build')::integer, 0) <> 13
    or v_policy->>'policy_version' <> 'production-2.0.1-vc13'
  then
    raise exception 'Android build 14 must not be advertised before Play goes live';
  end if;
end;
$verification$;
