create table if not exists public.paywall_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  funnel_session_id uuid not null,
  source text not null,
  variant_id text not null,
  segment_key text,
  event_name text not null,
  selected_tier public.subscription_tier,
  billing text,
  product_identifier text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint paywall_events_source_check
    check (source in ('in_app', 'onboarding_v2')),
  constraint paywall_events_event_name_check
    check (
      event_name in (
        'view',
        'close',
        'cta_tap',
        'plan_select',
        'billing_select',
        'purchase_started',
        'purchase_succeeded',
        'purchase_failed',
        'restore_tap'
      )
    ),
  constraint paywall_events_segment_key_check
    check (
      segment_key is null
      or segment_key in (
        'construction',
        'industrial_high_risk',
        'osgb_high_volume',
        'office_service',
        'health_team'
      )
    ),
  constraint paywall_events_billing_check
    check (billing is null or billing in ('yearly', 'monthly')),
  constraint paywall_events_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists paywall_events_user_created_idx
  on public.paywall_events (user_id, created_at desc);

create index if not exists paywall_events_funnel_session_idx
  on public.paywall_events (funnel_session_id, created_at);

create index if not exists paywall_events_variant_event_idx
  on public.paywall_events (variant_id, event_name, created_at desc);

alter table public.paywall_events enable row level security;

drop policy if exists paywall_events_select_own
  on public.paywall_events;
create policy paywall_events_select_own
  on public.paywall_events
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists paywall_events_insert_own
  on public.paywall_events;
create policy paywall_events_insert_own
  on public.paywall_events
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on public.paywall_events from anon, public;
grant select, insert on public.paywall_events to authenticated;
