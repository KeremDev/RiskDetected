-- vNext service-only configuration, per-run inspection and segregated metrics.

create or replace function public.admin_configure_analysis_engine_vnext_v1(
  p_primary_provider text,
  p_gemini_thinking_budget integer default 12288,
  p_openai_reasoning_effort text default 'high'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider text := lower(coalesce(p_primary_provider, ''));
  v_effort text := lower(coalesce(p_openai_reasoning_effort, ''));
  v_config jsonb;
begin
  if v_provider not in ('gemini', 'openai')
    or v_effort not in ('high', 'xhigh', 'max')
    or coalesce(p_gemini_thinking_budget, -1) not between 0 and 24576
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;

  update private.analysis_engine_configs
  set config = config || jsonb_build_object(
        'primary_provider', v_provider,
        'primary_model', case when v_provider = 'gemini'
          then 'gemini-2.5-flash' else 'gpt-5.6-luna' end,
        'fallback_provider', case when v_provider = 'gemini'
          then 'openai' else 'gemini' end,
        'fallback_model', case when v_provider = 'gemini'
          then 'gpt-5.6-luna' else 'gemini-2.5-flash' end,
        'gemini_thinking_budget', p_gemini_thinking_budget,
        'openai_reasoning_effort', v_effort
      ),
      updated_at = now()
  where is_active
  returning config into v_config;

  if v_config is null then
    return jsonb_build_object('ok', false, 'state', 'engine_config_missing');
  end if;
  return jsonb_build_object('ok', true, 'state', 'updated', 'config', v_config);
end;
$$;

create or replace function public.admin_set_analysis_engine_rollout_v1(
  p_rollout_mode text,
  p_kill_switch boolean,
  p_canary_percent integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mode text := lower(coalesce(p_rollout_mode, ''));
  v_value jsonb;
begin
  if v_mode not in ('off', 'shadow', 'user_allowlist', 'canary', 'on')
    or coalesce(p_canary_percent, -1) not between 0 and 100
  then
    return jsonb_build_object('ok', false, 'state', 'validation_failed');
  end if;
  v_value := jsonb_build_object(
    'policy_version', 3,
    'rollout_mode', v_mode,
    'kill_switch', coalesce(p_kill_switch, true),
    'canary_percent', p_canary_percent,
    'engine_version', 'vnext-v3'
  );
  insert into public.app_feature_flags (key, value)
  values ('analysis_engine_vnext', v_value)
  on conflict (key) do update set value = excluded.value;
  return jsonb_build_object('ok', true, 'state', 'updated', 'value', v_value);
end;
$$;

create or replace function public.admin_analysis_engine_run_v3(
  p_analysis_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
with target as (
  select r.*, a.status::text as analysis_status, a.photo_count,
    a.finding_count, a.created_at as analysis_created_at,
    a.completed_at as analysis_completed_at,
    coalesce(a.raw_ai_response->'_quality_trace_v3', '{}'::jsonb) as trace
  from private.analysis_engine_runs r
  join public.analyses a on a.id = r.analysis_id
  where r.analysis_id = p_analysis_id
  order by r.started_at desc
  limit 1
), photos as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'photo_run_id', p.id, 'photo_id', p.photo_id, 'photo_index', p.photo_index,
    'storage_path', p.storage_path, 'provider', p.provider, 'model', p.model,
    'status', p.status, 'attempt_count', p.attempt_count,
    'raw_fact_count', coalesce(jsonb_array_length(p.normalized_output->'hazard_facts'), 0),
    'inventory_count', coalesce(jsonb_array_length(p.normalized_output->'scene_inventory'), 0),
    'module_audit_count', coalesce(jsonb_array_length(p.normalized_output->'module_audit'), 0),
    'signal_count', coalesce(jsonb_array_length(p.normalized_output->'inspection_signals'), 0),
    'output_sha256', p.output_sha256,
    'input_tokens', p.input_tokens, 'output_tokens', p.output_tokens,
    'reasoning_tokens', p.reasoning_tokens, 'cost_usd', p.cost_usd,
    'duration_ms', p.duration_ms, 'error_code', p.error_code
  ) order by p.photo_index), '[]'::jsonb) value
  from private.analysis_photo_runs p
  where p.engine_run_id = (select id from target)
), attempts as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'attempt_id', p.id, 'photo_run_id', p.photo_run_id,
    'attempt_kind', p.attempt_kind, 'attempt_number', p.attempt_number,
    'provider', p.provider, 'model', p.model, 'state', p.state,
    'provider_request_id', p.provider_request_id,
    'input_tokens', p.input_tokens, 'output_tokens', p.output_tokens,
    'reasoning_tokens', p.reasoning_tokens,
    'cached_input_tokens', p.cached_input_tokens, 'cost_usd', p.cost_usd,
    'duration_ms', p.duration_ms, 'http_status', p.http_status,
    'error_code', p.error_code, 'created_at', p.created_at
  ) order by p.created_at), '[]'::jsonb) value
  from private.analysis_provider_attempts p
  where p.engine_run_id = (select id from target)
), lineage as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'fact_trace_id', l.fact_trace_id, 'final_ordinal', l.final_ordinal,
    'final_finding_id', l.final_finding_id,
    'source_photo_indices', l.source_photo_indices,
    'evidence_regions', l.evidence_regions,
    'semantic_inputs', l.semantic_inputs, 'score_output', l.score_output,
    'mutations', l.mutations, 'reason_codes', l.reason_codes
  ) order by l.final_ordinal nulls last), '[]'::jsonb) value
  from private.analysis_fact_lineage l
  where l.engine_run_id = (select id from target)
), counts as (
  select
    (select count(*) from public.findings f where f.analysis_id = p_analysis_id)::integer as database_findings,
    (select count(*) from private.analysis_module_audits m where m.engine_run_id = (select id from target))::integer as module_audits,
    (select count(*) from private.analysis_inspection_signals s where s.engine_run_id = (select id from target))::integer as inspection_signals,
    (select count(*) from private.analysis_fact_lineage l where l.engine_run_id = (select id from target))::integer as lineage_rows
)
select case when not exists (select 1 from target) then
  jsonb_build_object('analysis_id', p_analysis_id, 'status', 'not_found')
