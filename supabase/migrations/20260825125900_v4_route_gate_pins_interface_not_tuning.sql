-- The v4 route gate pinned prompt_version and router_version to literals.
-- Those two change on every quality fix, so bumping the config to
-- v4-vision-core-v4 / claim-routing-v3 silently routed every analysis back to
-- v3 with v4_fallback_reason = v4_integrity_mismatch. The engine deployed
-- correctly and never ran once.
--
-- The gate now checks what defines the wire contract with the deployed
-- function - engine, provider contract, domain schema - plus the reviewed
-- integrity_status and a well-formed prompt hash. Prompt and router versions
-- are recorded in the route snapshot, not used as an activation lock.

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
  v_v4_ok boolean := false;
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
  select * into v_route from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if found then
    return jsonb_build_object(
      'ok', true, 'state', 'pinned', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  select value into v_flag from public.app_feature_flags
  where key = 'analysis_engine_v4';
  select coalesce(enabled, false) into v_allowlisted
  from private.analysis_v4_allowlist where user_id = p_user_id;
  v_allowlisted := coalesce(v_allowlisted, false);

  v_client_ok := coalesce((p_client_routing->>'snapshot_version')::integer, 0) = 1
    and p_client_routing->>'source' = 'trusted_analyze_enqueue'
    and coalesce((p_client_routing->>'api_contract_version')::integer, 0) >= 3
    and coalesce((p_client_routing->>'safety_claim_v4_scoreless')::boolean, false);

  select * into v_config from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;
  v_config_found := found;

  v_v4_ok := coalesce(v_flag->>'rollout_mode', 'off') = 'user_allowlist'
    and not coalesce((v_flag->>'kill_switch')::boolean, true)
    and v_allowlisted and v_client_ok and v_config_found
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
    if coalesce((p_compute_routing->>'snapshot_version')::integer, 0) <> 1
      or p_compute_routing->>'source' <> 'trusted_analyze_enqueue'
      or v_route_name not in ('free_legacy','free_paid_trial','paid_plan','cancelled_plus_trial_free')
    then
      v_route_name := 'compute_route_snapshot_missing';
    elsif v_route_name in ('free_legacy','cancelled_plus_trial_free') then
      v_profile := 'economy';
    end if;
    if v_profile = 'economy' and coalesce((v_config.config->>'paid_flex_enabled')::boolean, false) then
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
    ) values (p_analysis_id, p_user_id, 'vnext', 'user_allowlist', v_snapshot)
    on conflict (analysis_id) do nothing;
    select * into v_route from private.analysis_engine_routes
    where analysis_id = p_analysis_id and user_id = p_user_id;
    return jsonb_build_object(
      'ok', true, 'state', 'resolved', 'engine', v_route.engine,
      'engine_variant', coalesce(v_route.config_snapshot->>'engine_variant', 'vnext-v3'),
      'rollout_mode', v_route.rollout_mode,
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  v_fallback_reason := case
    when coalesce(v_flag->>'rollout_mode', 'off') <> 'user_allowlist' then 'v4_rollout_off'
    when coalesce((v_flag->>'kill_switch')::boolean, true) then 'v4_kill_switch'
    when not v_allowlisted then 'v4_user_not_allowlisted'
    when not v_client_ok then 'v4_client_incompatible'
    when not v_config_found then 'v4_config_missing_or_invalid'
    else 'v4_contract_mismatch'
  end;
  v_base := public.resolve_analysis_engine_route_v4(p_user_id, p_analysis_id, p_compute_routing);
  update private.analysis_engine_routes
  set config_snapshot = jsonb_set(config_snapshot, '{v4_fallback_reason}', to_jsonb(v_fallback_reason), true)
  where analysis_id = p_analysis_id and user_id = p_user_id;
  return v_base || jsonb_build_object('v4_fallback_reason', v_fallback_reason);
exception when others then
  return jsonb_build_object('ok', false, 'state', 'v4_route_resolution_failed');
end;
$function$;

do $$
declare
  v_config private.analysis_v4_configs%rowtype;
begin
  select * into v_config from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc limit 1;

  if not found
    or v_config.engine_version <> 'vnext-v4'
    or v_config.provider_contract_version <> 'visual-claim-candidate-v1'
    or v_config.domain_schema_version <> 'safety-claim-v4.0'
    or v_config.prompt_version <> 'v4-vision-core-v4'
    or v_config.router_version <> 'claim-routing-v3'
    or v_config.prompt_sha256 !~ '^[a-f0-9]{64}$'
  then
    raise exception 'v4 route gate verification failed';
  end if;
end;
$$;
