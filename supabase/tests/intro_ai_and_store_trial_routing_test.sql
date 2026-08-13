begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(11);

select extensions.has_column(
  'public', 'user_subscriptions', 'store',
  'Subscription truth records the RevenueCat store'
);
select extensions.has_column(
  'public', 'user_subscriptions', 'base_plan_id',
  'Google Play base plan identity is persisted separately'
);
select extensions.has_column(
  'public', 'user_subscriptions', 'offer_id',
  'RevenueCat offer identity is persisted when available'
);
select extensions.has_column(
  'public', 'user_subscriptions', 'store_transaction_id',
  'Store transaction identity is retained for subscription verification'
);
select extensions.has_column(
  'public', 'user_subscriptions', 'period_type',
  'Verified RevenueCat period type is persisted'
);

select extensions.ok(
  position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef('public.reserve_analysis_quota(uuid,uuid,text)'::regprocedure)
  ) > 0,
  'First-analysis eligibility shares the atomic quota reservation lock'
);
select extensions.ok(
  position(
    'first_paid_ai_eligible'
    in pg_get_functiondef('public.reserve_analysis_quota(uuid,uuid,text)'::regprocedure)
  ) > 0,
  'Quota reservation returns the one-time paid-AI eligibility decision'
);
select extensions.ok(
  position(
    'is distinct from p_analysis_id'
    in pg_get_functiondef('public.reserve_analysis_quota(uuid,uuid,text)'::regprocedure)
  ) > 0,
  'Worker retries keep the same first-analysis decision idempotently'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000001801'::uuid,
  'intro-ai-routing@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

select extensions.is(
  (
    public.reserve_analysis_quota(
      '00000000-0000-4000-8000-000000001801'::uuid,
      '00000000-0000-4000-8000-000000001811'::uuid,
      'standard'
    )->>'first_paid_ai_eligible'
  )::boolean,
  true,
  'A new user receives paid-AI eligibility on the first reservation'
);

select extensions.is(
  (
    public.reserve_analysis_quota(
      '00000000-0000-4000-8000-000000001801'::uuid,
      '00000000-0000-4000-8000-000000001811'::uuid,
      'standard'
    )->>'first_paid_ai_eligible'
  )::boolean,
  true,
  'A worker retry for the same analysis preserves first eligibility'
);

update public.usage_events
set created_at = now() - interval '2 days'
where user_id = '00000000-0000-4000-8000-000000001801'::uuid;

select extensions.is(
  (
    public.reserve_analysis_quota(
      '00000000-0000-4000-8000-000000001801'::uuid,
      '00000000-0000-4000-8000-000000001812'::uuid,
      'standard'
    )->>'first_paid_ai_eligible'
  )::boolean,
  false,
  'A later analysis never receives the one-time paid-AI introduction'
);

select * from extensions.finish();
rollback;
