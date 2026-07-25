-- Analysis pipeline v2: atomic enqueue, leased worker claims, guarded terminal
-- writes, transactional finalization, and persistence-aware AI telemetry.
-- Production migration history version: 20260720100545.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.analyses
  add column if not exists failure_category text,
  add column if not exists failure_code text;

alter table public.analyses
  drop constraint if exists analyses_failure_category_check;
alter table public.analyses
  add constraint analyses_failure_category_check
  check (failure_category is null or failure_category in ('business', 'technical'));

create index if not exists analyses_failure_category_created_idx
  on public.analyses (failure_category, created_at desc)
  where status = 'failed';

-- The queue photo writer uses a deterministic sequence and needs a non-partial
-- conflict target so concurrent client retries can safely upsert metadata.
create unique index if not exists photos_analysis_sequence_v2_unique
  on public.photos (analysis_id, sequence_index);

alter table public.ai_usage_logs
  add column if not exists job_mode text,
  add column if not exists job_generation integer,
  add column if not exists worker_attempt integer,
  add column if not exists persistence_outcome text,
  add column if not exists persistence_error_code text,
  add column if not exists persistence_updated_at timestamptz;

alter table public.ai_usage_logs
  drop constraint if exists ai_usage_logs_job_mode_check;
alter table public.ai_usage_logs
  add constraint ai_usage_logs_job_mode_check
  check (job_mode is null or job_mode in ('analysis', 'repair'));

alter table public.ai_usage_logs
  drop constraint if exists ai_usage_logs_persistence_outcome_check;
alter table public.ai_usage_logs
  add constraint ai_usage_logs_persistence_outcome_check
  check (
    persistence_outcome is null
    or persistence_outcome in ('not_started', 'pending', 'persisted', 'failed', 'discarded')
  );

update public.ai_usage_logs
set persistence_outcome = case
      when error is null then 'persisted'
      else 'not_started'
    end,
    persistence_updated_at = coalesce(persistence_updated_at, created_at)
where persistence_outcome is null;

alter table public.ai_usage_logs
  alter column persistence_outcome set default 'not_started',
  alter column persistence_outcome set not null;

create index if not exists ai_usage_logs_persistence_pending_idx
  on public.ai_usage_logs (persistence_updated_at, created_at)
  where persistence_outcome = 'pending';

create index if not exists ai_usage_logs_job_analysis_idx
  on public.ai_usage_logs (analysis_id, job_generation, worker_attempt, created_at desc);

create table if not exists private.analysis_job_state (
  analysis_id uuid primary key references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  active_msg_id bigint,
  job_mode text not null default 'analysis'
    check (job_mode in ('analysis', 'repair')),
  generation integer not null default 1 check (generation > 0),
  claim_token uuid,
  claimed_at timestamptz,
  lease_expires_at timestamptz,
  worker_attempt_count integer not null default 0 check (worker_attempt_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, analysis_id)
);

revoke all on table private.analysis_job_state from public, anon, authenticated;
grant select, insert, update, delete on table private.analysis_job_state to service_role;

create index if not exists analysis_job_state_active_msg_idx
  on private.analysis_job_state (active_msg_id, generation)
  where active_msg_id is not null;
create index if not exists analysis_job_state_lease_idx
  on private.analysis_job_state (lease_expires_at)
  where claim_token is not null;

create or replace function private.tg_protect_completed_analysis_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status::text = 'completed' and new.status::text <> 'completed' then
    raise exception using
      errcode = '23514',
      message = 'completed_analysis_status_is_terminal';
  end if;
  return new;
end;
$$;

drop trigger if exists analyses_protect_completed_status on public.analyses;
create trigger analyses_protect_completed_status
  before update of status on public.analyses
  for each row
  execute function private.tg_protect_completed_analysis_status();

revoke all on function private.tg_protect_completed_analysis_status()
  from public, anon, authenticated;

create or replace function public.submit_analysis_job_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_message jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_generation integer;
  v_msg_id bigint;
  v_message jsonb;
