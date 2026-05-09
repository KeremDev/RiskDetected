-- Push notification device registry and user preferences.
-- APNs provider credentials are kept in Edge Function secrets, never in DB/client.

create table if not exists public.push_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null default 'ios' check (platform in ('ios')),
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  app_version text,
  device_model text,
  notifications_enabled boolean not null default true,
  last_registered_at timestamptz not null default now(),
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  analysis_complete boolean not null default true,
  report_ready boolean not null default true,
  account_updates boolean not null default true,
  marketing boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'skipped')),
  sent_count integer not null default 0,
  failure_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists push_device_tokens_user_idx
  on public.push_device_tokens (user_id);

create index if not exists push_device_tokens_active_idx
  on public.push_device_tokens (user_id, environment)
  where notifications_enabled = true;

create index if not exists notification_events_user_created_idx
  on public.notification_events (user_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists push_device_tokens_set_updated_at on public.push_device_tokens;
create trigger push_device_tokens_set_updated_at
before update on public.push_device_tokens
for each row execute function public.set_updated_at();

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
before update on public.notification_preferences
for each row execute function public.set_updated_at();

alter table public.push_device_tokens enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notification_events enable row level security;

drop policy if exists "Users read own push tokens" on public.push_device_tokens;
create policy "Users read own push tokens"
on public.push_device_tokens
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users insert own push tokens" on public.push_device_tokens;
create policy "Users insert own push tokens"
on public.push_device_tokens
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users update own push tokens" on public.push_device_tokens;
create policy "Users update own push tokens"
on public.push_device_tokens
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users delete own push tokens" on public.push_device_tokens;
create policy "Users delete own push tokens"
on public.push_device_tokens
for delete
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users read own notification preferences" on public.notification_preferences;
create policy "Users read own notification preferences"
on public.notification_preferences
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users insert own notification preferences" on public.notification_preferences;
create policy "Users insert own notification preferences"
on public.notification_preferences
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users update own notification preferences" on public.notification_preferences;
create policy "Users update own notification preferences"
on public.notification_preferences
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users read own notification events" on public.notification_events;
create policy "Users read own notification events"
on public.notification_events
for select
to authenticated
using (auth.uid() = user_id);
