-- Lossless, idempotent paywall analytics delivery for iOS and Android.
--
-- This migration intentionally repeats the attribution-v2 column contract with IF NOT EXISTS.
-- Production already has it, while the isolated Android staging project can lag the production
-- ledger. Applying this one migration is therefore safe on both environments and prevents a
-- staging build from silently rejecting every attributed event.

alter table public.paywall_events
  add column if not exists client_occurred_at timestamptz not null default now(),
  add column if not exists app_session_id uuid,
  add column if not exists entry_point text,
  add column if not exists entry_surface text,
  add column if not exists entry_component text,
  add column if not exists entry_target_tier public.subscription_tier,
  add column if not exists analysis_id uuid,
  add column if not exists result_section text,
  add column if not exists item_id text,
  add column if not exists entry_context jsonb not null default '{}'::jsonb,
  add column if not exists client_event_id uuid not null default gen_random_uuid();

alter table public.paywall_events
  drop constraint if exists paywall_events_event_name_check,
  drop constraint if exists paywall_events_entry_context_object_check,
  drop constraint if exists paywall_events_result_section_check;

alter table public.paywall_events
  add constraint paywall_events_event_name_check
    check (
      event_name in (
        'entry_tap',
        'view',
        'close',
        'cta_tap',
        'plan_select',
        'billing_select',
        'purchase_started',
        'purchase_succeeded',
        'purchase_failed',
        'purchase_cancelled',
        'payment_pending',
        'restore_tap',
        'personal_plan_view',
        'personal_plan_continue',
        'trial_invite_view',
        'trial_invite_cta_tap'
      )
    ),
  add constraint paywall_events_entry_context_object_check
    check (jsonb_typeof(entry_context) = 'object'),
  add constraint paywall_events_result_section_check
    check (
      result_section is null
      or result_section in (
        'risk_analysis',
        'expert_recommendations',
        'training_recommendations',
        'approved_notebook'
      )
    );

create unique index if not exists paywall_events_client_event_id_uidx
  on public.paywall_events (client_event_id);

create index if not exists paywall_events_entry_point_time_idx
  on public.paywall_events (entry_point, client_occurred_at desc)
  where entry_point is not null;

create index if not exists paywall_events_user_event_time_idx
  on public.paywall_events (user_id, event_name, client_occurred_at desc);

create index if not exists paywall_events_app_session_time_idx
  on public.paywall_events (app_session_id, client_occurred_at)
  where app_session_id is not null;

drop view if exists public.paywall_conversion_attribution;

create view public.paywall_conversion_attribution
with (security_invoker = true)
as
select
  purchase.id as purchase_event_id,
  purchase.user_id,
  purchase.funnel_session_id,
  purchase.app_session_id,
  coalesce(entry.client_occurred_at, purchase.client_occurred_at) as entry_clicked_at,
  purchase.client_occurred_at as purchased_at,
  greatest(
    extract(epoch from (
      purchase.client_occurred_at
      - coalesce(entry.client_occurred_at, purchase.client_occurred_at)
    )),
    0
  )::bigint as seconds_to_purchase,
  purchase.entry_point,
  purchase.entry_surface,
  purchase.entry_component,
  purchase.entry_target_tier,
  purchase.analysis_id,
  purchase.result_section,
  purchase.item_id,
  purchase.selected_tier as purchased_tier,
  purchase.billing,
  purchase.product_identifier,
  purchase.variant_id,
  purchase.source,
  purchase.entry_context,
  purchase.metadata,
  purchase.created_at as recorded_at
from public.paywall_events as purchase
left join lateral (
  select event.client_occurred_at
  from public.paywall_events as event
  where event.user_id = purchase.user_id
    and event.funnel_session_id = purchase.funnel_session_id
    and event.event_name = 'entry_tap'
  order by event.client_occurred_at asc
  limit 1
) as entry on true
where purchase.event_name = 'purchase_succeeded';

comment on column public.paywall_events.client_event_id is
  'Client-generated idempotency key retained across offline/retry delivery.';
comment on view public.paywall_conversion_attribution is
  'Successful purchases attributed to the exact in-app paywall entry point and funnel session.';

revoke all on public.paywall_conversion_attribution from anon, public;
grant select on public.paywall_conversion_attribution to authenticated;
