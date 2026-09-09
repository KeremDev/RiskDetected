-- Unify analysis telemetry without copying v4 provider attempts into the
-- legacy public.ai_usage_logs ledger. The private v4 run/attempt tables remain
-- authoritative, while admin consumers receive one compatible rollup.

create or replace function private.analysis_usage_rollup_v1(
  p_from timestamptz,
  p_to timestamptz,
  p_analysis_ids uuid[]
)
returns table (
  analysis_id uuid,
  user_id uuid,
  client_platform text,
  provider text,
  model text,
  usage_rows bigint,
  provider_calls bigint,
  tokens_in bigint,
  tokens_out bigint,
  reasoning_tokens bigint,
  total_tokens bigint,
  provider_attempt_total_tokens bigint,
  duration_ms bigint,
  provider_errors bigint,
  estimated_cost_usd numeric,
  measured_at timestamptz,
  telemetry_source text
)
language sql
stable
security definer
set search_path = ''
as $$
with v4_runs as (
  select r.*
  from private.analysis_engine_runs r
  where r.engine_version = 'vnext-v4'
    and (p_from is null or coalesce(r.completed_at, r.updated_at, r.started_at) >= p_from)
    and (p_to is null or coalesce(r.completed_at, r.updated_at, r.started_at) < p_to)
    and (p_analysis_ids is null or r.analysis_id = any(p_analysis_ids))
),
v4_run_totals as (
  select
    r.analysis_id,
    r.user_id,
    case when count(distinct nullif(r.provider, '')) = 1
      then min(nullif(r.provider, '')) else 'mixed' end as provider,
    case when count(distinct nullif(r.model, '')) = 1
      then min(nullif(r.model, '')) else 'mixed' end as model,
    coalesce(sum(r.duration_ms), 0)::bigint as duration_ms,
    max(coalesce(r.completed_at, r.updated_at, r.started_at)) as measured_at
  from v4_runs r
  group by r.analysis_id, r.user_id
),
v4_attempt_totals as (
  select
    r.analysis_id,
    count(a.id)::bigint as usage_rows,
    count(a.id)::bigint as provider_calls,
    coalesce(sum(a.input_tokens), 0)::bigint as tokens_in,
    coalesce(sum(a.output_tokens), 0)::bigint as tokens_out,
    coalesce(sum(a.reasoning_tokens), 0)::bigint as reasoning_tokens,
    coalesce(sum(a.input_tokens + a.output_tokens + a.reasoning_tokens), 0)::bigint as total_tokens,
    coalesce(sum(a.input_tokens + a.output_tokens + a.reasoning_tokens), 0)::bigint as provider_attempt_total_tokens,
    count(a.id) filter (
      where a.state in ('failed', 'ambiguous') or a.error_code is not null
    )::bigint as provider_errors,
    case
      when coalesce(sum(a.standard_equivalent_cost_usd), 0) > 0
        then sum(a.standard_equivalent_cost_usd)
      else coalesce(sum(a.cost_usd), 0)
    end as estimated_cost_usd,
    case
      when count(distinct nullif(a.provider, '')) = 0 then null
      when count(distinct nullif(a.provider, '')) = 1
        then min(nullif(a.provider, ''))
      else 'mixed'
    end as provider,
    case
      when count(distinct nullif(a.model, '')) = 0 then null
      when count(distinct nullif(a.model, '')) = 1
        then min(nullif(a.model, ''))
      else 'mixed'
    end as model
  from v4_runs r
  left join private.analysis_provider_attempts a on a.engine_run_id = r.id
  group by r.analysis_id
),
v4_usage as (
  select
    r.analysis_id,
    r.user_id,
    a.client_platform,
    coalesce(t.provider, r.provider, 'unknown') as provider,
    coalesce(t.model, r.model, 'unknown') as model,
    coalesce(t.usage_rows, 0)::bigint as usage_rows,
    coalesce(t.provider_calls, 0)::bigint as provider_calls,
    coalesce(t.tokens_in, 0)::bigint as tokens_in,
    coalesce(t.tokens_out, 0)::bigint as tokens_out,
    coalesce(t.reasoning_tokens, 0)::bigint as reasoning_tokens,
    coalesce(t.total_tokens, 0)::bigint as total_tokens,
    coalesce(t.provider_attempt_total_tokens, 0)::bigint as provider_attempt_total_tokens,
    r.duration_ms,
    coalesce(t.provider_errors, 0)::bigint as provider_errors,
    coalesce(t.estimated_cost_usd, 0)::numeric as estimated_cost_usd,
    r.measured_at,
    'v4_engine'::text as telemetry_source
  from v4_run_totals r
  join public.analyses a on a.id = r.analysis_id
  left join v4_attempt_totals t on t.analysis_id = r.analysis_id
),
legacy_usage as (
  select
    l.analysis_id,
    l.user_id,
    coalesce(
      min(a.client_platform) filter (where a.client_platform is not null),
      min(l.client_platform) filter (where l.client_platform is not null)
    ) as client_platform,
    case when count(distinct nullif(l.provider, '')) = 1
      then min(nullif(l.provider, '')) else 'mixed' end as provider,
    case when count(distinct nullif(l.model, '')) = 1
      then min(nullif(l.model, '')) else 'mixed' end as model,
    count(*)::bigint as usage_rows,
    coalesce(sum(coalesce(l.provider_request_count, 1)), 0)::bigint as provider_calls,
    coalesce(sum(l.tokens_in), 0)::bigint as tokens_in,
    coalesce(sum(l.tokens_out), 0)::bigint as tokens_out,
    coalesce(sum(l.thoughts_tokens), 0)::bigint as reasoning_tokens,
    coalesce(sum(coalesce(
      l.total_tokens,
      coalesce(l.tokens_in, 0) + coalesce(l.tokens_out, 0) + coalesce(l.thoughts_tokens, 0)
    )), 0)::bigint as total_tokens,
    coalesce(sum(coalesce(
      l.provider_attempt_total_tokens,
      l.total_tokens,
      coalesce(l.tokens_in, 0) + coalesce(l.tokens_out, 0) + coalesce(l.thoughts_tokens, 0)
    )), 0)::bigint as provider_attempt_total_tokens,
    coalesce(sum(l.duration_ms), 0)::bigint as duration_ms,
    count(*) filter (where l.error is not null or l.error_code is not null)::bigint as provider_errors,
    null::numeric as estimated_cost_usd,
    max(l.created_at) as measured_at,
    'legacy_ai_usage'::text as telemetry_source
  from public.ai_usage_logs l
  left join public.analyses a on a.id = l.analysis_id
  where (p_from is null or l.created_at >= p_from)
    and (p_to is null or l.created_at < p_to)
    and (p_analysis_ids is null or l.analysis_id = any(p_analysis_ids))
    -- v4 never needs a compatibility copy in ai_usage_logs. If a future
    -- deployment dual-writes, the private physical-attempt ledger wins.
    and not exists (
      select 1
      from private.analysis_engine_runs r
      where r.analysis_id = l.analysis_id
        and r.engine_version = 'vnext-v4'
    )
  group by l.analysis_id, l.user_id
)
select * from v4_usage
union all
select * from legacy_usage;
$$;

