-- Turns ai_expert_depth_v1 off and latches its kill switch.
--
-- 20260821191758 switched the flag to `on` for the general rollout. On the
-- first production analysis after analyze v173 (2026-08-21 22:46 local, the
-- analysis two minutes later) hazard detection collapsed: two of three photos
-- came back with actionable_layer_count = 0 and zero findings, and the same
-- three photos had produced Fine-Kinney scores of 120, 240 and 360 on the two
-- runs immediately before the deploy. The single model call now had to emit
-- scene_elements, twelve inspection layers, equipment_depth_scan and
-- process_safety_checks alongside findings, and the findings lost.
--
-- The flag was switched off by hand in production first, to stop the bleeding.
-- This migration records that state so a replay cannot silently re-enable the
-- feature: without it, 20260821191758 is the last word in the chain and every
-- fresh environment comes up with the regression active.
--
-- Re-enabling is a deliberate act that needs its own migration, after the
-- depth scan stops competing with hazard detection in the same call and
-- verification items stop being written into `findings`.

do $ai_expert_depth_v1_kill_switch$
declare
  v_value jsonb;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'ai_expert_depth_v1'
  for update;

  if v_value is null then
    raise exception 'ai_expert_depth_v1 flag is missing';
  end if;

  update public.app_feature_flags
  set value = v_value || jsonb_build_object(
        'rollout_mode', 'off',
        'kill_switch', true,
        'live_rollout_stage', 'halted',
        'halted_at', now(),
        'halted_reason', 'hazard_detection_regression_v173'
      ),
      updated_at = now()
  where key = 'ai_expert_depth_v1';

  select value into v_value
  from public.app_feature_flags
  where key = 'ai_expert_depth_v1';

  if v_value ->> 'rollout_mode' is distinct from 'off'
     or coalesce((v_value ->> 'kill_switch')::boolean, false) is not true then
    raise exception 'ai_expert_depth_v1 kill switch did not apply';
  end if;
end;
$ai_expert_depth_v1_kill_switch$;
