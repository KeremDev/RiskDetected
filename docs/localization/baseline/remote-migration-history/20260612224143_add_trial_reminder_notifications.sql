-- Plus yearly free-trial reminder notifications.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

alter table public.user_subscriptions
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists trial_product_id text,
  add column if not exists will_renew boolean,
  add column if not exists trial_reminder_sent_at timestamptz,
  add column if not exists trial_reminder_last_attempt_at timestamptz,
  add column if not exists trial_reminder_status text,
  add column if not exists trial_reminder_notification_event_id uuid
    references public.notification_events(id) on delete set null;

alter table public.user_subscriptions
  drop constraint if exists user_subscriptions_trial_product_check;
alter table public.user_subscriptions
  add constraint user_subscriptions_trial_product_check
  check (trial_product_id is null or trial_product_id = 'riskdetected_plus_yearly');

alter table public.user_subscriptions
  drop constraint if exists user_subscriptions_trial_dates_check;
alter table public.user_subscriptions
  add constraint user_subscriptions_trial_dates_check
  check (
    trial_started_at is null
    or trial_ends_at is null
    or trial_ends_at > trial_started_at
  );

alter table public.user_subscriptions
  drop constraint if exists user_subscriptions_trial_reminder_status_check;
alter table public.user_subscriptions
  add constraint user_subscriptions_trial_reminder_status_check
  check (
    trial_reminder_status is null
    or trial_reminder_status in ('pending', 'sent', 'skipped', 'failed', 'inactive')
  );

create index if not exists user_subscriptions_trial_reminder_due_idx
  on public.user_subscriptions (trial_ends_at, trial_reminder_last_attempt_at)
  where trial_reminder_sent_at is null
    and trial_ends_at is not null
    and trial_product_id = 'riskdetected_plus_yearly';

alter table public.notification_preferences
  add column if not exists trial_reminder boolean not null default true;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'riskdetected-trial-reminders-hourly'
  ) then
    perform cron.unschedule('riskdetected-trial-reminders-hourly');
  end if;
end $$;

select cron.schedule(
  'riskdetected-trial-reminders-hourly',
  '0 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-trial-reminder-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-trial-reminder-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'trial_reminder_secret')
    ),
    body := jsonb_build_object(
      'source', 'pg_cron',
      'limit', 100,
      'scheduled_at', now()
    ),
    timeout_milliseconds := 30000
  ) as request_id;
  $$
);

select pg_notify('pgrst', 'reload schema');;
