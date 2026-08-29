-- claim-routing-v26: the photograph can refute "could not be assessed from the
-- photograph".
--
-- Analysis 5d5b1b67, a construction site with five visible workers, two of them
-- working at height. The engine published two fatal fall-from-height findings --
-- a worker on an unprotected slab edge with no harness, and a worker on a
-- scaffold deck missing its mid rail and toeboard -- and then, from the same
-- provider output, printed:
--
--   "Çalışan maruziyeti değerlendirilemedi"
--   "Yüksekte çalışma değerlendirilemedi"
--   "Erişim ve kaçış yolları değerlendirilemedi"
--
-- The model had closed people_exposure, work_at_height and access_egress as
-- not_assessable_due_to_image while reporting exactly those hazards elsewhere in
-- the same answer. The reader was told the image cannot show work at height,
-- directly underneath two fatal work-at-height findings.
--
-- "not_assessable_due_to_image" is a statement about the IMAGE, so the image can
-- refute it. Three overlaps are decidable from the same output and are now
-- checked: people_exposure against visible people, work_at_height against a
-- published fall_from_height finding, access_egress against any published fall.
-- The record is dropped with a reason in the ledger rather than printed. Every
-- other module keeps its record -- telling the reader what could not be assessed
-- is the whole point of these items.
--
-- Prompt bundle untouched, single-photo thinking budget stays 3072; both asserted.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v26',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v26',
             'not_assessable_self_refutation_version', 1
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
    and router_version = 'claim-routing-v26'
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
