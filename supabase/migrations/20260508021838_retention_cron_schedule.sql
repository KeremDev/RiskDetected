-- Daily retention cleanup schedule.
--
-- Secrets required in Supabase Vault before this job runs:
-- - project_url: https://<project-ref>.supabase.co
-- - retention_cleanup_secret: same value as Edge Function RETENTION_CLEANUP_SECRET
--
-- The Edge Function is deployed with JWT verification disabled and protected by
-- the x-retention-cleanup-secret header. This keeps service-role credentials out
-- of source control and out of the cron SQL body.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-retention-cleanup-daily'
  ) then
    perform cron.unschedule('riskdetected-retention-cleanup-daily');
  end if;
end $$;

select cron.schedule(
  'riskdetected-retention-cleanup-daily',
  '15 2 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/retention-cleanup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-retention-cleanup-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'retention_cleanup_secret')
    ),
    body := jsonb_build_object(
      'source', 'pg_cron',
      'batch_size', 500,
      'scheduled_at', now()
    ),
    timeout_milliseconds := 30000
  ) as request_id;
  $$
);

select pg_notify('pgrst', 'reload schema');
