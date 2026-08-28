begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(28);

select has_function(
  'public', 'admin_analysis_quality_run_v1', array['uuid'],
  'single analysis quality RPC exists'
);
select has_function(
  'public', 'admin_analysis_quality_metrics_v1', array['integer', 'integer'],
  'aggregate analysis quality RPC exists'
);
select has_function(
  'private', 'evaluate_analysis_quality_regressions_v1', array[]::text[],
  'private regression evaluator exists'
);

select ok(
  not has_function_privilege(
    'anon', 'public.admin_analysis_quality_run_v1(uuid)', 'execute'
  ),
  'anon cannot read a quality run'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_analysis_quality_metrics_v1(integer,integer)',
    'execute'
  ),
  'authenticated users cannot read aggregate quality metrics'
);
select ok(
  has_function_privilege(
    'service_role', 'public.admin_analysis_quality_run_v1(uuid)', 'execute'
  ),
  'service role can read a quality run'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.admin_analysis_quality_metrics_v1(integer,integer)',
    'execute'
  ),
  'service role can read aggregate quality metrics'
);
select ok(
  not has_function_privilege(
    'authenticated', 'private.evaluate_analysis_quality_regressions_v1()',
    'execute'
  ),
  'regression evaluator is not exposed to app users'
);

select is(
  (
    select schedule from cron.job
    where jobname = 'riskdetected-analysis-quality-daily'
  ),
  '15 3 * * *',
  'daily quality evaluation runs at 06:15 Istanbul time'
);
select is(
  (
    select command from cron.job
    where jobname = 'riskdetected-analysis-quality-daily'
  ),
  'select private.evaluate_analysis_quality_regressions_v1(), private.evaluate_analysis_engine_regressions_v3();',
  'cron invokes the segregated legacy and vNext private evaluators'
);

select is(
  (
    select count(*)::integer from public.admin_alert_rules
    where rule_key in (
      'analysis_final_findings_per_photo_drop',
      'analysis_raw_findings_per_photo_drop',
      'analysis_zero_finding_photo_rate_rise',
      'analysis_raw_final_retention_drop'
    )
  ),
  4,
  'all four quality alert rules exist'
);

select is(
  private.evaluate_analysis_quality_regressions_v1()->>'status',
  'insufficient_sample',
  'low sample is reported without raising an alert'
);
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key like 'analysis_%'
  ),
  0,
  'low sample emits no alert event'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000901'::uuid,
  'quality-observability@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, completed_at,
  output_language, raw_ai_response
)
select
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000901'::uuid,
  'quality-baseline-' || sequence,
  'photo', 'completed', 1, now() - interval '10 days', 'tr',
  jsonb_build_object(
    '_input_audit', jsonb_build_object(
      'prompt_version', 'fixture-v1',
      'coverage_policy_version', 'fixture-policy-v1',
      'model', 'fixture-model',
      'provider', 'gemini',
      'user_plan', 'free'
    ),
    '_quality_trace_v1', jsonb_build_object(
      'version', 1,
      'trace_mode', 'full_trace',
      'cohort', jsonb_build_object(
        'prompt_version', 'fixture-v1',
        'policy_version', 'fixture-policy-v1',
        'model', 'fixture-model',
        'provider', 'gemini',
        'plan', 'free'
      ),
      'summary', jsonb_build_object(
        'raw_findings', 4,
        'final_findings', 4,
        'zero_finding_photos', case when sequence <= 2 then 1 else 0 end
      ),
      'repair', jsonb_build_object('called', false, 'added_count', 0),
      'provider', jsonb_build_object('schema_fallback_used', false),
      'rejections', '[]'::jsonb,
      'score_traces', '[]'::jsonb
    )
  )
from generate_series(1, 20) sequence;

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, completed_at,
  output_language, raw_ai_response
)
select
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000901'::uuid,
  'quality-current-' || sequence,
  'photo', 'completed', 1, now() - interval '1 day', 'tr',
  jsonb_build_object(
    '_input_audit', jsonb_build_object(
      'prompt_version', 'fixture-v1',
      'coverage_policy_version', 'fixture-policy-v1',
      'model', 'fixture-model',
      'provider', 'gemini',
      'user_plan', 'free'
    ),
    '_quality_trace_v1', jsonb_build_object(
      'version', 1,
      'trace_mode', 'full_trace',
      'cohort', jsonb_build_object(
        'prompt_version', 'fixture-v1',
        'policy_version', 'fixture-policy-v1',
        'model', 'fixture-model',
        'provider', 'gemini',
        'plan', 'free'
      ),
      'summary', jsonb_build_object(
        'raw_findings', 2,
        'final_findings', 2,
        'zero_finding_photos', 0
      ),
      'repair', jsonb_build_object('called', false, 'added_count', 0),
      'provider', jsonb_build_object('schema_fallback_used', false),
      'rejections', '[]'::jsonb,
      'score_traces', '[]'::jsonb
    )
  )
from generate_series(1, 10) sequence;

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, completed_at,
  output_language, raw_ai_response
)
values (
  gen_random_uuid(),
  '00000000-0000-4000-8000-000000000901'::uuid,
  'quality-legacy', 'photo', 'completed', 1, now() - interval '1 day',
  'tr', jsonb_build_object('_input_audit', jsonb_build_object('model', 'legacy'))
);

insert into public.findings (
  analysis_id, user_id, ordinal, title, category, description,
  recommended_action, confidence,
  fk_probability, fk_frequency, fk_severity, fk_band,
  m5_probability, m5_severity, m5_band, source_photo_indices
)
select
  a.id, a.user_id, ordinal,
  'Fixture finding ' || ordinal, 'fixture', 'fixture', 'fixture', 0.8,
  3, 2, 15, 'medium', 3, 3, 'medium', array[1]
