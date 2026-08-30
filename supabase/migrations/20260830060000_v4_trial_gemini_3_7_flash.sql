-- Second candidate: gemini-3.7-flash, thinking MEDIUM, per-part ultra_high.
--
-- The flash-lite trial was not wasted. It proved the Gemini 3 request path
-- works -- per-modality accounting showed 2183 image tokens, ultra_high applied
-- -- so this switch changes only the model name, and everything measured on
-- flash-lite carries over as a control.
--
-- MEDIUM is gemini-3.7-flash's own default, which is the configuration Google
-- tuned it for, and it keeps the model the single changed variable. It is also
-- the cost-responsible starting point: this model bills output at $3.75 against
-- 2.5 Flash's $2.50, and our workload is thinking-heavy -- the 2.5 baseline
-- burns about 15k output-plus-reasoning tokens a run. Expect roughly $0.06
-- against the $0.040 we pay now, and rather more at HIGH. If MEDIUM
-- under-delivers, HIGH is one UPDATE, exactly as it was on flash-lite.
--
-- The price is introductory and doubles on 2027-01-01, to $1.50 in and $7.50
-- out. The cost function reads the date rather than a constant, so the ledger
-- does not quietly report half the real figure from that morning onward.
--
-- What to look at, in this order, from the flash-lite post-mortem:
--
--   1. candidate count. flash-lite returned zero at both MEDIUM and HIGH while
--      describing floor equipment in its own scene summary. Perception was
--      never the problem there; claim generation was. Zero candidates means the
--      model is out, whatever its latency.
--   2. the floor clutter. gemini-2.5-flash found it in four runs out of four,
--      confirmed against the photograph each time. It is the one finding in
--      this frame we know to be real.
--   3. image_tokens in the provider log: 2183 confirms ultra_high applied.
--   4. Turkish diacritics in the scene summary. flash-lite returned "gorulmekte"
--      for "görülmekte" and only passed the language contract on the
--      short-text tolerance.
do $$
declare
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = jsonb_set(
        jsonb_set(
          jsonb_set(
            config || jsonb_build_object(
              'primary_model', 'gemini-3.7-flash',
              'model_trial_label', 'gemini-3.7-flash-medium-ultrahigh',
              'model_trial_previous_model', 'gemini-2.5-flash'
            ),
            '{compute_profiles,premium,primary_model}',
            '"gemini-3.7-flash"'::jsonb
          ),
          '{compute_profiles,premium,gemini_thinking_level}',
          '"MEDIUM"'::jsonb
        ),
        '{compute_profiles,economy,primary_model}',
        '"gemini-3.7-flash"'::jsonb
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'no active v4 config to switch';
  end if;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v30'
    and prompt_version = 'v4-vision-core-v10'
    and config->>'primary_model' = 'gemini-3.7-flash'
    and config->'compute_profiles'->'premium'->>'primary_model' = 'gemini-3.7-flash'
    and config->'compute_profiles'->'premium'->>'gemini_thinking_level' = 'MEDIUM'
    -- Ignored while a Gemini 3 model is selected; it is what rollback restores.
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072
    and config->>'model_trial_previous_model' = 'gemini-2.5-flash';
  if not found then
    raise exception 'model switch did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
