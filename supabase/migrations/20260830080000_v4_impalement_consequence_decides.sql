-- claim-routing-v31: a slip is how you reach the rebar, not what it does to you.
--
-- Analysis 4492df2f, a construction site with uncapped starter bars. The model
-- raised a correct impalement claim at criticality permanent, and its event
-- path read:
--
--   contact_or_failure: "kişinin KAYMASI veya dengesini kaybetmesi sonucu
--                        sivri uçlara düşmesi"
--   consequence:        "sivri metal donatı uçlarının vücuda SAPLANMASI
--                        sonucu ağır/kalıcı yaralanma"
--
-- impalementIntent scans the whole path for slip and trip words before deciding
-- anything, so "kayması" vetoed it. That exclusion exists for a good reason --
-- rebar also lies on the ground and gets tripped over -- but it was reading the
-- initiating clause, where a slip is simply how the person arrives at the
-- hazard. The consequence had already settled the question.
--
-- The cost was not cosmetic. With impalement vetoed the mechanism resolved to
-- fall_same_level; the dedup key then collapsed to the generic ground-access
-- one; the site-clutter claim from the same photograph merged into it; and the
-- merged item published under an impalement title at severity 7, capped by the
-- same-level policy. Two distinct real hazards became one, and the one that
-- survived was scored as the milder of them. The prompt's own anchor says
-- impalement is at least permanent, and gemini-2.5-flash published this same
-- hazard at band high.
--
-- Now the consequence is read first: if it names impalement, the claim is
-- impalement whatever led up to it. The slip exclusion still applies to
-- everything else, and a claim that ends in a same-level fall stays one --
-- both under test.
--
-- Model-independent. The defect was in the router and would have mis-scored the
-- same photograph for gemini-2.5-flash had its event path been worded this way.
do $$
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v31',
      config = config || jsonb_build_object('router_version', 'claim-routing-v31'),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v31'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-threshold-v1';
  if not found then
    raise exception 'v4 router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
