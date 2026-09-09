-- claim-routing-v12. Two-photo analysis 58057767.
--
-- 1. A wholly unprotected platform edge was titled as one missing member. The
--    candidate reads "Yükseltilmiş platform kenarında toplu koruma eksikliği"
--    with the cue "korkuluk, ara korkuluk veya etek tahtası bulunmamaktadır" --
--    nothing is there at all -- but the title picker tests for the mid-rail
--    before it tests for total absence, and the enumeration names the mid-rail,
--    so a fatal open edge was published as "Korkuluk sisteminde ara korkuluk
--    eksikliği". Total absence is recognised first now. The member branches keep
--    working when only a member is missing, and a lookbehind stops "ara korkuluk
--    yok" from reading as "korkuluk yok".
--
-- 2. An unsecured portable ladder used as permanent platform access was
--    published as "Güvenli geçiş yolunun dağınık malzemelerle engellenmesi" --
--    another fixed string asserting evidence that is not in the photograph, the
--    same shape as the wet-floor and rebar titles already corrected. Worse, the
--    access_egress mechanism was unconditionally fall_same_level, so a ladder
--    fall whose own event path reads "merdivenden düşme -> yere çarpma" was
--    capped at severity 7 and handed the housekeeping playbook, "Geçiş
--    yolundaki malzemeyi kaldırın". Both the title and the mechanism read the
--    event path now; a genuinely blocked route keeps its title and its
--    same-level mechanism.
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
  set router_version = 'claim-routing-v12',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v12',
             'title_total_absence_policy_version', 3,
             'ladder_access_mechanism_version', 1,
             'access_egress_title_evidence_version', 1,
             'finding_title_policy_version', 5,
             'mechanism_control_mapping_version', 19
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v12'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
