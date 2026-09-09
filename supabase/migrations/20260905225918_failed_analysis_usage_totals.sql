-- Keep terminal failures as observable as successful runs. Attempts are the source of truth;
-- never invent token usage for a provider error which returned no usage metadata.
create or replace function public.fail_analysis_engine_run_v3(
  p_user_id uuid, p_engine_run_id uuid, p_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run private.analysis_engine_runs%rowtype;
begin
  select * into v_run from private.analysis_engine_runs
  where id = p_engine_run_id and user_id = p_user_id for update;
  if not found or v_run.status not in ('running', 'failed') then
    return jsonb_build_object('ok', false, 'state', 'not_active_or_failed');
  end if;

  update private.analysis_engine_runs r
  set status = 'failed',
      error_code = case when v_run.status = 'failed' then v_run.error_code
        else left(nullif(p_error_code, ''), 160) end,
      total_provider_requests = a.requests,
      total_input_tokens = a.input_tokens,
      total_output_tokens = a.output_tokens,
      total_reasoning_tokens = a.reasoning_tokens,
      total_cost_usd = a.cost_usd,
      total_standard_equivalent_cost_usd = a.standard_cost,
      duration_ms = greatest(0, floor(extract(epoch from
        (coalesce(v_run.completed_at, now()) - v_run.started_at)) * 1000))::bigint,
      completed_at = coalesce(v_run.completed_at, now()),
      updated_at = now()
  from (
    select count(*)::integer as requests,
      coalesce(sum(input_tokens), 0) as input_tokens,
      coalesce(sum(output_tokens), 0) as output_tokens,
      coalesce(sum(reasoning_tokens), 0) as reasoning_tokens,
      coalesce(sum(cost_usd), 0) as cost_usd,
      coalesce(sum(standard_equivalent_cost_usd), 0) as standard_cost
    from private.analysis_provider_attempts where engine_run_id = p_engine_run_id
  ) a
  where r.id = p_engine_run_id and r.user_id = p_user_id;
  return jsonb_build_object('ok', true, 'state', 'recorded');
end;
$$;

revoke all on function public.fail_analysis_engine_run_v3(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.fail_analysis_engine_run_v3(uuid, uuid, text) to service_role;

-- Repair only failed terminal summaries using existing attempts; no model calls or quota writes.
do $$
declare r record;
begin
  for r in select id, user_id, error_code from private.analysis_engine_runs where status = 'failed'
  loop
    perform public.fail_analysis_engine_run_v3(r.user_id, r.id, r.error_code);
  end loop;
end;
$$;
