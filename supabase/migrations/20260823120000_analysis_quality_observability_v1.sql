-- Analysis Quality Observability V1
-- Measurement only: no prompt, scoring, guard, dedup, repair, reference, plan,
-- or finding-limit behavior changes are introduced by this migration.

create extension if not exists pg_cron with schema extensions;

create or replace function private.analysis_quality_window_v1(
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
with analysis_scope as (
  select
    a.id,
    a.user_id,
    a.canvas::text as canvas,
    coalesce(a.output_language, a.raw_ai_response->'_input_audit'->>'output_language', 'unknown') as output_language,
    coalesce(a.client_platform, a.raw_ai_response->'_input_audit'->>'client_platform', 'unknown') as client_platform,
    greatest(coalesce(a.photo_count, 0), 1) as photo_count,
    coalesce(nullif(a.raw_ai_response->'_quality_trace_v1', 'null'::jsonb), '{}'::jsonb) as trace,
    coalesce(nullif(a.raw_ai_response->'_input_audit', 'null'::jsonb), '{}'::jsonb) as audit,
    coalesce((select count(*) from public.findings f where f.analysis_id = a.id), 0)::integer as actual_final_findings,
    coalesce((select count(*) from public.analysis_photo_summaries aps where aps.analysis_id = a.id and coalesce(aps.generated_findings_count, 0) = 0), 0)::integer as legacy_zero_finding_photos,
    coalesce(a.completed_at, a.updated_at, a.created_at) as measured_at,
    coalesce(p.tier::text, 'free') as profile_plan
  from public.analyses a
  left join public.profiles p on p.id = a.user_id
  where a.status::text = 'completed'
    and a.kind::text = 'photo'
    and greatest(coalesce(a.photo_count, 0), 0) > 0
    and coalesce(a.completed_at, a.updated_at, a.created_at) >= p_from
    and coalesce(a.completed_at, a.updated_at, a.created_at) < p_to
),
usage_by_analysis as (
  select
    u.analysis_id,
    count(*)::integer as usage_rows,
    count(*) filter (where u.error is not null)::integer as provider_errors,
    coalesce(sum(u.tokens_in), 0)::bigint as tokens_in,
    coalesce(sum(u.tokens_out), 0)::bigint as tokens_out,
    coalesce(sum(u.total_tokens), 0)::bigint as total_tokens,
    coalesce(sum(u.provider_attempt_total_tokens), 0)::bigint as provider_attempt_total_tokens,
    coalesce(sum(u.duration_ms), 0)::bigint as duration_ms,
    coalesce(sum(u.provider_request_count), 0)::bigint as provider_request_count
  from public.ai_usage_logs u
  where u.analysis_id in (select id from analysis_scope)
  group by u.analysis_id
),
normalized as (
  select
    s.*,
    coalesce(
      s.trace->>'version' = '1' and s.trace->>'trace_mode' = 'full_trace',
      false
    ) as is_full_trace,
    coalesce(s.trace->'cohort'->>'prompt_version', s.audit->>'prompt_version', 'unknown') as prompt_version,
    coalesce(s.trace->'cohort'->>'policy_version', s.audit->>'coverage_policy_version', s.audit->>'atomic_finding_policy_version', 'unknown') as policy_version,
    coalesce(s.trace->'cohort'->>'model', s.audit->>'model', 'unknown') as model,
    coalesce(s.trace->'cohort'->>'provider', s.audit->>'provider', 'unknown') as provider,
    coalesce(s.trace->'cohort'->>'plan', s.audit->>'user_plan', s.profile_plan, 'free') as plan,
    case when s.photo_count > 1 then 'multi_photo' else 'single_photo' end as photo_mode,
    case when s.trace->'summary'->>'raw_findings' ~ '^[0-9]+$'
      then (s.trace->'summary'->>'raw_findings')::integer else null end as raw_findings,
    case when s.trace->'summary'->>'final_findings' ~ '^[0-9]+$'
      then (s.trace->'summary'->>'final_findings')::integer else null end as traced_final_findings,
    case when s.trace->'summary'->>'zero_finding_photos' ~ '^[0-9]+$'
      then (s.trace->'summary'->>'zero_finding_photos')::integer else null end as traced_zero_finding_photos,
    coalesce((select sum((r->>'count')::integer)
      from jsonb_array_elements(coalesce(s.trace->'rejections', '[]'::jsonb)) r
      where r->>'reason_code' in ('duplicate_exact', 'duplicate_fuzzy', 'repair_duplicate')), 0)::integer as dedup_rejected,
    coalesce((select sum((r->>'count')::integer)
      from jsonb_array_elements(coalesce(s.trace->'rejections', '[]'::jsonb)) r
      where r->>'reason_code' in (
        'evidence_unlinked', 'evidence_non_actionable', 'process_link_invalid',
        'contextual_ppe_rejected', 'repair_unsupported'
      )), 0)::integer as guard_rejected,
    coalesce((select sum(coalesce((photo->>'actionable_layer_count')::integer, 0))
      from jsonb_array_elements(coalesce(s.audit->'layer_audit'->'photos', '[]'::jsonb)) photo), 0)::integer as actionable_layers,
    coalesce((select sum(coalesce((photo->>'represented_actionable_layer_count')::integer, 0))
      from jsonb_array_elements(coalesce(s.audit->'layer_audit'->'photos', '[]'::jsonb)) photo), 0)::integer as represented_actionable_layers,
    coalesce((select sum(coalesce((photo->>'actionable_process_check_count')::integer, 0))
      from jsonb_array_elements(coalesce(s.audit->'layer_audit'->'photos', '[]'::jsonb)) photo), 0)::integer as actionable_process_checks,
    coalesce((select sum(coalesce((photo->>'represented_actionable_process_check_count')::integer, 0))
      from jsonb_array_elements(coalesce(s.audit->'layer_audit'->'photos', '[]'::jsonb)) photo), 0)::integer as represented_actionable_process_checks,
    coalesce((s.trace->'repair'->>'called')::boolean, false) as repair_called,
    coalesce((s.trace->'repair'->>'added_count')::integer, 0) as repair_added,
    coalesce((s.trace->'provider'->>'schema_fallback_used')::boolean, false) as schema_fallback_used,
    coalesce(u.usage_rows, 0) as usage_rows,
    coalesce(u.provider_errors, 0) as provider_errors,
    coalesce(u.tokens_in, 0) as tokens_in,
    coalesce(u.tokens_out, 0) as tokens_out,
    coalesce(u.total_tokens, 0) as total_tokens,
    coalesce(u.provider_attempt_total_tokens, 0) as provider_attempt_total_tokens,
    coalesce(u.duration_ms, 0) as duration_ms,
    coalesce(u.provider_request_count, 0) as provider_request_count
  from analysis_scope s
  left join usage_by_analysis u on u.analysis_id = s.id
),
full_trace as (
  select * from normalized where is_full_trace
),
legacy as (
  select * from normalized where not is_full_trace
),
score_rows as (
  select n.id as analysis_id, score
  from full_trace n
  cross join lateral jsonb_array_elements(coalesce(n.trace->'score_traces', '[]'::jsonb)) score
),
cohort_rows as (
  select
    prompt_version, policy_version, model, provider, plan, output_language,
    client_platform, canvas, photo_mode,
    count(*)::integer as analyses,
    sum(photo_count)::integer as photos,
    sum(raw_findings)::integer as raw_findings,
    sum(traced_final_findings)::integer as final_findings,
    sum(traced_zero_finding_photos)::integer as zero_finding_photos,
    sum(dedup_rejected)::integer as dedup_rejected,
    sum(guard_rejected)::integer as guard_rejected,
    count(*) filter (where repair_called)::integer as repair_calls,
    sum(repair_added)::integer as repair_added,
    sum(total_tokens)::bigint as total_tokens,
    sum(duration_ms)::bigint as duration_ms,
    sum(provider_errors)::integer as provider_errors
  from full_trace
  group by prompt_version, policy_version, model, provider, plan,
    output_language, client_platform, canvas, photo_mode
)
select jsonb_build_object(
  'from', p_from,
  'to', p_to,
  'full_trace', jsonb_build_object(
    'analyses', (select count(*) from full_trace),
    'sample_photos', (select coalesce(sum(photo_count), 0) from full_trace),
    'raw_findings', (select coalesce(sum(raw_findings), 0) from full_trace),
    'final_findings', (select coalesce(sum(traced_final_findings), 0) from full_trace),
    'raw_findings_per_photo', (select round(coalesce(sum(raw_findings), 0)::numeric / nullif(sum(photo_count), 0), 4) from full_trace),
    'final_findings_per_photo', (select round(coalesce(sum(traced_final_findings), 0)::numeric / nullif(sum(photo_count), 0), 4) from full_trace),
    'zero_finding_photo_rate', (select round(coalesce(sum(traced_zero_finding_photos), 0)::numeric / nullif(sum(photo_count), 0), 4) from full_trace),
    'raw_to_final_retention', (select round(coalesce(sum(traced_final_findings), 0)::numeric / nullif(sum(raw_findings), 0), 4) from full_trace),
    'dedup_rejected_count', (select coalesce(sum(dedup_rejected), 0) from full_trace),
    'dedup_rejection_rate', (select round(coalesce(sum(dedup_rejected), 0)::numeric / nullif(sum(raw_findings), 0), 4) from full_trace),
    'guard_rejected_count', (select coalesce(sum(guard_rejected), 0) from full_trace),
    'guard_rejection_rate', (select round(coalesce(sum(guard_rejected), 0)::numeric / nullif(sum(raw_findings), 0), 4) from full_trace),
    'actionable_layer_count', (select coalesce(sum(actionable_layers), 0) from full_trace),
    'represented_actionable_layer_count', (select coalesce(sum(represented_actionable_layers), 0) from full_trace),
    'actionable_layer_representation_rate', (select round(coalesce(sum(represented_actionable_layers), 0)::numeric / nullif(sum(actionable_layers), 0), 4) from full_trace),
    'actionable_process_check_count', (select coalesce(sum(actionable_process_checks), 0) from full_trace),
    'represented_actionable_process_check_count', (select coalesce(sum(represented_actionable_process_checks), 0) from full_trace),
    'actionable_process_check_representation_rate', (select round(coalesce(sum(represented_actionable_process_checks), 0)::numeric / nullif(sum(actionable_process_checks), 0), 4) from full_trace),
    'repair_calls', (select count(*) filter (where repair_called) from full_trace),
    'repair_added_findings', (select coalesce(sum(repair_added), 0) from full_trace),
    'repair_yield', (select round(coalesce(sum(repair_added), 0)::numeric / nullif(count(*) filter (where repair_called), 0), 4) from full_trace),
    'schema_fallbacks', (select count(*) filter (where schema_fallback_used) from full_trace),
    'provider_calls', (select coalesce(sum(provider_request_count), 0) from full_trace),
    'tokens_in', (select coalesce(sum(tokens_in), 0) from full_trace),
    'tokens_out', (select coalesce(sum(tokens_out), 0) from full_trace),
    'total_tokens', (select coalesce(sum(total_tokens), 0) from full_trace),
    'provider_attempt_total_tokens', (select coalesce(sum(provider_attempt_total_tokens), 0) from full_trace),
    'duration_ms', (select coalesce(sum(duration_ms), 0) from full_trace),
    'provider_errors', (select coalesce(sum(provider_errors), 0) from full_trace),
    'raw_to_final_severity_changes', jsonb_build_object(
      'changed', (select count(*) from score_rows where score->'model_raw'->'fk_severity' is distinct from score->'server_final'->'fk_severity'),
      'raised', (select count(*) from score_rows where jsonb_typeof(score->'model_raw'->'fk_severity') = 'number' and jsonb_typeof(score->'server_final'->'fk_severity') = 'number' and (score->'server_final'->>'fk_severity')::numeric > (score->'model_raw'->>'fk_severity')::numeric),
      'lowered', (select count(*) from score_rows where jsonb_typeof(score->'model_raw'->'fk_severity') = 'number' and jsonb_typeof(score->'server_final'->'fk_severity') = 'number' and (score->'server_final'->>'fk_severity')::numeric < (score->'model_raw'->>'fk_severity')::numeric)
    )
  ),
  'legacy_aggregate', jsonb_build_object(
    'analyses', (select count(*) from legacy),
    'sample_photos', (select coalesce(sum(photo_count), 0) from legacy),
    'final_findings', (select coalesce(sum(actual_final_findings), 0) from legacy),
    'final_findings_per_photo', (select round(coalesce(sum(actual_final_findings), 0)::numeric / nullif(sum(photo_count), 0), 4) from legacy),
    'zero_finding_photo_rate', (select round(coalesce(sum(legacy_zero_finding_photos), 0)::numeric / nullif(sum(photo_count), 0), 4) from legacy),
    'provider_calls', (select coalesce(sum(provider_request_count), 0) from legacy),
    'total_tokens', (select coalesce(sum(total_tokens), 0) from legacy),
    'duration_ms', (select coalesce(sum(duration_ms), 0) from legacy),
    'provider_errors', (select coalesce(sum(provider_errors), 0) from legacy),
    'not_comparable_to_full_trace', true
  ),
  'score_distributions', jsonb_build_object(
    'raw_fk_probability', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'model_raw'->>'fk_probability', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'raw_fk_frequency', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'model_raw'->>'fk_frequency', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'raw_fk_severity', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'model_raw'->>'fk_severity', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'final_fk_probability', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'server_final'->>'fk_probability', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'final_fk_frequency', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'server_final'->>'fk_frequency', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'final_fk_severity', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'server_final'->>'fk_severity', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'raw_m5_probability', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'model_raw'->>'m5_probability', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'raw_m5_severity', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'model_raw'->>'m5_severity', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'final_m5_probability', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'server_final'->>'m5_probability', 'missing') value, count(*) from score_rows group by 1 order by 1) d),
    'final_m5_severity', (select coalesce(jsonb_object_agg(value, count), '{}'::jsonb) from (select coalesce(score->'server_final'->>'m5_severity', 'missing') value, count(*) from score_rows group by 1 order by 1) d)
  ),
  'cohorts', (select coalesce(jsonb_agg(jsonb_build_object(
    'prompt_version', prompt_version, 'policy_version', policy_version,
    'model', model, 'provider', provider, 'plan', plan,
    'output_language', output_language, 'client_platform', client_platform,
    'canvas', canvas, 'photo_mode', photo_mode,
    'analyses', analyses, 'photos', photos,
    'raw_findings_per_photo', round(raw_findings::numeric / nullif(photos, 0), 4),
    'final_findings_per_photo', round(final_findings::numeric / nullif(photos, 0), 4),
    'zero_finding_photo_rate', round(zero_finding_photos::numeric / nullif(photos, 0), 4),
    'raw_to_final_retention', round(final_findings::numeric / nullif(raw_findings, 0), 4),
    'dedup_rejected', dedup_rejected, 'guard_rejected', guard_rejected,
    'repair_calls', repair_calls, 'repair_added', repair_added,
    'total_tokens', total_tokens, 'duration_ms', duration_ms,
    'provider_errors', provider_errors
  ) order by analyses desc, photos desc), '[]'::jsonb) from cohort_rows)
);
$$;

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
    'usage_rows', count(*),
    'provider_calls', coalesce(sum(provider_request_count), 0),
    'tokens_in', coalesce(sum(tokens_in), 0),
    'tokens_out', coalesce(sum(tokens_out), 0),
    'total_tokens', coalesce(sum(total_tokens), 0),
    'provider_attempt_total_tokens', coalesce(sum(provider_attempt_total_tokens), 0),
    'duration_ms', coalesce(sum(duration_ms), 0),
    'errors', count(*) filter (where error is not null),
    'estimated_cost_usd', null
  ) as value
  from public.ai_usage_logs
  where analysis_id = p_analysis_id
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

