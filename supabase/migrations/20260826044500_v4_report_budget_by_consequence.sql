-- claim-routing-v5.
--
-- Analysis abeb5b5b lost the storage-tank assurance that abeb5b5b's own photo 1
-- clearly supported (two visible process_vessel entities). It was not model
-- variance: boundedVisibleItems caps published items at eight, findings and
-- unscored items shared that budget, and the loser was chosen by display_order
-- whose final tie-break is the Turkish alphabet. The run produced four
-- findings, one verification request and four assurance items -- nine items --
-- and "Proses bütünlüğü" was cut because P sorts after K and M. Nothing
-- recorded the cut, so it looked like the engine had never found the tank.
--
-- Findings and unscored items now have separate budgets, survivors inside each
-- group are chosen by consequence rank, and whatever the budget drops is
-- written to the quality trace as report_budget_excluded.
--
-- Also in this router: assurance and verification titles no longer repeat the
-- item class ("... saha teyidi", "... konusunda saha doğrulaması gerekli"),
-- since the report already labels the class, and cue text that already ends in
-- a full stop no longer produces "...görülmektedir.. Bu durum ...".
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
  set router_version = 'claim-routing-v5',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v5',
             'report_budget_policy_version', 2,
             'report_budget_max_findings', 8,
             'report_budget_max_unscored', 6,
             'assurance_consequence_rank_version', 1,
             'assurance_title_suffix_removed', true,
             'assurance_public_copy_version', 5,
             'sentence_terminator_dedup_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v5'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