else (
  select jsonb_build_object(
    'version', 3, 'analysis_id', t.analysis_id,
    'analysis_status', t.analysis_status, 'engine_run_status', t.status,
    'engine_run_id', t.id, 'engine_version', t.engine_version,
    'schema_version', t.schema_version, 'prompt_version', t.prompt_version,
    'policy_version', t.policy_version,
    'control_catalog_version', t.control_catalog_version,
    'visual_input_mode', t.visual_input_mode,
    'provider', t.provider, 'model', t.model,
    'photo_count', t.photo_count, 'analysis_finding_count', t.finding_count,
    'database_finding_count', c.database_findings,
    'trace_final_count', case when t.trace->>'final_count' ~ '^[0-9]+$'
      then (t.trace->>'final_count')::integer else null end,
    'count_invariant_ok', c.database_findings = t.finding_count
      and c.database_findings = coalesce((t.trace->>'final_count')::integer, c.database_findings),
    'stages', coalesce(t.trace->'stages', '[]'::jsonb),
    'rejection_ledger', coalesce(t.trace->'rejection_ledger', '[]'::jsonb),
    'merge_ledger', coalesce(t.trace->'merge_ledger', '[]'::jsonb),
    'photo_runs', p.value, 'provider_attempts', a.value,
    'fact_lineage', l.value,
    'module_audit_count', c.module_audits,
    'inspection_signal_count', c.inspection_signals,
    'lineage_count', c.lineage_rows,
    'provider_request_count', t.total_provider_requests,
    'input_tokens', t.total_input_tokens, 'output_tokens', t.total_output_tokens,
    'reasoning_tokens', t.total_reasoning_tokens,
    'cost_usd', t.total_cost_usd, 'duration_ms', t.duration_ms,
    'started_at', t.started_at, 'completed_at', t.completed_at,
    'error_code', t.error_code
  ) from target t cross join photos p cross join attempts a
    cross join lineage l cross join counts c
)
end;
$$;