begin
  if p_user_id is null or p_analysis_id is null or p_message is null then
    return jsonb_build_object('ok', false, 'code', 'validation_failed');
  end if;

  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'analysis_not_found');
  end if;

  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id
  for update;

  if v_analysis.status::text in ('queued', 'analyzing') then
    return jsonb_build_object(
      'ok', true,
      'state', v_analysis.status::text,
      'enqueued', false,
      'pipeline_version', case when v_state.analysis_id is null then 1 else 2 end,
      'msg_id', v_state.active_msg_id,
      'generation', v_state.generation
    );
  end if;

  if v_analysis.status::text = 'completed' then
    return jsonb_build_object(
      'ok', true,
      'state', 'completed',
      'enqueued', false,
      'pipeline_version', case when v_state.analysis_id is null then 1 else 2 end
    );
  end if;

  if v_analysis.status::text = 'failed' then
    return jsonb_build_object(
      'ok', false,
      'code', 'analysis_already_failed',
      'state', 'failed',
      'enqueued', false
    );
  end if;

  if v_analysis.status::text <> 'pending' then
    return jsonb_build_object(
      'ok', false,
      'code', 'analysis_status_not_submittable',
      'state', v_analysis.status::text
    );
  end if;

  v_generation := coalesce(v_state.generation + 1, 1);
  v_message := (
    p_message
      - 'pipeline_version'
      - '__job_generation'
      - '__worker_claim_token'
      - '__queue_msg_id'
      - '__worker_attempt'
  ) ||
    jsonb_build_object(
      'analysis_id', p_analysis_id::text,
      'user_id', p_user_id::text,
      'job_mode', 'analysis',
      'pipeline_version', 2,
      '__job_generation', v_generation
    );

  select * into v_msg_id
  from pgmq.send('analysis_jobs', v_message, 0);

  insert into private.analysis_job_state (
    analysis_id,
    user_id,
    active_msg_id,
    job_mode,
    generation,
    claim_token,
    claimed_at,
    lease_expires_at,
    worker_attempt_count,
    updated_at
  ) values (
    p_analysis_id,
    p_user_id,
    v_msg_id,
    'analysis',
    v_generation,
    null,
    null,
    null,
    0,
    now()
  )
  on conflict (analysis_id) do update set
    user_id = excluded.user_id,
    active_msg_id = excluded.active_msg_id,
    job_mode = excluded.job_mode,
    generation = excluded.generation,
    claim_token = null,
    claimed_at = null,
    lease_expires_at = null,
    worker_attempt_count = 0,
    updated_at = now();

  update public.analyses
  set status = 'queued',
      queued_at = now(),
      status_message = coalesce(
        nullif(p_message->>'queued_status_message', ''),
        'Analiz kuyruğa alındı.'
      ),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'queued',
    'enqueued', true,
    'pipeline_version', 2,
    'msg_id', v_msg_id,
    'generation', v_generation
  );
end;
$$;

create or replace function public.validate_analysis_job_claim_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case
    when a.id is null then jsonb_build_object('ok', false, 'state', 'analysis_not_found')
    when a.status::text = 'completed' then jsonb_build_object('ok', false, 'state', 'completed')
    when a.status::text = 'failed' then jsonb_build_object('ok', false, 'state', 'failed')
    when s.analysis_id is null then jsonb_build_object('ok', false, 'state', 'job_state_missing')
    when s.active_msg_id is distinct from p_msg_id
      or s.generation is distinct from p_generation
      then jsonb_build_object('ok', false, 'state', 'superseded')
    when s.claim_token is distinct from p_claim_token
      then jsonb_build_object('ok', false, 'state', 'lost_claim')
    when s.lease_expires_at is null or s.lease_expires_at <= now()
      then jsonb_build_object('ok', false, 'state', 'lease_expired')
    else jsonb_build_object(
      'ok', true,
      'state', 'claimed',
      'worker_attempt', s.worker_attempt_count,
      'job_mode', s.job_mode,
      'lease_expires_at', s.lease_expires_at
    )
  end
  from (select 1) seed
  left join public.analyses a
    on a.id = p_analysis_id and a.user_id = p_user_id
  left join private.analysis_job_state s
    on s.analysis_id = a.id and s.user_id = a.user_id;
