-- claim-routing-v28: an absence you could not have seen is a field check.
--
-- Analysis 031d5068, a workshop with two overhead cranes photographed from the
-- far end of the bay. Two of its five items should not have been scored.
--
-- The first was fatal, FK 720, confidence 0.9 on every axis: "Vinç kancasında
-- emniyet mandalı eksikliği", supported by three cues of the form "güvenlik
-- mandalı görünmüyor". Its evidence region was 0.03 by 0.05 of the frame --
-- roughly thirty by seventy pixels, holding a hook about twelve pixels across.
-- A hook latch is a thin tongue across the throat, so at that scale it is one
-- pixel and JPEG noise. The latch was not missing in that photograph; it was
-- not depicted. The frame also holds two hooks, while the cues enumerate three.
--
-- Nothing in the wording gives that away, so the gate goes after the geometry,
-- which the model reported honestly even where its confidence did not. It fires
-- only on absence claims about a component: a small region is good evidence for
-- a puddle or a cable, where the region IS the thing, and poor evidence for a
-- part missing FROM the thing, which is smaller still. The floor of 0.004 sits
-- an order of magnitude clear of every genuine claim in the same run -- the
-- clutter region was 0.05 and the electrical one 0.02.
--
-- The second was serious, FK 126: "Sol taraftaki makinelerin koruyucularının
-- durumu uzaktan net olarak görülemiyor", recommending that the machine be
-- stopped and its moving parts enclosed -- a remedy for a deficiency the item's
-- own title says was never established. That candidate carried
-- visually_resolvable false, occlusion partial, a mechanism confidence of 0.5
-- and one affirmative cue reading "Sol tarafta çeşitli makineler mevcut", which
-- affirms that machines exist and nothing about their guards. Every signal
-- needed to stop it was already on the record; nothing read it. A scored
-- observed finding must now agree with the resolvability flag beside it.
--
-- A third door closes on the grammar. Turkish separates "görünmüyor", a plain
-- negative that is how a real absence gets written, from "görülemiyor", whose
-- impotential -eme- can only describe the observer. Only the second family is
-- matched, so the router's existing reading of the first is untouched.
--
-- All three demote rather than drop. Hook latches do go missing and guards do
-- come off; the field check is the right output for what the camera could not
-- resolve.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v28',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v28',
             'absence_resolution_floor', 0.004
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
    and router_version = 'claim-routing-v28'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072;
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
