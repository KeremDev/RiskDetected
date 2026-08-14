-- Additive queue metadata for Google Play's web account-deletion request path.
-- Existing iOS/Android calls remain immediate; only authenticated web requests opt into the
-- request_only queue. No new Data API table or client grant is introduced.

alter table public.account_deletion_requests
  add column if not exists requested_via text not null default 'legacy',
  add column if not exists completion_mode text not null default 'immediate',
  add column if not exists due_at timestamptz,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists last_error_code text;

alter table public.account_deletion_requests
  drop constraint if exists account_deletion_requests_requested_via_check;
alter table public.account_deletion_requests
  add constraint account_deletion_requests_requested_via_check
  check (requested_via in ('legacy', 'ios', 'android', 'web'));

alter table public.account_deletion_requests
  drop constraint if exists account_deletion_requests_completion_mode_check;
alter table public.account_deletion_requests
  add constraint account_deletion_requests_completion_mode_check
  check (completion_mode in ('immediate', 'request_only'));

alter table public.account_deletion_requests
  drop constraint if exists account_deletion_requests_attempt_count_check;
alter table public.account_deletion_requests
  add constraint account_deletion_requests_attempt_count_check
  check (attempt_count between 0 and 10);

update public.account_deletion_requests
set due_at = coalesce(due_at, created_at)
where due_at is null;

alter table public.account_deletion_requests
  alter column due_at set default now(),
  alter column due_at set not null;

create index if not exists account_deletion_requests_web_queue_idx
  on public.account_deletion_requests (due_at, next_attempt_at, created_at)
  where status in ('pending', 'processing')
    and completion_mode = 'request_only';

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (
    select 1 from cron.job
    where jobname = 'riskdetected-account-deletion-hourly'
  ) then
    perform cron.unschedule('riskdetected-account-deletion-hourly');
  end if;

  if exists (
    select 1 from vault.decrypted_secrets
    where name = 'project_url' and nullif(decrypted_secret, '') is not null
  ) and exists (
    select 1 from vault.decrypted_secrets
    where name = 'account_deletion_queue_secret' and nullif(decrypted_secret, '') is not null
  ) then
    perform cron.schedule(
      'riskdetected-account-deletion-hourly',
      '12 * * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret from vault.decrypted_secrets where name = 'project_url'
        ) || '/functions/v1/process-account-deletion-queue',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-account-deletion-queue-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'account_deletion_queue_secret'
          )
        ),
        body := jsonb_build_object('source', 'pg_cron', 'limit', 25),
        timeout_milliseconds := 120000
      ) as request_id;
      $cron$
    );
  else
    raise notice 'account deletion cron not scheduled: Vault secrets are missing';
  end if;
end
$$;

select pg_notify('pgrst', 'reload schema');
