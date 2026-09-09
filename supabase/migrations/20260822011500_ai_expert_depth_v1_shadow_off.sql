-- Turns ai_expert_depth_v1 off again: shadow measurement degraded the analysis.
--
-- 20260821204336 moved the flag to `shadow` to measure the depth structures
-- without running any of their behaviour. The measurement was built as a real
-- shadow: `expertDepthObserved = expertDepthEnabled || expertDepthShadow`, so
-- the response schema and the prompt still ask the model for
-- equipment_depth_scan and process_safety_checks. Nothing downstream consumes
-- them, but the model call itself changed, and that is where the damage was.
--
-- Three analyses over the same three photos, byte-identical inputs
-- (photo_input_audit decoded_byte_count matches across all three):
--
--   22:48 rollout_mode=on      first-pass findings 0 / 1 / 0
--   23:35 rollout_mode=off     first-pass findings 1 / 2 / 2
--   00:01 rollout_mode=shadow  first-pass findings 1 / 1 / 0
--
-- On the shadow run the model emitted twelve process-safety checks for photo 1
-- and one finding. Photo 3 went from coverage_status `actionable` with two
-- findings to `no_actionable_hazard` with none. This is the same competition
-- that caused the v173 regression: asking for the depth structures in the
-- hazard-detection call costs hazards, whether or not anything reads the
-- answer.
--
-- Shadow measurement of this feature cannot be free in the same call. Any
-- future attempt needs a separate model call, and that is a cost decision, not
-- a flag flip.

do $ai_expert_depth_v1_shadow_off$
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
        'halted_reason', 'shadow_measurement_degraded_hazard_detection'
      ),
      updated_at = now()
  where key = 'ai_expert_depth_v1';

  select value into v_value
  from public.app_feature_flags
  where key = 'ai_expert_depth_v1';

  if v_value ->> 'rollout_mode' is distinct from 'off'
     or coalesce((v_value ->> 'kill_switch')::boolean, false) is not true then
    raise exception 'ai_expert_depth_v1 shadow-off switch did not apply';
  end if;
end;
$ai_expert_depth_v1_shadow_off$;
