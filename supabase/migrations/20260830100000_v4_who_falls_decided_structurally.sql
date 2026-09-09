-- claim-routing-v33: who falls, decided structurally rather than by phrase.
--
-- Analysis a994c552 walked between the fixed phrases the falls module used to
-- tell a person from an object:
--
--   contact_or_failure: "Denge kaybı veya takılma sonucu kenardan BOŞLUĞA düşme"
--   consequence:        "YÜKSEKTEN ZEMİNE düşmeye bağlı ağır yaralanma veya can kaybı"
--
-- The list looks for "kenardan düşme", "yüksekten düşme" and "zeminle çarpışma"
-- as contiguous strings, and none of them survives an interposed word. So a
-- worker going over an unguarded slab edge was filed as a falling object. It
-- still scored critical, but work_at_height was left unanswered and the report
-- published "Yüksekte çalışma değerlendirilemedi" three items below a fatal
-- fall -- the same self-contradiction v31 closed for the other module, arriving
-- through a different door.
--
-- The candidate already says whose hazard it is, so the decision now reads the
-- structure: a person_ref together with a loss-of-footing clause is a person
-- going down; material going over an edge names the material in the possessive.
-- Mentioning material is not sufficient either way, because "malzemeye
-- takılarak düşme" is a worker tripping and the noun alone would file it as a
-- falling object.
--
-- Writing the test for the object case exposed an older defect underneath: the
-- existing phrase list matched "kenardan düşme" inside "Malzemenin kenardan
-- düşmesi", so material dropping off an edge was already being classified as a
-- person fall. Both directions are now under test.
--
-- Model-independent, like v31 and v32. The phrasing came from
-- gemini-3.7-flash, but the classifier would have made the same mistake on any
-- model that worded the clause this way.
do $$
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v33',
      config = config || jsonb_build_object('router_version', 'claim-routing-v33'),
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
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
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
