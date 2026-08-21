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

-- Halted on 2026-08-21: analyze v173 put the equipment depth scan in the same
-- model call as hazard detection and hazard detection collapsed. Re-enabling is
-- a deliberate act with its own migration; until then the chain must end `off`.
select is(
  (
    select value->>'rollout_mode'
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  'off',
  'expert depth stays disabled until the depth scan stops competing with hazard detection'
);

select is(
  (
    select (value->>'kill_switch')::boolean
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  true,
  'expert depth kill switch is latched'
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
