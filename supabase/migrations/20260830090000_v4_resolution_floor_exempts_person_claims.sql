-- claim-routing-v32: a claim about a person is not a claim about a component.
--
-- The resolution floor, added in v28, exists to stop a verdict on a part too
-- small to have been resolved: a crane hook latch inside twelve pixels of hook,
-- asset_ref hook_1, nobody in the frame, published fatal at FK 720.
--
-- In analysis 273613e1 it took a genuine fatal instead. A worker at an
-- unguarded slab edge -- person_ref person_upper_slab, no asset_ref, three
-- correct cues naming the missing top rail, mid rail and toeboard and the
-- absent lanyard -- arrived with an evidence region of 0.0022 and was demoted
-- to a field check. The photograph is heavily letterboxed and the camera is
-- far, so a whole standing human occupies a fraction of the canvas that a hook
-- latch also occupies. The identical hazard scored critical on the previous run
-- of the same image, where the model happened to report a larger box.
--
-- Distance shrinking a person is not the same fact as a part being below
-- resolution. The subject there is the person's exposure and the collective or
-- personal protection missing around them, and the frame contains an entire
-- human being to scale it by. person_ref separates the two cases exactly: the
-- hook claim carried an asset and no person, this one a person and no asset.
--
-- Guardrail hallucination is real and this does not reopen it. It is held by
-- the gates built for it -- barrier continuity, the sandwich rule, second-pass
-- disagreement, the double-contradiction drop -- none of which cares about
-- region size. The hook latch still falls, under test.
--
-- One consequence cascades: v31's rule that a published fall answers the
-- falling-objects module counts only scored observed findings, so while the
-- fall sat demoted the report also carried "Düşme ve düşen cisim
-- değerlendirilemedi". Restoring the finding closes that line too.
do $$
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v32',
      config = config || jsonb_build_object('router_version', 'claim-routing-v32'),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v32'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    -- Unchanged: the floor still applies to component claims.
    and (config->>'absence_resolution_floor')::numeric = 0.004;
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