from public.analyses a
cross join lateral generate_series(
  1,
  case when a.title like 'quality-baseline-%' then 4 else 2 end
) ordinal
where a.title like 'quality-baseline-%'
   or a.title like 'quality-current-%';

select is(
  (public.admin_analysis_quality_metrics_v1(7, 28)
    ->'current'->'full_trace'->>'sample_photos')::integer,
  10,
  'current window counts only full-trace photos'
);
select is(
  (public.admin_analysis_quality_metrics_v1(7, 28)
    ->'current'->'legacy_aggregate'->>'analyses')::integer,
  1,
  'legacy analyses are reported separately'
);
select is(
  (public.admin_analysis_quality_metrics_v1(7, 28)
    ->'baseline'->'full_trace'->>'sample_photos')::integer,
  20,
  'baseline has the minimum required full-trace sample'
);
select ok(
  jsonb_array_length(
    public.admin_analysis_quality_metrics_v1(7, 28)->'weekly_series'
  ) > 0,
  'historical weekly findings-per-photo series is returned'
);
select ok(
  public.admin_analysis_quality_metrics_v1(7, 28)
    ->'current' ?& array['full_trace', 'legacy_aggregate', 'score_distributions', 'cohorts'],
  'aggregate output includes trace, legacy, score, and cohort sections'
);

select ok(
  (public.admin_analysis_quality_run_v1((
    select id from public.analyses
    where title = 'quality-current-1'
  ))->>'trace_matches_database')::boolean,
  'single-run RPC verifies final trace count against persisted findings'
);
select is(
  public.admin_analysis_quality_run_v1((
    select id from public.analyses where title = 'quality-legacy'
  ))->>'trace_mode',
  'legacy_aggregate',
  'single-run RPC labels historical rows as legacy aggregate'
);

select is(
  private.evaluate_analysis_quality_regressions_v1()->>'status',
  'evaluated',
  'sufficient sample evaluates regression rules'
);
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key in (
      'analysis_final_findings_per_photo_drop',
      'analysis_raw_findings_per_photo_drop'
    ) and status = 'open' and severity = 'critical'
  ),
  2,
  '45 percent drops create critical raw and final alerts'
);

select private.evaluate_analysis_quality_regressions_v1();
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key in (
      'analysis_final_findings_per_photo_drop',
      'analysis_raw_findings_per_photo_drop'
    )
  ),
  2,
  'cooldown and active fingerprint prevent duplicate alerts'
);

update public.analyses
set raw_ai_response = jsonb_set(
  jsonb_set(raw_ai_response, '{_quality_trace_v1,summary,raw_findings}', '4'),
  '{_quality_trace_v1,summary,final_findings}', '3'
)
where title like 'quality-current-%';

update public.analyses
set raw_ai_response = jsonb_set(
  raw_ai_response,
  '{_quality_trace_v1,summary,zero_finding_photos}',
  case when title in ('quality-current-1', 'quality-current-2', 'quality-current-3') then '1'::jsonb else '0'::jsonb end
)
where title like 'quality-current-%';

insert into public.findings (
  analysis_id, user_id, ordinal, title, category, description,
  recommended_action, confidence,
  fk_probability, fk_frequency, fk_severity, fk_band,
  m5_probability, m5_severity, m5_band, source_photo_indices
)
select
  id, user_id, 3, 'Fixture finding 3', 'fixture', 'fixture', 'fixture', 0.8,
  3, 2, 15, 'medium', 3, 3, 'medium', array[1]
from public.analyses where title like 'quality-current-%';

select private.evaluate_analysis_quality_regressions_v1();
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key in (
      'analysis_zero_finding_photo_rate_rise',
      'analysis_raw_final_retention_drop'
    ) and status = 'open'
  ),
  2,
  'zero-photo and retention warning rules fire at their point thresholds'
);
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key in (
      'analysis_final_findings_per_photo_drop',
      'analysis_raw_findings_per_photo_drop'
    ) and status = 'resolved'
  ),
  2,
  'recovered raw and final rates resolve prior alerts'
);

select private.evaluate_analysis_quality_regressions_v1();
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key like 'analysis_%'
  ),
  4,
  'warning alerts also respect cooldown and fingerprint deduplication'
);

update public.analyses
set raw_ai_response = jsonb_set(
  jsonb_set(raw_ai_response, '{_quality_trace_v1,summary,final_findings}', '4'),
  '{_quality_trace_v1,summary,zero_finding_photos}', '0'
)
where title like 'quality-current-%';

insert into public.findings (
  analysis_id, user_id, ordinal, title, category, description,
  recommended_action, confidence,
  fk_probability, fk_frequency, fk_severity, fk_band,
  m5_probability, m5_severity, m5_band, source_photo_indices
)
select
  id, user_id, 4, 'Fixture finding 4', 'fixture', 'fixture', 'fixture', 0.8,
  3, 2, 15, 'medium', 3, 3, 'medium', array[1]
from public.analyses where title like 'quality-current-%';

select private.evaluate_analysis_quality_regressions_v1();
select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key like 'analysis_%' and status in ('open', 'acknowledged')
  ),
  0,
  'all quality alerts resolve after metrics recover'
);

select is(
  (
    select count(*)::integer from public.admin_alert_events
    where rule_key like 'analysis_%'
  ),
  4,
  'recovery resolves events without creating replacement events'
);

select * from extensions.finish();
rollback;
