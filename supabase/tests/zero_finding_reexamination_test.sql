begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

select ok(
  exists (
    select 1
    from public.app_feature_flags
    where key = 'ai_zero_finding_reexamination_v1'
  ),
  'zero-finding re-examination flag exists'
);

select is(
  (
    select value->>'policy_version'
    from public.app_feature_flags
    where key = 'ai_zero_finding_reexamination_v1'
  ),
  '1',
  'policy version is one; analyze falls back to off on any mismatch'
);

-- Unlike ai_expert_depth_v1 this never enters the hazard-detection call. It
-- only widens what a coverage-quality repair may attach a finding to, on
-- photos the first pass left empty, and every finding it recovers carries
-- needs_field_verification with confidence capped at 0.69.
select is(
  (
    select (value->>'kill_switch')::boolean
    from public.app_feature_flags
    where key = 'ai_zero_finding_reexamination_v1'
  ),
  false,
  'kill switch is open; the flag is read live so closing it stops the next repair'
);

select * from finish();

rollback;
