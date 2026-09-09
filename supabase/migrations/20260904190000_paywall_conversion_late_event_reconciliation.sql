-- Keep verified RevenueCat purchases attached to the exact client checkout funnel even when
-- the webhook reaches Supabase before the device's durable paywall-event queue is delivered.

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

create or replace function public.reconcile_paywall_conversion_from_client_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  conversion_event_id text;
  conversion_purchased_at timestamptz;
  entry_record public.paywall_events%rowtype;
begin
  if new.event_name not in ('purchase_started', 'purchase_succeeded')
     or new.entry_point is null
     or new.product_identifier is null then
    return new;
  end if;

  select attribution.revenuecat_event_id, attribution.purchased_at
    into conversion_event_id, conversion_purchased_at
  from public.subscription_conversion_attributions as attribution
  where attribution.user_id = new.user_id
    and attribution.product_identifier is not distinct from new.product_identifier
    and attribution.purchased_at between
      new.client_occurred_at - interval '24 hours'
      and new.client_occurred_at + interval '24 hours'
  order by abs(extract(epoch from (attribution.purchased_at - new.client_occurred_at))) asc
  limit 1;

  if conversion_event_id is null then
    return new;
  end if;

  select entry.*
    into entry_record
  from public.paywall_events as entry
  where entry.user_id = new.user_id
    and entry.funnel_session_id = new.funnel_session_id
    and entry.event_name = 'entry_tap'
  order by entry.client_occurred_at asc
  limit 1;

  update public.subscription_conversion_attributions
  set
    entry_event_id = entry_record.id,
    funnel_session_id = new.funnel_session_id,
    entry_clicked_at = coalesce(entry_record.client_occurred_at, new.client_occurred_at),
    seconds_to_purchase = greatest(
      extract(epoch from (
        conversion_purchased_at
        - coalesce(entry_record.client_occurred_at, new.client_occurred_at)
      )),
      0
    )::bigint,
    entry_point = coalesce(entry_record.entry_point, new.entry_point),
    entry_surface = coalesce(entry_record.entry_surface, new.entry_surface),
    entry_component = coalesce(entry_record.entry_component, new.entry_component),
    analysis_id = coalesce(entry_record.analysis_id, new.analysis_id),
    result_section = coalesce(entry_record.result_section, new.result_section),
    item_id = coalesce(entry_record.item_id, new.item_id),
    entry_context = case
      when entry_record.id is not null then entry_record.entry_context
      else new.entry_context
    end
  where revenuecat_event_id = conversion_event_id;

  return new;
end;
$$;

revoke all on function public.reconcile_paywall_conversion_from_client_event()
  from public, anon, authenticated;

drop trigger if exists reconcile_paywall_conversion_from_client_event
  on public.paywall_events;
create trigger reconcile_paywall_conversion_from_client_event
after insert on public.paywall_events
for each row
when (
  new.event_name in ('purchase_started', 'purchase_succeeded')
  and new.entry_point is not null
  and new.product_identifier is not null
)
execute function public.reconcile_paywall_conversion_from_client_event();

-- Repair historical conversions where the matching client checkout eventually arrived after
-- the webhook. Prefer an entry_tap in the same funnel; the purchase event already carries the
-- same immutable attribution context as a fallback.
with ranked_matches as (
  select
    attribution.revenuecat_event_id,
    attribution.purchased_at,
    checkout.id as checkout_event_id,
    checkout.funnel_session_id,
    checkout.client_occurred_at as checkout_at,
    checkout.entry_point as checkout_entry_point,
    checkout.entry_surface as checkout_entry_surface,
    checkout.entry_component as checkout_entry_component,
    checkout.analysis_id as checkout_analysis_id,
    checkout.result_section as checkout_result_section,
    checkout.item_id as checkout_item_id,
    checkout.entry_context as checkout_entry_context,
    row_number() over (
      partition by attribution.revenuecat_event_id
      order by
        abs(extract(epoch from (checkout.client_occurred_at - attribution.purchased_at))) asc,
        checkout.client_occurred_at desc
    ) as match_rank
  from public.subscription_conversion_attributions as attribution
  join public.paywall_events as checkout
    on checkout.user_id = attribution.user_id
   and checkout.event_name in ('purchase_started', 'purchase_succeeded')
   and checkout.product_identifier is not distinct from attribution.product_identifier
   and checkout.entry_point is not null
   and checkout.client_occurred_at between
     attribution.purchased_at - interval '24 hours'
     and attribution.purchased_at + interval '24 hours'
), resolved_matches as (
  select
    ranked.*,
    entry.id as entry_event_id,
    entry.client_occurred_at as entry_clicked_at,
    entry.entry_point,
    entry.entry_surface,
    entry.entry_component,
    entry.analysis_id,
    entry.result_section,
    entry.item_id,
    entry.entry_context
  from ranked_matches as ranked
  left join lateral (
    select candidate.*
    from public.paywall_events as candidate
    where candidate.funnel_session_id = ranked.funnel_session_id
      and candidate.user_id = (
        select owner.user_id
        from public.subscription_conversion_attributions as owner
        where owner.revenuecat_event_id = ranked.revenuecat_event_id
      )
      and candidate.event_name = 'entry_tap'
    order by candidate.client_occurred_at asc
    limit 1
  ) as entry on true
  where ranked.match_rank = 1
)
update public.subscription_conversion_attributions as attribution
set
  entry_event_id = resolved.entry_event_id,
  funnel_session_id = resolved.funnel_session_id,
  entry_clicked_at = coalesce(resolved.entry_clicked_at, resolved.checkout_at),
  seconds_to_purchase = greatest(
    extract(epoch from (
      resolved.purchased_at - coalesce(resolved.entry_clicked_at, resolved.checkout_at)
    )),
    0
  )::bigint,
  entry_point = coalesce(resolved.entry_point, resolved.checkout_entry_point),
  entry_surface = coalesce(resolved.entry_surface, resolved.checkout_entry_surface),
  entry_component = coalesce(resolved.entry_component, resolved.checkout_entry_component),
  analysis_id = coalesce(resolved.analysis_id, resolved.checkout_analysis_id),
  result_section = coalesce(resolved.result_section, resolved.checkout_result_section),
  item_id = coalesce(resolved.item_id, resolved.checkout_item_id),
  entry_context = coalesce(resolved.entry_context, resolved.checkout_entry_context, '{}'::jsonb)
from resolved_matches as resolved
where attribution.revenuecat_event_id = resolved.revenuecat_event_id
  and attribution.entry_point is null;

comment on function public.reconcile_paywall_conversion_from_client_event() is
  'Reconciles a RevenueCat conversion with its exact durable client checkout funnel when client telemetry arrives after the webhook.';
