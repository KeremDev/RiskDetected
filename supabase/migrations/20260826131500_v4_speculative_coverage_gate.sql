-- claim-routing-v13.
--
-- An unresolved module becomes a published field check. That is right when a
-- visible asset's condition cannot be read from the photograph, and wrong when
-- the model is only guessing that a hazard class might exist somewhere. On the
-- two-photo analysis 58057767 four of the twelve report items were the second
-- kind, all from one photo:
--
--   "Proses ortamında kimyasallar kullanılıyor OLABİLİR, ancak ..."
--   "Endüstriyel ekipmanların elektrik bağlantıları veya panoları MEVCUT
--    OLABİLİR, ancak ..."
--   "Endüstriyel ekipman ve boru tesisatı enerji içeriyor OLABİLİR, ancak ..."
--
-- beside one that belongs and stays:
--
--   "Boru tesisatı ve ekipmanların proses bütünlüğü (sızıntı, korozyon vb.)
--    görsel olarak tam olarak değerlendirilememektedir."
--
-- The prompt asks for unresolved_requires_verification when critical geometry is
-- occluded and the possible consequence is heavy. Speculating that a hazard
-- class exists is not that, and a reader cannot act on it. A coverage note whose
-- claim is that the hazard may exist, with no definite visual observation
-- alongside it, no longer produces an item; the drop is written to the routing
-- ledger as speculative_module_coverage with the note, so it stays auditable.
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
  set router_version = 'claim-routing-v13',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v13',
             'speculative_coverage_gate_version', 1,
             'unresolved_module_verification_version', 2,
             'generic_visual_hazard_gate_version', 6
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v13'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
