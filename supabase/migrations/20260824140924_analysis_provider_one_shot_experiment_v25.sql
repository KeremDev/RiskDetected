-- One-shot, server-authorized provider experiments for paired quality/cost
-- comparisons. The override is consumed atomically when a new vNext route is
-- pinned and never comes from the client request.

create table if not exists private.analysis_provider_experiment_overrides (
  experiment_id uuid not null default gen_random_uuid(),
  user_id uuid primary key references auth.users(id) on delete cascade,
  provider text not null,
  model text not null,
  reasoning_effort text not null default 'high',
  remaining_analyses integer not null default 1,
  enabled boolean not null default false,
  experiment_label text not null,
  expires_at timestamptz not null,
  last_consumed_analysis_id uuid references public.analyses(id)
    on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint analysis_provider_experiment_provider_check
    check (provider = 'openai'),
  constraint analysis_provider_experiment_model_check
    check (model = 'gpt-5.6-luna'),
  constraint analysis_provider_experiment_effort_check
    check (reasoning_effort in ('high', 'xhigh', 'max')),
  constraint analysis_provider_experiment_remaining_check
    check (remaining_analyses between 0 and 10),
  constraint analysis_provider_experiment_label_check
    check (char_length(experiment_label) between 1 and 80)
);

create unique index if not exists analysis_provider_experiment_id_idx
  on private.analysis_provider_experiment_overrides (experiment_id);
create index if not exists analysis_provider_experiment_active_idx
  on private.analysis_provider_experiment_overrides
    (enabled, expires_at)
  where enabled and remaining_analyses > 0;

alter table private.analysis_provider_experiment_overrides
  enable row level security;
revoke all on table private.analysis_provider_experiment_overrides
  from public, anon, authenticated;
grant select, insert, update, delete
  on table private.analysis_provider_experiment_overrides to service_role;

