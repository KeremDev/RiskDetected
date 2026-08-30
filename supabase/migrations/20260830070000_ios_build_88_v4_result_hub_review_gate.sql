-- RiskDetected iOS 2.0.0 (build 88) App Review gate.
--
-- Build 88 keeps build 87 enabled while admitting the replacement binary to
-- the fail-closed V4 engine and the new result hub. The App Store release
-- policy is intentionally not advanced here: existing users must not receive
-- an update prompt until build 88 is actually available on the storefront.

do $preflight$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
begin
  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if v_engine_flag is null
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_engine_flag->>'required_api_contract', '') <> '3'
    or coalesce(v_engine_flag->>'required_capability', '') <> 'safety_claim_v4_scoreless'
  then
    raise exception 'build 88 V4 preflight state mismatch';
  end if;

  if v_hub_flag is null
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_hub_flag->>'required_capability', '') <> 'analysis_result_hub_v1'
  then
    raise exception 'build 88 result hub preflight state mismatch';
  end if;
end;
$preflight$;

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_ios_builds}',
      (
        select jsonb_agg(distinct build order by build)
        from jsonb_array_elements_text(
          coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["88"]'::jsonb
        ) as build
      ),
      true
    ),
    updated_at = now()
where key = 'analysis_engine_v4';

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_ios_builds}',
      (
        select jsonb_agg(distinct build order by build)
        from jsonb_array_elements_text(
          coalesce(value->'enabled_ios_builds', '[]'::jsonb) || '["88"]'::jsonb
        ) as build
      ),
      true
    ),
    updated_at = now()
where key = 'analysis_result_hub_v1';

do $verification$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
  v_config private.analysis_v4_configs%rowtype;
begin
  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  select * into v_config
  from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc
  limit 1;

  if not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'build 88 V4 review gate verification failed';
  end if;

  if not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'build 88 result hub review gate verification failed';
  end if;

  if not found
    or v_config.engine_version <> 'vnext-v4'
    or v_config.provider_contract_version <> 'visual-claim-candidate-v1'
    or v_config.domain_schema_version <> 'safety-claim-v4.0'
    or v_config.prompt_sha256 !~ '^[a-f0-9]{64}$'
  then
    raise exception 'build 88 active V4 configuration verification failed';
  end if;
end;
$verification$;
