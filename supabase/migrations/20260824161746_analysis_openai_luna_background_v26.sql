-- Luna-only asynchronous Responses transport. Gemini and non-Luna OpenAI
-- routes keep their existing synchronous behavior. The active config flag is
-- deliberately independent so this experiment can be disabled without a
-- client release or schema rollback.

create table if not exists private.analysis_openai_background_responses (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null
    references private.analysis_engine_runs(id) on delete cascade,
  photo_run_id uuid not null
    references private.analysis_photo_runs(id) on delete cascade,
  analysis_id uuid not null
    references public.analyses(id) on delete cascade,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  phase text not null check (phase in ('primary', 'targeted')),
  logical_key text not null check (
    length(logical_key) between 1 and 240
  ),
  attempt_id uuid not null default gen_random_uuid(),
  attempt_kind text not null check (
    attempt_kind in (
      'primary', 'technical_retry', 'schema_repair',
      'provider_fallback', 'targeted_reinspection'
    )
  ),
  attempt_number integer not null default 1 check (attempt_number > 0),
  model text not null,
  prompt_sha256 text not null check (length(prompt_sha256) = 64),
  provider_request_id text,
  provider_status text not null default 'creating' check (
    provider_status in (
      'creating', 'queued', 'in_progress', 'completed', 'failed',
      'cancelled', 'incomplete', 'expired'
    )
  ),
  poll_count integer not null default 0 check (poll_count >= 0),
  last_http_status integer,
  last_duration_ms bigint,
  error_code text,
  submitted_at timestamptz,
  last_polled_at timestamptz,
  expires_at timestamptz,
  terminal_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (engine_run_id, phase, logical_key),
  unique (attempt_id),
  unique (provider_request_id)
);

create index if not exists analysis_openai_background_pending_idx
  on private.analysis_openai_background_responses (
    provider_status, last_polled_at, created_at
  )
  where provider_status in ('creating', 'queued', 'in_progress');

alter table private.analysis_openai_background_responses
  enable row level security;
revoke all on table private.analysis_openai_background_responses
  from public, anon, authenticated;
grant select, insert, update, delete
  on table private.analysis_openai_background_responses to service_role;

create or replace function public.begin_analysis_openai_background_v1(
  p_user_id uuid,
  p_engine_run_id uuid,
  p_photo_run_id uuid,
  p_phase text,
  p_logical_key text,
  p_attempt_kind text,
  p_attempt_number integer,
  p_model text,
  p_prompt_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
  v_photo private.analysis_photo_runs%rowtype;
  v_background private.analysis_openai_background_responses%rowtype;
  v_created boolean := false;
begin
  select * into v_run
  from private.analysis_engine_runs
  where id = p_engine_run_id and user_id = p_user_id
  for update;
  if not found or v_run.status <> 'running' then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_running');
  end if;

  select * into v_photo
  from private.analysis_photo_runs
  where id = p_photo_run_id
    and engine_run_id = p_engine_run_id
    and user_id = p_user_id;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'photo_run_not_found');
  end if;
  if p_phase not in ('primary', 'targeted')
    or p_attempt_kind not in (
      'primary', 'technical_retry', 'schema_repair',
      'provider_fallback', 'targeted_reinspection'
    )
    or nullif(left(coalesce(p_logical_key, ''), 240), '') is null
    or p_model <> 'gpt-5.6-luna'
    or coalesce(p_prompt_sha256, '') !~ '^[0-9a-f]{64}$'
  then
    return jsonb_build_object('ok', false, 'state', 'background_contract_invalid');
  end if;

  select * into v_background
  from private.analysis_openai_background_responses b
  where b.engine_run_id = p_engine_run_id
    and b.phase = p_phase
    and b.logical_key = left(p_logical_key, 240)
  for update;

  if not found then
    insert into private.analysis_openai_background_responses (
      engine_run_id, photo_run_id, analysis_id, user_id, phase, logical_key,
      attempt_kind, attempt_number, model, prompt_sha256
    ) values (
      p_engine_run_id, p_photo_run_id, v_run.analysis_id, p_user_id,
      p_phase, left(p_logical_key, 240), p_attempt_kind,
      greatest(coalesce(p_attempt_number, 1), 1), p_model, p_prompt_sha256
    )
    returning * into v_background;
    v_created := true;
  elsif v_background.photo_run_id <> p_photo_run_id
    or v_background.model <> p_model
    or v_background.prompt_sha256 <> p_prompt_sha256
    or v_background.attempt_kind <> p_attempt_kind
  then
    return jsonb_build_object('ok', false, 'state', 'background_contract_mismatch');
  end if;

  if (
      v_background.provider_status = 'creating'
      and v_background.provider_request_id is null
      and v_background.created_at + interval '2 minutes' <= now()
    ) or (
      v_background.provider_status in ('queued', 'in_progress')
      and v_background.expires_at is not null
      and v_background.expires_at <= now()
    )
  then
    update private.analysis_openai_background_responses
    set provider_status = 'expired',
        error_code = 'provider_background_expired',
        terminal_at = now(),
        updated_at = now()
    where id = v_background.id
    returning * into v_background;
  end if;

  return jsonb_build_object(
    'ok', true,
    'state', case when v_created then 'created' else 'found' end,
    'background_id', v_background.id,
    'attempt_id', v_background.attempt_id,
    'attempt_number', v_background.attempt_number,
    'provider_request_id', v_background.provider_request_id,
    'provider_status', v_background.provider_status,
    'submitted_at', v_background.submitted_at,
    'expires_at', v_background.expires_at,
    'poll_count', v_background.poll_count,
    'error_code', v_background.error_code
  );
