-- claim-routing-v14. Two-photo analysis c42829fa.
--
-- 1. The model named a background machine a "taşlama makinesi" and the title
--    repeated it. Zoomed in it is the headstock of a second lathe with a rusty
--    faceplate on the spindle: the exposed rotating part is real, the equipment
--    class was a guess. The model said as much -- visibility 0.7, the only
--    candidate in the run below 1.0, over the hedged cue "dönen parça açıkta ve
--    koruyucusuz görünüyor". A title may describe what was seen; it may not name
--    equipment the model is not sure it recognised. Below 0.8 visibility the
--    class noun is replaced with "makine" and the observed condition is kept.
--
-- 2. An open platform edge whose event path reads "korumasız kenardan düşme ->
--    zeminle çarpışma" was scored as a falling object. The cue list enumerated
--    everything absent, including the toeboard, and the toeboard shortcut added
--    in claim-routing-v6 claimed it. That shortcut exists for material dropping
--    through a missing toeboard, not for a person going over the edge, so the
--    event path is now read first and on its own. The finding kept FK 720 either
--    way -- both mechanisms cap at 40 -- but its root cause, control line and
--    measures were all written for a falling load.
--
-- 3. One unsecured ladder produced two findings, one under falls_falling_objects
--    and one under access_egress, both at FK 126. The semantic dedup key carries
--    the module, so they never met. A ladder fall is now keyed on the asset
--    instead, whichever module notices it. The falls one had also taken the
--    edge-protection title "Çalışma kenarında düşmeye karşı koruma eksikliği",
--    colliding with the genuine open-edge finding beside it and being
--    disambiguated to "... (platform)" -- two different hazards under two
--    near-identical names, neither naming the ladder. Ladder evidence now takes
--    the ladder title before the edge branches are considered.
--
-- 4. The speculative-coverage gate added in claim-routing-v13 let one through:
--    "elektriksel bileşenler OLABİLİR ancak ... tespit edilemiyor" matched
--    "tespit edil" as a definite observation, so the note slipped past the gate
--    on its own negation. Negated observations are stripped before the test.
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
  set router_version = 'claim-routing-v14',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v14',
             'equipment_class_confidence_gate_version', 1,
             'edge_fall_event_path_priority_version', 1,
             'ladder_asset_identity_dedup_version', 1,
             'speculative_coverage_gate_version', 2,
             'finding_title_policy_version', 6,
             'mechanism_control_mapping_version', 20
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v14'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
