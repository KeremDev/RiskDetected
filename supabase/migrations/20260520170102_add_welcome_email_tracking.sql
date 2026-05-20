alter table public.profiles
  add column if not exists welcome_email_sent_at timestamptz,
  add column if not exists welcome_email_status text,
  add column if not exists welcome_email_error text;

alter table public.profiles
  drop constraint if exists profiles_welcome_email_status_check;

alter table public.profiles
  add constraint profiles_welcome_email_status_check
  check (
    welcome_email_status is null
    or welcome_email_status in ('sending', 'sent', 'email_failed')
  );
