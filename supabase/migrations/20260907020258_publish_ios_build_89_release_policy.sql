-- iOS 2.0.1 (build 89) is publicly available on the Turkish App Store.
-- Publish it only after confirming that both production analysis surfaces admit the build.
do $migration$
declare
  v_policy jsonb;
  v_latest_build integer;
  v_engine_flag jsonb;
  v_hub_flag jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'ios_release_policy'
  for update;

  if v_policy is null then
    raise exception 'ios_release_policy feature flag is missing';
  end if;

  v_latest_build := case
    when v_policy->>'latest_build' ~ '^[0-9]+$' then (v_policy->>'latest_build')::integer
    else 0
  end;

  if v_latest_build not in (88, 89) then
    raise exception 'Refusing to publish build 89 from unexpected iOS latest build %', v_latest_build;
  end if;

  if v_latest_build = 88
    and (
      v_policy->>'minimum_supported_build' <> '88'
      or v_policy->>'hard_update_enabled' <> 'true'
      or v_policy->>'soft_update_enabled' <> 'true'
      or v_policy->>'policy_version' <> 'build-88-appstore-general-release-reconciled'
    )
  then
    raise exception 'Refusing to publish build 89 from unexpected build-88 policy state: %', v_policy;
  end if;

  if v_latest_build = 89
    and (
      v_policy->>'minimum_supported_build' <> '88'
      or v_policy->>'hard_update_enabled' <> 'true'
      or v_policy->>'soft_update_enabled' <> 'true'
      or v_policy->>'policy_version' <> 'build-89-appstore-general-release'
    )
  then
    raise exception 'Refusing to overwrite unexpected build-89 policy state: %', v_policy;
  end if;

  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if v_engine_flag is null
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'required_api_contract', '') <> '3'
    or coalesce(v_engine_flag->>'required_capability', '') <> 'safety_claim_v4_scoreless'
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ?& array['87', '88'])
  then
    raise exception 'iOS build 89 V4 preflight state mismatch';
  end if;

  if v_hub_flag is null
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_hub_flag->>'required_capability', '') <> 'analysis_result_hub_v1'
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ?& array['87', '88'])
  then
    raise exception 'iOS build 89 result-hub preflight state mismatch';
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
    raise exception 'iOS build 89 active V4 configuration preflight failed';
  end if;

  -- Production already admitted build 89 during App Review. Keeping this promotion here makes
  -- a clean database reproduce that production state before the public policy is advertised.
  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{enabled_ios_builds}',
        (
          select jsonb_agg(distinct build order by build)
          from jsonb_array_elements_text(
            coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["89"]'::jsonb
          ) as build
        ),
        true
      ),
      updated_at = now()
  where key in ('analysis_engine_v4', 'analysis_result_hub_v1');

  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '89')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '89')
  then
    raise exception 'iOS build 89 release gates are not ready';
  end if;

  update public.app_feature_flags
  set value = v_policy || jsonb_build_object(
        'minimum_supported_build', 88,
        'latest_build', 89,
        'hard_update_enabled', true,
        'soft_update_enabled', true,
        'app_store_url', 'https://apps.apple.com/tr/app/riskdetected-risk-assessment/id6769498181',
        'policy_version', 'build-89-appstore-general-release'
      ),
      updated_at = now()
  where key = 'ios_release_policy';
end;
$migration$;

do $verification$
declare
  v_policy jsonb;
begin
  select value into v_policy
  from public.app_feature_flags
  where key = 'ios_release_policy';

  if v_policy->>'minimum_supported_build' <> '88'
    or v_policy->>'latest_build' <> '89'
    or v_policy->>'hard_update_enabled' <> 'true'
    or v_policy->>'soft_update_enabled' <> 'true'
    or v_policy->>'policy_version' <> 'build-89-appstore-general-release'
    or v_policy->>'app_store_url' <> 'https://apps.apple.com/tr/app/riskdetected-risk-assessment/id6769498181'
  then
    raise exception 'iOS build 89 release policy verification failed';
  end if;
end;
$verification$;
