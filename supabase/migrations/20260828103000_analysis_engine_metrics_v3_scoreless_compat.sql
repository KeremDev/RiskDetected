-- Keep the historical v3 metrics window isolated from v4 scoreless items.
-- `jsonb_object_agg` rejects a NULL field name; v4 intentionally persists
-- assurance/verification rows with nullable P/F/S values. The v3 window used
-- to read every engine version and every finding, which broke the daily quality
-- evaluator as soon as scoreless rows existed.

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
    (select count(*) from public.findings f
      where f.analysis_id = r.analysis_id and coalesce(f.is_scored, true))::integer final_findings,
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
  where r.engine_version = 'vnext-v3'
    and r.status = 'completed' and a.status::text = 'completed'
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
  where coalesce(f.is_scored, true)
), distributions as (
  select jsonb_build_object(
    'fk_probability', (select coalesce(jsonb_object_agg(v, n) filter (where v is not null), '{}'::jsonb) from (select fk_probability::text v, count(*) n from score_rows where fk_probability is not null group by 1) q),
    'fk_frequency', (select coalesce(jsonb_object_agg(v, n) filter (where v is not null), '{}'::jsonb) from (select fk_frequency::text v, count(*) n from score_rows where fk_frequency is not null group by 1) q),
    'fk_severity', (select coalesce(jsonb_object_agg(v, n) filter (where v is not null), '{}'::jsonb) from (select fk_severity::text v, count(*) n from score_rows where fk_severity is not null group by 1) q),
    'm5_probability', (select coalesce(jsonb_object_agg(v, n) filter (where v is not null), '{}'::jsonb) from (select m5_probability::text v, count(*) n from score_rows where m5_probability is not null group by 1) q),
    'm5_severity', (select coalesce(jsonb_object_agg(v, n) filter (where v is not null), '{}'::jsonb) from (select m5_severity::text v, count(*) n from score_rows where m5_severity is not null group by 1) q)
  ) value
), cohorts as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'prompt_version', prompt_version, 'policy_version', policy_version,
    'provider', provider, 'model', model, 'plan', plan,
    'output_language', output_language, 'canvas', canvas, 'photo_mode', photo_mode,
    'analyses', analyses, 'photos', photos,
    'raw_facts_per_photo', round(raw_facts::numeric / nullif(photos, 0), 4),
    'final_findings_per_photo', round(final_findings::numeric / nullif(photos, 0), 4),
    'zero_finding_photo_rate', round(zero_photos::numeric / nullif(photos, 0), 4),
    'cost_usd', cost_usd, 'duration_ms', duration_ms
  ) order by analyses desc), '[]'::jsonb) value
  from cohort
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
  'score_distributions', (select value from distributions),
  'cohorts', (select value from cohorts)
) from runs;
$$;

revoke all on function private.analysis_engine_window_v3(timestamptz, timestamptz)
  from public, anon, authenticated;

do $$
begin
  perform private.analysis_engine_window_v3(now() - interval '7 days', now());
end $$;
