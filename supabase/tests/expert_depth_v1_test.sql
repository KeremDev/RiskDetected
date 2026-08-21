begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select ok(
  exists (
    select 1
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  'expert depth feature flag exists'
);

select is(
  (
    select value->>'policy_version'
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  '1',
  'expert depth policy version is one'
);

-- Halted twice on 2026-08-21: first after the v173 regression with the flag
-- `on`, then again after the `shadow` measurement produced the same collapse.
-- Shadow was not free -- it still asks the model for equipment_depth_scan and
-- process_safety_checks in the hazard-detection call, and hazards lose. Any
-- future measurement needs its own model call, so both `on` and `shadow` are
-- deliberate acts that need their own migration.
select is(
  (
    select value->>'rollout_mode'
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  'off',
  'expert depth is off; shadow degraded hazard detection too'
);

select is(
  (
    select (value->>'kill_switch')::boolean
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  true,
  'kill switch is latched so a replay cannot bring the feature back'
);

select ok(
  position(
    'display_group'
    in pg_get_functiondef(
      'public.finalize_analysis_result_v2(uuid,uuid,bigint,integer,uuid,jsonb,jsonb,jsonb)'::regprocedure
    )
  ) > 0,
  'pipeline finalization persists the existing display group field'
);

select * from finish();

rollback;