$$;

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
  v_lease_seconds integer := greatest(30, least(coalesce(p_lease_seconds, 300), 900));
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

  if v_state.worker_attempt_count >= greatest(1, least(coalesce(p_max_attempts, 3), 10)) then
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

    return jsonb_build_object('ok', false, 'state', 'max_attempts');
  end if;

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
    'lease_seconds', v_lease_seconds,
    'lease_expires_at', now() + make_interval(secs => v_lease_seconds)
  );
end;
$$;

create or replace function public.defer_analysis_job_message_v2(
  p_msg_id bigint,
  p_visibility_timeout integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform * from pgmq.set_vt(
    'analysis_jobs',
    p_msg_id,
    greatest(1, least(coalesce(p_visibility_timeout, 30), 900))
  );
  return found;
end;
$$;

create or replace function public.record_analysis_job_failure_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_error text,
  p_failure_code text,
  p_status_message text,
  p_terminal boolean default false,
  p_raw_ai_response jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
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

  if p_terminal then
    update public.analyses
    set status = 'failed',
        status_message = coalesce(nullif(p_status_message, ''), 'Analiz tamamlanamadı.'),
        last_worker_error = left(coalesce(p_error, 'worker_failed'), 2000),
        failure_category = 'technical',
        failure_code = left(coalesce(nullif(p_failure_code, ''), 'worker_failed'), 120),
        raw_ai_response = coalesce(p_raw_ai_response, raw_ai_response)
    where id = p_analysis_id and user_id = p_user_id;

    delete from public.usage_events
    where user_id = p_user_id
      and source_id = p_analysis_id
      and feature in ('analysis_standard', 'analysis_detailed')
      and event_type = 'reserved';
  else
    update public.analyses
    set last_worker_error = left(coalesce(p_error, 'worker_retry'), 2000),
        failure_category = null,
        failure_code = null
    where id = p_analysis_id and user_id = p_user_id;
  end if;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', case when p_terminal then 'failed' else 'retry_pending' end,
    'worker_attempt', v_state.worker_attempt_count
  );
end;
$$;

create or replace function public.transition_analysis_to_repair_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_message jsonb,
  p_intermediate_raw_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_generation integer;
  v_msg_id bigint;
  v_message jsonb;
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

  v_generation := v_state.generation + 1;
  v_message := (
    p_message
      - 'pipeline_version'
      - '__job_generation'
      - '__worker_claim_token'
      - '__queue_msg_id'
      - '__worker_attempt'
  ) ||
    jsonb_build_object(
      'analysis_id', p_analysis_id::text,
      'user_id', p_user_id::text,
      'job_mode', 'repair',
      'pipeline_version', 2,
      '__job_generation', v_generation
    );

  select * into v_msg_id
  from pgmq.send('analysis_jobs', v_message, 0);

  update private.analysis_job_state
  set active_msg_id = v_msg_id,
      job_mode = 'repair',
      generation = v_generation,
      claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  update public.analyses
  set status = 'queued',
      queued_at = now(),
      status_message = coalesce(
        nullif(p_message->>'queued_status_message', ''),
        'Analiz kapsamı ikinci taramaya alındı.'
      ),
      raw_ai_response = coalesce(p_intermediate_raw_response, raw_ai_response),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'repair_queued',
    'msg_id', v_msg_id,
    'generation', v_generation
  );
end;
$$;

