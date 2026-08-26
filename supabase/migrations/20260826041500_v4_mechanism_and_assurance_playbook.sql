-- claim-routing-v4.
--
-- Four routing defects and one missing output, all observed on analysis
-- 0c365919 (three photos, manufacturing):
--
-- 1. mechanismCode folded module_id into the text it pattern-matched, and the
--    module id `falls_falling_objects` literally contains "falling" and
--    "object". The falling-object branch therefore matched every candidate of
--    that module and fall_from_height was unreachable. A missing mid-rail was
--    scored as a falling object, which skipped the partial-barrier severity cap
--    and published FK 720 / critical where FK 270 / high was correct.
-- 2. The housekeeping title was a fixed string claiming a wet floor regardless
--    of evidence, so a photo showing only cardboard was published as
--    "ıslak zeminde ... kayma riski".
-- 3. module_coverage entries answered `unresolved_requires_verification` were
--    dropped without a trace; only not_assessable_due_to_image produced an item.
-- 4. Observed-finding descriptions opened with the provider's lowercase cue.
-- 5. Unscored items carried an empty recommended_measures array and an empty
--    references_text even on profiles whose jurisdiction policy allows
--    references, so a tank assurance item said the internal integrity could not
--    be confirmed and then offered no step and no standard.
--
-- Tuning only on the database side: the prompt bundle is untouched, so
-- prompt_version and prompt_sha256 must not move.
do $$
declare
  v_prompt text;
  v_sha text;
begin
  select prompt_version, prompt_sha256 into v_prompt, v_sha
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  update private.analysis_v4_configs
  set router_version = 'claim-routing-v4',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v4',
             'mechanism_module_id_contamination_fix_version', 1,
             'wet_surface_title_policy_version', 2,
             'unresolved_module_verification_version', 1,
             'observed_description_sentence_case_version', 1,
             'assurance_playbook_version', 1,
             'api_tank_reference_policy_version', 2,
             'approved_reference_renderer_version', 4,
             'assurance_corrective_copy_version', 3
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v4'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
