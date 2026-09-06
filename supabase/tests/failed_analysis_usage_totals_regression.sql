begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(11);

select has_function(
  'public',
  'fail_analysis_engine_run_v3',
  array['uuid', 'uuid', 'text'],
  'failed analysis settlement RPC exists'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  'failed-analysis-totals@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, plan_at_creation
) values (
  '00000000-0000-4000-8000-00000000fa02'::uuid,
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  'failed totals fixture',
  'photo',
  'pending',
  1,
  'free'
);

insert into private.analysis_engine_runs (
  id, analysis_id, user_id, queue_msg_id, job_generation, job_mode,
  engine_version, schema_version, prompt_version, policy_version,
  control_catalog_version, visual_input_mode, provider, model, status,
  config_snapshot
) values (
  '00000000-0000-4000-8000-00000000fa03'::uuid,
  '00000000-0000-4000-8000-00000000fa02'::uuid,
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  1,
  1,
  'analysis',
  'vnext-v4',
  'safety-claim-v4.0',
  'fixture-prompt',
  'fixture-policy',
  'fixture-controls',
  'native_multi_photo',
  'gemini',
  'fixture-model',
  'running',
  '{}'::jsonb
);

insert into private.analysis_provider_attempts (
  id, engine_run_id, analysis_id, user_id, attempt_kind, attempt_number,
  provider, model, state, input_tokens, output_tokens, reasoning_tokens,
  cached_input_tokens, cost_usd, standard_equivalent_cost_usd,
  duration_ms, http_status, error_code
) values (
  '00000000-0000-4000-8000-00000000fa04'::uuid,
  '00000000-0000-4000-8000-00000000fa03'::uuid,
  '00000000-0000-4000-8000-00000000fa02'::uuid,
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  'primary',
  1,
  'gemini',
  'fixture-model',
  'failed',
  120,
  30,
  10,
  5,
  0.50,
  0.75,
  900,
  503,
  'provider_unavailable'
);

create temporary table first_failure as
select public.fail_analysis_engine_run_v3(
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  '00000000-0000-4000-8000-00000000fa03'::uuid,
  'fixture_provider_failure'
) response;

select is(
  (select response->>'state' from first_failure),
  'recorded',
  'running analysis is settled as failed'
);

select ok(
  exists (
    select 1
    from private.analysis_engine_runs
    where id = '00000000-0000-4000-8000-00000000fa03'::uuid
      and status = 'failed'
      and completed_at is not null
      and duration_ms >= 0
  ),
  'failed run records terminal timing fields'
);

select ok(
  exists (
    select 1
    from private.analysis_engine_runs
    where id = '00000000-0000-4000-8000-00000000fa03'::uuid
      and total_provider_requests = 1
      and total_input_tokens = 120
      and total_output_tokens = 30
      and total_reasoning_tokens = 10
      and total_cost_usd = 0.50
      and total_standard_equivalent_cost_usd = 0.75
  ),
  'failed run totals are rebuilt from provider attempts'
);

select is(
  (
    select error_code
    from private.analysis_engine_runs
    where id = '00000000-0000-4000-8000-00000000fa03'::uuid
  ),
  'fixture_provider_failure',
  'first terminal error is recorded'
);

create temporary table failed_snapshot_before_repeat as
select to_jsonb(e) - 'updated_at' snapshot
from private.analysis_engine_runs e
where id = '00000000-0000-4000-8000-00000000fa03'::uuid;

create temporary table repeated_failure as
select public.fail_analysis_engine_run_v3(
  '00000000-0000-4000-8000-00000000fa01'::uuid,
  '00000000-0000-4000-8000-00000000fa03'::uuid,
  'must_not_replace_original_error'
) response;

select is(
  (select response->>'state' from repeated_failure),
  'recorded',
  'repeated settlement is accepted idempotently'
);

select is(
  (select snapshot from failed_snapshot_before_repeat),
  (
    select to_jsonb(e) - 'updated_at'
    from private.analysis_engine_runs e
    where id = '00000000-0000-4000-8000-00000000fa03'::uuid
  ),
  'repeated settlement does not change terminal data'
);

select is(
  (
    public.fail_analysis_engine_run_v3(
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-4000-8000-00000000fa03'::uuid,
      'wrong_owner'
    )->>'ok'
  )::boolean,
  false,
  'wrong owner cannot settle a run'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.fail_analysis_engine_run_v3(uuid,uuid,text)',
    'execute'
  ),
  'authenticated users cannot execute failure settlement'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.fail_analysis_engine_run_v3(uuid,uuid,text)',
    'execute'
  ),
  'anonymous users cannot execute failure settlement'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.fail_analysis_engine_run_v3(uuid,uuid,text)',
    'execute'
  ),
  'service role can execute failure settlement'
);

select * from extensions.finish();
rollback;
