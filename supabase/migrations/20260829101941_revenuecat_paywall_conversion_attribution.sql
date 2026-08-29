create table if not exists public.subscription_conversion_attributions (
  revenuecat_event_id text primary key
    references public.subscription_events(event_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  product_identifier text,
  purchased_tier public.subscription_tier,
  purchased_at timestamptz not null,
  entry_event_id uuid references public.paywall_events(id) on delete set null,
  funnel_session_id uuid,
  entry_clicked_at timestamptz,
  seconds_to_purchase bigint,
  entry_point text,
  entry_surface text,
  entry_component text,
  analysis_id uuid,
  result_section text,
  item_id text,
  entry_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint subscription_conversion_seconds_check
    check (seconds_to_purchase is null or seconds_to_purchase >= 0),
  constraint subscription_conversion_entry_context_object_check
    check (jsonb_typeof(entry_context) = 'object')
);

create index if not exists subscription_conversion_user_purchase_idx
  on public.subscription_conversion_attributions (user_id, purchased_at desc);

create index if not exists subscription_conversion_entry_point_idx
  on public.subscription_conversion_attributions (entry_point, purchased_at desc)
  where entry_point is not null;

alter table public.subscription_conversion_attributions enable row level security;

revoke all on public.subscription_conversion_attributions
  from anon, authenticated, public;
grant select, insert, update on public.subscription_conversion_attributions
  to service_role;

comment on table public.subscription_conversion_attributions is
  'RevenueCat-verified initial purchases and upgrades attributed to the latest paywall entry tap within 24 hours.';