create or replace function private.analysis_engine_window_v3(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
with runs as (
  select r.*, a.output_language, a.canvas::text canvas,
    coalesce(a.plan_at_creation, 'free') plan,
    coalesce(a.raw_ai_response->'_quality_trace_v3', '{}'::jsonb) trace,
    (select count(*) from private.analysis_photo_runs p
      where p.engine_run_id = r.id and p.status = 'completed')::integer photos,
    (select count(*) from public.findings f where f.analysis_id = r.analysis_id)::integer final_findings,
    (select count(*) from public.analysis_photo_summaries s
      where s.analysis_id = r.analysis_id and coalesce(s.generated_findings_count, 0) = 0)::integer zero_photos,
    coalesce((select (stage->>'total')::integer
      from jsonb_array_elements(coalesce(a.raw_ai_response->'_quality_trace_v3'->'stages', '[]'::jsonb)) stage
      where stage->>'name' = 'provider_parsed_fact' limit 1), 0)::integer raw_facts,
    coalesce((select (stage->>'total')::integer
      from jsonb_array_elements(coalesce(a.raw_ai_response->'_quality_trace_v3'->'stages', '[]'::jsonb)) stage
      where stage->>'name' = 'evidence_valid_fact' limit 1), 0)::integer evidence_valid,
    coalesce((select (stage->>'total')::integer
      from jsonb_array_elements(coalesce(a.raw_ai_response->'_quality_trace_v3'->'stages', '[]'::jsonb)) stage
      where stage->>'name' = 'targeted_added_fact' limit 1), 0)::integer targeted_added,
    coalesce((select count(*) from jsonb_array_elements(coalesce(a.raw_ai_response->'_quality_trace_v3'->'rejection_ledger', '[]'::jsonb)) x
      where x->>'reason_code' in ('evidence_unlinked','evidence_non_actionable','absence_only_claim','process_link_invalid','contextual_ppe_rejected')), 0)::integer guard_rejected,
    coalesce((select count(*) from jsonb_array_elements(coalesce(a.raw_ai_response->'_quality_trace_v3'->'rejection_ledger', '[]'::jsonb)) x
      where x->>'reason_code' in ('duplicate_exact','duplicate_fuzzy')), 0)::integer dedup_rejected,
    coalesce(jsonb_array_length(a.raw_ai_response->'_quality_trace_v3'->'merge_ledger'), 0)::integer cross_photo_merged,
    (select count(*) from private.analysis_provider_attempts pa where pa.engine_run_id = r.id and pa.attempt_kind = 'targeted_reinspection')::integer targeted_calls,
    (select count(*) from private.analysis_provider_attempts pa where pa.engine_run_id = r.id and pa.state in ('failed','ambiguous'))::integer provider_errors
  from private.analysis_engine_runs r
  join public.analyses a on a.id = r.analysis_id
  where r.status = 'completed' and a.status::text = 'completed'
    and r.completed_at >= p_from and r.completed_at < p_to
), cohort as (
  select prompt_version, policy_version, provider, model, plan,
    coalesce(output_language, 'unknown') output_language, canvas,
    case when photos > 1 then 'multi_photo' else 'single_photo' end photo_mode,
    count(*) analyses, sum(photos) photos, sum(raw_facts) raw_facts,
    sum(final_findings) final_findings, sum(zero_photos) zero_photos,
    sum(total_cost_usd) cost_usd, sum(duration_ms) duration_ms
  from runs
  group by prompt_version, policy_version, provider, model, plan,
    output_language, canvas, photo_mode
), score_rows as (
  select f.fk_probability, f.fk_frequency, f.fk_severity,
    f.m5_probability, f.m5_severity
  from public.findings f
  join runs r on r.analysis_id = f.analysis_id
)
select jsonb_build_object(
  'analyses', count(*), 'sample_photos', coalesce(sum(photos), 0),
  'raw_facts', coalesce(sum(raw_facts), 0),
  'final_findings', coalesce(sum(final_findings), 0),
  'raw_facts_per_photo', round(coalesce(sum(raw_facts), 0)::numeric / nullif(sum(photos), 0), 4),
  'final_findings_per_photo', round(coalesce(sum(final_findings), 0)::numeric / nullif(sum(photos), 0), 4),
  'zero_finding_photo_rate', round(coalesce(sum(zero_photos), 0)::numeric / nullif(sum(photos), 0), 4),
  'raw_to_final_retention', round(coalesce(sum(final_findings), 0)::numeric / nullif(sum(raw_facts), 0), 4),
  'evidence_retention', round(coalesce(sum(evidence_valid), 0)::numeric / nullif(sum(raw_facts), 0), 4),
  'guard_rejected', coalesce(sum(guard_rejected), 0),
  'dedup_rejected', coalesce(sum(dedup_rejected), 0),
  'cross_photo_merged', coalesce(sum(cross_photo_merged), 0),
  'targeted_calls', coalesce(sum(targeted_calls), 0),
  'targeted_added', coalesce(sum(targeted_added), 0),
  'targeted_yield', round(coalesce(sum(targeted_added), 0)::numeric / nullif(sum(targeted_calls), 0), 4),
  'provider_calls', coalesce(sum(total_provider_requests), 0),
  'provider_errors', coalesce(sum(provider_errors), 0),
  'input_tokens', coalesce(sum(total_input_tokens), 0),
  'output_tokens', coalesce(sum(total_output_tokens), 0),
  'reasoning_tokens', coalesce(sum(total_reasoning_tokens), 0),
  'cost_usd', coalesce(sum(total_cost_usd), 0),
  'average_cost_usd', round(coalesce(sum(total_cost_usd), 0) / nullif(count(*), 0), 6),
  'duration_ms', coalesce(sum(duration_ms), 0),
  'average_duration_ms', round(coalesce(sum(duration_ms), 0)::numeric / nullif(count(*), 0), 0),
  'score_distributions', jsonb_build_object(
    'fk_probability', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select fk_probability::text v, count(*) n from score_rows group by 1) q),
    'fk_frequency', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select fk_frequency::text v, count(*) n from score_rows group by 1) q),
    'fk_severity', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select fk_severity::text v, count(*) n from score_rows group by 1) q),
    'm5_probability', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select m5_probability::text v, count(*) n from score_rows group by 1) q),
    'm5_severity', (select coalesce(jsonb_object_agg(v, n), '{}'::jsonb) from (select m5_severity::text v, count(*) n from score_rows group by 1) q)
  ),
  'cohorts', (select coalesce(jsonb_agg(jsonb_build_object(
    'prompt_version', prompt_version, 'policy_version', policy_version,
    'provider', provider, 'model', model, 'plan', plan,
    'output_language', output_language, 'canvas', canvas, 'photo_mode', photo_mode,
    'analyses', analyses, 'photos', photos,
    'raw_facts_per_photo', round(raw_facts::numeric / nullif(photos, 0), 4),
    'final_findings_per_photo', round(final_findings::numeric / nullif(photos, 0), 4),
    'zero_finding_photo_rate', round(zero_photos::numeric / nullif(photos, 0), 4),
    'cost_usd', cost_usd, 'duration_ms', duration_ms
  ) order by analyses desc), '[]'::jsonb) from cohort)
) from runs;
$$;

