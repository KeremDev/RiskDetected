-- RiskDetected analysis engine vNext v3.
--
-- The public mobile contract stays backward-compatible. All engine execution,
-- provider-attempt, module-audit, signal and lineage state is private and may
-- only be accessed through service-role RPCs.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.analysis_engine_configs (
  id uuid primary key default gen_random_uuid(),
  engine_version text not null,
  schema_version text not null,
  prompt_version text not null,
  policy_version text not null,
  control_catalog_version text not null,
  config jsonb not null default '{}'::jsonb,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (engine_version)
);

create unique index if not exists analysis_engine_configs_one_active_idx
  on private.analysis_engine_configs (is_active)
  where is_active;

insert into private.analysis_engine_configs (
  engine_version,
  schema_version,
  prompt_version,
  policy_version,
  control_catalog_version,
  config,
  is_active
) values (
  'vnext-v3',
  'hazard-fact-v3',
  'vnext-photo-expert-v3',
  'semantic-risk-v3',
  'controls-v3',
  jsonb_build_object(
    'visual_input_mode', 'legacy_flattened_1536',
    'visual_assets_version', 1,
    'max_parallel_photo_runs', 3,
    'max_targeted_reinspection_runs', 1,
    'primary_provider', 'gemini',
    'primary_model', 'gemini-2.5-flash',
    'gemini_thinking_budget', 12288,
    'fallback_provider', 'openai',
    'fallback_model', 'gpt-5.6-luna',
    'openai_reasoning_effort', 'high',
    'average_cost_limit_usd', 0.10
  ),
  true
)
on conflict (engine_version) do update set
  schema_version = excluded.schema_version,
  prompt_version = excluded.prompt_version,
  policy_version = excluded.policy_version,
  control_catalog_version = excluded.control_catalog_version,
  config = excluded.config,
  is_active = excluded.is_active,
  updated_at = now();