create or replace function public.arm_analysis_provider_experiment_v1(
  p_user_id uuid,
  p_model text,
  p_reasoning_effort text default 'high',
  p_remaining_analyses integer default 1,
  p_expires_at timestamptz default (now() + interval '2 hours'),
  p_experiment_label text default 'provider-quality-cost-a-b-v1'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_override private.analysis_provider_experiment_overrides%rowtype;
begin
  if p_user_id is null
    or p_model <> 'gpt-5.6-luna'
    or p_reasoning_effort not in ('high', 'xhigh', 'max')
    or coalesce(p_remaining_analyses, 0) not between 1 and 10
    or p_expires_at is null
    or p_expires_at <= now()
    or p_expires_at > now() + interval '24 hours'
    or char_length(coalesce(p_experiment_label, '')) not between 1 and 80
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;

  if not exists (
    select 1
    from private.analysis_engine_allowlist a
    where a.user_id = p_user_id and a.enabled
  ) then
    return jsonb_build_object('ok', false, 'state', 'user_not_allowlisted');
  end if;

  insert into private.analysis_provider_experiment_overrides (
    experiment_id, user_id, provider, model, reasoning_effort,
    remaining_analyses, enabled, experiment_label, expires_at,
    last_consumed_analysis_id, updated_at
  ) values (
    gen_random_uuid(), p_user_id, 'openai', p_model, p_reasoning_effort,
    p_remaining_analyses, true, p_experiment_label, p_expires_at,
    null, now()
  )
  on conflict (user_id) do update set
    experiment_id = gen_random_uuid(),
    provider = excluded.provider,
    model = excluded.model,
    reasoning_effort = excluded.reasoning_effort,
    remaining_analyses = excluded.remaining_analyses,
    enabled = true,
    experiment_label = excluded.experiment_label,
    expires_at = excluded.expires_at,
    last_consumed_analysis_id = null,
    updated_at = now()
  returning * into v_override;

  return jsonb_build_object(
    'ok', true,
    'state', 'armed',
    'experiment_id', v_override.experiment_id,
    'provider', v_override.provider,
    'model', v_override.model,
    'reasoning_effort', v_override.reasoning_effort,
    'remaining_analyses', v_override.remaining_analyses,
    'expires_at', v_override.expires_at,
    'experiment_label', v_override.experiment_label
  );
end;
$$;

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
  v_snapshot jsonb;
  v_profile_config jsonb := '{}'::jsonb;
  v_experiment private.analysis_provider_experiment_overrides%rowtype;
  v_experiment_applied boolean := false;
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

  v_engine_config := coalesce(
    v_route.config_snapshot->'engine_config',
    '{}'::jsonb
  );
  v_route_name := nullif(p_compute_routing->>'ai_execution_route', '');
  v_snapshot_valid := coalesce(
      (p_compute_routing->>'snapshot_version')::integer,
      0
    ) = 1
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
  elsif coalesce(
      (v_engine_config->>'compute_profile_routing_enabled')::boolean,
      false
    )
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

  -- Only a valid, new vNext route may atomically consume the one-shot row.
  if v_snapshot_valid
    and v_validation_reason = 'trusted_route_valid'
    and v_route.engine = 'vnext'
  then
    update private.analysis_provider_experiment_overrides e
    set remaining_analyses = e.remaining_analyses - 1,
        enabled = (e.remaining_analyses - 1) > 0,
        last_consumed_analysis_id = p_analysis_id,
        updated_at = now()
    where e.user_id = p_user_id
      and e.enabled
      and e.remaining_analyses > 0
      and e.expires_at > now()
      and exists (
        select 1 from private.analysis_engine_allowlist a
        where a.user_id = p_user_id and a.enabled
      )
    returning * into v_experiment;

    if found then
      v_experiment_applied := true;
      v_profile_config := coalesce(
        v_engine_config->'compute_profiles'->v_compute_profile,
        '{}'::jsonb
      );
      if jsonb_typeof(v_profile_config) <> 'object' then
        v_profile_config := '{}'::jsonb;
      end if;
      v_profile_config := v_profile_config || jsonb_build_object(
        'primary_provider', v_experiment.provider,
        'primary_model', v_experiment.model,
        'fallback_provider', v_experiment.provider,
        'fallback_model', v_experiment.model,
        'openai_reasoning_effort', v_experiment.reasoning_effort
      );
      if jsonb_typeof(v_engine_config->'compute_profiles') <> 'object' then
        v_engine_config := jsonb_set(
          v_engine_config,
          '{compute_profiles}',
          '{}'::jsonb,
          true
        );
      end if;
      v_engine_config := jsonb_set(
        v_engine_config,
        array['compute_profiles', v_compute_profile],
        v_profile_config,
        true
      );
      v_provider_pool := 'paid_standard';
      v_service_tier := 'standard';
    end if;
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
    end,
    'provider_experiment_id', case when v_experiment_applied
      then v_experiment.experiment_id else null end,
    'provider_experiment_label', case when v_experiment_applied
      then v_experiment.experiment_label else null end,
    'provider_experiment_one_shot', v_experiment_applied,
    'provider_experiment_provider', case when v_experiment_applied
      then v_experiment.provider else null end,
    'provider_experiment_model', case when v_experiment_applied
      then v_experiment.model else null end,
    'provider_experiment_reasoning_effort', case when v_experiment_applied
      then v_experiment.reasoning_effort else null end
  );

  v_snapshot := jsonb_set(
    jsonb_set(
      v_route.config_snapshot,
      '{engine_config}',
      v_engine_config,
      true
    ),
    '{compute_routing}',
    v_routing,
    true
  );

  update private.analysis_engine_routes
  set config_snapshot = v_snapshot
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

-- begin_analysis_engine_run_v3 historically copied provider from the global
-- config while model came from the pinned route. Correct both columns from the
-- selected per-run profile before insert so experiment telemetry is exact.
create or replace function private.apply_analysis_run_provider_snapshot_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_profile text;
  v_provider text;
  v_model text;
begin
  v_profile := coalesce(
    new.config_snapshot #>> '{compute_routing,compute_profile}',
    'premium'
  );
  v_provider := new.config_snapshot #>> array[
    'engine_config', 'compute_profiles', v_profile, 'primary_provider'
  ];
  v_model := new.config_snapshot #>> array[
    'engine_config', 'compute_profiles', v_profile, 'primary_model'
  ];
  if v_provider in ('gemini', 'openai') then
    new.provider := v_provider;
  end if;
  if nullif(v_model, '') is not null then
    new.model := left(v_model, 160);
  end if;
  return new;
end;
$$;

drop trigger if exists analysis_run_provider_snapshot
  on private.analysis_engine_runs;
create trigger analysis_run_provider_snapshot
before insert on private.analysis_engine_runs
for each row execute function private.apply_analysis_run_provider_snapshot_v1();

revoke all on function public.arm_analysis_provider_experiment_v1(
  uuid, text, text, integer, timestamptz, text
) from public, anon, authenticated;
grant execute on function public.arm_analysis_provider_experiment_v1(
  uuid, text, text, integer, timestamptz, text
) to service_role;

-- Preserve the existing service-only contract after replacing v4.
revoke all on function public.resolve_analysis_engine_route_v4(
  uuid, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.resolve_analysis_engine_route_v4(
  uuid, uuid, jsonb
) to service_role;

select pg_notify('pgrst', 'reload schema');
