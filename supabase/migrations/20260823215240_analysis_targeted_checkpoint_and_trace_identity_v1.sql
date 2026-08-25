-- Persist the single targeted semantic result independently from primary
-- photo runs. This prevents a worker/finalization retry from paying for and
-- repeating the same targeted provider call.

create table if not exists private.analysis_targeted_runs (
  id uuid primary key default gen_random_uuid(),
  engine_run_id uuid not null unique
    references private.analysis_engine_runs(id) on delete cascade,
  analysis_id uuid not null
    references public.analyses(id) on delete cascade,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  photo_run_id uuid not null
    references private.analysis_photo_runs(id) on delete cascade,
  signal_id text not null,
  photo_index integer not null check (photo_index between 1 and 3),
  provider text not null,
  model text not null,
  status text not null check (status in ('confirmed', 'rejected', 'failed')),
  normalized_output jsonb,
  output_sha256 text,
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists analysis_targeted_runs_analysis_idx
  on private.analysis_targeted_runs (analysis_id);
create index if not exists analysis_targeted_runs_user_idx
  on private.analysis_targeted_runs (user_id);
create index if not exists analysis_targeted_runs_photo_run_idx
  on private.analysis_targeted_runs (photo_run_id);

alter table private.analysis_targeted_runs enable row level security;
revoke all on table private.analysis_targeted_runs from public, anon, authenticated;
grant select, insert, update, delete on table private.analysis_targeted_runs
  to service_role;

create or replace function public.checkpoint_analysis_targeted_run_v1(
  p_user_id uuid,
  p_engine_run_id uuid,
  p_photo_run_id uuid,
  p_signal_id text,
  p_photo_index integer,
  p_provider text,
  p_model text,
  p_status text,
  p_normalized_output jsonb,
  p_output_sha256 text,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
  v_targeted_id uuid;
  v_inserted boolean := false;
begin
  select * into v_run
  from private.analysis_engine_runs
  where id = p_engine_run_id and user_id = p_user_id
  for update;

  if not found or v_run.status <> 'running' then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_running');
  end if;
  if nullif(trim(coalesce(p_signal_id, '')), '') is null
    or p_photo_index not between 1 and 3
    or p_status not in ('confirmed', 'rejected', 'failed')
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;
  if not exists (
    select 1
    from private.analysis_photo_runs p
    where p.id = p_photo_run_id
      and p.engine_run_id = p_engine_run_id
      and p.user_id = p_user_id
      and p.photo_index = p_photo_index
  ) then
    return jsonb_build_object('ok', false, 'state', 'photo_run_not_found');
  end if;

  insert into private.analysis_targeted_runs (
    engine_run_id, analysis_id, user_id, photo_run_id, signal_id,
    photo_index, provider, model, status, normalized_output,
    output_sha256, error_code
  ) values (
    p_engine_run_id, v_run.analysis_id, p_user_id, p_photo_run_id,
    left(p_signal_id, 160), p_photo_index, left(p_provider, 80),
    left(p_model, 160), p_status, p_normalized_output,
    nullif(p_output_sha256, ''), left(nullif(p_error_code, ''), 160)
  )
  on conflict (engine_run_id) do nothing
  returning id into v_targeted_id;

  v_inserted := found;
  if not v_inserted then
    select id into v_targeted_id
    from private.analysis_targeted_runs
    where engine_run_id = p_engine_run_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'state', case when v_inserted then 'checkpointed' else 'already_checkpointed' end,
    'targeted_run_id', v_targeted_id
  );
end;
$$;

create or replace function public.get_analysis_targeted_run_v1(
  p_user_id uuid,
  p_engine_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_targeted private.analysis_targeted_runs%rowtype;
begin
  if not exists (
    select 1
    from private.analysis_engine_runs r
    where r.id = p_engine_run_id and r.user_id = p_user_id
  ) then
    return jsonb_build_object('ok', false, 'state', 'engine_run_not_found');
  end if;

  select * into v_targeted
  from private.analysis_targeted_runs
  where engine_run_id = p_engine_run_id and user_id = p_user_id;

  if not found then
    return jsonb_build_object('ok', true, 'state', 'not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'state', 'found',
    'targeted_run_id', v_targeted.id,
    'signal_id', v_targeted.signal_id,
    'photo_index', v_targeted.photo_index,
    'provider', v_targeted.provider,
    'model', v_targeted.model,
    'status', v_targeted.status,
    'normalized_output', v_targeted.normalized_output,
    'output_sha256', v_targeted.output_sha256,
    'error_code', v_targeted.error_code
  );
end;
$$;

revoke all on function public.checkpoint_analysis_targeted_run_v1(
  uuid, uuid, uuid, text, integer, text, text, text, jsonb, text, text
) from public, anon, authenticated;
revoke all on function public.get_analysis_targeted_run_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.checkpoint_analysis_targeted_run_v1(
  uuid, uuid, uuid, text, integer, text, text, text, jsonb, text, text
) to service_role;
grant execute on function public.get_analysis_targeted_run_v1(uuid, uuid)
  to service_role;

update private.analysis_engine_configs
set config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
      'targeted_checkpoint_version', 1,
      'provider_fact_trace_identity_version', 2
    ),
    updated_at = now()
where engine_version = 'vnext-v3' and is_active = true;