create or replace function public.admin_analysis_quality_metrics_v1(
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
  v_current_full jsonb;
  v_baseline_full jsonb;
  v_weekly jsonb;
begin
  v_current := private.analysis_quality_window_v1(
    v_now - make_interval(days => v_current_days), v_now
  );
  v_baseline := private.analysis_quality_window_v1(
    v_now - make_interval(days => v_current_days + v_baseline_days),
    v_now - make_interval(days => v_current_days)
  );
  v_current_full := v_current->'full_trace';
  v_baseline_full := v_baseline->'full_trace';

  select coalesce(jsonb_agg(row_value order by week_start), '[]'::jsonb)
  into v_weekly
  from (
    select
      date_trunc('week', coalesce(a.completed_at, a.updated_at, a.created_at) at time zone 'Europe/Istanbul') as week_start,
      jsonb_build_object(
        'week_start', date_trunc('week', coalesce(a.completed_at, a.updated_at, a.created_at) at time zone 'Europe/Istanbul'),
        'analyses', count(*),
        'full_trace_analyses', count(*) filter (where a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'),
        'full_trace_photos', coalesce(sum(greatest(coalesce(a.photo_count, 0), 1)) filter (where a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'), 0),
        'full_trace_final_findings', coalesce(sum(case
          when a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'
            and a.raw_ai_response->'_quality_trace_v1'->'summary'->>'final_findings' ~ '^[0-9]+$'
          then (a.raw_ai_response->'_quality_trace_v1'->'summary'->>'final_findings')::integer
          else 0 end), 0),
        'full_trace_final_findings_per_photo', round(
          coalesce(sum(case
            when a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'
              and a.raw_ai_response->'_quality_trace_v1'->'summary'->>'final_findings' ~ '^[0-9]+$'
            then (a.raw_ai_response->'_quality_trace_v1'->'summary'->>'final_findings')::integer
            else 0 end), 0)::numeric /
          nullif(sum(greatest(coalesce(a.photo_count, 0), 1)) filter (where a.raw_ai_response->'_quality_trace_v1'->>'version' = '1'), 0), 4
        ),
        'legacy_analyses', count(*) filter (where coalesce(a.raw_ai_response->'_quality_trace_v1'->>'version', '') <> '1'),
        'legacy_photos', coalesce(sum(greatest(coalesce(a.photo_count, 0), 1)) filter (where coalesce(a.raw_ai_response->'_quality_trace_v1'->>'version', '') <> '1'), 0),
        'legacy_final_findings', coalesce(sum(case
          when coalesce(a.raw_ai_response->'_quality_trace_v1'->>'version', '') <> '1'
          then (select count(*) from public.findings f where f.analysis_id = a.id)
          else 0 end), 0),
        'legacy_final_findings_per_photo', round(
          coalesce(sum(case
            when coalesce(a.raw_ai_response->'_quality_trace_v1'->>'version', '') <> '1'
            then (select count(*) from public.findings f where f.analysis_id = a.id)
            else 0 end), 0)::numeric /
          nullif(sum(greatest(coalesce(a.photo_count, 0), 1)) filter (where coalesce(a.raw_ai_response->'_quality_trace_v1'->>'version', '') <> '1'), 0), 4
        ),
        'series_mode', 'segregated'
      ) as row_value
    from public.analyses a
    where a.status::text = 'completed'
      and a.kind::text = 'photo'
      and greatest(coalesce(a.photo_count, 0), 0) > 0
      and coalesce(a.completed_at, a.updated_at, a.created_at) >= v_now - interval '84 days'
    group by 1
  ) weekly;

  return jsonb_build_object(
    'version', 1,
    'generated_at', v_now,
    'current_days', v_current_days,
    'baseline_days', v_baseline_days,
    'current', v_current,
    'baseline', v_baseline,
    'comparison', jsonb_build_object(
      'final_findings_per_photo_change_ratio', case
        when nullif((v_baseline_full->>'final_findings_per_photo')::numeric, 0) is null then null
        else round(((v_current_full->>'final_findings_per_photo')::numeric - (v_baseline_full->>'final_findings_per_photo')::numeric) / nullif((v_baseline_full->>'final_findings_per_photo')::numeric, 0), 4) end,
      'raw_findings_per_photo_change_ratio', case
        when nullif((v_baseline_full->>'raw_findings_per_photo')::numeric, 0) is null then null
        else round(((v_current_full->>'raw_findings_per_photo')::numeric - (v_baseline_full->>'raw_findings_per_photo')::numeric) / nullif((v_baseline_full->>'raw_findings_per_photo')::numeric, 0), 4) end,
      'zero_finding_photo_rate_change_points', round(coalesce((v_current_full->>'zero_finding_photo_rate')::numeric, 0) - coalesce((v_baseline_full->>'zero_finding_photo_rate')::numeric, 0), 4),
      'raw_to_final_retention_change_points', round(coalesce((v_current_full->>'raw_to_final_retention')::numeric, 0) - coalesce((v_baseline_full->>'raw_to_final_retention')::numeric, 0), 4)
    ),
    'weekly_series', v_weekly
  );
end;
$$;

insert into public.admin_alert_rules (
  rule_key, name, description, metric_key, operator, threshold, severity,
  cooldown_minutes
)
values
  ('analysis_final_findings_per_photo_drop', 'Final bulgu/fotoğraf düşüşü', 'Tam izli analizlerde final bulgu/fotoğraf baseline değerinin altına düştü.', 'final_findings_per_photo_drop_ratio', 'gte', 0.30, 'warning', 1440),
  ('analysis_raw_findings_per_photo_drop', 'Ham bulgu/fotoğraf düşüşü', 'Tam izli analizlerde ham bulgu/fotoğraf baseline değerinin altına düştü.', 'raw_findings_per_photo_drop_ratio', 'gte', 0.30, 'warning', 1440),
  ('analysis_zero_finding_photo_rate_rise', 'Sıfır bulgulu fotoğraf artışı', 'Sıfır bulgulu fotoğraf oranı hem iki katına çıktı hem en az 15 puan arttı.', 'zero_finding_photo_rate_change_points', 'gte', 0.15, 'warning', 1440),
  ('analysis_raw_final_retention_drop', 'Ham-final retention düşüşü', 'Ham model çıktısından final bulguya retention en az 20 puan düştü.', 'raw_to_final_retention_drop_points', 'gte', 0.20, 'warning', 1440)
on conflict (rule_key) do update set
  name = excluded.name,
  description = excluded.description,
  metric_key = excluded.metric_key,
  operator = excluded.operator,
  threshold = excluded.threshold,
  severity = excluded.severity,
  cooldown_minutes = excluded.cooldown_minutes,
  updated_at = now();

create or replace function private.record_analysis_quality_alert_v1(
  p_rule_key text,
  p_severity text,
  p_metric_value numeric,
  p_threshold numeric,
  p_title text,
  p_message text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.admin_alert_rules%rowtype;
begin
  select * into v_rule
  from public.admin_alert_rules
  where rule_key = p_rule_key and is_enabled;
  if not found then return false; end if;

  if exists (
    select 1 from public.admin_alert_events e
    where e.rule_id = v_rule.id
      and (
        e.status in ('open', 'acknowledged')
        or e.created_at >= now() - make_interval(mins => v_rule.cooldown_minutes)
      )
  ) then
    return false;
  end if;

  insert into public.admin_alert_events (
    rule_id, rule_key, severity, title, message, metric_key, metric_value,
    threshold, status, fingerprint
  ) values (
    v_rule.id, v_rule.rule_key, p_severity, p_title, p_message,
    v_rule.metric_key, p_metric_value, p_threshold, 'open',
    'analysis-quality:' || v_rule.rule_key
  ) on conflict do nothing;
  return found;
end;
$$;

create or replace function private.resolve_analysis_quality_alert_v1(
  p_rule_key text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.admin_alert_events
  set status = 'resolved', resolved_at = now(), updated_at = now()
  where rule_key = p_rule_key and status in ('open', 'acknowledged');
$$;

create or replace function private.evaluate_analysis_quality_regressions_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_metrics jsonb := public.admin_analysis_quality_metrics_v1(7, 28);
  v_current jsonb;
  v_baseline jsonb;
  v_current_photos integer;
  v_baseline_photos integer;
  v_final_drop numeric;
  v_raw_drop numeric;
  v_zero_current numeric;
  v_zero_baseline numeric;
  v_retention_drop numeric;
  v_emitted integer := 0;
begin
  v_current := v_metrics->'current'->'full_trace';
  v_baseline := v_metrics->'baseline'->'full_trace';
  v_current_photos := coalesce((v_current->>'sample_photos')::integer, 0);
  v_baseline_photos := coalesce((v_baseline->>'sample_photos')::integer, 0);

  if v_current_photos < 10 or v_baseline_photos < 20 then
    return jsonb_build_object(
      'status', 'insufficient_sample',
      'current_photos', v_current_photos,
      'baseline_photos', v_baseline_photos,
      'alerts_emitted', 0
    );
  end if;

  v_final_drop := case when nullif((v_baseline->>'final_findings_per_photo')::numeric, 0) is null then 0 else
    1 - coalesce((v_current->>'final_findings_per_photo')::numeric, 0) / nullif((v_baseline->>'final_findings_per_photo')::numeric, 0) end;
  v_raw_drop := case when nullif((v_baseline->>'raw_findings_per_photo')::numeric, 0) is null then 0 else
    1 - coalesce((v_current->>'raw_findings_per_photo')::numeric, 0) / nullif((v_baseline->>'raw_findings_per_photo')::numeric, 0) end;
  v_zero_current := coalesce((v_current->>'zero_finding_photo_rate')::numeric, 0);
  v_zero_baseline := coalesce((v_baseline->>'zero_finding_photo_rate')::numeric, 0);
  v_retention_drop := coalesce((v_baseline->>'raw_to_final_retention')::numeric, 0) - coalesce((v_current->>'raw_to_final_retention')::numeric, 0);

  if v_final_drop >= 0.30 then
    if private.record_analysis_quality_alert_v1(
      'analysis_final_findings_per_photo_drop',
      case when v_final_drop >= 0.45 then 'critical' else 'warning' end,
      v_final_drop, case when v_final_drop >= 0.45 then 0.45 else 0.30 end,
      'Final bulgu/fotoğraf regresyonu',
      format('Final bulgu/fotoğraf baseline değerine göre %% %s düştü.', round(v_final_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else
    perform private.resolve_analysis_quality_alert_v1('analysis_final_findings_per_photo_drop');
  end if;

  if v_raw_drop >= 0.30 then
    if private.record_analysis_quality_alert_v1(
      'analysis_raw_findings_per_photo_drop',
      case when v_raw_drop >= 0.45 then 'critical' else 'warning' end,
      v_raw_drop, case when v_raw_drop >= 0.45 then 0.45 else 0.30 end,
      'Ham bulgu/fotoğraf regresyonu',
      format('Ham bulgu/fotoğraf baseline değerine göre %% %s düştü.', round(v_raw_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else
    perform private.resolve_analysis_quality_alert_v1('analysis_raw_findings_per_photo_drop');
  end if;

  if v_zero_current >= v_zero_baseline * 2 and v_zero_current - v_zero_baseline >= 0.15 then
    if private.record_analysis_quality_alert_v1(
      'analysis_zero_finding_photo_rate_rise', 'warning',
      v_zero_current - v_zero_baseline, 0.15,
      'Sıfır bulgulu fotoğraf oranı regresyonu',
      format('Sıfır bulgulu fotoğraf oranı %% %s seviyesine çıktı; baseline %% %s.', round(v_zero_current * 100, 1), round(v_zero_baseline * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else
    perform private.resolve_analysis_quality_alert_v1('analysis_zero_finding_photo_rate_rise');
  end if;

  if v_retention_drop >= 0.20 then
    if private.record_analysis_quality_alert_v1(
      'analysis_raw_final_retention_drop', 'warning',
      v_retention_drop, 0.20,
      'Ham-final retention regresyonu',
      format('Raw→final retention baseline değerine göre %s puan düştü.', round(v_retention_drop * 100, 1))
    ) then v_emitted := v_emitted + 1; end if;
  else
    perform private.resolve_analysis_quality_alert_v1('analysis_raw_final_retention_drop');
  end if;

  return jsonb_build_object(
    'status', 'evaluated',
    'current_photos', v_current_photos,
    'baseline_photos', v_baseline_photos,
    'alerts_emitted', v_emitted,
    'final_drop_ratio', round(v_final_drop, 4),
    'raw_drop_ratio', round(v_raw_drop, 4),
    'zero_rate_change_points', round(v_zero_current - v_zero_baseline, 4),
    'retention_drop_points', round(v_retention_drop, 4)
  );
end;
$$;

revoke all on function private.analysis_quality_window_v1(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function private.record_analysis_quality_alert_v1(text, text, numeric, numeric, text, text) from public, anon, authenticated;
revoke all on function private.resolve_analysis_quality_alert_v1(text) from public, anon, authenticated;
revoke all on function private.evaluate_analysis_quality_regressions_v1() from public, anon, authenticated;
revoke all on function public.admin_analysis_quality_run_v1(uuid) from public, anon, authenticated;
revoke all on function public.admin_analysis_quality_metrics_v1(integer, integer) from public, anon, authenticated;

grant execute on function public.admin_analysis_quality_run_v1(uuid) to service_role;
grant execute on function public.admin_analysis_quality_metrics_v1(integer, integer) to service_role;

do $$
begin
  if exists (
    select 1 from cron.job
    where jobname = 'riskdetected-analysis-quality-daily'
  ) then
    perform cron.unschedule('riskdetected-analysis-quality-daily');
  end if;
  perform cron.schedule(
    'riskdetected-analysis-quality-daily',
    '15 3 * * *',
    'select private.evaluate_analysis_quality_regressions_v1();'
  );
end
$$;
