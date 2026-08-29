begin;

select plan(8);

select has_table('public', 'subscription_conversion_attributions', 'subscription conversion attribution table exists');
select has_column('public', 'subscription_conversion_attributions', 'revenuecat_event_id', 'conversion keeps the RevenueCat event');
select has_column('public', 'subscription_conversion_attributions', 'user_id', 'conversion keeps the user');
select has_column('public', 'subscription_conversion_attributions', 'entry_point', 'conversion keeps the paywall entry point');
select has_column('public', 'subscription_conversion_attributions', 'entry_clicked_at', 'conversion keeps the originating click time');
select has_column('public', 'subscription_conversion_attributions', 'purchased_at', 'conversion keeps the purchase time');
select has_column('public', 'subscription_conversion_attributions', 'seconds_to_purchase', 'conversion exposes time to purchase');
select ok(
  (select relrowsecurity
   from pg_class
   where oid = 'public.subscription_conversion_attributions'::regclass),
  'subscription conversion attribution table has RLS enabled'
);

select * from finish();
rollback;
