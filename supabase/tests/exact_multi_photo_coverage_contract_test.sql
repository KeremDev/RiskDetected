begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(25);

select has_column('public', 'ai_usage_logs', 'coverage_schema_version', 'coverage schema version exists');
select has_column('public', 'ai_usage_logs', 'coverage_contract_outcome', 'coverage outcome exists');
select has_column('public', 'ai_usage_logs', 'coverage_expected_records', 'coverage expected count exists');
select has_column('public', 'ai_usage_logs', 'coverage_returned_records', 'coverage returned count exists');
select has_column('public', 'ai_usage_logs', 'coverage_schema_fallback_used', 'coverage fallback flag exists');
select has_column('public', 'ai_usage_logs', 'provider_request_count', 'provider request count exists');
select has_column('public', 'ai_usage_logs', 'provider_attempt_total_tokens', 'provider token aggregate exists');
select has_column('public', 'ai_usage_logs', 'provider_attempts', 'provider attempts exist');

select ok(
  exists (
    select 1 from public.app_feature_flags
    where key = 'multi_photo_exact_coverage_schema'
  ),
  'exact coverage feature flag exists'
);

select ok(
  (
    select value->>'rollout_mode' = 'on'
      and value->>'schema_version' = '2'
      and value->>'kill_switch' = 'false'
    from public.app_feature_flags
    where key = 'multi_photo_exact_coverage_schema'
  ),
  'exact coverage feature flag matches the attested production rollout'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '00000000-0000-4000-8000-000000000601'::uuid,
    'exact-coverage-test-a@example.invalid',
    'authenticated', 'authenticated', now(), now()
  ),
  (
    '00000000-0000-4000-8000-000000000602'::uuid,
    'exact-coverage-test-b@example.invalid',
    'authenticated', 'authenticated', now(), now()
  );

insert into public.analyses (id, user_id, kind, status, photo_count)
values
  (
    '00000000-0000-4000-8000-000000000611'::uuid,
    '00000000-0000-4000-8000-000000000601'::uuid,
    'photo', 'completed', 3
  ),
  (
    '00000000-0000-4000-8000-000000000612'::uuid,
    '00000000-0000-4000-8000-000000000602'::uuid,
    'photo', 'completed', 3
  );

select lives_ok(
  $$
    insert into public.ai_usage_logs (analysis_id, user_id, model)
    values (
      '00000000-0000-4000-8000-000000000611'::uuid,
      '00000000-0000-4000-8000-000000000601'::uuid,
      'legacy-model'
    )
  $$,
  'legacy usage inserts remain valid'
);

select throws_ok(
  $$
    update public.ai_usage_logs
    set coverage_schema_version = 3
    where analysis_id = '00000000-0000-4000-8000-000000000611'::uuid
  $$,
  '23514', null,
  'unsupported coverage schema versions are rejected'
);

select throws_ok(
  $$
    update public.ai_usage_logs
    set coverage_contract_outcome = 'unknown'
    where analysis_id = '00000000-0000-4000-8000-000000000611'::uuid
  $$,
  '23514', null,
  'unknown coverage outcomes are rejected'
);

select throws_ok(
  $$
    update public.ai_usage_logs
    set provider_request_count = -1
    where analysis_id = '00000000-0000-4000-8000-000000000611'::uuid
  $$,
  '23514', null,
  'negative provider request counts are rejected'
);

select throws_ok(
  $$
    update public.ai_usage_logs
    set provider_attempts = '{}'::jsonb
    where analysis_id = '00000000-0000-4000-8000-000000000611'::uuid
  $$,
  '23514', null,
  'provider attempts must be a JSON array'
);

select throws_ok(
  $$
    update public.ai_usage_logs
    set provider_attempts = (
      select jsonb_agg(jsonb_build_object('sequence', value))
      from generate_series(1, 33) value
    )
    where analysis_id = '00000000-0000-4000-8000-000000000611'::uuid
  $$,
  '23514', null,
  'provider attempts are capped at 32 records'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.ai_usage_logs'::regclass),
  'ai usage RLS remains enabled'
);

