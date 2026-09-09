-- Persist every physical v4 provider attempt with an authoritative prompt and
-- budget snapshot. Unlike v4, the function returns a bounded SQLSTATE reason
-- so the worker can fail closed instead of silently losing billed usage.
create or replace function public.record_analysis_provider_attempt_v5(
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
  p_service_tier_fallback_reason text,
  p_prompt_sha256 text,
  p_prompt_bundle_sha256 text,
  p_max_output_tokens integer
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
  where id=p_engine_run_id and user_id=p_user_id;
  if not found then
    return jsonb_build_object('ok',false,'state','engine_run_not_found');
  end if;

  insert into private.analysis_provider_attempts (
    id,engine_run_id,photo_run_id,analysis_id,user_id,attempt_kind,
    attempt_number,provider,model,state,provider_request_id,input_tokens,
    output_tokens,reasoning_tokens,cached_input_tokens,cost_usd,duration_ms,
    http_status,error_code,compute_profile,provider_pool,
    requested_service_tier,effective_service_tier,
    standard_equivalent_cost_usd,service_tier_fallback_reason,
    prompt_sha256,prompt_bundle_sha256,max_output_tokens,updated_at
  ) values (
    p_attempt_id,p_engine_run_id,p_photo_run_id,v_run.analysis_id,p_user_id,
    p_attempt_kind,greatest(coalesce(p_attempt_number,1),1),p_provider,p_model,
    p_state,left(nullif(p_provider_request_id,''),200),
    greatest(coalesce(p_input_tokens,0),0),
    greatest(coalesce(p_output_tokens,0),0),
    greatest(coalesce(p_reasoning_tokens,0),0),
    greatest(coalesce(p_cached_input_tokens,0),0),
    greatest(coalesce(p_cost_usd,0),0),p_duration_ms,p_http_status,
    left(nullif(p_error_code,''),160),
    case when p_compute_profile in ('premium','economy') then p_compute_profile end,
    case when p_provider_pool in ('paid_standard','paid_flex') then p_provider_pool end,
    case when p_requested_service_tier in ('standard','flex') then p_requested_service_tier end,
    case when p_effective_service_tier in ('standard','flex') then p_effective_service_tier end,
    greatest(coalesce(p_standard_equivalent_cost_usd,0),0),
    left(nullif(p_service_tier_fallback_reason,''),160),
    lower(nullif(p_prompt_sha256,'')),
    lower(nullif(p_prompt_bundle_sha256,'')),
    p_max_output_tokens,now()
  )
  on conflict (id) do update set
    photo_run_id=coalesce(excluded.photo_run_id,private.analysis_provider_attempts.photo_run_id),
    state=excluded.state,
    provider_request_id=excluded.provider_request_id,
    input_tokens=excluded.input_tokens,
    output_tokens=excluded.output_tokens,
    reasoning_tokens=excluded.reasoning_tokens,
    cached_input_tokens=excluded.cached_input_tokens,
    cost_usd=excluded.cost_usd,
    duration_ms=excluded.duration_ms,
    http_status=excluded.http_status,
    error_code=excluded.error_code,
    compute_profile=coalesce(excluded.compute_profile,private.analysis_provider_attempts.compute_profile),
    provider_pool=coalesce(excluded.provider_pool,private.analysis_provider_attempts.provider_pool),
    requested_service_tier=coalesce(excluded.requested_service_tier,private.analysis_provider_attempts.requested_service_tier),
    effective_service_tier=coalesce(excluded.effective_service_tier,private.analysis_provider_attempts.effective_service_tier),
    standard_equivalent_cost_usd=excluded.standard_equivalent_cost_usd,
    service_tier_fallback_reason=coalesce(excluded.service_tier_fallback_reason,private.analysis_provider_attempts.service_tier_fallback_reason),
    prompt_sha256=excluded.prompt_sha256,
    prompt_bundle_sha256=excluded.prompt_bundle_sha256,
    max_output_tokens=excluded.max_output_tokens,
    updated_at=now();

  return jsonb_build_object('ok',true,'state','recorded');
exception when others then
  return jsonb_build_object(
    'ok',false,
    'state','attempt_record_failed',
    'reason_code','sqlstate_' || sqlstate
  );
end;
$$;

revoke all on function public.record_analysis_provider_attempt_v5(
  uuid,uuid,uuid,uuid,text,integer,text,text,text,text,
  bigint,bigint,bigint,bigint,numeric,bigint,integer,text,
  text,text,text,text,numeric,text,text,text,integer
) from public,anon,authenticated;
grant execute on function public.record_analysis_provider_attempt_v5(
  uuid,uuid,uuid,uuid,text,integer,text,text,text,text,
  bigint,bigint,bigint,bigint,numeric,bigint,integer,text,
  text,text,text,text,numeric,text,text,text,integer
) to service_role;

update private.analysis_v4_configs
set prompt_version='v4-vision-core-v2',
    prompt_sha256='3fe0a08edd8465d2c052099b9ea7de2e789167f97e4325e0a9be7f1afdfd2a99',
    coverage_version='critical-coverage-v2',
    config=coalesce(config,'{}'::jsonb) || jsonb_build_object(
      'prompt_version','v4-vision-core-v2',
      'prompt_sha256','3fe0a08edd8465d2c052099b9ea7de2e789167f97e4325e0a9be7f1afdfd2a99',
      'prompt_bundle_sha256','3fe0a08edd8465d2c052099b9ea7de2e789167f97e4325e0a9be7f1afdfd2a99',
      'coverage_version','critical-coverage-v2',
      'coverage_repair_prompt_version',1,
      'deterministic_coverage_recovery_version',1,
      'provider_attempt_rpc_version',5
    ),
    integrity_status='valid',
    updated_at=now()
where is_active and engine_version='vnext-v4';

do $$
declare
  v_definition text;
  v_begin_definition text;
begin
  if not exists (
    select 1 from private.analysis_v4_configs
    where is_active and engine_version='vnext-v4'
      and prompt_version='v4-vision-core-v2'
  ) then
    raise exception 'active vnext-v4 config not found';
  end if;
  select pg_get_functiondef(
    'public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)'::regprocedure
  ) into v_definition;
  if position('v4-vision-core-v1' in v_definition)=0 then
    raise exception 'route v5 prompt guard baseline mismatch';
  end if;
  execute replace(
    v_definition,
    'v4-vision-core-v1',
    'v4-vision-core-v2'
  );
  select pg_get_functiondef(
    'public.begin_analysis_engine_run_v4(uuid,uuid,bigint,integer,uuid,text)'::regprocedure
  ) into v_begin_definition;
  if position('v4-vision-core-v1' in v_begin_definition)=0 then
    raise exception 'begin v4 prompt guard baseline mismatch';
  end if;
  execute replace(
    v_begin_definition,
    'v4-vision-core-v1',
    'v4-vision-core-v2'
  );
end;
$$;

select pg_notify('pgrst','reload schema');
