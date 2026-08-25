-- begin_analysis_engine_run_v4 pinned prompt_version to a literal and wrote
-- prompt/policy/control versions into the run row as literals too. The route
-- gate had the same defect one layer up; fixing that one exposed this one, and
-- the analysis stopped at 98% with v4_snapshot_invalid.
--
-- Migration 20260825120043 already had to hand-edit both literals for the same
-- reason, which is the signal that they should not be literals. The interface
-- check stays - engine_version, schema_version and a well-formed prompt hash -
-- and every version the run row records is now read from the snapshot the
-- route already pinned. A run stays fully attributable without a constant that
-- must be edited on every quality pass.

create or replace function public.begin_analysis_engine_run_v4(
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
  v_route private.analysis_engine_routes%rowtype;
  v_run private.analysis_engine_runs%rowtype;
  v_engine jsonb;
  v_photo_runs jsonb;
begin
  select * into v_state from private.analysis_job_state
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if not found or v_state.active_msg_id is distinct from p_msg_id
    or v_state.generation is distinct from p_generation
    or v_state.claim_token is distinct from p_claim_token then
    return jsonb_build_object('ok', false, 'state', 'lost_claim');
  end if;
  select * into v_route from private.analysis_engine_routes
  where analysis_id = p_analysis_id and user_id = p_user_id;
  if not found or v_route.engine <> 'vnext'
    or v_route.config_snapshot->>'engine_variant' <> 'vnext-v4' then
    return jsonb_build_object('ok', false, 'state', 'route_not_v4');
  end if;
  v_engine := v_route.config_snapshot->'engine_config';
  if coalesce(v_engine->>'engine_version','') <> 'vnext-v4'
    or coalesce(v_engine->>'schema_version','') <> 'safety-claim-v4.0'
    or coalesce(v_engine->>'prompt_version','') = ''
    or coalesce(v_engine->>'prompt_sha256','') !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok', false, 'state', 'v4_snapshot_invalid');
  end if;

  insert into private.analysis_engine_runs (
    analysis_id,user_id,queue_msg_id,job_generation,job_mode,
    engine_version,schema_version,prompt_version,policy_version,
    control_catalog_version,visual_input_mode,provider,model,status,config_snapshot
  ) values (
    p_analysis_id,p_user_id,p_msg_id,p_generation,
    case when p_job_mode='repair' then 'repair' else 'analysis' end,
    'vnext-v4','safety-claim-v4.0',
    v_engine->>'prompt_version',
    coalesce(v_engine->>'policy_version','claim-routing-v3'),
    coalesce(v_engine->>'control_catalog_version','controls-v20'),
    coalesce(v_engine->>'visual_input_mode','native_per_photo'),
    'gemini',coalesce(v_engine->>'primary_model','gemini-2.5-flash'),'running',v_route.config_snapshot
  ) on conflict (analysis_id,job_generation,job_mode) do update set
    queue_msg_id=excluded.queue_msg_id,
    status=case when private.analysis_engine_runs.status='completed' then 'completed' else 'running' end,
    error_code=case when private.analysis_engine_runs.status='completed' then private.analysis_engine_runs.error_code else null end,
    completed_at=case when private.analysis_engine_runs.status='completed' then private.analysis_engine_runs.completed_at else null end,
    updated_at=now()
  returning * into v_run;

  update private.analysis_provider_attempts set state='ambiguous',
    error_code='ambiguous_provider_attempt',updated_at=now()
  where engine_run_id=v_run.id and state='received';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'photo_id',p.photo_id,'photo_index',p.photo_index,
    'storage_path',p.storage_path,'status',p.status,'provider',p.provider,
    'model',p.model,'attempt_count',p.attempt_count,
    'normalized_output',p.normalized_output,'input_tokens',p.input_tokens,
    'output_tokens',p.output_tokens,'reasoning_tokens',p.reasoning_tokens,
    'cost_usd',p.cost_usd,'duration_ms',p.duration_ms,'error_code',p.error_code
  ) order by p.photo_index),'[]'::jsonb)
  into v_photo_runs
  from private.analysis_photo_runs p where p.engine_run_id=v_run.id;

  return jsonb_build_object(
    'ok',true,
    'state',case when v_run.status='completed' then 'completed' else 'running' end,
    'engine_run_id',v_run.id,
    'engine_version',v_run.engine_version,
    'schema_version',v_run.schema_version,
    'prompt_version',v_run.prompt_version,
    'policy_version',v_run.policy_version,
    'control_catalog_version',v_run.control_catalog_version,
    'provider',v_run.provider,
    'model',v_run.model,
    'visual_input_mode',v_run.visual_input_mode,
    'config_snapshot',v_run.config_snapshot,
    'photo_runs',v_photo_runs
  );
end;
$$;
