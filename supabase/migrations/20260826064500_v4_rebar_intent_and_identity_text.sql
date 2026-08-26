-- claim-routing-v9. Single-photo construction analysis 35264d07.
--
-- 1. Rebar appears in two unrelated hazards on the same site: starter bars
--    projecting from a column that a person can be impaled on, and lengths of
--    rebar lying among the clutter you trip over. The title and the mechanism
--    both matched the noun alone, so a candidate whose own event path reads
--    "Takılma, kayma veya düşme -> Aynı seviyede düşme" was published as
--    "Açıkta kalan sivri filiz veya donatı uçları (2)" with mechanism
--    sharp_edge_contact and the impalement root cause. It also collided with the
--    genuine impalement finding's title, and the uniqueness pass hid that behind
--    a "(2)". The event path decides now, not the noun.
--
-- 2. The scene graph writes person_2. cleanText's possessive and locative rules
--    allowed only whitespace before the digit, so "person_2'de" missed them,
--    fell through to the bare-identifier rule and published the broken
--    "çalışan'de kişisel düşme önleyici sistem görünmüyor". Both rules take the
--    underscore now, and any apostrophe suffix orphaned by a substitution is
--    swept up after it.
--
-- 3. people_exposure treated any mention of carrying as overexertion, so a
--    timber on a shoulder whose consequence is "Kişinin nesne tarafından
--    çarpılması" was capped at the strain ceiling of 7. Overexertion now needs a
--    strain consequence.
--
-- 4. critical_demotions listed bare candidate keys. An electrical line whose
--    energy state genuinely cannot be read from a photograph is a
--    doctrine-driven field check, not a defect; an unexplained demotion is. The
--    entries carry their routing reason so the two can be told apart.
--
-- 5. Hardening, not an observed failure: the partial-barrier severity cap
--    matched "eksik" and "bulunmuyor" but not "görünmüyor" or "mevcut değil",
--    so the same scaffold could score 540 or 202 depending on the verb the model
--    chose. In this run the cap did fire, through the label. Now all three
--    phrasings cap alike.
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
  set router_version = 'claim-routing-v9',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v9',
             'rebar_impalement_intent_version', 1,
             'scene_identity_suffix_cleanup_version', 1,
             'ergonomic_strain_consequence_version', 1,
             'critical_demotion_audit_version', 2,
             'incomplete_guardrail_severity_policy_version', 2,
             'structured_identifier_label_guard_version', 2
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v9'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