end;
$$;

create or replace function public.checkpoint_analysis_openai_background_v1(
  p_user_id uuid,
  p_background_id uuid,
  p_provider_request_id text,
  p_provider_status text,
  p_http_status integer default null,
  p_duration_ms bigint default null,
  p_error_code text default null,
  p_polled boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_background private.analysis_openai_background_responses%rowtype;
  v_request_id text := nullif(left(coalesce(p_provider_request_id, ''), 200), '');
  v_status text := lower(coalesce(p_provider_status, ''));
begin
  select * into v_background
  from private.analysis_openai_background_responses
  where id = p_background_id and user_id = p_user_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'background_not_found');
  end if;
  if v_status not in (
    'creating', 'queued', 'in_progress', 'completed', 'failed',
    'cancelled', 'incomplete', 'expired'
  ) then
    return jsonb_build_object('ok', false, 'state', 'background_status_invalid');
  end if;
  if v_request_id is not null and v_request_id !~ '^resp_[A-Za-z0-9_-]+$' then
    return jsonb_build_object('ok', false, 'state', 'background_response_id_invalid');
  end if;
  if v_background.provider_request_id is not null
    and v_request_id is not null
    and v_background.provider_request_id <> v_request_id
  then
    return jsonb_build_object('ok', false, 'state', 'background_response_id_mismatch');
  end if;

  update private.analysis_openai_background_responses
  set provider_request_id = coalesce(provider_request_id, v_request_id),
      provider_status = v_status,
      poll_count = poll_count + case when p_polled then 1 else 0 end,
      last_http_status = p_http_status,
      last_duration_ms = p_duration_ms,
      error_code = left(nullif(coalesce(p_error_code, ''), ''), 160),
      submitted_at = case
        when submitted_at is null and v_request_id is not null then now()
        else submitted_at
      end,
      last_polled_at = case when p_polled then now() else last_polled_at end,
      expires_at = case
        when expires_at is null and v_request_id is not null
          then now() + interval '8 minutes'
        else expires_at
      end,
      terminal_at = case
        when v_status in ('completed', 'failed', 'cancelled', 'incomplete', 'expired')
          then coalesce(terminal_at, now())
        else null
      end,
      updated_at = now()
  where id = p_background_id
  returning * into v_background;

  return jsonb_build_object(
    'ok', true,
    'state', 'checkpointed',
    'background_id', v_background.id,
    'attempt_id', v_background.attempt_id,
    'provider_request_id', v_background.provider_request_id,
    'provider_status', v_background.provider_status,
    'submitted_at', v_background.submitted_at,
    'expires_at', v_background.expires_at,
    'poll_count', v_background.poll_count
  );
exception when unique_violation then
  return jsonb_build_object('ok', false, 'state', 'background_response_id_already_used');
end;
$$;

-- A background poll is progress, not a worker failure. Release the lease and
-- neutralize the claim increment so the ordinary three-failure budget remains
-- available for actual application/transport failures.
create or replace function public.release_analysis_job_background_wait_v1(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state private.analysis_job_state%rowtype;
begin
  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;
  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      worker_attempt_count = greatest(worker_attempt_count - 1, 0),
      updated_at = now()
  where analysis_id = p_analysis_id and user_id = p_user_id;

  update public.analyses
  set status = 'analyzing',
      status_message = 'Analiz yüksek doğrulukla işleniyor.',
      worker_attempt_count = greatest(worker_attempt_count - 1, 0),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id
    and user_id = p_user_id
    and status::text not in ('completed', 'failed');

  return jsonb_build_object(
    'ok', true,
    'state', 'background_wait_released',
    'worker_attempt', greatest(v_state.worker_attempt_count - 1, 0)
  );
end;
$$;

revoke all on function public.begin_analysis_openai_background_v1(
  uuid, uuid, uuid, text, text, text, integer, text, text
) from public, anon, authenticated;
revoke all on function public.checkpoint_analysis_openai_background_v1(
  uuid, uuid, text, text, integer, bigint, text, boolean
) from public, anon, authenticated;
revoke all on function public.release_analysis_job_background_wait_v1(
  uuid, uuid, bigint, integer, uuid
) from public, anon, authenticated;

grant execute on function public.begin_analysis_openai_background_v1(
  uuid, uuid, uuid, text, text, text, integer, text, text
) to service_role;
grant execute on function public.checkpoint_analysis_openai_background_v1(
  uuid, uuid, text, text, integer, bigint, text, boolean
) to service_role;
grant execute on function public.release_analysis_job_background_wait_v1(
  uuid, uuid, bigint, integer, uuid
) to service_role;

update private.analysis_engine_configs
set config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
  'openai_luna_background_enabled', true,
  'openai_luna_background_version', 'openai-luna-background-v1',
  'openai_luna_background_poll_seconds', 15,
  'quality_trace_stage_version', 17
)
where is_active;
