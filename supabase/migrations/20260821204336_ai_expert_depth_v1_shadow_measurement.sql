-- Moves ai_expert_depth_v1 from halted to shadow for measurement.
--
-- 20260821200612 latched the kill switch after the v173 hazard-detection
-- regression. Since then the depth structures were moved behind `findings` in
-- the response schema, verification items were taken out of `findings`
-- entirely, and shadow mode was fixed: it used to record a single
-- `evaluable: false` because the schema that asks for the equipment scan was
-- gated on `enabled`, so there was nothing to observe.
--
-- Shadow asks the model for the depth structures and records what they
-- contain. Nothing behavioural runs: no verification item is injected, the
-- process-safety guard stays off, findings and risk totals are untouched.
--
-- What this is measuring, before deciding whether to enable the feature:
--   * how often equipment is actually detected (periodic_verification_candidate_count)
--   * what the depth structures cost in output tokens now that they come last
--   * whether hazard detection holds up with the structures present
--
-- Going to `on` needs its own migration and evidence from these fields.

do $ai_expert_depth_v1_shadow$
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
        'rollout_mode', 'shadow',
        'kill_switch', false,
        'live_rollout_stage', 'shadow_measurement',
        'shadow_started_at', now()
      ),
      updated_at = now()
  where key = 'ai_expert_depth_v1';

  select value into v_value
  from public.app_feature_flags
  where key = 'ai_expert_depth_v1';

  if v_value ->> 'rollout_mode' is distinct from 'shadow'
     or coalesce((v_value ->> 'kill_switch')::boolean, true) is not false then
    raise exception 'ai_expert_depth_v1 shadow switch did not apply';
  end if;
end;
$ai_expert_depth_v1_shadow$;
