-- Temporary subscription overrides for controlled QA on live TestFlight builds.
-- This table is intentionally not readable by anon/authenticated clients.

create table if not exists public.subscription_test_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tier text not null check (tier in ('plus', 'pro')),
  reason text not null default 'manual_test',
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by text not null default current_user,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_test_overrides_valid_window
    check (expires_at > starts_at)
);

create index if not exists subscription_test_overrides_user_active
  on public.subscription_test_overrides (user_id, expires_at desc)
  where revoked_at is null;

alter table public.subscription_test_overrides enable row level security;

revoke all on table public.subscription_test_overrides from anon, authenticated;
grant select, insert, update, delete on table public.subscription_test_overrides to service_role;
