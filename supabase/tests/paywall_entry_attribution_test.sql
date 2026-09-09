begin;

select plan(23);

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
select has_column('public', 'paywall_events', 'client_event_id', 'paywall delivery keeps its idempotency key');
select has_view('public', 'paywall_conversion_attribution', 'conversion attribution view exists');
select has_table('public', 'subscription_conversion_attributions', 'verified conversion attribution table exists');

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'paywall_events'
      and indexname = 'paywall_events_client_event_id_uidx'
      and indexdef ilike 'create unique index%'
  ),
  'client event id is unique for retry-safe inserts'
);

select ok(
  (select pg_get_constraintdef(oid) like '%entry_tap%purchase_cancelled%payment_pending%'
   from pg_constraint
   where conrelid = 'public.paywall_events'::regclass
     and conname = 'paywall_events_event_name_check'),
  'event constraint accepts entry, cancellation and pending outcomes'
);

select ok(
  (select pg_get_constraintdef(oid) like '%training_recommendations%'
   from pg_constraint
   where conrelid = 'public.paywall_events'::regclass
     and conname = 'paywall_events_result_section_check'),
  'training promotion is a first-class attributed result section'
);

select ok(
  (select reloptions @> array['security_invoker=true']
   from pg_class
   where oid = 'public.paywall_conversion_attribution'::regclass),
  'conversion attribution view uses invoker security'
);

select ok(
  to_regprocedure('public.reconcile_paywall_conversion_from_client_event()') is not null,
  'late client events have a conversion reconciliation function'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgname = 'reconcile_paywall_conversion_from_client_event'
      and tgrelid = 'public.paywall_events'::regclass
      and not tgisinternal
  ),
  'paywall event delivery invokes conversion reconciliation'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.reconcile_paywall_conversion_from_client_event()',
    'execute'
  ),
  'anonymous clients cannot call the security-definer reconciliation function'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.reconcile_paywall_conversion_from_client_event()',
    'execute'
  ),
  'authenticated clients cannot call the security-definer reconciliation function'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'subscription_conversion_attributions'
      and indexname = 'subscription_conversion_entry_event_idx'
  ),
  'conversion entry-event foreign key has a covering index'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'subscription_conversion_attributions'
      and policyname = 'subscription_conversion_service_only'
  ),
  'conversion attribution table explicitly denies authenticated client access'
);

select * from finish();
rollback;
