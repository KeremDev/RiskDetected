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

-- Halted on 2026-08-21 after the v173 regression, then moved to shadow once the
-- depth structures were reordered behind `findings` and shadow was fixed to
-- actually measure. `shadow` asks the model for the structures and records
-- them; nothing behavioural runs. Going to `on` needs its own migration.
select is(
  (
    select value->>'rollout_mode'
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  'shadow',
  'expert depth is in shadow measurement, not enabled'
);

select is(
  (
    select (value->>'kill_switch')::boolean
    from public.app_feature_flags
    where key = 'ai_expert_depth_v1'
  ),
  false,
  'shadow requires the kill switch open; behaviour stays off through rollout_mode'
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