create or replace function public.finalize_analysis_result_v2(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_findings jsonb,
  p_analysis_result jsonb,
  p_photo_summaries jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_analysis public.analyses%rowtype;
  v_state private.analysis_job_state%rowtype;
  v_finding jsonb;
  v_summary jsonb;
  v_source_indices integer[];
  v_inserted integer := 0;
begin
  select * into v_analysis
  from public.analyses
  where id = p_analysis_id and user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;
  if v_analysis.status::text = 'completed' then
    return jsonb_build_object(
      'ok', true,
      'state', 'already_completed',
      'finding_count', v_analysis.finding_count
    );
  end if;

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

  delete from public.findings
  where analysis_id = p_analysis_id
    and user_id = p_user_id
    and origin = 'ai';

  for v_finding in
    select value from jsonb_array_elements(coalesce(p_findings, '[]'::jsonb))
  loop
    select coalesce(array_agg(value::integer), '{}'::integer[])
      into v_source_indices
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(v_finding->'source_photo_indices') = 'array'
          then v_finding->'source_photo_indices'
        else '[]'::jsonb
      end
    );

    insert into public.findings (
      analysis_id,
      user_id,
      ordinal,
      title,
      category,
      description,
      recommended_action,
      recommended_measures,
      references_text,
      root_cause_text,
      confidence,
      needs_field_verification,
      origin,
      ai_original_snapshot,
      source_photo_indices,
      source_photo_observations,
      finding_budget_policy,
      ai_confidence,
      fk_probability,
      fk_frequency,
      fk_severity,
      fk_band,
      m5_probability,
      m5_severity,
      m5_band,
      display_order
    ) values (
      p_analysis_id,
      p_user_id,
      (v_finding->>'ordinal')::integer,
      v_finding->>'title',
      v_finding->>'category',
      v_finding->>'description',
      v_finding->>'recommended_action',
      coalesce(v_finding->'recommended_measures', '[]'::jsonb),
      v_finding->>'references_text',
      v_finding->>'root_cause_text',
      coalesce((v_finding->>'confidence')::numeric, 0),
      coalesce((v_finding->>'needs_field_verification')::boolean, false),
      'ai',
      v_finding->'ai_original_snapshot',
      v_source_indices,
      v_finding->'source_photo_observations',
      v_finding->'finding_budget_policy',
      nullif(v_finding->>'ai_confidence', '')::numeric,
      (v_finding->>'fk_probability')::numeric,
      (v_finding->>'fk_frequency')::numeric,
      (v_finding->>'fk_severity')::numeric,
      (v_finding->>'fk_band')::public.risk_level,
      (v_finding->>'m5_probability')::integer,
      (v_finding->>'m5_severity')::integer,
      (v_finding->>'m5_band')::public.risk_level,
      (v_finding->>'display_order')::integer
    );
    v_inserted := v_inserted + 1;
  end loop;

  update public.analyses
  set status = 'completed',
      status_message = p_analysis_result->>'status_message',
      completed_at = now(),
      ai_summary = p_analysis_result->>'ai_summary',
      total_score_fk = nullif(p_analysis_result->>'total_score_fk', '')::numeric,
      total_score_m5 = nullif(p_analysis_result->>'total_score_m5', '')::integer,
      highest_band_fk = nullif(p_analysis_result->>'highest_band_fk', '')::public.risk_level,
      highest_band_m5 = nullif(p_analysis_result->>'highest_band_m5', '')::public.risk_level,
      finding_count = v_inserted,
      generated_findings_count = v_inserted,
      visible_findings_count = v_inserted,
      hidden_or_rejected_findings_count = coalesce(
        nullif(p_analysis_result->>'hidden_or_rejected_findings_count', '')::integer,
        0
      ),
      max_findings_per_photo = coalesce(
        nullif(p_analysis_result->>'max_findings_per_photo', '')::integer,
        max_findings_per_photo
      ),
      max_findings_total = nullif(p_analysis_result->>'max_findings_total', '')::integer,
      raw_ai_response = p_analysis_result->'raw_ai_response',
      ai_models_used = array(
        select jsonb_array_elements_text(
          coalesce(p_analysis_result->'ai_models_used', '[]'::jsonb)
        )
      ),
      last_worker_error = null,
      failure_category = null,
      failure_code = null
  where id = p_analysis_id and user_id = p_user_id;

  update public.usage_events
  set event_type = 'completed'
  where user_id = p_user_id
    and source_id = p_analysis_id
    and feature in ('analysis_standard', 'analysis_detailed')
    and event_type = 'reserved';

  begin
    for v_summary in
      select value
      from jsonb_array_elements(coalesce(p_photo_summaries, '[]'::jsonb))
    loop
      insert into public.analysis_photo_summaries (
        analysis_id,
        user_id,
        photo_id,
        photo_sequence_index,
        scene_summary,
        candidate_findings_count,
        generated_findings_count,
        highest_risk_level,
        ai_confidence,
        coverage_status,
        coverage_gap_reason,
        target_findings_min,
        target_findings_max,
        raw_summary
      ) values (
        p_analysis_id,
        p_user_id,
        nullif(v_summary->>'photo_id', '')::uuid,
        (v_summary->>'photo_sequence_index')::integer,
        v_summary->>'scene_summary',
        coalesce(nullif(v_summary->>'candidate_findings_count', '')::integer, 0),
        coalesce(nullif(v_summary->>'generated_findings_count', '')::integer, 0),
        v_summary->>'highest_risk_level',
        nullif(v_summary->>'ai_confidence', '')::numeric,
        v_summary->>'coverage_status',
        v_summary->>'coverage_gap_reason',
        nullif(v_summary->>'target_findings_min', '')::integer,
        nullif(v_summary->>'target_findings_max', '')::integer,
        v_summary->'raw_summary'
      )
      on conflict (analysis_id, photo_sequence_index) do update set
        user_id = excluded.user_id,
        photo_id = excluded.photo_id,
        scene_summary = excluded.scene_summary,
        candidate_findings_count = excluded.candidate_findings_count,
        generated_findings_count = excluded.generated_findings_count,
        highest_risk_level = excluded.highest_risk_level,
        ai_confidence = excluded.ai_confidence,
        coverage_status = excluded.coverage_status,
        coverage_gap_reason = excluded.coverage_gap_reason,
        target_findings_min = excluded.target_findings_min,
        target_findings_max = excluded.target_findings_max,
        raw_summary = excluded.raw_summary;
    end loop;
  exception when others then
    raise warning 'analysis_photo_summaries skipped for analysis %: %',
      p_analysis_id, sqlerrm;
  end;

  update private.analysis_job_state
  set claim_token = null,
      claimed_at = null,
      lease_expires_at = null,
      updated_at = now()
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'completed',
    'finding_count', v_inserted
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
    )
  );
