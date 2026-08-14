-- Exact multi-photo coverage contract and physical provider request telemetry.
-- Additive-only: legacy rows and the current client response contract remain valid.

alter table public.ai_usage_logs
  add column if not exists coverage_schema_version integer,
  add column if not exists coverage_contract_outcome text,
  add column if not exists coverage_expected_records integer,
  add column if not exists coverage_returned_records integer,
  add column if not exists coverage_schema_fallback_used boolean not null default false,
  add column if not exists provider_request_count integer not null default 0,
  add column if not exists provider_attempt_total_tokens bigint not null default 0,
  add column if not exists provider_attempts jsonb not null default '[]'::jsonb;

alter table public.ai_usage_logs
  drop constraint if exists ai_usage_logs_coverage_schema_version_check,
  drop constraint if exists ai_usage_logs_coverage_contract_outcome_check,
  drop constraint if exists ai_usage_logs_coverage_expected_records_check,
  drop constraint if exists ai_usage_logs_coverage_returned_records_check,
  drop constraint if exists ai_usage_logs_provider_request_count_check,
  drop constraint if exists ai_usage_logs_provider_attempt_total_tokens_check,
  drop constraint if exists ai_usage_logs_provider_attempts_check;

alter table public.ai_usage_logs
  add constraint ai_usage_logs_coverage_schema_version_check
    check (coverage_schema_version is null or coverage_schema_version in (1, 2)),
  add constraint ai_usage_logs_coverage_contract_outcome_check
    check (
      coverage_contract_outcome is null
      or coverage_contract_outcome in (
        'not_applicable',
        'complete',
        'normalized_contract_violation',
        'missing_records'
      )
    ),
  add constraint ai_usage_logs_coverage_expected_records_check
    check (coverage_expected_records is null or coverage_expected_records >= 0),
  add constraint ai_usage_logs_coverage_returned_records_check
    check (coverage_returned_records is null or coverage_returned_records >= 0),
  add constraint ai_usage_logs_provider_request_count_check
    check (provider_request_count >= 0),
  add constraint ai_usage_logs_provider_attempt_total_tokens_check
    check (provider_attempt_total_tokens >= 0),
  add constraint ai_usage_logs_provider_attempts_check
    check (
      jsonb_typeof(provider_attempts) = 'array'
      and jsonb_array_length(provider_attempts) <= 32
    );

create index if not exists ai_usage_logs_coverage_metrics_idx
  on public.ai_usage_logs (created_at desc, coverage_contract_outcome)
  where coverage_schema_version = 2;

create or replace function public.admin_analysis_pipeline_metrics_v2()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'queue_depth', (select count(*) from pgmq.q_analysis_jobs),
    'queued_analyses', (
      select count(*) from public.analyses where status::text = 'queued'
    ),
    'analyzing_analyses', (
      select count(*) from public.analyses where status::text = 'analyzing'
    ),
    'expired_analysis_leases', (
      select count(*)
      from private.analysis_job_state
      where claim_token is not null and lease_expires_at <= now()
    ),
    'abandoned_pending_drafts', (
      select count(*)
      from public.analyses
      where status::text = 'pending'
        and photo_count = 0
        and queued_at is null
        and worker_started_at is null
        and created_at < now() - interval '24 hours'
    ),
    'failed_analyses_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and (failure_category = 'technical' or failure_category is null)
    ),
    'business_rejections_7d', (
      select count(*)
      from public.analyses
      where status::text = 'failed'
        and created_at >= now() - interval '7 days'
        and failure_category = 'business'
    ),
    'persistence_pending_over_5m', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'pending'
        and persistence_updated_at < now() - interval '5 minutes'
    ),
    'ambiguous_dispatches_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'dispatch_ambiguous_transport'
        and created_at >= now() - interval '24 hours'
    ),
    'ambiguous_then_first_attempt_completed_24h', (
      select count(distinct (a.analysis_id, a.job_generation, a.worker_attempt))
      from private.analysis_job_events a
      where a.event_type = 'dispatch_ambiguous_transport'
        and a.created_at >= now() - interval '24 hours'
        and exists (
          select 1
          from private.analysis_job_events f
          where f.analysis_id = a.analysis_id
            and f.job_generation = a.job_generation
            and f.worker_attempt = a.worker_attempt
            and f.event_type = 'finalized'
            and f.created_at >= a.created_at
        )
    ),
    'lease_expiry_retries_24h', (
      select count(*)
      from private.analysis_job_events
      where event_type = 'lease_expired_retry'
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_multiple_successful_ai_calls_24h', (
      select count(*)
      from (
        select
          analysis_id,
          coalesce(job_mode, 'analysis') as logical_job_mode,
          coalesce(job_generation, 1) as logical_generation
        from public.ai_usage_logs
        where analysis_id is not null
          and error is null
          and created_at >= now() - interval '24 hours'
        group by
          analysis_id,
          coalesce(job_mode, 'analysis'),
          coalesce(job_generation, 1)
        having count(*) > 1
      ) duplicated_successes
    ),
    'discarded_lost_claim_24h', (
      select count(*)
      from public.ai_usage_logs
      where persistence_outcome = 'discarded'
        and persistence_error_code = 'lost_claim'
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_coverage_repair_24h', (
      select count(distinct analysis_id)
      from public.ai_usage_logs
      where job_mode = 'repair'
        and created_at >= now() - interval '24 hours'
    ),
    'successful_coverage_repair_calls_24h', (
      select count(*)
      from public.ai_usage_logs
      where job_mode = 'repair'
        and error is null
        and created_at >= now() - interval '24 hours'
    ),
    'analyses_with_multiple_provider_requests_24h', (
      select count(distinct analysis_id)
      from public.ai_usage_logs
      where provider_request_count > 1
        and created_at >= now() - interval '24 hours'
    ),
    'coverage_contract_violations_24h', (
      select count(*)
      from public.ai_usage_logs
      where coverage_contract_outcome in (
          'normalized_contract_violation',
          'missing_records'
        )
        and created_at >= now() - interval '24 hours'
    ),
    'coverage_schema_fallbacks_24h', (
      select count(*)
      from public.ai_usage_logs
      where coverage_schema_fallback_used
        and created_at >= now() - interval '24 hours'
    ),
    'provider_attempt_total_tokens_24h', (
      select coalesce(sum(provider_attempt_total_tokens), 0)
      from public.ai_usage_logs
      where created_at >= now() - interval '24 hours'
    )
  );
$$;

insert into public.app_feature_flags (key, value)
values (
  'multi_photo_exact_coverage_schema',
  jsonb_build_object(
    'rollout_mode', 'off',
    'enabled_user_hashes', jsonb_build_array(),
    'schema_version', 2,
    'kill_switch', false
  )
)
on conflict (key) do nothing;

revoke all on function public.admin_analysis_pipeline_metrics_v2()
  from public, anon, authenticated;
grant execute on function public.admin_analysis_pipeline_metrics_v2()
  to service_role;

select pg_notify('pgrst', 'reload schema');
