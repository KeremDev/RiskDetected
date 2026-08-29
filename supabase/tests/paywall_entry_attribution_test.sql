begin;

select plan(12);

select has_column('public', 'paywall_events', 'client_occurred_at');
select has_column('public', 'paywall_events', 'app_session_id');
select has_column('public', 'paywall_events', 'entry_point');
select has_column('public', 'paywall_events', 'entry_surface');
select has_column('public', 'paywall_events', 'entry_component');
select has_column('public', 'paywall_events', 'entry_target_tier');
select has_column('public', 'paywall_events', 'analysis_id');
select has_column('public', 'paywall_events', 'result_section');
select has_column('public', 'paywall_events', 'item_id');
select has_column('public', 'paywall_events', 'entry_context');
select has_view('public', 'paywall_conversion_attribution');

select ok(
  (select reloptions @> array['security_invoker=true']
   from pg_class
   where oid = 'public.paywall_conversion_attribution'::regclass),
  'conversion attribution view uses invoker security'
);

select * from finish();
rollback;
