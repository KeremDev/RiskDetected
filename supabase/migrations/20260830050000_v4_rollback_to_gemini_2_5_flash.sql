-- gemini-3.5-flash-lite trial ended. Back to gemini-2.5-flash.
--
-- Three runs on one crane workshop photograph, the same frame gemini-2.5-flash
-- had already been measured on four times.
--
--   run 1  HTTP 400        request shape, ours, fixed
--   run 2  thinking MEDIUM 0 candidates, 0 scored
--   run 3  thinking HIGH   0 candidates, 0 scored
--
-- Zero candidates means zero claims reached the router, not zero findings after
-- the gates: the routing ledger is empty both times. gemini-2.5-flash produced
-- four candidates and found the floor clutter in four runs out of four, each
-- confirmed against the photograph by eye.
--
-- Both explanations we had are now ruled out by measurement rather than
-- argument.
--
-- Resolution was not the limit. The per-part media_resolution did apply:
-- Google's per-modality prompt accounting reports 2183 image tokens, which is
-- ultra_high for this aspect ratio, against roughly 1120 at the default. The
-- model was given the most of the picture the API can give it.
--
-- Thinking was not the limit either. HIGH raised reasoning from 3040 to 7291
-- tokens, cost by 41% and latency by 31%, and produced exactly the same
-- nothing. The third run's own scene summary reads "zemin uzerinde cesitli
-- ekipmanlar gorulmektedir" -- it describes equipment on the floor and then
-- emits no candidate about it. Perception happened; claim generation did not.
-- That summary also came back without Turkish diacritics, which is its own
-- warning about this model on this contract.
--
-- What is left is the model. It is genuinely faster and cheaper -- 23.5s and
-- $0.020 against 65.6s and $0.040 at MEDIUM -- and neither number means
-- anything when the output tells a site with a cluttered floor that it is
-- clean. A hazard engine that finds nothing is worse than a slow one.
--
-- The Gemini 3 request path stays in the code and under test, so the second
-- candidate model is a config change with no redeploy.
do $$
declare
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = jsonb_set(
        jsonb_set(
          config || jsonb_build_object(
            'primary_model', 'gemini-2.5-flash',
            'model_trial_label', 'reverted-to-gemini-2.5-flash',
            'model_trial_result_3_5_flash_lite',
              'zero candidates at MEDIUM and HIGH; ultra_high confirmed applied at 2183 image tokens'
          ),
          '{compute_profiles,premium,primary_model}',
          '"gemini-2.5-flash"'::jsonb
        ),
        '{compute_profiles,economy,primary_model}',
        '"gemini-2.5-flash"'::jsonb
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'no active v4 config to revert';
  end if;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v30'
    and config->>'primary_model' = 'gemini-2.5-flash'
    and config->'compute_profiles'->'premium'->>'primary_model' = 'gemini-2.5-flash'
    -- The budget 2.5 actually uses, restored to what it ran on for four
    -- measured runs. The thinking level is left on the row and ignored while a
    -- 2.5 model is selected.
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072;
  if not found then
    raise exception 'rollback did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
