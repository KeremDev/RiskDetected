begin;

select plan(12);

select has_column('public', 'paywall_events', 'client_occurred_at', 'paywall click keeps the client timestamp');
select has_column('public', 'paywall_events', 'app_session_id', 'paywall click keeps the app session');
select has_column('public', 'paywall_events', 'entry_point', 'paywall click keeps the entry point');
select has_column('public', 'paywall_events', 'entry_surface', 'paywall click keeps the entry surface');
select has_column('public', 'paywall_events', 'entry_component', 'paywall click keeps the component');
select has_column('public', 'paywall_events', 'entry_target_tier', 'paywall click keeps the target tier');
select has_column('public', 'paywall_events', 'analysis_id', 'paywall click can be attributed to an analysis');
select has_column('public', 'paywall_events', 'result_section', 'paywall click can be attributed to a result section');
select has_column('public', 'paywall_events', 'item_id', 'paywall click can be attributed to a result item');
select has_column('public', 'paywall_events', 'entry_context', 'paywall click keeps structured context');
select has_view('public', 'paywall_conversion_attribution', 'conversion attribution view exists');

select ok(
  (select reloptions @> array['security_invoker=true']
   from pg_class
   where oid = 'public.paywall_conversion_attribution'::regclass),
  'conversion attribution view uses invoker security'
);

select * from finish();
rollback;
