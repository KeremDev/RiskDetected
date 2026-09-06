-- Run after the migration INSIDE a transaction, then ROLLBACK.
-- This integration check uses existing failed runs with provider attempts; no model calls.
do $$
declare
  r private.analysis_engine_runs%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
begin
  select * into r from private.analysis_engine_runs
  where status = 'failed' and exists (
    select 1 from private.analysis_provider_attempts a where a.engine_run_id = analysis_engine_runs.id
  ) order by started_at desc limit 1;
  if not found then raise exception 'fixture_missing: need a failed run with attempts'; end if;

  perform public.fail_analysis_engine_run_v3(r.user_id, r.id, r.error_code);
  if exists (
    select 1 from private.analysis_engine_runs e where e.id = r.id and (
      e.total_provider_requests <> (select count(*) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
      or e.total_input_tokens <> (select coalesce(sum(input_tokens),0) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
      or e.total_output_tokens <> (select coalesce(sum(output_tokens),0) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
      or e.total_reasoning_tokens <> (select coalesce(sum(reasoning_tokens),0) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
      or e.total_cost_usd <> (select coalesce(sum(cost_usd),0) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
      or e.total_standard_equivalent_cost_usd <> (select coalesce(sum(standard_equivalent_cost_usd),0) from private.analysis_provider_attempts a where a.engine_run_id = r.id)
    )
  ) then raise exception 'failed totals do not match attempts'; end if;

  select to_jsonb(e) - 'updated_at' into v_before from private.analysis_engine_runs e where id = r.id;
  perform public.fail_analysis_engine_run_v3(r.user_id, r.id, 'must_not_replace_original_error');
  select to_jsonb(e) - 'updated_at' into v_after from private.analysis_engine_runs e where id = r.id;
  if v_before <> v_after then raise exception 'repeated failure is not idempotent'; end if;
  v_result := public.fail_analysis_engine_run_v3('00000000-0000-0000-0000-000000000000', r.id, 'wrong_owner');
  if (v_result->>'ok')::boolean then raise exception 'wrong owner accepted'; end if;
  if has_function_privilege('authenticated', 'public.fail_analysis_engine_run_v3(uuid,uuid,text)', 'execute')
    or has_function_privilege('anon', 'public.fail_analysis_engine_run_v3(uuid,uuid,text)', 'execute') then
    raise exception 'privileged function exposed';
  end if;
end;
$$;
