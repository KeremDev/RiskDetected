-- RiskDetected iOS 2.0.0 (build 87) release gate.
--
-- Build 87 is a fail-closed V4 client: a route/configuration problem must be
-- retried and must never silently enter V3 or the legacy engine. Older iOS
-- builds and every Android build keep their existing resolver behaviour.

create or replace function public.resolve_analysis_engine_route_v5(
  p_user_id uuid,
  p_analysis_id uuid,
  p_compute_routing jsonb default '{}'::jsonb,
  p_client_routing jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_route private.analysis_engine_routes%rowtype;
  v_config private.analysis_v4_configs%rowtype;
  v_flag jsonb := '{}'::jsonb;
  v_allowlisted boolean := false;
  v_client_ok boolean := false;
  v_config_found boolean := false;
  v_rollout_allowed boolean := false;
  v_v4_ok boolean := false;
  v_v4_required boolean := false;
  v_general_release_approved boolean := false;
  v_rollout_mode text := 'off';
  v_platform text := lower(coalesce(p_client_routing->>'client_platform', ''));
  v_client_build_text text := coalesce(p_client_routing->>'client_app_build', '');
  v_client_build integer := null;
  v_plan text := 'free';
  v_profile text := 'premium';
  v_pool text := 'paid_standard';
  v_tier text := 'standard';
  v_route_name text;
  v_compute jsonb;
  v_snapshot jsonb;
  v_base jsonb;
  v_fallback_reason text := null;
begin
  if v_client_build_text ~ '^[0-9]+$' then
    v_client_build := v_client_build_text::integer;
  end if;
  v_v4_required := v_platform = 'ios' and coalesce(v_client_build, 0) >= 87;

  select value into v_flag from public.app_feature_flags
  where key = 'analysis_engine_v4';
  v_flag := coalesce(v_flag, '{}'::jsonb);
  v_rollout_mode := lower(coalesce(v_flag->>'rollout_mode', 'off'));
  v_general_release_approved := coalesce(
    v_flag->>'general_release_approved', 'false'
  ) = 'true';

  select coalesce(enabled, false) into v_allowlisted
  from private.analysis_v4_allowlist where user_id = p_user_id;
  v_allowlisted := coalesce(v_allowlisted, false);

  v_client_ok := coalesce(p_client_routing->>'snapshot_version', '') = '1'
    and p_client_routing->>'source' = 'trusted_analyze_enqueue'
    and coalesce(p_client_routing->>'api_contract_version', '') ~ '^[0-9]+$'
    and (p_client_routing->>'api_contract_version')::integer >= 3
    and coalesce(p_client_routing->>'safety_claim_v4_scoreless', 'false') = 'true';

  v_rollout_allowed := case v_rollout_mode
    when 'user_allowlist' then v_allowlisted
    when 'build_allowlist' then
      v_general_release_approved and (
        (v_platform = 'ios' and coalesce(v_flag->'enabled_ios_builds', '[]'::jsonb) ? v_client_build_text)
        or
        (v_platform = 'android' and coalesce(v_flag->'enabled_android_builds', '[]'::jsonb) ? v_client_build_text)
      )
    when 'min_build' then
      v_general_release_approved and v_client_build is not null and (
        (v_platform = 'ios'
          and coalesce(v_flag->>'min_ios_build', '') ~ '^[0-9]+$'
          and v_client_build >= (v_flag->>'min_ios_build')::integer)
        or
        (v_platform = 'android'
          and coalesce(v_flag->>'min_android_build', '') ~ '^[0-9]+$'
          and v_client_build >= (v_flag->>'min_android_build')::integer)
      )
    when 'all' then v_general_release_approved
    else false
  end;

  -- Route snapshots are immutable. A build-87 request may reuse only a V4
  -- snapshot; an accidentally pinned legacy/V3 route fails closed.
  select * into v_route from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if found then
    if v_v4_required
      and coalesce(v_route.config_snapshot->>'engine_variant', '') <> 'vnext-v4'
    then
      return jsonb_build_object(
        'ok', false,
        'state', 'v4_required_unavailable',
        'error_code', 'v4_required_existing_route_mismatch',
        'retryable', true,
        'required_engine_variant', 'vnext-v4'
      );
    end if;
    return jsonb_build_object(
      'ok', true, 'state', 'pinned', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  select * into v_config from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;
  v_config_found := found;

  v_v4_ok := v_rollout_allowed
    and not (coalesce(v_flag->>'kill_switch', 'true') = 'true')
    and v_client_ok and v_config_found
    and v_config.engine_version = 'vnext-v4'
    and v_config.provider_contract_version = 'visual-claim-candidate-v1'
    and v_config.domain_schema_version = 'safety-claim-v4.0'
    and coalesce(v_config.prompt_version, '') <> ''
    and coalesce(v_config.router_version, '') <> ''
    and v_config.prompt_sha256 ~ '^[a-f0-9]{64}$';

  if v_v4_ok then
    select coalesce(a.plan_at_creation::text, 'free') into v_plan
    from public.analyses a where a.id = p_analysis_id and a.user_id = p_user_id;
    v_route_name := nullif(p_compute_routing->>'ai_execution_route', '');
    if coalesce(p_compute_routing->>'snapshot_version', '') <> '1'
      or p_compute_routing->>'source' <> 'trusted_analyze_enqueue'
      or v_route_name not in ('free_legacy','free_paid_trial','paid_plan','cancelled_plus_trial_free')
    then
      v_route_name := 'compute_route_snapshot_missing';
    elsif v_route_name in ('free_legacy','cancelled_plus_trial_free') then
      v_profile := 'economy';
    end if;
    if v_profile = 'economy' and coalesce(v_config.config->>'paid_flex_enabled', 'false') = 'true' then
      v_pool := 'paid_flex'; v_tier := 'flex';
    end if;
    v_compute := jsonb_build_object(
      'snapshot_version', 1,
      'ai_execution_route', v_route_name,
      'compute_profile', v_profile,
      'compute_profile_version', coalesce(v_config.config->>'compute_profile_version', 'compute-profile-v1'),
      'provider_pool', v_pool,
      'requested_service_tier', v_tier,
      'product_plan', v_plan,
      'source', 'trusted_analyze_enqueue'
    );
    v_snapshot := jsonb_build_object(
      'engine_variant', 'vnext-v4',
      'engine_config', v_config.config || jsonb_build_object(
        'engine_version', v_config.engine_version,
        'schema_version', v_config.domain_schema_version,
        'provider_contract_version', v_config.provider_contract_version,
        'prompt_version', v_config.prompt_version,
        'prompt_sha256', v_config.prompt_sha256,
        'policy_version', v_config.router_version,
        'coverage_version', v_config.coverage_version,
        'assurance_version', v_config.assurance_version,
        'standards_version', v_config.standards_version,
        'quality_trace_version', v_config.quality_trace_version,
        'report_projection_version', v_config.report_projection_version
      ),
      'compute_routing', v_compute,
      'client_routing', p_client_routing
    );
    insert into private.analysis_engine_routes (
      analysis_id, user_id, engine, rollout_mode, config_snapshot
    ) values (p_analysis_id, p_user_id, 'vnext', v_rollout_mode, v_snapshot)
    on conflict (analysis_id) do nothing;
    select * into v_route from private.analysis_engine_routes
    where analysis_id = p_analysis_id and user_id = p_user_id;

    if v_v4_required
      and coalesce(v_route.config_snapshot->>'engine_variant', '') <> 'vnext-v4'
    then
      return jsonb_build_object(
        'ok', false,
        'state', 'v4_required_unavailable',
        'error_code', 'v4_required_route_pin_race',
        'retryable', true,
        'required_engine_variant', 'vnext-v4'
      );
    end if;

    return jsonb_build_object(
      'ok', true, 'state', 'resolved', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  v_fallback_reason := case
    when coalesce(v_flag->>'kill_switch', 'true') = 'true' then 'v4_kill_switch'
    when v_rollout_mode not in ('user_allowlist','build_allowlist','min_build','all') then 'v4_rollout_off'
    when v_rollout_mode <> 'user_allowlist' and not v_general_release_approved then 'v4_general_release_not_approved'
    when not v_rollout_allowed then 'v4_rollout_gate_miss'
    when not v_client_ok then 'v4_client_incompatible'
    when not v_config_found then 'v4_config_missing_or_invalid'
    else 'v4_contract_mismatch'
  end;

  if v_v4_required then
    return jsonb_build_object(
      'ok', false,
      'state', 'v4_required_unavailable',
      'error_code', v_fallback_reason,
      'retryable', true,
      'required_engine_variant', 'vnext-v4'
    );
  end if;

  v_base := public.resolve_analysis_engine_route_v4(p_user_id, p_analysis_id, p_compute_routing);
  update private.analysis_engine_routes
  set config_snapshot = jsonb_set(config_snapshot, '{v4_fallback_reason}', to_jsonb(v_fallback_reason), true)
  where analysis_id = p_analysis_id and user_id = p_user_id;
  return v_base || jsonb_build_object('v4_fallback_reason', v_fallback_reason);
exception when others then
  if v_v4_required then
    return jsonb_build_object(
      'ok', false,
      'state', 'v4_required_unavailable',
      'error_code', 'v4_route_resolution_failed',
      'retryable', true,
      'required_engine_variant', 'vnext-v4'
    );
  end if;
  return jsonb_build_object('ok', false, 'state', 'v4_route_resolution_failed');
end;
$function$;

revoke all on function public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)
  to service_role;

update public.app_feature_flags
set value = coalesce(value, '{}'::jsonb) || jsonb_build_object(
      'rollout_mode', 'build_allowlist',
      'enabled_ios_builds', jsonb_build_array('87'),
      'general_release_approved', true,
      'required_api_contract', 3,
      'required_capability', 'safety_claim_v4_scoreless',
      'kill_switch', false
    ),
    updated_at = now()
where key = 'analysis_engine_v4';

update public.app_feature_flags
set value = coalesce(value, '{}'::jsonb) || jsonb_build_object(
      'rollout_mode', 'build_allowlist',
      'enabled_ios_builds', jsonb_build_array('87'),
      'required_capability', 'analysis_result_hub_v1',
      'kill_switch', false
    ),
    updated_at = now()
where key = 'analysis_result_hub_v1';

do $verification$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
  v_config private.analysis_v4_configs%rowtype;
begin
  select value into v_engine_flag from public.app_feature_flags
  where key = 'analysis_engine_v4';
  select value into v_hub_flag from public.app_feature_flags
  where key = 'analysis_result_hub_v1';
  select * into v_config from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;

  if v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'build 87 V4 release gate verification failed';
  end if;

  if v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'build 87 result hub gate verification failed';
  end if;

  if not found
    or v_config.engine_version <> 'vnext-v4'
    or v_config.provider_contract_version <> 'visual-claim-candidate-v1'
    or v_config.domain_schema_version <> 'safety-claim-v4.0'
    or v_config.prompt_sha256 !~ '^[a-f0-9]{64}$'
  then
    raise exception 'build 87 active V4 configuration verification failed';
  end if;
end;
$verification$;
