-- Trial: gemini-2.5-flash -> gemini-3.5-flash-lite, thinking MEDIUM, media ultra_high.
--
-- A trial, not a migration. Two or three analyses on this model, then the same
-- on a second candidate, then a decision.
--
-- Three things about it are worth writing down, because none matched what we
-- expected going in.
--
-- 1. It is not cheaper. gemini-3.5-flash-lite lists at $0.30 / $2.50, the same
--    as gemini-2.5-flash. "Lite" stopped meaning cheap at Gemini 3 -- what it
--    buys is latency and a newer vision stack, not money. The cost table now
--    names each family instead of matching one "lite" substring, which would
--    have priced 3.5-flash-lite as though it were the 2.5 one and under-
--    reported every run by a factor of three.
--
-- 2. media_resolution "high" would have changed nothing. On Gemini 3 the
--    default allocation for an image is 1120 tokens, exactly what "high" asks
--    for. Only ultra_high, at 2240, gives the model more of the picture -- and
--    that is the lever this workload actually needs. Three runs of one crane
--    workshop produced, in turn, a fatal missing hook latch, then no claim at
--    all, then the same latch declared present, all from a hook twelve pixels
--    across. No reasoning budget resolves a detail that was never in the
--    tensor. About three hundredths of a cent per analysis.
--
-- 3. Thinking is MEDIUM rather than HIGH, on the evidence. Raising the 2.5
--    budget from 3072 to 6144 bought nothing on this workload and was reverted.
--    Every defect fixed in v28 through v30 was perceptual or a routing bug, not
--    a reasoning failure. MEDIUM also keeps the model the single changed
--    variable, so a bad result stays interpretable.
--
-- temperature is dropped for Gemini 3: Google's migration guidance says values
-- below the default of 1.0 cause looping and degradation on these models. We
-- ran 0.1 for reproducibility, which was right on 2.5 and is the documented
-- wrong choice here. Run-to-run variance is already a known property of this
-- engine, and the routing gates -- the resolution floor above all -- are what
-- contain it.
--
-- Rollback is one statement: set primary_model back to gemini-2.5-flash. The
-- request shape follows the model name, so 2.5 keeps its budget, its
-- temperature and MEDIA_RESOLUTION_HIGH with no redeploy.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = jsonb_set(
        jsonb_set(
          config || jsonb_build_object(
            'primary_model', 'gemini-3.5-flash-lite',
            'model_trial_label', 'gemini-3.5-flash-lite-medium-ultrahigh',
            'model_trial_previous_model', 'gemini-2.5-flash'
          ),
          '{compute_profiles,premium}',
          coalesce(config->'compute_profiles'->'premium', '{}'::jsonb)
            || jsonb_build_object(
                 'primary_model', 'gemini-3.5-flash-lite',
                 'gemini_thinking_level', 'MEDIUM'
               )
        ),
        '{compute_profiles,economy}',
        coalesce(config->'compute_profiles'->'economy', '{}'::jsonb)
          || jsonb_build_object(
               'primary_model', 'gemini-3.5-flash-lite',
               'gemini_thinking_level', 'LOW'
             )
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
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and router_version = 'claim-routing-v30'
    and integrity_status = 'valid'
    and config->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'gemini_thinking_level' = 'MEDIUM'
    -- The 2.5 budget stays on the row: it is what rollback restores, and it is
    -- ignored while a Gemini 3 model is selected.
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072;
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
