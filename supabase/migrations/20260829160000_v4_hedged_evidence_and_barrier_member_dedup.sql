-- claim-routing-v23: a hypothesis is not an observation, and two guardrail
-- members are not one finding.
--
-- Analysis afd0ffa9, first run at the raised thinking budget. The guardrail
-- hallucination finally left the scored output: the model published four
-- positive controls reading "tam bir korkuluk sistemi (üst korkuluk, ara
-- korkuluk ve etek tahtası) mevcuttur" for both platforms, which is what the
-- photograph shows, and the one residual member claim was demoted by the
-- continuity gate. Two defects remained.
--
-- 1. The only scored item was "Tankların üzerinde bulunan ekipmanların hareketli
--    veya sıkışma noktaları OLABİLECEK kısımlarında belirgin bir koruyucu
--    görünmüyor" -- permanent, FK 270. The tank tops carry piping, a wrapped
--    valve and structural steel; no drive, no coupling, nothing turning. The
--    model did not see an unguarded moving part, it reasoned there might be one.
--    A cue that says "might be" is a hypothesis and now routes to a field check.
--    Bare "olabilir" is excluded: the consequence sentence the engine writes
--    itself ends "...sonucuna neden olabilir".
--
-- 2. The report showed a title about the mid rail over a description about the
--    toeboard. Two different members of one rail share an event path -- edge,
--    fall, injury -- so the dedup key collapsed them into a single item. The
--    member is now part of the claim's identity.
--
-- Prompt bundle untouched: v4-vision-core-v10 and its hash carry over. The
-- single-photo thinking budget stays at 6144 and is asserted here.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v23',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v23',
             'hedged_evidence_gate', true,
             'barrier_member_dedup_identity_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v23'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 6144;
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
