-- Lets a coverage-quality repair reopen `checked_no_hazard` layers, but only
-- on photos the first pass left with no finding at all.
--
-- Measured on 2026-08-22 across six runs of one identical three-photo set
-- (byte-identical inputs, verified through photo_input_audit): the third photo
-- produced two findings on two runs and none on a third. On the empty run the
-- layers that had carried those findings -- excavation_confined_special_work
-- and machinery_equipment -- came back `checked_no_hazard`, and the repair pass
-- is forbidden to attach a finding to anything but `actionable` or
-- `uncertain`. Its only open layer was `ppe`, and it correctly reported
-- insufficient visual evidence. The miss was permanent by construction.
--
-- Raising the repair thinking budget from 1024 to 3072 made the model think
-- 2.4x longer (969 -> 2305 thought tokens) and change nothing, which is what
-- pointed at the layer statuses rather than the budget.
--
-- What this does not do:
--   * it does not touch the initial analysis call, so it cannot repeat the
--     expert-depth regression, where asking the hazard-detection call for more
--     structure cost hazards
--   * it does not reopen `not_visible`; that status records that the layer
--     could not be seen, and a finding built on it would be invention
--   * it does not apply to a photo that already produced a finding, whose
--     audit is working
--
-- Every finding recovered this way is capped at 0.69 confidence with
-- needs_field_verification set, so it reaches the user as something to confirm
-- on site. `zero_finding_reexamination_recovered_count` in the analysis audit
-- counts them.
--
-- The flag is read live on each repair rather than pinned to the queued job,
-- so turning it off stops the next repair instead of draining the queue:
--   update public.app_feature_flags
--   set value = value || '{"rollout_mode":"off","kill_switch":true}'::jsonb
--   where key = 'ai_zero_finding_reexamination_v1';

insert into public.app_feature_flags (key, value)
values (
  'ai_zero_finding_reexamination_v1',
  jsonb_build_object(
    'policy_version', 1,
    'rollout_mode', 'on',
    'kill_switch', false,
    'enabled_user_hashes', '[]'::jsonb
  )
)
on conflict (key) do nothing;

do $ai_zero_finding_reexamination_v1$
declare
  v_value jsonb;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'ai_zero_finding_reexamination_v1';

  if v_value is null then
    raise exception 'ai_zero_finding_reexamination_v1 flag is missing';
  end if;

  if coalesce((v_value ->> 'policy_version')::int, 0) <> 1 then
    raise exception 'ai_zero_finding_reexamination_v1 policy version mismatch';
  end if;
end;
$ai_zero_finding_reexamination_v1$;
