-- Prevent ambiguous nested Edge Function transport failures from releasing an
-- active analysis claim. Queue messages opt in with claim_guard_version = 2.

create table if not exists private.analysis_job_events (
  id bigint generated always as identity primary key,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  msg_id bigint not null,
  job_generation integer not null check (job_generation > 0),
  worker_attempt integer not null check (worker_attempt > 0),
  job_mode text not null check (job_mode in ('analysis', 'repair')),
  event_type text not null check (
    event_type in (
      'claim_acquired',
      'dispatch_success_response',
      'dispatch_application_error',
      'dispatch_ambiguous_transport',
      'claim_kept',
      'claim_released_for_retry',
      'terminal_failed',
      'repair_superseded',
      'finalized',
      'message_deleted_after_response_loss',
      'lease_expired_retry',
      'max_attempts'
    )
  ),
  http_status integer check (
    http_status is null or (http_status between 100 and 599)
  ),
  response_code text,
  claim_action text,
  safe_error_text varchar(500),
  created_at timestamptz not null default now()
);

alter table private.analysis_job_events enable row level security;

revoke all on table private.analysis_job_events
  from public, anon, authenticated;
grant select, insert, update, delete on table private.analysis_job_events
  to service_role;

revoke all on sequence private.analysis_job_events_id_seq
  from public, anon, authenticated;
grant usage, select on sequence private.analysis_job_events_id_seq
  to service_role;

create index if not exists analysis_job_events_analysis_created_idx
  on private.analysis_job_events (analysis_id, created_at desc);
create index if not exists analysis_job_events_type_created_idx
  on private.analysis_job_events (event_type, created_at desc);
create index if not exists analysis_job_events_attempt_idx
  on private.analysis_job_events (
    analysis_id,
    job_generation,
    worker_attempt,
    created_at
  );

create or replace function public.record_analysis_job_event_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_worker_attempt integer,
  p_job_mode text,
  p_event_type text,
  p_http_status integer default null,
  p_response_code text default null,
  p_claim_action text default null,
  p_safe_error_text text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_safe_error text;
begin
  if not exists (
    select 1
    from public.analyses a
    where a.id = p_analysis_id
      and a.user_id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;

  if p_msg_id is null
    or p_generation is null or p_generation <= 0
    or p_worker_attempt is null or p_worker_attempt <= 0
    or p_job_mode not in ('analysis', 'repair')
    or p_event_type not in (
      'claim_acquired',
      'dispatch_success_response',
      'dispatch_application_error',
      'dispatch_ambiguous_transport',
      'claim_kept',
      'claim_released_for_retry',
      'terminal_failed',
      'repair_superseded',
      'finalized',
      'message_deleted_after_response_loss',
      'lease_expired_retry',
      'max_attempts'
    )
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;

  v_safe_error := nullif(
    left(
      regexp_replace(
        coalesce(p_safe_error_text, ''),
        'Bearer[[:space:]]+[^[:space:]]+',
        'Bearer [redacted]',
        'gi'
      ),
      500
    ),
    ''
  );

  insert into private.analysis_job_events (
    analysis_id,
    user_id,
    msg_id,
    job_generation,
    worker_attempt,
    job_mode,
    event_type,
    http_status,
    response_code,
    claim_action,
    safe_error_text
  ) values (
    p_analysis_id,
    p_user_id,
    p_msg_id,
    p_generation,
    p_worker_attempt,
    p_job_mode,
    p_event_type,
    case
      when p_http_status between 100 and 599 then p_http_status
      else null
    end,
    left(nullif(p_response_code, ''), 120),
    left(nullif(p_claim_action, ''), 80),
    v_safe_error
  );

  return jsonb_build_object('ok', true, 'state', 'recorded');
exception when others then
  -- Telemetry must never change queue or analysis correctness.
  return jsonb_build_object('ok', false, 'state', 'event_record_failed');
end;
$$;

-- Include why a successful claim was granted so lease-expiry retries can be
-- distinguished from explicit, controlled retry releases.
create or replace function public.claim_analysis_job_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_job_mode text,
  p_lease_seconds integer default 300,
  p_max_attempts integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_token uuid;
  v_attempt integer;
  v_claim_reason text;
  v_lease_seconds integer := greatest(
    30,
    least(coalesce(p_lease_seconds, 300), 900)
  );
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object('ok', false, 'state', 'completed');
  end if;
  if v_analysis.status::text = 'failed' then
    return jsonb_build_object('ok', false, 'state', 'failed');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'job_state_missing');
  end if;
  if v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.job_mode is distinct from (
      case when p_job_mode = 'repair' then 'repair' else 'analysis' end
    )
  then
    return jsonb_build_object('ok', false, 'state', 'superseded');
  end if;

  if v_state.claim_token is not null
    and v_state.lease_expires_at is not null
    and v_state.lease_expires_at > now()
  then
    return jsonb_build_object(
      'ok', false,
      'state', 'busy',
      'retry_after_seconds', greatest(
        1,
        ceil(extract(epoch from (v_state.lease_expires_at - now())))::integer
      ),
      'worker_attempt', v_state.worker_attempt_count
    );
  end if;

  if v_state.worker_attempt_count >= greatest(
    1,
    least(coalesce(p_max_attempts, 3), 10)
  ) then
    update public.analyses
    set status = 'failed',
        status_message = 'Analiz arka planda tamamlanamadı. Lütfen tekrar dene.',
        last_worker_error = 'worker_attempts_exhausted',
        failure_category = 'technical',
        failure_code = 'worker_attempts_exhausted'
    where id = p_analysis_id and user_id = p_user_id;

    delete from public.usage_events
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';

    update private.analysis_job_state
    set claim_token = null,
        claimed_at = null,
        lease_expires_at = null,
        updated_at = now()
    where analysis_id = p_analysis_id;

    return jsonb_build_object(
      'ok', false,
      'state', 'max_attempts',
      'worker_attempt', v_state.worker_attempt_count
    );
  end if;

  v_claim_reason := case
    when v_state.worker_attempt_count = 0 then 'initial'
    when v_state.claim_token is not null
      and v_state.lease_expires_at is not null
      and v_state.lease_expires_at <= now()
      then 'lease_expired'
    else 'released_retry'
  end;
  v_token := gen_random_uuid();
  v_attempt := v_state.worker_attempt_count + 1;

  update private.analysis_job_state
  set claim_token = v_token,
      claimed_at = now(),
      lease_expires_at = now() + make_interval(secs => v_lease_seconds),
      worker_attempt_count = v_attempt,
      updated_at = now()
  where analysis_id = p_analysis_id;

  update public.analyses
  set status = 'analyzing',
      started_at = coalesce(started_at, now()),
      worker_started_at = now(),
      worker_attempt_count = v_attempt,
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'claimed',
    'claim_token', v_token,
    'worker_attempt', v_attempt,
    'claim_reason', v_claim_reason,
    'lease_seconds', v_lease_seconds,
    'lease_expires_at', now() + make_interval(secs => v_lease_seconds)
  );
