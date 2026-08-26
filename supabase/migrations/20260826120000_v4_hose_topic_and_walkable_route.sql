-- claim-routing-v11. Same hose-coupling close-up, re-run as 41f14e70.
--
-- Two items in that report did not belong, and both came out of
-- claim-routing-v10.
--
-- 1. Routing a hose assembly to process_integrity was right -- it carries the
--    same non-visual assurance as fixed piping -- but the topic's copy is
--    written for vessels, so a close-up of a coupling lying in gravel published
--    "Proses tankı ve borulama bütünlüğü" and a description about "tank veya
--    borulama sisteminin iç bütünlüğü". No tank is in the frame. Hose
--    assemblies now have their own topic, hose_assembly_integrity, with their
--    own field steps -- pressure class stamp, test record, manufacturer-approved
--    coupling and pin rather than a wire, whip check -- and hose standards
--    (TS EN 853/856, TS EN ISO 4413/4414) instead of the API tank series. The
--    separate id means a photo holding both a vessel and a hose line gets both
--    assurances.
--
-- 2. An offcut of wire and some dry grass in the gravel became "Yerdeki gevşek
--    tel ve döküntülerden kaynaklanan takılma tehlikesi". There is no walking
--    route in a macro frame: the model declared one accessible region covering
--    the whole image with is_global set, which says ground is everywhere, not
--    that people walk here. Scenes with a real trip hazard look different -- the
--    construction photos carry four people and named routes, none global. A
--    same-level candidate now needs a person in the scene or at least one
--    non-global accessible region, and is hard-rejected as
--    no_walkable_route_in_scene otherwise, with the counts recorded.
--
-- Also: the fall_same_level control line asserted a wet surface in every
-- same-level finding, repeating the over-claim the housekeeping title already
-- had to lose.
--
-- Tuning only: the prompt bundle is untouched.
do $$
declare
  v_prompt text;
  v_sha text;
begin
  select prompt_version, prompt_sha256 into v_prompt, v_sha
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  update private.analysis_v4_configs
  set router_version = 'claim-routing-v11',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v11',
             'hose_assembly_assurance_topic_version', 1,
             'walkable_route_gate_version', 1,
             'generic_visual_hazard_gate_version', 5,
             'wet_surface_title_policy_version', 3,
             'asset_assurance_catalog_version', 'asset-assurance-v11'
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v11'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