create table if not exists private.analysis_engine_allowlist (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.analysis_engine_routes (
  analysis_id uuid primary key references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  engine text not null check (engine in ('legacy', 'vnext')),
  rollout_mode text not null,
  config_snapshot jsonb not null default '{}'::jsonb,
  pinned_at timestamptz not null default now()
);

create index if not exists analysis_engine_routes_user_pinned_idx
  on private.analysis_engine_routes (user_id, pinned_at desc);

create table if not exists private.analysis_engine_runs (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  queue_msg_id bigint not null,
  job_generation integer not null check (job_generation > 0),
  job_mode text not null default 'analysis' check (job_mode in ('analysis', 'repair')),
  engine_version text not null,
  schema_version text not null,
  prompt_version text not null,
  policy_version text not null,
  control_catalog_version text not null,
  visual_input_mode text not null,
  provider text not null,
  model text not null,
  status text not null default 'running'
    check (status in ('running', 'completed', 'failed', 'superseded')),
  config_snapshot jsonb not null default '{}'::jsonb,
  total_provider_requests integer not null default 0,
  total_input_tokens bigint not null default 0,
  total_output_tokens bigint not null default 0,
  total_reasoning_tokens bigint not null default 0,
  total_cost_usd numeric(14, 8) not null default 0,
  duration_ms bigint,
  error_code text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (analysis_id, job_generation, job_mode)
);

create index if not exists analysis_engine_runs_user_started_idx
  on private.analysis_engine_runs (user_id, started_at desc);
create index if not exists analysis_engine_runs_status_started_idx
  on private.analysis_engine_runs (status, started_at desc);

create table if not exists private.analysis_photo_runs (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_id uuid references public.photos(id) on delete set null,
  photo_index integer not null check (photo_index between 1 and 3),
  storage_path text not null,
  provider text not null,
  model text not null,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  normalized_output jsonb,
  output_sha256 text,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  reasoning_tokens bigint not null default 0,
  cost_usd numeric(14, 8) not null default 0,
  duration_ms bigint,
  error_code text,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (engine_run_id, photo_index)
);

create index if not exists analysis_photo_runs_analysis_idx
  on private.analysis_photo_runs (analysis_id, photo_index);

create table if not exists private.analysis_provider_attempts (
  id uuid primary key,
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  photo_run_id uuid references private.analysis_photo_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  attempt_kind text not null
    check (attempt_kind in ('primary', 'technical_retry', 'schema_repair', 'targeted_reinspection', 'provider_fallback')),
  attempt_number integer not null check (attempt_number > 0),
  provider text not null,
  model text not null,
  state text not null
    check (state in ('started', 'received', 'persisted', 'failed', 'ambiguous')),
  provider_request_id text,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  reasoning_tokens bigint not null default 0,
  cached_input_tokens bigint not null default 0,
  cost_usd numeric(14, 8) not null default 0,
  duration_ms bigint,
  http_status integer,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists analysis_provider_attempts_run_created_idx
  on private.analysis_provider_attempts (engine_run_id, created_at);

create table if not exists private.analysis_module_audits (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_index integer not null check (photo_index between 1 and 3),
  module_id text not null,
  entity_refs text[] not null default '{}',
  status text not null check (status in ('not_applicable', 'scanned_no_positive_evidence', 'positive_evidence')),
  created_at timestamptz not null default now(),
  unique (engine_run_id, photo_index, module_id)
);

create table if not exists private.analysis_inspection_signals (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  signal_id text not null,
  photo_index integer not null check (photo_index between 1 and 3),
  evidence_region jsonb,
  affirmative_cues jsonb not null default '[]'::jsonb,
  potential_consequence_class text,
  reason_code text not null,
  status text not null check (status in ('internal', 'targeted', 'confirmed', 'rejected')),
  created_at timestamptz not null default now(),
  unique (engine_run_id, signal_id)
);

create table if not exists private.analysis_fact_lineage (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  fact_trace_id text not null,
  final_ordinal integer,
  final_finding_id uuid references public.findings(id) on delete set null,
  source_photo_indices integer[] not null default '{}',
  evidence_regions jsonb not null default '[]'::jsonb,
  semantic_inputs jsonb not null default '{}'::jsonb,
  score_output jsonb not null default '{}'::jsonb,
  mutations jsonb not null default '[]'::jsonb,
  reason_codes text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (engine_run_id, fact_trace_id)
);

create index if not exists analysis_fact_lineage_finding_idx
  on private.analysis_fact_lineage (final_finding_id)
  where final_finding_id is not null;

alter table private.analysis_engine_configs enable row level security;
alter table private.analysis_engine_allowlist enable row level security;
alter table private.analysis_engine_routes enable row level security;
alter table private.analysis_engine_runs enable row level security;
alter table private.analysis_photo_runs enable row level security;
alter table private.analysis_provider_attempts enable row level security;
alter table private.analysis_module_audits enable row level security;
alter table private.analysis_inspection_signals enable row level security;
alter table private.analysis_fact_lineage enable row level security;

revoke all on table private.analysis_engine_configs from public, anon, authenticated;
revoke all on table private.analysis_engine_allowlist from public, anon, authenticated;
revoke all on table private.analysis_engine_routes from public, anon, authenticated;
revoke all on table private.analysis_engine_runs from public, anon, authenticated;
revoke all on table private.analysis_photo_runs from public, anon, authenticated;
revoke all on table private.analysis_provider_attempts from public, anon, authenticated;
revoke all on table private.analysis_module_audits from public, anon, authenticated;
revoke all on table private.analysis_inspection_signals from public, anon, authenticated;
revoke all on table private.analysis_fact_lineage from public, anon, authenticated;

insert into public.app_feature_flags (key, value)
values (
  'analysis_engine_vnext',
  jsonb_build_object(
    'policy_version', 3,
    'rollout_mode', 'off',
    'kill_switch', true,
    'canary_percent', 0,
    'engine_version', 'vnext-v3'
  )
)
on conflict (key) do nothing;

create or replace function public.resolve_analysis_engine_route_v3(
  p_user_id uuid,
  p_analysis_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing private.analysis_engine_routes%rowtype;
  v_flag jsonb := '{}'::jsonb;
  v_config private.analysis_engine_configs%rowtype;
  v_mode text := 'off';
  v_engine text := 'legacy';
  v_canary integer := 0;
  v_bucket integer := 0;
  v_allowlisted boolean := false;
  v_snapshot jsonb;
begin
  if p_user_id is null or p_analysis_id is null then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;

  if not exists (
    select 1 from public.analyses
    where id = p_analysis_id and user_id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'state', 'analysis_not_found');
  end if;

  select * into v_existing
  from private.analysis_engine_routes
  where analysis_id = p_analysis_id;

  if found then
    return jsonb_build_object(
      'ok', true,
      'state', 'pinned',
      'engine', v_existing.engine,
      'rollout_mode', v_existing.rollout_mode,
      'config_snapshot', v_existing.config_snapshot
    );
  end if;

  select value into v_flag
  from public.app_feature_flags
  where key = 'analysis_engine_vnext';
  v_flag := coalesce(v_flag, '{}'::jsonb);
  v_mode := coalesce(nullif(v_flag->>'rollout_mode', ''), 'off');
  v_canary := greatest(0, least(100, case
    when coalesce(v_flag->>'canary_percent', '') ~ '^[0-9]+$'
      then (v_flag->>'canary_percent')::integer
    else 0
  end));
  v_bucket := mod(abs(hashtext(p_analysis_id::text))::bigint, 100)::integer;

  select coalesce(enabled, false) into v_allowlisted
  from private.analysis_engine_allowlist
  where user_id = p_user_id;
  v_allowlisted := coalesce(v_allowlisted, false);

  select * into v_config
  from private.analysis_engine_configs
  where is_active
  order by updated_at desc
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'state', 'engine_config_missing');
  end if;

  if coalesce((v_flag->>'kill_switch')::boolean, true) then
    v_engine := 'legacy';
  elsif v_mode = 'on' then
    v_engine := 'vnext';
  elsif v_mode = 'user_allowlist' and v_allowlisted then
    v_engine := 'vnext';
  elsif v_mode = 'canary' and v_bucket < v_canary then
    v_engine := 'vnext';
  else
    v_engine := 'legacy';
  end if;

  v_snapshot := jsonb_build_object(
    'flag', v_flag,
    'allowlisted', v_allowlisted,
    'canary_bucket', v_bucket,
    'engine_version', v_config.engine_version,
    'schema_version', v_config.schema_version,
    'prompt_version', v_config.prompt_version,
    'policy_version', v_config.policy_version,
    'control_catalog_version', v_config.control_catalog_version,
    'engine_config', coalesce(v_config.config, '{}'::jsonb)
  );

  insert into private.analysis_engine_routes (
    analysis_id, user_id, engine, rollout_mode, config_snapshot
  ) values (
    p_analysis_id, p_user_id, v_engine, v_mode, v_snapshot
  )
  on conflict (analysis_id) do nothing;

  select * into v_existing
  from private.analysis_engine_routes
  where analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'resolved',
    'engine', v_existing.engine,
    'rollout_mode', v_existing.rollout_mode,
    'config_snapshot', v_existing.config_snapshot
  );
exception when others then
  return jsonb_build_object('ok', false, 'state', 'route_resolution_failed');
end;
$$;

create or replace function public.admin_set_analysis_engine_vnext_user_v1(
  p_user_id uuid,
  p_enabled boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;
  insert into private.analysis_engine_allowlist (user_id, enabled, note)
  values (p_user_id, coalesce(p_enabled, false), left(p_note, 500))
  on conflict (user_id) do update set
    enabled = excluded.enabled,
    note = excluded.note,
    updated_at = now();
  return jsonb_build_object('ok', true, 'state', 'updated');
end;
$$;

create or replace function public.begin_analysis_engine_run_v3(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_job_mode text default 'analysis'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state private.analysis_job_state%rowtype;
  v_config private.analysis_engine_configs%rowtype;
  v_route private.analysis_engine_routes%rowtype;
  v_run private.analysis_engine_runs%rowtype;
  v_photo_runs jsonb;
begin
  select * into v_state
  from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id;

  if not found
    or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token
  then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;

  select * into v_route
  from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if not found or v_route.engine <> 'vnext' then
    return jsonb_build_object('ok', false, 'state', 'route_not_vnext');
  end if;

  select * into v_config
  from private.analysis_engine_configs
  where is_active
  order by updated_at desc
  limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'engine_config_missing');
  end if;

  insert into private.analysis_engine_runs (
    analysis_id, user_id, queue_msg_id, job_generation, job_mode,
    engine_version, schema_version, prompt_version, policy_version,
    control_catalog_version, visual_input_mode, provider, model,
    status, config_snapshot
  ) values (
    p_analysis_id, p_user_id, p_msg_id, p_generation,
    case when p_job_mode = 'repair' then 'repair' else 'analysis' end,
    v_config.engine_version, v_config.schema_version, v_config.prompt_version,
    v_config.policy_version, v_config.control_catalog_version,
    coalesce(v_config.config->>'visual_input_mode', 'legacy_flattened_1536'),
    coalesce(v_config.config->>'primary_provider', 'gemini'),
    coalesce(v_route.config_snapshot->'engine_config'->>'primary_model', 'gemini-2.5-flash'),
    'running', v_route.config_snapshot
  )
  on conflict (analysis_id, job_generation, job_mode) do update set
    queue_msg_id = excluded.queue_msg_id,
    status = case
      when private.analysis_engine_runs.status = 'completed' then 'completed'
      else 'running'
    end,
    error_code = case
      when private.analysis_engine_runs.status = 'completed'
        then private.analysis_engine_runs.error_code
      else null
    end,
    completed_at = case
      when private.analysis_engine_runs.status = 'completed'
        then private.analysis_engine_runs.completed_at
      else null
    end,
    updated_at = now()
  returning * into v_run;

  update private.analysis_provider_attempts
  set state = 'ambiguous',
      error_code = 'ambiguous_provider_attempt',
      updated_at = now()
  where engine_run_id = v_run.id
    and state = 'received';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'photo_id', p.photo_id,
    'photo_index', p.photo_index,
    'storage_path', p.storage_path,
    'status', p.status,
    'provider', p.provider,
    'model', p.model,
    'attempt_count', p.attempt_count,
    'normalized_output', p.normalized_output,
    'input_tokens', p.input_tokens,
    'output_tokens', p.output_tokens,
    'reasoning_tokens', p.reasoning_tokens,
    'cost_usd', p.cost_usd,
    'duration_ms', p.duration_ms,
    'error_code', p.error_code
  ) order by p.photo_index), '[]'::jsonb)
  into v_photo_runs
  from private.analysis_photo_runs p
  where p.engine_run_id = v_run.id;

  return jsonb_build_object(
    'ok', true,
    'state', case when v_run.status = 'completed' then 'completed' else 'running' end,
    'engine_run_id', v_run.id,
    'engine_version', v_run.engine_version,
    'schema_version', v_run.schema_version,
    'prompt_version', v_run.prompt_version,
    'policy_version', v_run.policy_version,
    'control_catalog_version', v_run.control_catalog_version,
    'provider', v_run.provider,
    'model', v_run.model,
    'visual_input_mode', v_run.visual_input_mode,
    'config_snapshot', v_run.config_snapshot,
    'photo_runs', v_photo_runs
  );
