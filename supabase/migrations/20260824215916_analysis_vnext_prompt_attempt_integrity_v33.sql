-- Persist the exact rendered prompt identity and the actual generation ceiling
-- on every provider attempt. This migration is intentionally configuration
-- neutral so the compatible schema can land before the v27 worker is enabled.

alter table private.analysis_provider_attempts
  add column if not exists prompt_sha256 text,
  add column if not exists prompt_bundle_sha256 text,
  add column if not exists max_output_tokens integer;

alter table private.analysis_provider_attempts
  drop constraint if exists analysis_provider_attempts_prompt_sha256_check,
  add constraint analysis_provider_attempts_prompt_sha256_check
    check (prompt_sha256 is null or prompt_sha256 ~ '^[0-9a-f]{64}$'),
  drop constraint if exists analysis_provider_attempts_prompt_bundle_sha256_check,
  add constraint analysis_provider_attempts_prompt_bundle_sha256_check
    check (
      prompt_bundle_sha256 is null or
      prompt_bundle_sha256 ~ '^[0-9a-f]{64}$'
    ),
  drop constraint if exists analysis_provider_attempts_max_output_tokens_check,
  add constraint analysis_provider_attempts_max_output_tokens_check
    check (max_output_tokens is null or max_output_tokens between 1024 and 20480);

comment on column private.analysis_provider_attempts.prompt_sha256 is
  'SHA-256 of the exact rendered prompt sent in this attempt.';
comment on column private.analysis_provider_attempts.prompt_bundle_sha256 is
  'Versioned canonical prompt/schema bundle SHA-256 deployed by the worker.';
comment on column private.analysis_provider_attempts.max_output_tokens is
  'Provider generation ceiling; Gemini counts visible output plus thinking.';

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
    standard_equivalent_cost_usd, service_tier_fallback_reason,
    prompt_sha256, prompt_bundle_sha256, max_output_tokens, updated_at
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
    left(nullif(p_service_tier_fallback_reason, ''), 160),
    case when lower(coalesce(p_prompt_sha256, '')) ~ '^[0-9a-f]{64}$'
      then lower(p_prompt_sha256) else null end,
    case when lower(coalesce(p_prompt_bundle_sha256, '')) ~ '^[0-9a-f]{64}$'
      then lower(p_prompt_bundle_sha256) else null end,
    case when p_max_output_tokens between 1024 and 20480
      then p_max_output_tokens else null end,
    now()
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
    prompt_sha256 = coalesce(
      excluded.prompt_sha256,
      private.analysis_provider_attempts.prompt_sha256
    ),
    prompt_bundle_sha256 = coalesce(
      excluded.prompt_bundle_sha256,
      private.analysis_provider_attempts.prompt_bundle_sha256
    ),
    max_output_tokens = coalesce(
      excluded.max_output_tokens,
      private.analysis_provider_attempts.max_output_tokens
    ),
    updated_at = now();

  return jsonb_build_object('ok', true, 'state', 'recorded');
exception when others then
  return jsonb_build_object('ok', false, 'state', 'attempt_record_failed');
end;
$$;

revoke all on function public.record_analysis_provider_attempt_v5(
  uuid, uuid, uuid, uuid, text, integer, text, text, text, text,
  bigint, bigint, bigint, bigint, numeric, bigint, integer, text,
  text, text, text, text, numeric, text, text, text, integer
) from public, anon, authenticated;
grant execute on function public.record_analysis_provider_attempt_v5(
  uuid, uuid, uuid, uuid, text, integer, text, text, text, text,
  bigint, bigint, bigint, bigint, numeric, bigint, integer, text,
  text, text, text, text, numeric, text, text, text, integer
) to service_role;

select pg_notify('pgrst', 'reload schema');
