begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(8);

select extensions.has_function(
  'public',
  'check_report_quota_eligibility',
  array['uuid', 'text', 'text'],
  'report quota preflight exists'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.check_report_quota_eligibility(uuid,text,text)',
    'execute'
  ),
  'anon cannot call report quota preflight'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.check_report_quota_eligibility(uuid,text,text)',
    'execute'
  ),
  'authenticated cannot query another user report quota'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.check_report_quota_eligibility(uuid,text,text)',
    'execute'
  ),
  'service role can call report quota preflight'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000001901'::uuid,
  'report-preflight@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

select extensions.is(
  (public.check_report_quota_eligibility(
    '00000000-0000-4000-8000-000000001901'::uuid,
    'standard',
    'pdf'
  )->>'allowed')::boolean,
  true,
  'new free user can create a standard report'
);

insert into public.usage_events (user_id, feature, event_type, metadata)
values (
  '00000000-0000-4000-8000-000000001901'::uuid,
  'report_standard',
  'completed',
  '{"source":"pgtap"}'::jsonb
);

select extensions.is(
  (public.check_report_quota_eligibility(
    '00000000-0000-4000-8000-000000001901'::uuid,
    'standard',
    'pdf'
  )->>'allowed')::boolean,
  true,
  'a used standard report never blocks the next one on free'
);

select extensions.is(
  (public.check_report_quota_eligibility(
    '00000000-0000-4000-8000-000000001901'::uuid,
    'riskAnalysis',
    'pdf'
  )->>'allowed')::boolean,
  true,
  'standard report use does not consume the free risk-analysis trial'
);

insert into public.usage_events (user_id, feature, event_type, metadata)
values (
  '00000000-0000-4000-8000-000000001901'::uuid,
  'report_risk_analysis_trial',
  'completed',
  '{"source":"pgtap"}'::jsonb
);

select extensions.is(
  public.check_report_quota_eligibility(
    '00000000-0000-4000-8000-000000001901'::uuid,
    'riskAnalysis',
    'pdf'
  )->>'error_code',
  'free_risk_analysis_trial_exhausted',
  'used free risk-analysis trial is rejected before report download'
);

select * from extensions.finish();
rollback;