select ok(
  not has_function_privilege(
    'anon', 'public.admin_analysis_pipeline_metrics_v2()', 'execute'
  ),
  'anon cannot read pipeline metrics'
);

select ok(
  has_function_privilege(
    'service_role', 'public.admin_analysis_pipeline_metrics_v2()', 'execute'
  ),
  'service role can read pipeline metrics'
);

select ok(
  public.admin_analysis_pipeline_metrics_v2() ?& array[
    'queue_depth', 'queued_analyses', 'analyzing_analyses',
    'ambiguous_dispatches_24h', 'discarded_lost_claim_24h'
  ],
  'legacy pipeline metric keys remain present'
);

select ok(
  public.admin_analysis_pipeline_metrics_v2() ?& array[
    'analyses_with_coverage_repair_24h',
    'successful_coverage_repair_calls_24h',
    'analyses_with_multiple_provider_requests_24h',
    'coverage_contract_violations_24h',
    'coverage_schema_fallbacks_24h',
    'provider_attempt_total_tokens_24h'
  ],
  'new coverage and provider metric keys are present'
);

delete from public.ai_usage_logs where model = 'legacy-model';

create temporary table exact_coverage_metric_baseline as
select
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_multiple_successful_ai_calls_24h')::bigint as duplicates,
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_coverage_repair_24h')::bigint as repairs,
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_multiple_provider_requests_24h')::bigint as multi_requests,
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'coverage_contract_violations_24h')::bigint as violations;

insert into public.ai_usage_logs (
  analysis_id, user_id, model, error, job_mode, job_generation,
  coverage_schema_version, coverage_contract_outcome,
  provider_request_count, provider_attempt_total_tokens, provider_attempts,
  persistence_outcome, persistence_updated_at
)
values
  (
    '00000000-0000-4000-8000-000000000611'::uuid,
    '00000000-0000-4000-8000-000000000601'::uuid,
    'gemini-2.5-flash', null, 'analysis', 1, 2, 'complete', 1, 100,
    '[{"sequence":1}]'::jsonb, 'persisted', now()
  ),
  (
    '00000000-0000-4000-8000-000000000611'::uuid,
    '00000000-0000-4000-8000-000000000601'::uuid,
    'gemini-2.5-flash', null, 'repair', 2, 2, 'complete', 1, 80,
    '[{"sequence":1}]'::jsonb, 'persisted', now()
  ),
  (
    '00000000-0000-4000-8000-000000000612'::uuid,
    '00000000-0000-4000-8000-000000000602'::uuid,
    'gemini-2.5-flash', null, 'analysis', 1, 2,
    'normalized_contract_violation', 2, 200,
    '[{"sequence":1},{"sequence":2}]'::jsonb, 'persisted', now()
  ),
  (
    '00000000-0000-4000-8000-000000000612'::uuid,
    '00000000-0000-4000-8000-000000000602'::uuid,
    'gemini-2.5-flash', null, 'analysis', 1, 2, 'complete', 1, 100,
    '[{"sequence":1}]'::jsonb, 'persisted', now()
  );

select is(
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_multiple_successful_ai_calls_24h')::bigint,
  (select duplicates + 1 from exact_coverage_metric_baseline),
  'analysis plus repair is not a duplicate, same logical generation is'
);

select is(
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_coverage_repair_24h')::bigint,
  (select repairs + 1 from exact_coverage_metric_baseline),
  'coverage repairs are counted separately'
);

select is(
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'analyses_with_multiple_provider_requests_24h')::bigint,
  (select multi_requests + 1 from exact_coverage_metric_baseline),
  'physical provider retries are counted separately'
);

select is(
  (public.admin_analysis_pipeline_metrics_v2()
    ->> 'coverage_contract_violations_24h')::bigint,
  (select violations + 1 from exact_coverage_metric_baseline),
  'coverage contract violations are counted separately'
);

select * from extensions.finish();
rollback;
