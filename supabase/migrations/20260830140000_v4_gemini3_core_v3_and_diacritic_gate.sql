-- v4-gemini3-core-v3 and claim-routing-v34: repairing v2, and a gate it exposed.
--
-- core-v2 was a net loss and the numbers are unambiguous. Against core-v1 on
-- the same photograph: provider calls 2 to 3, latency 25.8s to 37.1s, cost
-- $0.0242 to $0.0342. It bought one extra hazard -- the worker carrying long
-- material, missing from every previous run of every model except 2.5 -- and
-- broke two contract rules to get it.
--
-- Both breaks were the prompt's fault, not the model's.
--
-- Forbidding not_assessable_due_to_image where a visible entity exists pushed
-- six modules into no_actionable_issue_visible closures carrying neither a note
-- nor an entity ref. The validator calls that empty_closure_evidence, and v2
-- had told the model to keep notes short without ever saying they could not be
-- absent. Now: every coverage row carries a short note or an entity ref, and
-- writing briefly is not the same as writing nothing.
--
-- The push for more candidates also produced one missing a required field,
-- which is a hard rejection with no recovery path and cost the paid retry
-- outright. The candidate contract is now stated in the prompt instead of only
-- in the schema.
--
-- Separately, and not caused by any of this: gemini-3.5-flash-lite published
-- three findings and a positive control in Turkish with the diacritics stripped
-- -- "Su birikintisi yakinindan gecen elektrik kablosu". The language gate
-- could not see it. That gate looks for English, needs three English markers to
-- fire, and stripped Turkish carries none: it is not another language, it is
-- this one misspelled. The model did the same thing on its very first trial
-- run, so it is a trait rather than an accident.
--
-- The new test is deliberately narrow -- eighty characters or more, at least
-- two Turkish function words, not one of ıİşŞğĞçÇöÖüÜ -- because a false
-- verdict costs a retry on a correct answer, and short labels like "motor
-- kaplini" legitimately carry no diacritic. It runs per block, like the English
-- check, since that run was mixed: the first finding kept its diacritics and
-- the next two lost theirs.
--
-- One near miss worth recording. The first version of this edit matched a KANIT
-- line that appears in both prompts and replaced the copy in V4_PROMPT_COMMON,
-- moving the base bundle SHA off 823b6ad1 and quietly rewriting the
-- gemini-2.5-flash prompt that five measured runs depend on. The integrity test
-- caught it before deploy. Shared strings between the two prompts need indexed
-- edits, not first-match replacement.
do $$
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v34',
      config = config || jsonb_build_object(
        'router_version', 'claim-routing-v34',
        'gemini3_prompt_version', 'v4-gemini3-core-v3',
        'gemini3_prompt_sha256',
          '8b9a6ac9755429e046bcb6f69beea6f0d8a3e3b8f7da685083231b0dfe2b3168'
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v34'
    -- Unmoved, and checked here precisely because this migration nearly moved it.
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'prompt_bundle_sha256' =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v3'
    and config->>'gemini3_prompt_sha256' =
      '8b9a6ac9755429e046bcb6f69beea6f0d8a3e3b8f7da685083231b0dfe2b3168';
  if not found then
    raise exception 'core v3 and diacritic gate did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
