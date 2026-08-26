-- claim-routing-v8.
--
-- The self-contradiction gate shipped in claim-routing-v7 was unsound, and
-- analysis 4a692f65 showed why. The new prompt made the provider enumerate the
-- barrier members it can see, and it wrote:
--     "Korkuluklarda ara korkuluk mevcut (C1 hariç)."
--     "Korkuluklarda etek tahtası mevcut (C2 hariç)."
-- That is consistency, not contradiction: the model carved the two flagged
-- candidates out of its own statement. The gate ignored the carve-out, read
-- both controls as flat affirmations, and demoted both candidates. A guardrail
-- genuinely missing its mid-rail at one bay -- a real and common defect -- would
-- have been suppressed exactly the same way.
--
-- Three corrections.
--
-- 1. A control that excludes the candidate ("hariç", "dışında", or naming the
--    candidate key) no longer counts as affirming that component.
-- 2. A component the model reports present along the run but missing at one
--    spot is a localised gap. Telling that apart from a rail seen edge-on or
--    hidden behind plant is finer geometry than a flattened photo carries, so it
--    becomes a verification_request under its own reason code,
--    localized_barrier_gap_unresolved, rather than a fabricated contradiction.
--    Complete absence of a member, with no control claiming it present, stays a
--    scored finding.
-- 3. componentsClaimedAbsent scanned a 90-character window that ran across
--    clause boundaries, so "üst korkuluk mevcut; ara korkuluk bulunmuyor" marked
--    the top rail absent as well. It now reads clause by clause and drops any
--    component the same sentence says is present.
--
-- The unscored report budget also moves from six to eight. Three verification
-- requests plus the assurance items overran six on this run and the cut fell on
-- the crane's periodic-inspection assurance and the machine-guard assurance,
-- both legally required checks, to make room for barrier claims the photograph
-- did not support.
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
  set router_version = 'claim-routing-v8',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v8',
             'provider_self_contradiction_gate_version', 2,
             'localized_barrier_gap_version', 1,
             'barrier_clause_scoped_absence_version', 1,
             'report_budget_max_unscored', 8,
             'report_budget_policy_version', 3
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v8'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
