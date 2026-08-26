-- claim-routing-v10. Single-photo close-up of a hose coupling, analysis 1e738d1c.
--
-- The engine read the photograph well: a bent wire standing in for the safety
-- pin, heavy corrosion on the male half, surface cracking on the hose. Three
-- defects in what it did with that read.
--
-- 1. The most severe of the three candidates got the lowest severity cap. Its
--    consequence, "Bağlantının ayrılması ve basınçlı akışkanın kontrolsüz
--    salınımı", contained the phrase "basınçlı akışkan", and mechanismCode
--    matched that phrase alone -> hydraulic_pneumatic_release, whose cap of 15
--    exists for fluid injected into tissue. The model had called it fatal; the
--    cap cut severity to 15 and published FK 270 where 720 was right. The two
--    lesser corrosion findings beside it, lacking the phrase, kept the cap of
--    40. A coupling letting go, a hose whipping or a line bursting is stored
--    energy released as a whole; the event path decides now, and injection
--    wording is what selects the lower cap.
--
-- 2. A pressurised hose assembly produced no assurance item at all. The visible
--    asset matcher knew tanks, vessels and process piping but not hoses,
--    couplings, unions or flanges, so the pressure rating, test certificate,
--    inspection date and whip restraint were never asked for.
--
-- 3. All three findings published the same recommended action word for word.
--    Root cause and measures moved to the mechanism in claim-routing-v6, but the
--    one-line action stayed keyed by module, and all three share
--    process_integrity. Each mechanism now carries its own line.
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
  set router_version = 'claim-routing-v10',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v10',
             'pressure_separation_mechanism_version', 1,
             'hose_coupling_assurance_version', 1,
             'mechanism_control_mapping_version', 18,
             'mechanism_control_line_version', 1,
             'asset_assurance_catalog_version', 'asset-assurance-v10'
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v10'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
