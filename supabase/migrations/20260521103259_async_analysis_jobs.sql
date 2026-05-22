-- Durable background analysis jobs.
-- Client requests enqueue work; Edge workers consume this queue and complete analyses
-- even if the iOS app leaves the foreground after the enqueue request succeeds.

create extension if not exists pgmq;
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

alter type public.analysis_status add value if not exists 'queued';

alter table public.analyses
  add column if not exists queued_at timestamptz,
  add column if not exists worker_started_at timestamptz,
  add column if not exists last_worker_error text,
  add column if not exists worker_attempt_count integer not null default 0,
  add column if not exists completion_push_sent_at timestamptz;

create index if not exists analyses_async_status_idx
  on public.analyses (status, queued_at, worker_started_at);

create index if not exists analyses_completion_push_pending_idx
  on public.analyses (status, completed_at, completion_push_sent_at);

do $$
begin
  perform pgmq.create('analysis_jobs');
exception
  when duplicate_table or duplicate_object then
    null;
end $$;

create or replace function public.enqueue_analysis_job_message(p_message jsonb)
returns bigint
language sql
security definer
set search_path = public, pgmq
as $$
  select pgmq.send('analysis_jobs', p_message, 0);
$$;

create or replace function public.read_analysis_job_messages(
  p_limit integer default 1,
  p_visibility_timeout integer default 600
)
returns jsonb
language sql
security definer
set search_path = public, pgmq
as $$
  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
  from pgmq.read(
    'analysis_jobs',
    greatest(1, least(p_visibility_timeout, 900)),
    greatest(1, least(p_limit, 3))
  ) as m;
$$;

create or replace function public.delete_analysis_job_message(p_msg_id bigint)
returns boolean
language sql
security definer
set search_path = public, pgmq
as $$
  select pgmq.delete('analysis_jobs', p_msg_id);
$$;

revoke all on function public.enqueue_analysis_job_message(jsonb) from public, anon, authenticated;
revoke all on function public.read_analysis_job_messages(integer, integer) from public, anon, authenticated;
revoke all on function public.delete_analysis_job_message(bigint) from public, anon, authenticated;
grant execute on function public.enqueue_analysis_job_message(jsonb) to service_role;
grant execute on function public.read_analysis_job_messages(integer, integer) to service_role;
grant execute on function public.delete_analysis_job_message(bigint) to service_role;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-analysis-jobs-every-minute'
  ) then
    perform cron.unschedule('riskdetected-analysis-jobs-every-minute');
  end if;
end $$;

select cron.schedule(
  'riskdetected-analysis-jobs-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/process-analysis-jobs',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-analysis-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'analysis_worker_secret')
    ),
    body := jsonb_build_object(
      'source', 'pg_cron',
      'limit', 1,
      'scheduled_at', now()
    ),
    timeout_milliseconds := 30000
  ) as request_id;
  $$
);

select pg_notify('pgrst', 'reload schema');