end;
$$;

create or replace function public.admin_analysis_pipeline_metrics_v2()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'queue_depth', (select count(*) from pgmq.q_analysis_jobs),
    'queued_analyses', (
      select count(*) from public.analyses where status::text = 'queued'
    ),
    'analyzing_analyses', (
      select count(*) from public.analyses where status::text = 'analyzing'
    ),
    'expired_analysis_leases', (
      select count(*)
      from private.analysis_job_state
      where claim_token is not null and lease_expires_at <= now()
    ),
    'abandoned_pending_drafts', (
      select count(*)
      from public.analyses
      where status::text = 'pending'
        and photo_count = 0
        and queued_at is null
        and worker_started_at is null
        and created_at < now() - interval '24 hours'
    ),
    'failed_analyses_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and (failure_category = 'technical' or failure_category is null)
    ),
    'business_rejections_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and failure_category = 'business'
    ),
    'persistence_pending_over_5m', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'pending'
        and persistence_updated_at < now() - interval '5 minutes'
    ),
    'ambiguous_dispatches_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'dispatch_ambiguous_transport'
        and created_at >= now() - interval '24 hours'
    ),
    'ambiguous_then_first_attempt_completed_24h', (
      select count(distinct (a.analysis_id, a.job_generation, a.worker_attempt))
      from private.analysis_job_events a
      where a.event_type = 'dispatch_ambiguous_transport'
        and a.created_at >= now() - interval '24 hours'
        and exists (
          select 1
          from private.analysis_job_events f
          where f.analysis_id = a.analysis_id
            and f.job_generation = a.job_generation
            and f.worker_attempt = a.worker_attempt
            and f.event_type = 'finalized'
            and f.created_at >= a.created_at
        )
    ),
    'lease_expiry_retries_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'lease_expired_retry'
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_multiple_successful_ai_calls_24h', (
      select count(*)
      from (
        select analysis_id
        from public.ai_usage_logs
        where analysis_id is not null
          and error is null
          and created_at >= now() - interval '24 hours'
        group by analysis_id
        having count(*) > 1
      ) duplicated_successes
    ),
    'discarded_lost_claim_24h', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'discarded'
        and persistence_error_code = 'lost_claim'
        and created_at >= now() - interval '24 hours'
    )
  );
$$;

insert into public.app_feature_flags (key, value)
values (
  'analysis_ambiguous_dispatch_guard',
  jsonb_build_object(
    'rollout_mode', 'off',
    'enabled_user_hashes', jsonb_build_array()
  )
)
on conflict (key) do nothing;

revoke all on function public.record_analysis_job_event_v2(
  uuid,
  uuid,
  bigint,
  integer,
  integer,
  text,
  text,
  integer,
  text,
  text,
  text
) from public, anon, authenticated;
revoke all on function public.claim_analysis_job_v2(
  uuid,
  uuid,
  bigint,
  integer,
  text,
  integer,
  integer
) from public, anon, authenticated;
revoke all on function public.admin_analysis_pipeline_metrics_v2()
  from public, anon, authenticated;

grant execute on function public.record_analysis_job_event_v2(
  uuid,
  uuid,
  bigint,
  integer,
  integer,
  text,
  text,
  integer,
  text,
  text,
  text
) to service_role;
grant execute on function public.claim_analysis_job_v2(
  uuid,
  uuid,
  bigint,
  integer,
  text,
  integer,
  integer
) to service_role;
grant execute on function public.admin_analysis_pipeline_metrics_v2()
  to service_role;