$$;

insert into public.app_feature_flags (key, value)
values (
  'analysis_pipeline_v2',
  jsonb_build_object(
    'rollout_mode', 'off',
    'enabled_user_hashes', jsonb_build_array(),
    'lease_seconds', 300,
    'max_worker_attempts', 3
  )
)
on conflict (key) do nothing;

revoke all on function public.submit_analysis_job_v2(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.validate_analysis_job_claim_v2(uuid, uuid, bigint, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.claim_analysis_job_v2(uuid, uuid, bigint, integer, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.defer_analysis_job_message_v2(bigint, integer)
  from public, anon, authenticated;
revoke all on function public.record_analysis_job_failure_v2(uuid, uuid, bigint, integer, uuid, text, text, text, boolean, jsonb)
  from public, anon, authenticated;
revoke all on function public.transition_analysis_to_repair_v2(uuid, uuid, bigint, integer, uuid, jsonb, jsonb)
  from public, anon, authenticated;
revoke all on function public.finalize_analysis_result_v2(uuid, uuid, bigint, integer, uuid, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
revoke all on function public.admin_analysis_pipeline_metrics_v2()
  from public, anon, authenticated;

grant execute on function public.submit_analysis_job_v2(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.validate_analysis_job_claim_v2(uuid, uuid, bigint, integer, uuid)
  to service_role;
grant execute on function public.claim_analysis_job_v2(uuid, uuid, bigint, integer, text, integer, integer)
  to service_role;
grant execute on function public.defer_analysis_job_message_v2(bigint, integer)
  to service_role;
grant execute on function public.record_analysis_job_failure_v2(uuid, uuid, bigint, integer, uuid, text, text, text, boolean, jsonb)
  to service_role;
grant execute on function public.transition_analysis_to_repair_v2(uuid, uuid, bigint, integer, uuid, jsonb, jsonb)
  to service_role;
grant execute on function public.finalize_analysis_result_v2(uuid, uuid, bigint, integer, uuid, jsonb, jsonb, jsonb)
  to service_role;
grant execute on function public.admin_analysis_pipeline_metrics_v2()
  to service_role;

select pg_notify('pgrst', 'reload schema');
