-- Reconcile the web account-deletion worker schedule after operators provision
-- the project URL and queue secret in Vault. The original additive migration
-- intentionally remained fail-safe when those values were absent.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
declare
  has_project_url boolean;
  has_queue_secret boolean;
begin
  select exists (
    select 1
    from vault.decrypted_secrets
    where name = 'project_url'
      and nullif(decrypted_secret, '') is not null
  ) into has_project_url;

  select exists (
    select 1
    from vault.decrypted_secrets
    where name = 'account_deletion_queue_secret'
      and nullif(decrypted_secret, '') is not null
  ) into has_queue_secret;

  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-account-deletion-hourly'
  ) then
    perform cron.unschedule('riskdetected-account-deletion-hourly');
  end if;

  if has_project_url and has_queue_secret then
    perform cron.schedule(
      'riskdetected-account-deletion-hourly',
      '12 * * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'project_url'
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
