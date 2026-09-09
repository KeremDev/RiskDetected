begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, private, extensions, pg_catalog;

select extensions.plan(23);

select has_function(
  'private',
  'analysis_usage_rollup_v1',
  array['timestamp with time zone', 'timestamp with time zone', 'uuid[]'],
  'canonical analysis usage rollup exists'
);
select function_privs_are(
  'private', 'analysis_usage_rollup_v1',
  array['timestamp with time zone', 'timestamp with time zone', 'uuid[]'],
  'service_role', array['EXECUTE'],
  'service role can execute canonical usage rollup'
);
select function_privs_are(
  'private', 'analysis_usage_rollup_v1',
  array['timestamp with time zone', 'timestamp with time zone', 'uuid[]'],
  'authenticated', array[]::text[],
  'authenticated users cannot execute canonical usage rollup'
);
select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'analysis_usage_rollup_v1'
  ),
  'canonical usage rollup is security definer'
);
select ok(
  (
    select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'analysis_usage_rollup_v1'
  ),
  'canonical usage rollup pins an empty search path'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  'v4-telemetry@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (
  id, user_id, title, kind, status, photo_count, plan_at_creation
) values
  (
    '00000000-0000-4000-8000-00000000fb02'::uuid,
    '00000000-0000-4000-8000-00000000fb01'::uuid,
    'trusted routing fixture', 'photo', 'pending', 1, 'plus'
  ),
  (
    '00000000-0000-4000-8000-00000000fb03'::uuid,
    '00000000-0000-4000-8000-00000000fb01'::uuid,
    'untrusted routing fixture', 'photo', 'pending', 1, 'plus'
  ),
  (
    '00000000-0000-4000-8000-00000000fb04'::uuid,
    '00000000-0000-4000-8000-00000000fb01'::uuid,
    'immutable routing fixture', 'photo', 'pending', 1, 'plus'
  );

create temporary table trusted_submit as
select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  '00000000-0000-4000-8000-00000000fb02'::uuid,
  jsonb_build_object(
    'analysis_engine_client_routing', jsonb_build_object(
      'source', 'trusted_analyze_enqueue',
      'client_platform', ' IOS ',
      'client_app_build', '89'
    )
  )
) response;

select is(
  (select response->>'state' from trusted_submit),
  'queued',
  'trusted analysis submission is queued'
);
select is(
  (select client_platform from public.analyses
    where id = '00000000-0000-4000-8000-00000000fb02'),
  'ios',
  'trusted submission persists normalized client platform'
);
select is(
  (select client_build from public.analyses
    where id = '00000000-0000-4000-8000-00000000fb02'),
  '89',
  'trusted submission persists client build'
);

select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  '00000000-0000-4000-8000-00000000fb03'::uuid,
  jsonb_build_object(
    'analysis_engine_client_routing', jsonb_build_object(
      'source', 'raw_client_payload',
      'client_platform', 'ios',
      'client_app_build', '89'
    )
  )
);
select is(
  (select client_platform from public.analyses
    where id = '00000000-0000-4000-8000-00000000fb03'),
  null,
  'untrusted routing metadata is ignored'
);
select is(
  (select client_build from public.analyses
    where id = '00000000-0000-4000-8000-00000000fb03'),
  null,
  'untrusted build metadata is ignored'
);

update public.analyses
set client_platform = 'android', client_build = '7'
where id = '00000000-0000-4000-8000-00000000fb04';
select public.submit_analysis_job_v2(
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  '00000000-0000-4000-8000-00000000fb04'::uuid,
  jsonb_build_object(
    'analysis_engine_client_routing', jsonb_build_object(
      'source', 'trusted_analyze_enqueue',
      'client_platform', 'ios',
      'client_app_build', '89'
    )
  )
);
select is(
  (select client_platform || ':' || client_build from public.analyses
    where id = '00000000-0000-4000-8000-00000000fb04'),
  'android:7',
  'an existing client identity is not overwritten'
);

update public.analyses
set status = 'completed',
    completed_at = now(),
    output_language = 'tr',
    canvas = 'general',
    raw_ai_response = jsonb_build_object('_summary', 'fixture')
where id = '00000000-0000-4000-8000-00000000fb02';