end;
$$;

create or replace function public.checkpoint_analysis_photo_run_v3(
  p_user_id uuid,
  p_engine_run_id uuid,
  p_photo_id uuid,
  p_photo_index integer,
  p_storage_path text,
  p_provider text,
  p_model text,
  p_status text,
  p_attempt_count integer,
  p_normalized_output jsonb,
  p_output_sha256 text,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_reasoning_tokens bigint,
  p_cost_usd numeric,
  p_duration_ms bigint,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
  v_photo_run_id uuid;
begin
  select * into v_run
  from private.analysis_engine_runs
  where id = p_engine_run_id and user_id = p_user_id
  for update;
  if not found or v_run.status <> 'running' then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_running');
  end if;

  insert into private.analysis_photo_runs (
    engine_run_id, analysis_id, user_id, photo_id, photo_index, storage_path,
    provider, model, status, attempt_count, normalized_output, output_sha256,
    input_tokens, output_tokens, reasoning_tokens, cost_usd, duration_ms,
    error_code, started_at, completed_at, updated_at
  ) values (
    v_run.id, v_run.analysis_id, v_run.user_id, p_photo_id, p_photo_index,
    p_storage_path, p_provider, p_model,
    case when p_status in ('pending', 'running', 'completed', 'failed') then p_status else 'failed' end,
    greatest(coalesce(p_attempt_count, 0), 0), p_normalized_output,
    nullif(p_output_sha256, ''), greatest(coalesce(p_input_tokens, 0), 0),
    greatest(coalesce(p_output_tokens, 0), 0),
    greatest(coalesce(p_reasoning_tokens, 0), 0),
    greatest(coalesce(p_cost_usd, 0), 0), p_duration_ms,
    left(nullif(p_error_code, ''), 160), now(),
    case when p_status in ('completed', 'failed') then now() else null end,
    now()
  )
  on conflict (engine_run_id, photo_index) do update set
    photo_id = excluded.photo_id,
    storage_path = excluded.storage_path,
    provider = excluded.provider,
    model = excluded.model,
    status = excluded.status,
    attempt_count = excluded.attempt_count,
    normalized_output = excluded.normalized_output,
    output_sha256 = excluded.output_sha256,
    input_tokens = excluded.input_tokens,
    output_tokens = excluded.output_tokens,
    reasoning_tokens = excluded.reasoning_tokens,
    cost_usd = excluded.cost_usd,
    duration_ms = excluded.duration_ms,
    error_code = excluded.error_code,
    started_at = coalesce(private.analysis_photo_runs.started_at, excluded.started_at),
    completed_at = excluded.completed_at,
    updated_at = now()
  returning id into v_photo_run_id;

  return jsonb_build_object('ok', true, 'state', 'checkpointed', 'photo_run_id', v_photo_run_id);
end;
$$;

create or replace function public.record_analysis_provider_attempt_v3(
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
  p_error_code text
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
    http_status, error_code, updated_at
  ) values (
    p_attempt_id, p_engine_run_id, p_photo_run_id, v_run.analysis_id,
    p_user_id, p_attempt_kind, greatest(coalesce(p_attempt_number, 1), 1),
    p_provider, p_model, p_state, left(nullif(p_provider_request_id, ''), 200),
    greatest(coalesce(p_input_tokens, 0), 0), greatest(coalesce(p_output_tokens, 0), 0),
    greatest(coalesce(p_reasoning_tokens, 0), 0),
    greatest(coalesce(p_cached_input_tokens, 0), 0),
    greatest(coalesce(p_cost_usd, 0), 0), p_duration_ms, p_http_status,
    left(nullif(p_error_code, ''), 160), now()
  )
  on conflict (id) do update set
    photo_run_id = coalesce(excluded.photo_run_id, private.analysis_provider_attempts.photo_run_id),
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
    updated_at = now();

  return jsonb_build_object('ok', true, 'state', 'recorded');
exception when others then
  return jsonb_build_object('ok', false, 'state', 'attempt_record_failed');
end;
$$;

create or replace function public.fail_analysis_engine_run_v3(
  p_user_id uuid,
  p_engine_run_id uuid,
  p_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.analysis_engine_runs
  set status = 'failed',
      error_code = left(nullif(p_error_code, ''), 160),
      completed_at = now(),
      updated_at = now()
  where id = p_engine_run_id and user_id = p_user_id and status = 'running';
  return jsonb_build_object('ok', true, 'state', 'recorded');
end;
$$;

create or replace function public.finalize_analysis_result_v3(
  p_user_id uuid,
  p_analysis_id uuid,
  p_msg_id bigint,
  p_generation integer,
  p_claim_token uuid,
  p_engine_run_id uuid,
  p_findings jsonb,
  p_analysis_result jsonb,
  p_photo_summaries jsonb default '[]'::jsonb,
  p_fact_lineage jsonb default '[]'::jsonb,
  p_module_audits jsonb default '[]'::jsonb,
  p_inspection_signals jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
  v_result jsonb;
  v_item jsonb;
  v_source_indices integer[];
  v_total_requests integer;
  v_total_input bigint;
  v_total_output bigint;
  v_total_reasoning bigint;
  v_total_cost numeric;
begin
  select * into v_run
  from private.analysis_engine_runs
  where id = p_engine_run_id
    and analysis_id = p_analysis_id
    and user_id = p_user_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_found');
  end if;

  v_result := public.finalize_analysis_result_v2(
    p_user_id,
    p_analysis_id,
    p_msg_id,
    p_generation,
    p_claim_token,
    coalesce(p_findings, '[]'::jsonb),
    p_analysis_result,
    coalesce(p_photo_summaries, '[]'::jsonb)
  );

  if coalesce(v_result->>'ok', 'false') <> 'true' then
    return v_result;
  end if;

  -- v2 owns the proven claim/quota/finalization transaction. v3 enriches the
  -- inserted rows with fields that v2 intentionally did not persist.
  for v_item in select value from jsonb_array_elements(coalesce(p_findings, '[]'::jsonb))
  loop
    update public.findings f
    set photo_id = (
          select p.id
          from public.photos p
          where p.analysis_id = p_analysis_id
            and p.user_id = p_user_id
            and p.sequence_index = case
              when jsonb_typeof(v_item->'source_photo_indices') = 'array'
                then nullif(v_item->'source_photo_indices'->>0, '')::integer
              else null
            end
          limit 1
        ),
        bounding_box = case
          when jsonb_typeof(v_item->'bounding_box') = 'object'
            then v_item->'bounding_box'
          else null
        end,
        residual_fk_probability = nullif(v_item->>'residual_fk_probability', '')::numeric,
        residual_fk_frequency = nullif(v_item->>'residual_fk_frequency', '')::numeric,
        residual_fk_severity = nullif(v_item->>'residual_fk_severity', '')::numeric,
        residual_m5_probability = nullif(v_item->>'residual_m5_probability', '')::integer,
        residual_m5_severity = nullif(v_item->>'residual_m5_severity', '')::integer
    where f.analysis_id = p_analysis_id
      and f.user_id = p_user_id
      and f.ordinal = (v_item->>'ordinal')::integer;
  end loop;

  delete from private.analysis_module_audits where engine_run_id = p_engine_run_id;
  for v_item in select value from jsonb_array_elements(coalesce(p_module_audits, '[]'::jsonb))
  loop
    insert into private.analysis_module_audits (
      engine_run_id, analysis_id, user_id, photo_index, module_id, entity_refs, status
    ) values (
      p_engine_run_id, p_analysis_id, p_user_id,
      (v_item->>'photo_index')::integer,
      left(v_item->>'module_id', 120),
      array(select jsonb_array_elements_text(coalesce(v_item->'entity_refs', '[]'::jsonb))),
      v_item->>'status'
    );
  end loop;

  delete from private.analysis_inspection_signals where engine_run_id = p_engine_run_id;
  for v_item in select value from jsonb_array_elements(coalesce(p_inspection_signals, '[]'::jsonb))
  loop
    insert into private.analysis_inspection_signals (
      engine_run_id, analysis_id, user_id, signal_id, photo_index,
      evidence_region, affirmative_cues, potential_consequence_class,
      reason_code, status
    ) values (
      p_engine_run_id, p_analysis_id, p_user_id,
      left(v_item->>'signal_id', 160),
      (v_item->>'photo_index')::integer,
      v_item->'evidence_region',
      coalesce(v_item->'affirmative_cues', '[]'::jsonb),
      left(v_item->>'potential_consequence_class', 100),
      left(v_item->>'reason_code', 160),
      v_item->>'status'
    );
  end loop;

  delete from private.analysis_fact_lineage where engine_run_id = p_engine_run_id;
  for v_item in select value from jsonb_array_elements(coalesce(p_fact_lineage, '[]'::jsonb))
  loop
    select coalesce(array_agg(value::integer), '{}'::integer[])
    into v_source_indices
    from jsonb_array_elements_text(coalesce(v_item->'source_photo_indices', '[]'::jsonb));

    insert into private.analysis_fact_lineage (
      engine_run_id, analysis_id, user_id, fact_trace_id, final_ordinal,
      final_finding_id, source_photo_indices, evidence_regions,
      semantic_inputs, score_output, mutations, reason_codes
    ) values (
      p_engine_run_id, p_analysis_id, p_user_id,
      left(v_item->>'fact_trace_id', 200),
      nullif(v_item->>'final_ordinal', '')::integer,
      (
        select f.id from public.findings f
        where f.analysis_id = p_analysis_id
          and f.user_id = p_user_id
          and f.ordinal = nullif(v_item->>'final_ordinal', '')::integer
        limit 1
      ),
      v_source_indices,
      coalesce(v_item->'evidence_regions', '[]'::jsonb),
      coalesce(v_item->'semantic_inputs', '{}'::jsonb),
      coalesce(v_item->'score_output', '{}'::jsonb),
      coalesce(v_item->'mutations', '[]'::jsonb),
      array(select jsonb_array_elements_text(coalesce(v_item->'reason_codes', '[]'::jsonb)))
    );
  end loop;

  select
    count(*),
    coalesce(sum(input_tokens), 0),
    coalesce(sum(output_tokens), 0),
    coalesce(sum(reasoning_tokens), 0),
    coalesce(sum(cost_usd), 0)
  into v_total_requests, v_total_input, v_total_output, v_total_reasoning, v_total_cost
  from private.analysis_provider_attempts
  where engine_run_id = p_engine_run_id;

  update private.analysis_engine_runs
  set status = 'completed',
      total_provider_requests = v_total_requests,
      total_input_tokens = v_total_input,
      total_output_tokens = v_total_output,
      total_reasoning_tokens = v_total_reasoning,
      total_cost_usd = v_total_cost,
      duration_ms = coalesce(
        nullif(p_analysis_result->>'duration_ms', '')::bigint,
        floor(extract(epoch from (now() - started_at)) * 1000)::bigint
      ),
      completed_at = now(),
      error_code = null,
      updated_at = now()
  where id = p_engine_run_id;

  return v_result || jsonb_build_object(
    'engine', 'vnext',
    'engine_run_id', p_engine_run_id,
    'provider_requests', v_total_requests,
    'provider_cost_usd', v_total_cost
  );
end;
$$;

revoke all on function public.resolve_analysis_engine_route_v3(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_set_analysis_engine_vnext_user_v1(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.begin_analysis_engine_run_v3(uuid, uuid, bigint, integer, uuid, text) from public, anon, authenticated;
revoke all on function public.checkpoint_analysis_photo_run_v3(uuid, uuid, uuid, integer, text, text, text, text, integer, jsonb, text, bigint, bigint, bigint, numeric, bigint, text) from public, anon, authenticated;
revoke all on function public.record_analysis_provider_attempt_v3(uuid, uuid, uuid, uuid, text, integer, text, text, text, text, bigint, bigint, bigint, bigint, numeric, bigint, integer, text) from public, anon, authenticated;
revoke all on function public.fail_analysis_engine_run_v3(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.finalize_analysis_result_v3(uuid, uuid, bigint, integer, uuid, uuid, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

grant execute on function public.resolve_analysis_engine_route_v3(uuid, uuid) to service_role;
grant execute on function public.admin_set_analysis_engine_vnext_user_v1(uuid, boolean, text) to service_role;
grant execute on function public.begin_analysis_engine_run_v3(uuid, uuid, bigint, integer, uuid, text) to service_role;
grant execute on function public.checkpoint_analysis_photo_run_v3(uuid, uuid, uuid, integer, text, text, text, text, integer, jsonb, text, bigint, bigint, bigint, numeric, bigint, text) to service_role;
grant execute on function public.record_analysis_provider_attempt_v3(uuid, uuid, uuid, uuid, text, integer, text, text, text, text, bigint, bigint, bigint, bigint, numeric, bigint, integer, text) to service_role;
grant execute on function public.fail_analysis_engine_run_v3(uuid, uuid, text) to service_role;
grant execute on function public.finalize_analysis_result_v3(uuid, uuid, bigint, integer, uuid, uuid, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to service_role;

insert into public.model_pricing_catalog (
  provider, model, effective_from, input_price_per_million,
  output_price_per_million, cached_price_per_million,
  thoughts_price_per_million, currency, notes
) values
  ('gemini', 'gemini-2.5-flash', '2026-08-01', 0.30, 2.50, 0.03, 2.50, 'USD', 'Gemini 2.5 Flash standard pricing; output includes thinking tokens.'),
  ('openai', 'gpt-5.6-luna', '2026-08-01', 0.20, 1.20, 0.02, 1.20, 'USD', 'OpenAI GPT-5.6 Luna standard pricing.'),
  ('openai', 'gpt-5.6-terra', '2026-08-01', 2.00, 12.00, null, 12.00, 'USD', 'OpenAI GPT-5.6 Terra standard pricing.'),
  ('openai', 'gpt-5.6-sol', '2026-08-01', 4.00, 20.00, null, 20.00, 'USD', 'OpenAI GPT-5.6 Sol standard pricing.')
on conflict (provider, model, effective_from) do update set
  input_price_per_million = excluded.input_price_per_million,
  output_price_per_million = excluded.output_price_per_million,
  cached_price_per_million = excluded.cached_price_per_million,
  thoughts_price_per_million = excluded.thoughts_price_per_million,
  notes = excluded.notes;

select pg_notify('pgrst', 'reload schema');
