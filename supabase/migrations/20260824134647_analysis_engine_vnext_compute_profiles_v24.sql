-- vNext compute-profile routing and cost telemetry. Product entitlements stay
-- on analyses.plan_at_creation; this snapshot controls only server-side AI
-- spend and is pinned once per analysis.

alter table private.analysis_engine_runs
  add column if not exists ai_execution_route text generated always as
    (config_snapshot #>> '{compute_routing,ai_execution_route}') stored,
  add column if not exists compute_profile text generated always as
    (config_snapshot #>> '{compute_routing,compute_profile}') stored,
  add column if not exists compute_profile_version text generated always as
    (config_snapshot #>> '{compute_routing,compute_profile_version}') stored,
  add column if not exists provider_pool text generated always as
    (config_snapshot #>> '{compute_routing,provider_pool}') stored,
  add column if not exists requested_service_tier text generated always as
    (config_snapshot #>> '{compute_routing,requested_service_tier}') stored,
  add column if not exists total_standard_equivalent_cost_usd numeric(14, 8)
    not null default 0;

alter table private.analysis_provider_attempts
  add column if not exists compute_profile text,
  add column if not exists provider_pool text,
  add column if not exists requested_service_tier text,
  add column if not exists effective_service_tier text,
  add column if not exists standard_equivalent_cost_usd numeric(14, 8)
    not null default 0,
  add column if not exists service_tier_fallback_reason text;

create index if not exists analysis_engine_runs_compute_profile_started_idx
  on private.analysis_engine_runs (compute_profile, started_at desc);
create index if not exists analysis_provider_attempts_service_tier_created_idx
  on private.analysis_provider_attempts
    (requested_service_tier, effective_service_tier, created_at desc);

create or replace function private.refresh_analysis_standard_cost_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update private.analysis_engine_runs r
  set total_standard_equivalent_cost_usd = (
        select coalesce(sum(a.standard_equivalent_cost_usd), 0)
        from private.analysis_provider_attempts a
        where a.engine_run_id = new.engine_run_id
      ),
      updated_at = now()
  where r.id = new.engine_run_id;
  return new;
end;
$$;

drop trigger if exists analysis_provider_attempts_standard_cost_refresh
  on private.analysis_provider_attempts;
create trigger analysis_provider_attempts_standard_cost_refresh
after insert or update of standard_equivalent_cost_usd
on private.analysis_provider_attempts
for each row execute function private.refresh_analysis_standard_cost_v1();

create or replace function public.resolve_analysis_engine_route_v4(
  p_user_id uuid,
  p_analysis_id uuid,
  p_compute_routing jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base jsonb;
  v_route private.analysis_engine_routes%rowtype;
  v_plan text;
  v_engine_config jsonb := '{}'::jsonb;
  v_route_name text;
  v_compute_profile text := 'premium';
  v_provider_pool text := 'paid_standard';
  v_service_tier text := 'standard';
  v_validation_reason text := 'trusted_route_valid';
  v_snapshot_valid boolean := false;
  v_routing jsonb;
begin
  v_base := public.resolve_analysis_engine_route_v3(p_user_id, p_analysis_id);
  if coalesce((v_base->>'ok')::boolean, false) is not true then
    return v_base;
  end if;

  select * into v_route
  from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'route_not_found');
  end if;
  select a.plan_at_creation::text into v_plan
  from public.analyses a
  where a.id = p_analysis_id and a.user_id = p_user_id;
  if v_route.config_snapshot ? 'compute_routing' then
    return v_base || jsonb_build_object(
      'state', 'pinned',
      'config_snapshot', v_route.config_snapshot
    );
  end if;

  v_engine_config := coalesce(v_route.config_snapshot->'engine_config', '{}'::jsonb);
  v_route_name := nullif(p_compute_routing->>'ai_execution_route', '');
  v_snapshot_valid := coalesce((p_compute_routing->>'snapshot_version')::integer, 0) = 1
    and p_compute_routing->>'source' = 'trusted_analyze_enqueue'
    and v_route_name in (
      'free_legacy', 'free_paid_trial', 'paid_plan',
      'cancelled_plus_trial_free'
    );

  if not v_snapshot_valid then
    v_route_name := 'compute_route_snapshot_missing';
    v_validation_reason := 'trusted_compute_route_snapshot_missing';
  elsif (v_route_name in ('free_legacy', 'free_paid_trial') and v_plan <> 'free')
    or (v_route_name = 'cancelled_plus_trial_free' and v_plan <> 'plus')
    or (v_route_name = 'paid_plan' and v_plan = 'free')
  then
    v_validation_reason := 'compute_route_plan_mismatch';
  elsif coalesce((v_engine_config->>'compute_profile_routing_enabled')::boolean, false)
    and v_route_name in ('free_legacy', 'cancelled_plus_trial_free')
  then
    v_compute_profile := 'economy';
  end if;

  if v_validation_reason = 'compute_route_plan_mismatch' then
    v_compute_profile := 'premium';
  end if;
  if v_compute_profile = 'economy'
    and coalesce((v_engine_config->>'paid_flex_enabled')::boolean, false)
  then
    v_provider_pool := 'paid_flex';
    v_service_tier := 'flex';
  end if;

  v_routing := jsonb_build_object(
    'snapshot_version', 1,
    'ai_execution_route', v_route_name,
    'compute_profile', v_compute_profile,
    'compute_profile_version', coalesce(
      nullif(v_engine_config->>'compute_profile_version', ''),
      'compute-profile-v1'
    ),
    'provider_pool', v_provider_pool,
    'requested_service_tier', v_service_tier,
    'product_plan', coalesce(v_plan, 'free'),
    'first_paid_ai_eligible', coalesce(
      (p_compute_routing->>'first_paid_ai_eligible')::boolean,
      false
    ),
    'cancelled_plus_trial_free_candidate', coalesce(
      (p_compute_routing->>'cancelled_plus_trial_free_candidate')::boolean,
      false
    ),
    'cancelled_plus_trial_free_enabled', coalesce(
      (p_compute_routing->>'cancelled_plus_trial_free_enabled')::boolean,
      false
    ),
    'cancelled_plus_trial_routing_mode', left(
      coalesce(p_compute_routing->>'cancelled_plus_trial_routing_mode', ''),
      40
    ),
    'cancelled_plus_trial_routing_reason', left(
      coalesce(p_compute_routing->>'cancelled_plus_trial_routing_reason', ''),
      120
    ),
    'validation_reason', v_validation_reason,
    'source', case when v_snapshot_valid
      then 'trusted_analyze_enqueue'
      else 'safe_premium_fallback'
    end
  );

  update private.analysis_engine_routes
  set config_snapshot = jsonb_set(
    config_snapshot,
    '{compute_routing}',
    v_routing,
    true
  )
  where analysis_id = p_analysis_id and user_id = p_user_id
  returning * into v_route;

  return v_base || jsonb_build_object(
    'state', 'resolved',
    'config_snapshot', v_route.config_snapshot
  );
exception when others then
  return jsonb_build_object(
    'ok', false,
    'state', 'compute_route_resolution_failed'
  );
end;
$$;

create or replace function public.record_analysis_provider_attempt_v4(
  p_attempt_id uuid,
  p_user_id uuid,
  p_engine_run_id uuid,
  p_photo_run_id uuid,
  p_attempt_kind text,
  p_attempt_number integer,
  p_provider text,
  p_model text,
  p_state text,
  p_provider_request_id text,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_reasoning_tokens bigint,
  p_cached_input_tokens bigint,
  p_cost_usd numeric,
  p_duration_ms bigint,
  p_http_status integer,
  p_error_code text,
  p_compute_profile text,
  p_provider_pool text,
  p_requested_service_tier text,
  p_effective_service_tier text,
  p_standard_equivalent_cost_usd numeric,
  p_service_tier_fallback_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
begin
  select * into v_run
  from private.analysis_engine_runs
  where id = p_engine_run_id and user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_found');
  end if;

  insert into private.analysis_provider_attempts (
    id, engine_run_id, photo_run_id, analysis_id, user_id, attempt_kind,
    attempt_number, provider, model, state, provider_request_id, input_tokens,
    output_tokens, reasoning_tokens, cached_input_tokens, cost_usd, duration_ms,
    http_status, error_code, compute_profile, provider_pool,
    requested_service_tier, effective_service_tier,
    standard_equivalent_cost_usd, service_tier_fallback_reason, updated_at
  ) values (
    p_attempt_id, p_engine_run_id, p_photo_run_id, v_run.analysis_id,
    p_user_id, p_attempt_kind, greatest(coalesce(p_attempt_number, 1), 1),
    p_provider, p_model, p_state, left(nullif(p_provider_request_id, ''), 200),
    greatest(coalesce(p_input_tokens, 0), 0),
    greatest(coalesce(p_output_tokens, 0), 0),
    greatest(coalesce(p_reasoning_tokens, 0), 0),
    greatest(coalesce(p_cached_input_tokens, 0), 0),
    greatest(coalesce(p_cost_usd, 0), 0), p_duration_ms, p_http_status,
    left(nullif(p_error_code, ''), 160),
    case when p_compute_profile in ('premium', 'economy')
      then p_compute_profile else null end,
    case when p_provider_pool in ('paid_standard', 'paid_flex')
      then p_provider_pool else null end,
    case when p_requested_service_tier in ('standard', 'flex')
      then p_requested_service_tier else null end,
    case when p_effective_service_tier in ('standard', 'flex')
      then p_effective_service_tier else null end,
    greatest(coalesce(p_standard_equivalent_cost_usd, 0), 0),
    left(nullif(p_service_tier_fallback_reason, ''), 160), now()
  )
  on conflict (id) do update set
    photo_run_id = coalesce(
      excluded.photo_run_id,
      private.analysis_provider_attempts.photo_run_id
    ),
    state = excluded.state,
    provider_request_id = excluded.provider_request_id,
    input_tokens = excluded.input_tokens,
    output_tokens = excluded.output_tokens,
    reasoning_tokens = excluded.reasoning_tokens,
    cached_input_tokens = excluded.cached_input_tokens,
    cost_usd = excluded.cost_usd,
    duration_ms = excluded.duration_ms,
    http_status = excluded.http_status,
    error_code = excluded.error_code,
    compute_profile = coalesce(
      excluded.compute_profile,
      private.analysis_provider_attempts.compute_profile
    ),
    provider_pool = coalesce(
      excluded.provider_pool,
      private.analysis_provider_attempts.provider_pool
    ),
    requested_service_tier = coalesce(
      excluded.requested_service_tier,
      private.analysis_provider_attempts.requested_service_tier
    ),
    effective_service_tier = coalesce(
      excluded.effective_service_tier,
      private.analysis_provider_attempts.effective_service_tier
    ),
    standard_equivalent_cost_usd = excluded.standard_equivalent_cost_usd,
    service_tier_fallback_reason = coalesce(
      excluded.service_tier_fallback_reason,
      private.analysis_provider_attempts.service_tier_fallback_reason
    ),
    updated_at = now();

  return jsonb_build_object('ok', true, 'state', 'recorded');
exception when others then
  return jsonb_build_object('ok', false, 'state', 'attempt_record_failed');
end;
$$;

update private.analysis_engine_configs
set
  schema_version = 'hazard-fact-v3.5',
  prompt_version = 'vnext-photo-expert-v23',
  policy_version = 'semantic-risk-v24',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'compute_profile_version', 'compute-profile-v1',
    'compute_profile_routing_enabled', true,
    'paid_flex_enabled', true,
    'premium_thinking_optimization_enabled', true,
    'compact_provider_contract_enabled', true,
    'economy_standard_fallback_enabled', true,
    'compute_profiles', jsonb_build_object(
      'premium', jsonb_build_object(
        'primary_provider', 'gemini',
        'primary_model', 'gemini-2.5-flash',
        'fallback_provider', 'openai',
        'fallback_model', 'gpt-5.6-luna',
        'gemini_thinking_budget', 2048,
        'technical_retry_gemini_thinking_budget', 1536,
        'targeted_gemini_thinking_budget', 768,
        'max_provider_output_tokens', 8192,
        'targeted_max_provider_output_tokens', 3072,
        'openai_reasoning_effort', 'high'
      ),
      'economy', jsonb_build_object(
        'primary_provider', 'gemini',
        'primary_model', 'gemini-2.5-flash',
        'fallback_provider', 'gemini',
        'fallback_model', 'gemini-2.5-flash',
        'gemini_thinking_budget', 512,
        'technical_retry_gemini_thinking_budget', 256,
        'targeted_gemini_thinking_budget', 256,
        'max_provider_output_tokens', 6144,
        'targeted_max_provider_output_tokens', 2048,
        'openai_reasoning_effort', 'high'
      )
    ),
    'cost_telemetry_version', 2,
    'quality_trace_stage_version', 16
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

revoke all on function public.resolve_analysis_engine_route_v4(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.record_analysis_provider_attempt_v4(
  uuid, uuid, uuid, uuid, text, integer, text, text, text, text,
  bigint, bigint, bigint, bigint, numeric, bigint, integer, text,
  text, text, text, text, numeric, text
) from public, anon, authenticated;
grant execute on function public.resolve_analysis_engine_route_v4(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.record_analysis_provider_attempt_v4(
  uuid, uuid, uuid, uuid, text, integer, text, text, text, text,
  bigint, bigint, bigint, bigint, numeric, bigint, integer, text,
  text, text, text, text, numeric, text
) to service_role;

select pg_notify('pgrst', 'reload schema');
