-- claim-routing-v29: the resolution floor cuts both ways.
--
-- v28 stopped analysis 031d5068 scoring a missing crane hook latch on an
-- evidence region of 0.03 by 0.05 -- twelve pixels of hook, where a latch is
-- one pixel and JPEG noise. The next run of the same photograph, 3e76e187, did
-- not raise that claim at all. It published the opposite one instead, as a
-- positive control:
--
--   "Her iki tavan vincinin kancalarında güvenlik mandalları mevcut."
--   cue: "Kancaların ağız kısmında mandallar açıkça görülüyor."
--   evidence_region: 0.03 x 0.05
--
-- Identical pixels, identical confidence, opposite conclusion. Nothing is
-- açıkça görülüyor at that scale, and the absence and the presence were equally
-- unavailable to the camera.
--
-- The positive control is the more dangerous of the two. A false absence sends
-- someone to check a hook that is fine. A false presence tells the reader the
-- hooks were checked and are fine, and an inspector who reads that may not go
-- and look. So the floor is mirrored: a positive control below it is not
-- published, and the report says nothing about the hooks rather than something
-- it cannot support.
--
-- The threshold is unchanged and still separates cleanly. The same run's
-- warning-label control sits at 0.1 by 0.05 -- 0.005, above the floor -- and
-- that label really is legible when the frame is enlarged.
--
-- Also in this version: material overhanging a pallet rack was told to fit a
-- toeboard. It shares both mechanism and module with a brick on a slab edge, so
-- v28's module-keyed variant could not tell them apart. Playbooks now also
-- match the asset the model named, and racking gets the control that belongs to
-- it: correct the overhang, stack within the beam, unitise loose loads, fit
-- rack backing, post the beam capacity.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v29',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v29',
             'absence_resolution_floor', 0.004,
             'positive_control_resolution_floor', 0.004
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
    and router_version = 'claim-routing-v29'
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
