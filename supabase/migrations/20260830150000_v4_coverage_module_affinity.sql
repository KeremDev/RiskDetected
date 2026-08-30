-- claim-routing-v35: one hazard belongs to several modules.
--
-- The coverage validator required a finding_present row to name a candidate
-- whose module_id equalled the row's module exactly. A worker at an unguarded
-- slab edge is work_at_height by task, falls_falling_objects by mechanism, and
-- people_exposure because a person is standing in it -- and a candidate can
-- carry only one module_id. Exact equality therefore asked the model to solve
-- something unsolvable: bind the candidate to one module and every other row
-- naming the same hazard is rejected.
--
-- Three successive Gemini 3 prompt versions failed at this, each differently
-- and each on the same four modules -- access_egress, energy,
-- falls_falling_objects, people_exposure:
--
--   core-v1  downgraded the extra rows to not_assessable_due_to_image, which
--            put "değerlendirilemedi" in a report that had just scored the
--            hazard critical
--   core-v2  closed them with neither note nor entity ref, which the same
--            validator rejects as empty_closure_evidence
--   core-v3  wrote finding_present without a binding, which is where this
--            started
--
-- Each version traded one violation for another because the constraint had no
-- satisfying answer. The prompt was never the problem; three attempts at
-- rewording it were three attempts at the wrong layer.
--
-- A finding_present row can now also be closed by a candidate from a module
-- that shares the hazard. The pairs mirror the ones imageAnswersThisModule
-- already uses to drop a contradictory not_assessable row, so the two places
-- agree about which modules overlap. people_exposure accepts any module,
-- because any hazard with a person in it is that module's subject. Unrelated
-- modules still require their own candidate, under test -- this is a mapping,
-- not an opening.
do $$
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v35',
      config = config || jsonb_build_object('router_version', 'claim-routing-v35'),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v35'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v3';
  if not found then
    raise exception 'coverage affinity bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
