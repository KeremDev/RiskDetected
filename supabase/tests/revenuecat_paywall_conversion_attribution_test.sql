begin;

select plan(8);

select has_table('public', 'subscription_conversion_attributions');
select has_column('public', 'subscription_conversion_attributions', 'revenuecat_event_id');
select has_column('public', 'subscription_conversion_attributions', 'user_id');
select has_column('public', 'subscription_conversion_attributions', 'entry_point');
select has_column('public', 'subscription_conversion_attributions', 'entry_clicked_at');
select has_column('public', 'subscription_conversion_attributions', 'purchased_at');
select has_column('public', 'subscription_conversion_attributions', 'seconds_to_purchase');
select row_security_active('public.subscription_conversion_attributions');

select * from finish();
rollback;
