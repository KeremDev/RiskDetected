begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(2);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000001902'::uuid,
  'result-hub-standard-report@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

insert into public.usage_events (user_id, feature, event_type, metadata)
values (
  '00000000-0000-4000-8000-000000001902'::uuid,
  'report_risk_analysis_trial',
  'completed',
  '{"source":"pgtap"}'::jsonb
);

select extensions.is(
  (public.check_report_quota_eligibility_v2(
    '00000000-0000-4000-8000-000000001902'::uuid,
    'standard',
    'pdf',
    'risk_analysis'
  )->>'allowed')::boolean,
  true,
  'used risk-table gift does not block a standard PDF from the risk section'
);

select extensions.is(
  public.check_report_quota_eligibility_v2(
    '00000000-0000-4000-8000-000000001902'::uuid,
    'riskAnalysis',
    'pdf',
    'risk_analysis'
  )->>'error_code',
  'free_risk_analysis_trial_exhausted',
  'used risk-table gift still blocks another risk-analysis table'
);

select * from extensions.finish();
rollback;