insert into private.analysis_engine_runs (
  id, analysis_id, user_id, queue_msg_id, job_generation, job_mode,
  engine_version, schema_version, prompt_version, policy_version,
  control_catalog_version, visual_input_mode, provider, model, status,
  config_snapshot, total_provider_requests, total_input_tokens,
  total_output_tokens, total_reasoning_tokens, total_cost_usd,
  total_standard_equivalent_cost_usd, duration_ms, completed_at
) values (
  '00000000-0000-4000-8000-00000000fb05'::uuid,
  '00000000-0000-4000-8000-00000000fb02'::uuid,
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  9001, 1, 'analysis', 'vnext-v4', 'safety-claim-v4.0',
  'fixture-prompt', 'fixture-policy', 'fixture-controls',
  'native_per_photo', 'gemini', 'fixture-model', 'completed', '{}'::jsonb,
  1, 100, 50, 25, 0.10, 0.125, 1800, now()
);

insert into private.analysis_provider_attempts (
  id, engine_run_id, analysis_id, user_id, attempt_kind, attempt_number,
  provider, model, state, input_tokens, output_tokens, reasoning_tokens,
  cached_input_tokens, cost_usd, standard_equivalent_cost_usd,
  duration_ms, http_status
) values (
  '00000000-0000-4000-8000-00000000fb06'::uuid,
  '00000000-0000-4000-8000-00000000fb05'::uuid,
  '00000000-0000-4000-8000-00000000fb02'::uuid,
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  'primary', 1, 'gemini', 'fixture-model', 'persisted',
  100, 50, 25, 0, 0.10, 0.125, 1600, 200
);

-- A compatibility dual-write must never cause double counting.
insert into public.ai_usage_logs (
  analysis_id, user_id, provider, model, tokens_in, tokens_out,
  thoughts_tokens, total_tokens, provider_attempt_total_tokens,
  provider_request_count, duration_ms, client_platform
) values (
  '00000000-0000-4000-8000-00000000fb02'::uuid,
  '00000000-0000-4000-8000-00000000fb01'::uuid,
  'gemini', 'duplicate-fixture-model', 999, 999, 999, 2997, 2997, 9, 9999,
  'ios'
);

select is(
  (select count(*)::integer
   from private.analysis_usage_rollup_v1(
     null, null, array['00000000-0000-4000-8000-00000000fb02'::uuid]
   )),
  1,
  'canonical rollup returns one authoritative row for a v4 analysis'
);
select is(
  (select telemetry_source
   from private.analysis_usage_rollup_v1(
     null, null, array['00000000-0000-4000-8000-00000000fb02'::uuid]
   )),
  'v4_engine',
  'v4 private telemetry wins over a compatibility row'
);
select is(
  (select provider_calls::integer
   from private.analysis_usage_rollup_v1(
     null, null, array['00000000-0000-4000-8000-00000000fb02'::uuid]
   )),
  1,
  'v4 provider calls are counted exactly once'
);
select is(
  (select total_tokens
   from private.analysis_usage_rollup_v1(
     null, null, array['00000000-0000-4000-8000-00000000fb02'::uuid]
   )),
  175::bigint,
  'v4 input, output, and reasoning tokens are combined'
);
select is(
  (select estimated_cost_usd
   from private.analysis_usage_rollup_v1(
     null, null, array['00000000-0000-4000-8000-00000000fb02'::uuid]
   )),
  0.125::numeric,
  'v4 standard-equivalent cost is reported'
);
select is(
  (public.admin_analysis_quality_run_v1(
    '00000000-0000-4000-8000-00000000fb02'::uuid
  )->'cost'->>'provider_calls')::integer,
  1,
  'single-run quality RPC includes the v4 provider call'
);
select is(
  (public.admin_analysis_quality_run_v1(
    '00000000-0000-4000-8000-00000000fb02'::uuid
  )->'cost'->>'total_tokens')::bigint,
  175::bigint,
  'single-run quality RPC includes v4 tokens'
);
select is(
  (private.analysis_quality_window_v1(
    now() - interval '1 day', now() + interval '1 day'
  )->'legacy_aggregate'->>'provider_calls')::integer,
  1,
  'quality window includes v4 provider usage in its compatible bucket'
);
select is(
  (private.analysis_quality_window_v1(
    now() - interval '1 day', now() + interval '1 day'
  )->'legacy_aggregate'->>'total_tokens')::bigint,
  175::bigint,
  'quality window includes v4 token usage without the duplicate row'
);
select is(
  (public.admin_platform_overview_v1(30, 'ios')->'ai'->>'calls')::integer,
  1,
  'iOS platform overview includes the v4 provider call'
);
select is(
  (public.admin_platform_overview_v1(30, 'ios')->'ai'->>'total_tokens')::bigint,
  175::bigint,
  'iOS platform overview includes the v4 token total'
);
select is(
  (public.admin_platform_overview_v1(30, 'android')->'ai'->>'calls')::integer,
  0,
  'platform filtering excludes the iOS v4 call from Android'
);

select * from extensions.finish();
rollback;
