-- v4-gemini3-core-v2: the binding rule loses its escape hatch.
--
-- core-v1 worked on what it was written for. In analysis e4bee3d9 every
-- finding_present row carried a candidate_key, where the run before it had four
-- that did not; the schema rejection went away with them, the wasted provider
-- call went away with that, and the run fell from 37.7s and $0.0348 to 25.8s
-- and $0.0242 -- a third off both, on identical output.
--
-- But the model resolved the tension downward. Told not to write
-- finding_present without a candidate, it marked falls_falling_objects, energy
-- and machinery not_assessable_due_to_image instead of producing the
-- candidates. The letter of the rule, not its intent, and the text had left
-- that door open: it said what not to do and never said what to do instead.
--
-- So the outcomes are now ordered explicitly. Something visible with a defect
-- on it is a candidate and finding_present. Something visible without one is a
-- positive control or no_actionable_issue_visible.
-- not_assessable_due_to_image is reserved for the photograph physically not
-- showing the module -- frame excludes the area, light insufficient, wholly
-- occluded -- and is forbidden outright when a visible entity of that module is
-- in the scene. unresolved_requires_verification stays available for heavy
-- consequences behind occluded geometry, but only after the candidate is
-- recorded; it does not stand in for the record.
--
-- The other direction is held in the same breath, because an instruction that
-- reads as "always find something" buys recall at the price of the fabricated
-- hook latch: do not raise a candidate for something you did not see, and do
-- not bury what you did see in a coverage note. Both halves are under test.
--
-- Hashed at 4a1b962e..., separately as always, so V4_PROMPT_VERSION stays
-- v4-vision-core-v10 at 823b6ad1... and gemini-2.5-flash is untouched.
do $$
begin
  update private.analysis_v4_configs
  set config = config || jsonb_build_object(
        'gemini3_prompt_version', 'v4-gemini3-core-v2',
        'gemini3_prompt_sha256',
          '4a1b962ea8b861dfc0c70c47d26793d3a7623f4b970a91bf605a7a80882093a6'
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v33'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v2'
    and config->>'gemini3_prompt_sha256' =
      '4a1b962ea8b861dfc0c70c47d26793d3a7623f4b970a91bf605a7a80882093a6';
  if not found then
    raise exception 'gemini3 core prompt v2 did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
