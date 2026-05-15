-- Keep demo accounts aligned with backend quota checks.
--
-- The app can show demo tiers from cached profile/subscription state, but
-- database-side quota enforcement intentionally trusts `user_subscriptions`
-- instead of `profiles.tier`. These rows make the known demo accounts behave
-- like real paid users in report/archive flows without relaxing production RLS
-- or using editable profile data for authorization.

with demo_accounts as (
  select
    u.id as user_id,
    lower(u.email) as email,
    case lower(u.email)
      when 'demo@riskdetected.app' then 'pro'
      when 'plus@riskdetected.app' then 'plus'
      else 'free'
    end as tier
  from auth.users u
  where lower(u.email) in (
    'demo@riskdetected.app',
    'plus@riskdetected.app',
    'free@riskdetected.app'
  )
),
paid_demo_accounts as (
  select *
  from demo_accounts
  where tier in ('plus', 'pro')
)
insert into public.user_subscriptions (
  user_id,
  tier,
  source,
  status,
  revenuecat_app_user_id,
  product_id,
  entitlement_id,
  entitlement_ids,
  environment,
  current_period_ends_at,
  last_event_id,
  updated_at
)
select
  user_id,
  tier,
  'demo',
  'active',
  'demo:' || user_id::text,
  'riskdetected_' || tier || '_demo',
  'riskdetected_' || tier,
  array['riskdetected_' || tier],
  'demo',
  null,
  'seed_demo_subscriptions',
  now()
from paid_demo_accounts
on conflict (user_id) do update
set tier = excluded.tier,
    source = excluded.source,
    status = excluded.status,
    revenuecat_app_user_id = excluded.revenuecat_app_user_id,
    product_id = excluded.product_id,
    entitlement_id = excluded.entitlement_id,
    entitlement_ids = excluded.entitlement_ids,
    environment = excluded.environment,
    current_period_ends_at = excluded.current_period_ends_at,
    last_event_id = excluded.last_event_id,
    updated_at = now();

update public.profiles p
set tier = d.tier::public.subscription_tier
from (
  select
    u.id as user_id,
    case lower(u.email)
      when 'demo@riskdetected.app' then 'pro'
      when 'plus@riskdetected.app' then 'plus'
      else 'free'
    end as tier
  from auth.users u
  where lower(u.email) in (
    'demo@riskdetected.app',
    'plus@riskdetected.app',
    'free@riskdetected.app'
  )
) d
where p.id = d.user_id
  and p.tier::text is distinct from d.tier;
