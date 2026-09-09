-- claim-routing-v15. Two-photo analysis 12063bd4.
--
-- The scene graph numbers equipment, and those ordinals reached the report:
--   "Makine 3 üzerinde açıkta kalan elektrik kabloları"
--   "Torna tezgahı 1'de açıkta bulunan kurşun vida ve besleme çubuğu"
--   "Torna tezgahı 1'in çalışma noktasında koruyucu eksikliği"
-- A reader has no numbering to match them against. This is the same leak as the
-- person_2 identifiers cleaned in claim-routing-v9; the person rules were added
-- then and the equipment ones were not.
--
-- Dropping the digits alone does not work in Turkish, because the case suffix
-- hangs off the numeral: "Torna tezgahı 1'de" would become "Torna tezgahı de".
-- The suffix is rebuilt on the noun with vowel harmony, the possessive buffer n
-- and consonant assimilation, so the three cases above read "Makine üzerinde",
-- "Torna tezgahında" and "Torna tezgahının", and "Tank 4'te" reads "Tankta".
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
  set router_version = 'claim-routing-v15',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v15',
             'equipment_ordinal_cleanup_version', 1,
             'turkish_case_suffix_rebuild_version', 1,
             'structured_identifier_label_guard_version', 3,
             'canonical_text_normalization_version', 2
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v15'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
