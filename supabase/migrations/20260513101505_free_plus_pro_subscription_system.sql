-- Free / Plus / Pro subscription system.
--
-- Backend source of truth:
-- - RevenueCat webhook writes public.user_subscriptions + public.profiles.tier.
-- - Edge Functions and DB triggers read plan capability from the database.
-- - iOS may mirror RevenueCat for UX, but limits must not trust the client.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

do $$
declare
  tier_type_oid oid;
begin
  select a.atttypid
    into tier_type_oid
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_type t on t.oid = a.atttypid
  where n.nspname = 'public'
    and c.relname = 'profiles'
    and a.attname = 'tier'
    and t.typtype = 'e'
  limit 1;

  if tier_type_oid is not null then
    execute format('alter type %s add value if not exists %L', tier_type_oid::regtype, 'plus');
  end if;
end;
$$;

alter table public.profiles
  drop constraint if exists profiles_tier_check;

alter table public.profiles
  add constraint profiles_tier_check
  check (tier::text in ('free', 'plus', 'pro'));

alter table public.analyses
  add column if not exists analysis_mode text not null default 'standard';

alter table public.analyses
  drop constraint if exists analyses_analysis_mode_check;

alter table public.analyses
  add constraint analyses_analysis_mode_check
  check (analysis_mode in ('standard', 'detailed', 'emergency', 'procedure'));

create index if not exists analyses_user_mode_created
  on public.analyses (user_id, analysis_mode, created_at desc);

create table if not exists public.user_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'plus', 'pro')),
  source text not null default 'revenuecat',
  status text not null default 'inactive',
  revenuecat_app_user_id text,
  product_id text,
  entitlement_id text,
  entitlement_ids text[] not null default '{}',
  environment text,
  current_period_ends_at timestamptz,
  last_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_subscriptions_status_expires
  on public.user_subscriptions (status, current_period_ends_at);

alter table public.user_subscriptions enable row level security;

drop policy if exists "Users read own subscription" on public.user_subscriptions;
create policy "Users read own subscription"
  on public.user_subscriptions for select
  using (auth.uid() = user_id);

grant select on public.user_subscriptions to authenticated;

create table if not exists public.subscription_events (
  event_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  app_user_id text,
  event_type text not null,
  product_id text,
  entitlement_ids text[] not null default '{}',
  environment text,
  raw_event jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists subscription_events_user_received
  on public.subscription_events (user_id, received_at desc);

alter table public.subscription_events enable row level security;

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null,
  event_type text not null,
  source_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists usage_events_user_feature_created
  on public.usage_events (user_id, feature, created_at desc);

alter table public.usage_events enable row level security;

drop policy if exists "Users read own usage events" on public.usage_events;
create policy "Users read own usage events"
  on public.usage_events for select
  using (auth.uid() = user_id);

grant select on public.usage_events to authenticated;

create or replace function private.user_plan_tier(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, private
as $$
  select case
    when us.tier in ('plus', 'pro')
      and us.status in ('active', 'trialing', 'grace_period')
      and (us.current_period_ends_at is null or us.current_period_ends_at > now())
      then us.tier
    when p.tier::text in ('plus', 'pro') then p.tier::text
    else 'free'
  end
  from public.profiles p
  left join public.user_subscriptions us on us.user_id = p.id
  where p.id = p_user_id
  limit 1;
$$;

revoke all on function private.user_plan_tier(uuid) from public, anon, authenticated;

create or replace function private.report_monthly_limit(p_tier text)
returns integer
language sql
immutable
set search_path = private
as $$
  select case p_tier
    when 'free' then 3
    when 'plus' then 150
    when 'pro' then null
    else 3
  end;
$$;

revoke all on function private.report_monthly_limit(text) from public, anon, authenticated;

create or replace function private.archive_retention_days(p_tier text)
returns integer
language sql
immutable
set search_path = private
as $$
  select case p_tier
    when 'free' then 7
    when 'plus' then 30
    when 'pro' then null
    else 7
  end;
$$;

revoke all on function private.archive_retention_days(text) from public, anon, authenticated;

create or replace function public.enforce_report_plan_limits()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  tier text;
  monthly_limit integer;
  month_start timestamptz;
  month_end timestamptz;
  used_count integer;
begin
  tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);

  if monthly_limit is null then
    return new;
  end if;

  month_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  month_end := month_start + interval '1 month';

  select count(*)
    into used_count
  from public.reports r
  where r.user_id = new.user_id
    and r.created_at >= month_start
    and r.created_at < month_end;

  if used_count >= monthly_limit then
    raise exception 'report_quota_exceeded:%/%', monthly_limit, monthly_limit
      using errcode = 'P0001',
            hint = 'Upgrade plan or wait until the next monthly quota period.';
  end if;

  return new;
end;
$$;

drop trigger if exists reports_enforce_plan_limits on public.reports;
create trigger reports_enforce_plan_limits
  before insert on public.reports
  for each row
  execute function public.enforce_report_plan_limits();

create or replace function public.set_photo_retention_fields()
returns trigger
language plpgsql
set search_path = public, private
as $$
declare
  user_tier text;
  retention_days integer;
begin
  user_tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  retention_days := private.archive_retention_days(user_tier);

  if new.retention_expires_at is null then
    new.retention_expires_at := case
      when retention_days is null then null
      else coalesce(new.created_at, now()) + make_interval(days => retention_days)
    end;
  end if;

  if new.retention_policy is null or new.retention_policy = 'analysis_photo' then
    new.retention_policy := case
      when retention_days is null then 'pro_photo_unlimited'
      else user_tier || '_photo_' || retention_days || 'd'
    end;
  end if;

  return new;
end;
$$;

update public.photos ph
set retention_expires_at = case
      when private.archive_retention_days(coalesce(private.user_plan_tier(ph.user_id), 'free')) is null then null
      else coalesce(ph.created_at, now()) +
        make_interval(days => private.archive_retention_days(coalesce(private.user_plan_tier(ph.user_id), 'free')))
    end,
    retention_policy = case
      when private.archive_retention_days(coalesce(private.user_plan_tier(ph.user_id), 'free')) is null then 'pro_photo_unlimited'
      else coalesce(private.user_plan_tier(ph.user_id), 'free') || '_photo_' ||
        private.archive_retention_days(coalesce(private.user_plan_tier(ph.user_id), 'free')) || 'd'
    end
where ph.retention_policy in ('analysis_photo', 'free_photo_30d', 'pro_photo_365d')
   or ph.retention_policy is null;

select pg_notify('pgrst', 'reload schema');
