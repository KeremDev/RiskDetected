-- 1) Son paywall giriş tıklamaları: kim, ne zaman, hangi ekrandan/karttan?
select
  users.email,
  events.user_id,
  events.client_occurred_at as clicked_at,
  events.entry_surface,
  events.entry_point,
  events.entry_component,
  events.entry_target_tier,
  events.analysis_id,
  events.result_section,
  events.item_id,
  events.funnel_session_id
from public.paywall_events as events
left join auth.users as users on users.id = events.user_id
where events.event_name = 'entry_tap'
order by events.client_occurred_at desc
limit 500;

-- 2) RevenueCat tarafından doğrulanmış satın alma/plan yükseltme dönüşümleri.
select
  users.email,
  conversions.user_id,
  conversions.entry_clicked_at,
  conversions.purchased_at,
  conversions.seconds_to_purchase,
  conversions.entry_surface,
  conversions.entry_point,
  conversions.entry_component,
  conversions.purchased_tier,
  conversions.product_identifier,
  conversions.analysis_id,
  conversions.result_section,
  conversions.item_id,
  conversions.revenuecat_event_id
from public.subscription_conversion_attributions as conversions
left join auth.users as users on users.id = conversions.user_id
order by conversions.purchased_at desc
limit 500;

-- 3) Kaynak bazında tıklama → satın alma özeti.
with clicks as (
  select
    entry_point,
    count(*) as click_count,
    count(distinct user_id) as unique_users
  from public.paywall_events
  where event_name = 'entry_tap'
  group by entry_point
), conversions as (
  select
    entry_point,
    count(*) as purchase_count,
    count(distinct user_id) as purchasing_users
  from public.subscription_conversion_attributions
  group by entry_point
)
select
  clicks.entry_point,
  clicks.click_count,
  clicks.unique_users,
  coalesce(conversions.purchase_count, 0) as purchase_count,
  coalesce(conversions.purchasing_users, 0) as purchasing_users,
  round(
    100.0 * coalesce(conversions.purchase_count, 0)
    / nullif(clicks.click_count, 0),
    2
  ) as click_to_purchase_percent
from clicks
left join conversions using (entry_point)
order by purchase_count desc, click_count desc;
