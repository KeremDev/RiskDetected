-- Second look at gemini-3.5-flash-lite, on everything it never saw.
--
-- It was set aside for returning zero candidates at MEDIUM and again at HIGH,
-- while its own coverage note called a cluttered floor "düzenli ve boş". That
-- read as a perception failure rather than a threshold one, and a threshold
-- addendum cannot fix a model that denies the thing is there.
--
-- But that judgement rested on a single sentence, and four things have landed
-- since, none of which this model has been measured under:
--
--   the Gemini 3 candidate-threshold addendum, which it receives automatically
--     -- isGemini3 covers the 3.5 family and there is a test that says so
--   v31  impalement decided by the consequence, not the slip that led to it
--   v32  the resolution floor no longer demotes a claim about a person
--   v33  who falls decided from the candidate's structure, not a phrase list
--
-- All three router fixes were found on gemini-3.7-flash runs and every one of
-- them was ours, not the model's: correct candidates classified wrongly on the
-- way out. A model that produced few candidates would have been judged on that
-- same broken path.
--
-- The economics justify the retest on their own. flash-lite lists at $0.30 in
-- and $2.50 out against 3.7 Flash's $0.75 and $3.75, so the last construction
-- run's tokens would have cost about $0.025 instead of $0.040 -- and from
-- 2027-01-01, when the 3.7 introductory price doubles, roughly a third as much.
-- It was also the faster of the two.
--
-- One number decides it, and it is the candidate count, not the score. Zero
-- confirms the perception diagnosis and closes the model for good. Anything
-- above zero means the diagnosis was wrong and the cheaper, faster model is a
-- serious contender.
--
-- Rollback stays one statement, as it has all along.
do $$
declare
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = jsonb_set(
        jsonb_set(
          jsonb_set(
            config || jsonb_build_object(
              'primary_model', 'gemini-3.5-flash-lite',
              'model_trial_label', 'gemini-3.5-flash-lite-retrial-addendum-v33',
              'model_trial_previous_model', 'gemini-3.7-flash'
            ),
            '{compute_profiles,premium,primary_model}',
            '"gemini-3.5-flash-lite"'::jsonb
          ),
          '{compute_profiles,premium,gemini_thinking_level}',
          '"MEDIUM"'::jsonb
        ),
        '{compute_profiles,economy,primary_model}',
        '"gemini-3.5-flash-lite"'::jsonb
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
    and router_version = 'claim-routing-v33'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'gemini_thinking_level' = 'MEDIUM'
    -- The addendum it never received on its first trial.
    and config->>'gemini3_prompt_version' = 'v4-gemini3-threshold-v1';
  if not found then
    raise exception 'flash-lite retrial did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