create or replace function public.admin_analysis_engine_metrics_v3(
  current_days integer default 7,
  baseline_days integer default 28
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := now();
  v_current_days integer := greatest(1, least(coalesce(current_days, 7), 90));
  v_baseline_days integer := greatest(1, least(coalesce(baseline_days, 28), 365));
  v_current jsonb;
  v_baseline jsonb;
begin
  v_current := private.analysis_engine_window_v3(
    v_now - make_interval(days => v_current_days), v_now
  );
  v_baseline := private.analysis_engine_window_v3(
    v_now - make_interval(days => v_current_days + v_baseline_days),
    v_now - make_interval(days => v_current_days)
  );
  return jsonb_build_object(
    'version', 3, 'engine', 'vnext', 'generated_at', v_now,
    'current', v_current, 'baseline', v_baseline,
    'sample_status', case
      when coalesce((v_current->>'sample_photos')::integer, 0) < 10
        or coalesce((v_baseline->>'sample_photos')::integer, 0) < 20
      then 'insufficient_sample' else 'sufficient' end,
    'comparison', jsonb_build_object(
      'final_findings_per_photo_change_ratio', case
        when nullif((v_baseline->>'final_findings_per_photo')::numeric, 0) is null then null
        else round(((v_current->>'final_findings_per_photo')::numeric - (v_baseline->>'final_findings_per_photo')::numeric) / (v_baseline->>'final_findings_per_photo')::numeric, 4) end,
      'raw_facts_per_photo_change_ratio', case
        when nullif((v_baseline->>'raw_facts_per_photo')::numeric, 0) is null then null
        else round(((v_current->>'raw_facts_per_photo')::numeric - (v_baseline->>'raw_facts_per_photo')::numeric) / (v_baseline->>'raw_facts_per_photo')::numeric, 4) end,
      'zero_finding_photo_rate_change_points', round(coalesce((v_current->>'zero_finding_photo_rate')::numeric, 0) - coalesce((v_baseline->>'zero_finding_photo_rate')::numeric, 0), 4),
      'retention_change_points', round(coalesce((v_current->>'raw_to_final_retention')::numeric, 0) - coalesce((v_baseline->>'raw_to_final_retention')::numeric, 0), 4)
    )
  );
end;
$$;

insert into public.admin_alert_rules (
  rule_key, name, description, metric_key, operator, threshold, severity,
  cooldown_minutes
) values
  ('vnext_final_findings_per_photo_drop', 'vNext final bulgu/fotoğraf düşüşü', 'vNext final bulgu/fotoğraf baseline değerine göre düştü.', 'vnext_final_findings_per_photo_drop_ratio', 'gte', 0.30, 'warning', 1440),
  ('vnext_raw_facts_per_photo_drop', 'vNext ham fact/fotoğraf düşüşü', 'vNext ham fact/fotoğraf baseline değerine göre düştü.', 'vnext_raw_facts_per_photo_drop_ratio', 'gte', 0.30, 'warning', 1440),
  ('vnext_zero_finding_photo_rate_rise', 'vNext sıfır bulgulu fotoğraf artışı', 'vNext sıfır bulgulu fotoğraf oranı iki katına ve en az 15 puan arttı.', 'vnext_zero_finding_photo_rate_change_points', 'gte', 0.15, 'warning', 1440),
  ('vnext_raw_final_retention_drop', 'vNext ham-final retention düşüşü', 'vNext raw fact-final finding retention en az 20 puan düştü.', 'vnext_raw_to_final_retention_drop_points', 'gte', 0.20, 'warning', 1440)
on conflict (rule_key) do update set
  name = excluded.name, description = excluded.description,
  metric_key = excluded.metric_key, operator = excluded.operator,
  threshold = excluded.threshold, severity = excluded.severity,
  cooldown_minutes = excluded.cooldown_minutes, updated_at = now();

create or replace function private.evaluate_analysis_engine_regressions_v3()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_metrics jsonb := public.admin_analysis_engine_metrics_v3(7, 28);
  v_current jsonb;
  v_baseline jsonb;
  v_final_drop numeric := 0;
  v_raw_drop numeric := 0;
  v_zero_current numeric := 0;
  v_zero_baseline numeric := 0;
  v_retention_drop numeric := 0;
  v_emitted integer := 0;
begin
  if v_metrics->>'sample_status' <> 'sufficient' then
    return jsonb_build_object(
      'status', 'insufficient_sample',
      'current_photos', coalesce((v_metrics->'current'->>'sample_photos')::integer, 0),
      'baseline_photos', coalesce((v_metrics->'baseline'->>'sample_photos')::integer, 0),
      'alerts_emitted', 0
    );
  end if;
  v_current := v_metrics->'current';
  v_baseline := v_metrics->'baseline';
  v_final_drop := 1 - coalesce((v_current->>'final_findings_per_photo')::numeric, 0)
    / nullif((v_baseline->>'final_findings_per_photo')::numeric, 0);
  v_raw_drop := 1 - coalesce((v_current->>'raw_facts_per_photo')::numeric, 0)
    / nullif((v_baseline->>'raw_facts_per_photo')::numeric, 0);
  v_zero_current := coalesce((v_current->>'zero_finding_photo_rate')::numeric, 0);
  v_zero_baseline := coalesce((v_baseline->>'zero_finding_photo_rate')::numeric, 0);
  v_retention_drop := coalesce((v_baseline->>'raw_to_final_retention')::numeric, 0)
    - coalesce((v_current->>'raw_to_final_retention')::numeric, 0);

  if v_final_drop >= 0.30 then
    if private.record_analysis_quality_alert_v1(
      'vnext_final_findings_per_photo_drop',
      case when v_final_drop >= 0.45 then 'critical' else 'warning' end,
      v_final_drop, case when v_final_drop >= 0.45 then 0.45 else 0.30 end,
      'vNext final bulgu/fotoğraf regresyonu',
      format('vNext final bulgu/fotoğraf baseline değerine göre %% %s düştü.', round(v_final_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else perform private.resolve_analysis_quality_alert_v1('vnext_final_findings_per_photo_drop'); end if;

  if v_raw_drop >= 0.30 then
    if private.record_analysis_quality_alert_v1(
      'vnext_raw_facts_per_photo_drop',
      case when v_raw_drop >= 0.45 then 'critical' else 'warning' end,
      v_raw_drop, case when v_raw_drop >= 0.45 then 0.45 else 0.30 end,
      'vNext ham fact/fotoğraf regresyonu',
      format('vNext ham fact/fotoğraf baseline değerine göre %% %s düştü.', round(v_raw_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else perform private.resolve_analysis_quality_alert_v1('vnext_raw_facts_per_photo_drop'); end if;

  if v_zero_current >= v_zero_baseline * 2 and v_zero_current - v_zero_baseline >= 0.15 then
    if private.record_analysis_quality_alert_v1(
      'vnext_zero_finding_photo_rate_rise', 'warning',
      v_zero_current - v_zero_baseline, 0.15,
      'vNext sıfır bulgulu fotoğraf regresyonu',
      format('vNext sıfır bulgulu fotoğraf oranı %% %s; baseline %% %s.', round(v_zero_current * 100, 1), round(v_zero_baseline * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else perform private.resolve_analysis_quality_alert_v1('vnext_zero_finding_photo_rate_rise'); end if;

  if v_retention_drop >= 0.20 then
    if private.record_analysis_quality_alert_v1(
      'vnext_raw_final_retention_drop', 'warning', v_retention_drop, 0.20,
      'vNext ham-final retention regresyonu',
      format('vNext raw→final retention %s puan düştü.', round(v_retention_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else perform private.resolve_analysis_quality_alert_v1('vnext_raw_final_retention_drop'); end if;

  return jsonb_build_object(
    'status', 'evaluated', 'alerts_emitted', v_emitted,
    'final_drop_ratio', round(v_final_drop, 4),
    'raw_drop_ratio', round(v_raw_drop, 4),
    'zero_rate_change_points', round(v_zero_current - v_zero_baseline, 4),
    'retention_drop_points', round(v_retention_drop, 4)
  );
end;
$$;

revoke all on function public.admin_configure_analysis_engine_vnext_v1(text, integer, text) from public, anon, authenticated;
revoke all on function public.admin_set_analysis_engine_rollout_v1(text, boolean, integer) from public, anon, authenticated;
revoke all on function public.admin_analysis_engine_run_v3(uuid) from public, anon, authenticated;
revoke all on function public.admin_analysis_engine_metrics_v3(integer, integer) from public, anon, authenticated;
revoke all on function private.analysis_engine_window_v3(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function private.evaluate_analysis_engine_regressions_v3() from public, anon, authenticated;

grant execute on function public.admin_configure_analysis_engine_vnext_v1(text, integer, text) to service_role;
grant execute on function public.admin_set_analysis_engine_rollout_v1(text, boolean, integer) to service_role;
grant execute on function public.admin_analysis_engine_run_v3(uuid) to service_role;
grant execute on function public.admin_analysis_engine_metrics_v3(integer, integer) to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'riskdetected-analysis-quality-daily') then
    perform cron.unschedule('riskdetected-analysis-quality-daily');
  end if;
  perform cron.schedule(
    'riskdetected-analysis-quality-daily',
    '15 3 * * *',
    'select private.evaluate_analysis_quality_regressions_v1(), private.evaluate_analysis_engine_regressions_v3();'
  );
end
$$;

select pg_notify('pgrst', 'reload schema');
