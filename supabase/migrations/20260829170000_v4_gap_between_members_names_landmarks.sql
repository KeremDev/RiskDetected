-- claim-routing-v24: a gap located BETWEEN two members does not accuse them.
--
-- Analysis 12d20568 wrote "üst korkuluk ile etek tahtası arasında boşluk var;
-- ara korkuluk bulunmuyor". Only the mid rail is missing there; the top rail and
-- the toeboard are the landmarks that bound the gap and are plainly standing.
-- The clause parser read all three as claimed absent, which put
-- mid_rail+toeboard+top_rail on a mid-rail claim's dedup identity and -- the
-- part that matters -- opened a path where a second pass affirming the two
-- landmarks could hard-drop the claim about the member between them.
--
-- The outcome of that run was still correct: the sandwich gate demoted the claim
-- on mid_rail and the drop needs a second-pass sighting it did not have. The
-- defect was one disagreement away from deleting a true finding.
--
-- Prompt bundle untouched: v4-vision-core-v10 and its hash carry over. The
-- single-photo thinking budget stays at 6144 and is asserted here.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v24',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v24',
             'barrier_gap_landmark_clause_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v24'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 6144;
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
