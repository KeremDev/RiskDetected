-- claim-routing-v20: an absence claim contradicted twice is wrong, not unresolved.
--
-- Analysis 9b9ff9c2, same photograph as four earlier runs. The primary pass
-- produced four candidates saying the platform top rail was missing --
-- criticality fatal -- and in the SAME output published a positive control
-- reading "Platform kenarlarında korkuluk sistemi (üst korkuluk, ara korkuluk,
-- etek tahtası)". The second pass then affirmed the top rail on all three
-- platform sections independently.
--
-- Both gates fired and both did the cautious thing: field check. So the report
-- opened with two fatal-criticality items over a rail the engine had twice
-- recorded as present, and carried one scored finding out of ten items.
--
-- One dissent is a disagreement and stays a field check. Two independent
-- affirmations against a single absence claim are not a disagreement -- the
-- claim is wrong, and it is dropped with a recorded reason rather than printed
-- at fatal criticality.
--
-- Prompt bundle is untouched: v4-vision-core-v9 and its hash carry over.
do $$
declare
  v_sha constant text :=
    '41008e19f4b4e95f79fb2f6e8630c118ad71bed4f350420a42715a60cb1da656';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v20',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v20',
             'barrier_absence_double_contradiction_drop', true
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v9'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v20'
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