revoke all on function private.analysis_usage_rollup_v1(
  timestamptz, timestamptz, uuid[]
) from public, anon, authenticated;
grant execute on function private.analysis_usage_rollup_v1(
  timestamptz, timestamptz, uuid[]
) to service_role;

-- Preserve the original quality calculations and replace only their usage
-- counters with the canonical ledger. V4 analyses intentionally remain in the
-- legacy-quality bucket because they have a separate scoreless quality model.
alter function private.analysis_quality_window_v1(timestamptz, timestamptz)
  rename to analysis_quality_window_pre_v4_v1;

create function private.analysis_quality_window_v1(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_full_usage jsonb;
  v_legacy_usage jsonb;
begin
  v_result := private.analysis_quality_window_pre_v4_v1(p_from, p_to);

  with analysis_scope as (
    select
      a.id,
      coalesce(
        a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'
        and a.raw_ai_response->'_quality_trace_v1'->>'trace_mode' = 'full_trace',
        false
      ) as is_full_trace
    from public.analyses a
    where a.status::text = 'completed'
      and a.kind::text = 'photo'
      and greatest(coalesce(a.photo_count, 0), 0) > 0
      and coalesce(a.completed_at, a.updated_at, a.created_at) >= p_from
      and coalesce(a.completed_at, a.updated_at, a.created_at) < p_to
  ), usage as (
    select u.*, s.is_full_trace
    from private.analysis_usage_rollup_v1(
      null,
      null,
      array(select id from analysis_scope)
    ) u
    join analysis_scope s on s.id = u.analysis_id
  )
  select
    jsonb_build_object(
      'usage_rows', coalesce(sum(usage_rows) filter (where is_full_trace), 0),
      'provider_calls', coalesce(sum(provider_calls) filter (where is_full_trace), 0),
      'tokens_in', coalesce(sum(tokens_in) filter (where is_full_trace), 0),
      'tokens_out', coalesce(sum(tokens_out) filter (where is_full_trace), 0),
      'total_tokens', coalesce(sum(total_tokens) filter (where is_full_trace), 0),
      'provider_attempt_total_tokens', coalesce(sum(provider_attempt_total_tokens) filter (where is_full_trace), 0),
      'duration_ms', coalesce(sum(duration_ms) filter (where is_full_trace), 0),
      'provider_errors', coalesce(sum(provider_errors) filter (where is_full_trace), 0),
      'estimated_cost_usd', sum(estimated_cost_usd) filter (where is_full_trace)
    ),
    jsonb_build_object(
      'usage_rows', coalesce(sum(usage_rows) filter (where not is_full_trace), 0),
      'provider_calls', coalesce(sum(provider_calls) filter (where not is_full_trace), 0),
      'tokens_in', coalesce(sum(tokens_in) filter (where not is_full_trace), 0),
      'tokens_out', coalesce(sum(tokens_out) filter (where not is_full_trace), 0),
      'total_tokens', coalesce(sum(total_tokens) filter (where not is_full_trace), 0),
      'provider_attempt_total_tokens', coalesce(sum(provider_attempt_total_tokens) filter (where not is_full_trace), 0),
      'duration_ms', coalesce(sum(duration_ms) filter (where not is_full_trace), 0),
      'provider_errors', coalesce(sum(provider_errors) filter (where not is_full_trace), 0),
      'estimated_cost_usd', sum(estimated_cost_usd) filter (where not is_full_trace)
    )
  into v_full_usage, v_legacy_usage
  from usage;

  v_result := jsonb_set(
    v_result,
    '{full_trace}',
    coalesce(v_result->'full_trace', '{}'::jsonb) || v_full_usage,
    true
  );
  v_result := jsonb_set(
    v_result,
    '{legacy_aggregate}',
    coalesce(v_result->'legacy_aggregate', '{}'::jsonb) || v_legacy_usage,
    true
  );
  return v_result;
end;
$$;

revoke all on function private.analysis_quality_window_v1(
  timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function private.analysis_quality_window_v1(
  timestamptz, timestamptz
) to service_role;

create or replace function public.admin_analysis_quality_run_v1(
  p_analysis_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
with target as (
  select
    a.id,
    a.user_id,
    a.status::text as status,
    a.created_at,
    a.completed_at,
    a.has_user_edits,
    greatest(coalesce(a.photo_count, 0), 0) as photo_count,
    a.canvas::text as canvas,
    coalesce(a.output_language, a.raw_ai_response->'_input_audit'->>'output_language', 'unknown') as output_language,
    coalesce(a.raw_ai_response->'_quality_trace_v1', '{}'::jsonb) as trace,
    coalesce(a.raw_ai_response->'_input_audit', '{}'::jsonb) as audit,
    coalesce((select count(*) from public.findings f where f.analysis_id = a.id), 0)::integer as database_final_findings
  from public.analyses a
  where a.id = p_analysis_id
), usage_summary as (
  select jsonb_build_object(
    'usage_rows', coalesce(sum(usage_rows), 0),
    'provider_calls', coalesce(sum(provider_calls), 0),
    'tokens_in', coalesce(sum(tokens_in), 0),
    'tokens_out', coalesce(sum(tokens_out), 0),
    'reasoning_tokens', coalesce(sum(reasoning_tokens), 0),
    'total_tokens', coalesce(sum(total_tokens), 0),
    'provider_attempt_total_tokens', coalesce(sum(provider_attempt_total_tokens), 0),
    'duration_ms', coalesce(sum(duration_ms), 0),
    'errors', coalesce(sum(provider_errors), 0),
    'estimated_cost_usd', sum(estimated_cost_usd),
    'provider', min(provider),
    'model', min(model),
    'telemetry_source', min(telemetry_source)
  ) as value
  from private.analysis_usage_rollup_v1(
    null,
    null,
    array[p_analysis_id]
  )
)
select case when not exists (select 1 from target) then
  jsonb_build_object('analysis_id', p_analysis_id, 'status', 'not_found')
else (
  select jsonb_build_object(
    'analysis_id', t.id,
    'status', t.status,
    'created_at', t.created_at,
    'completed_at', t.completed_at,
    'has_user_edits', t.has_user_edits,
    'photo_count', t.photo_count,
    'canvas', t.canvas,
    'output_language', t.output_language,
    'trace_mode', case when t.trace->>'version' = '1' then 'full_trace' else 'legacy_aggregate' end,
    'quality_trace_v1', case when t.trace->>'version' = '1' then t.trace else null end,
    'database_final_findings', t.database_final_findings,
    'trace_final_findings', case when t.trace->'summary'->>'final_findings' ~ '^[0-9]+$' then (t.trace->'summary'->>'final_findings')::integer else null end,
    'trace_matches_database', case when t.trace->'summary'->>'final_findings' ~ '^[0-9]+$' then (t.trace->'summary'->>'final_findings')::integer = t.database_final_findings else null end,
    'persistence_integrity_status', case
      when coalesce(t.trace->'summary'->>'final_findings', '') !~ '^[0-9]+$' then 'not_evaluable'
      when t.has_user_edits then 'user_edited_after_persistence'
      when (t.trace->'summary'->>'final_findings')::integer = t.database_final_findings then 'matched'
      else 'mismatch'
    end,
    'score_mutations', coalesce(t.trace->'score_traces', '[]'::jsonb),
    'repair', coalesce(t.trace->'repair', '{}'::jsonb),
    'provider', coalesce(t.trace->'provider', '{}'::jsonb),
    'cost', u.value,
    'legacy_aggregate', case when t.trace->>'version' = '1' then null else jsonb_build_object(
      'final_findings', t.database_final_findings,
      'photo_count', t.photo_count,
      'final_findings_per_photo', round(t.database_final_findings::numeric / nullif(t.photo_count, 0), 4),
      'not_comparable_to_full_trace', true
    ) end
  ) from target t cross join usage_summary u
) end;
$$;

revoke all on function public.admin_analysis_quality_run_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_analysis_quality_run_v1(uuid)
  to service_role;

-- Keep the established platform overview contract and replace only the AI
-- section. `calls` now means physical provider calls for both engines.
alter function public.admin_platform_overview_v1(integer, text)
  rename to admin_platform_overview_pre_v4_v1;

create function public.admin_platform_overview_v1(
  p_days integer default 30,
  p_platform text default 'all'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_platform text := lower(trim(coalesce(p_platform, 'all')));
  v_start timestamptz;
  v_result jsonb;
  v_ai jsonb;
begin
  -- The preserved function remains the authority for validation and every
  -- non-AI metric in this response.
  v_result := public.admin_platform_overview_pre_v4_v1(p_days, p_platform);
  v_start := (
    date_trunc('day', pg_catalog.now() at time zone 'Europe/Istanbul')
    - pg_catalog.make_interval(days => p_days - 1)
  ) at time zone 'Europe/Istanbul';

  select jsonb_build_object(
    'calls', coalesce(sum(provider_calls), 0),
    'usage_rows', coalesce(sum(usage_rows), 0),
    'total_tokens', coalesce(sum(total_tokens), 0),
    'provider_attempt_total_tokens', coalesce(sum(provider_attempt_total_tokens), 0),
    'provider_errors', coalesce(sum(provider_errors), 0),
    'estimated_cost_usd', sum(estimated_cost_usd)
  )
  into v_ai
  from private.analysis_usage_rollup_v1(v_start, null, null)
  where v_platform = 'all'
     or coalesce(client_platform, 'unknown') = v_platform;

  return jsonb_set(v_result, '{ai}', v_ai, true);
end;
$$;

revoke all on function public.admin_platform_overview_v1(integer, text)
  from public, anon, authenticated;
grant execute on function public.admin_platform_overview_v1(integer, text)
  to service_role;

-- Persist the trusted client identity before any idempotent early return so a
-- repeated enqueue can repair metadata lost by older versions of this RPC.
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
  v_client_routing jsonb := '{}'::jsonb;
  v_client_platform text;
  v_client_build text;
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

  if jsonb_typeof(p_message->'analysis_engine_client_routing') = 'object' then
    v_client_routing := p_message->'analysis_engine_client_routing';
  end if;
  if v_client_routing->>'source' = 'trusted_analyze_enqueue' then
    v_client_platform := lower(btrim(coalesce(v_client_routing->>'client_platform', '')));
    v_client_build := btrim(coalesce(v_client_routing->>'client_app_build', ''));
    if v_client_platform not in ('ios', 'android') then
      v_client_platform := null;
    end if;
    if v_client_build !~ '^[1-9][0-9]{0,8}$' then
      v_client_build := null;
    end if;
  end if;

  if (v_analysis.client_platform is null and v_client_platform is not null)
    or (v_analysis.client_build is null and v_client_build is not null)
  then
    update public.analyses
    set client_platform = coalesce(client_platform, v_client_platform),
        client_build = coalesce(client_build, v_client_build)
    where id = p_analysis_id and user_id = p_user_id;
    v_analysis.client_platform := coalesce(v_analysis.client_platform, v_client_platform);
    v_analysis.client_build := coalesce(v_analysis.client_build, v_client_build);
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

revoke all on function public.submit_analysis_job_v2(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.submit_analysis_job_v2(uuid, uuid, jsonb)
  to service_role;

-- Repair existing v4 rows only when at least one result event supplies both
-- valid values and every valid observation agrees. Existing non-null values
-- are immutable and are never overwritten.
with valid_events as (
  select
    e.analysis_id,
    e.user_id,
    lower(btrim(e.client_platform)) as client_platform,
    btrim(e.client_app_build) as client_build
  from private.analysis_result_events e
  where e.analysis_id is not null
    and lower(btrim(coalesce(e.client_platform, ''))) in ('ios', 'android')
    and btrim(coalesce(e.client_app_build, '')) ~ '^[1-9][0-9]{0,8}$'
), event_identity as (
  select
    analysis_id,
    user_id,
    min(client_platform) as client_platform,
    min(client_build) as client_build
  from valid_events
  group by analysis_id, user_id
  having count(distinct client_platform) = 1
     and count(distinct client_build) = 1
)
update public.analyses a
set client_platform = coalesce(a.client_platform, e.client_platform),
    client_build = coalesce(a.client_build, e.client_build)
from event_identity e
where a.id = e.analysis_id
  and a.user_id = e.user_id
  and (a.client_platform is null or a.client_build is null)
  and exists (
    select 1
    from private.analysis_engine_runs r
    where r.analysis_id = a.id
      and r.engine_version = 'vnext-v4'
  );
