-- A prompt of its own for the Gemini 3 family. 2.5 keeps its own, untouched.
--
-- The addendum is replaced by a full core prompt, because appending was making
-- the two texts argue. The 2.5 prompt is five thousand characters largely made
-- of restraint -- five paragraphs on guardrails alone, written to stop a model
-- that over-claims after one photograph produced five different false rail
-- claims in five runs. Bolting "do not decide importance yourself" onto the end
-- of that told the model two opposite things at once.
--
-- What replaces them is what was measured on Gemini 3, in order of cost.
--
-- ÖNCE ADAY, SONRA KAPSAM is the largest single loss and it is new here. In
-- analysis fcbd02a9, gemini-3.5-flash-lite marked seven modules finding_present
-- and bound candidates to three. The four unbound rows -- access_egress,
-- energy, falls_falling_objects, people_exposure -- were rewritten by the
-- server's coverage recovery and the hazards behind them never reached the
-- report. The model had seen them and written them into the wrong array. It
-- also cost a wasted provider call, which is most of why that run took 37
-- seconds against the 3.7 run's 27.
--
-- ADAY EŞİĞİ carries over from the addendum. gemini-3.7-flash returned zero
-- candidates on a cluttered workshop floor and said why in its own coverage
-- note: materials present, but not critical on the main walkway. Severity is
-- decided downstream and that judgement was never the model's to make.
--
-- The guardrail rules survive as two lines instead of five paragraphs. The
-- hallucination they defend against is real, but the router holds it
-- independently -- barrier continuity, the sandwich rule, second-pass
-- disagreement, the resolution floor -- and none of those needs the prompt to
-- talk the model out of looking.
--
-- Two additions come from hazards these models kept missing on the construction
-- frame: long material carried on a shoulder, in the mandatory site scan, and a
-- severity anchor for a cable in standing water. 3.7 missed the cable twice;
-- flash-lite found it and scored it 7.
--
-- The evidence bar is unchanged and now stands as its own section. The failure
-- in the other direction is the fabricated hook latch that cost three router
-- versions, and a prompt reading as "claim more" would buy recall at that price.
--
-- Hashed separately at 8ce1f193..., so V4_PROMPT_VERSION stays
-- v4-vision-core-v10 at 823b6ad1... and the gemini-2.5-flash baseline is
-- byte-identical. Substituted for the base rather than swapped wholesale, so
-- the per-call context -- photo index, output language, sector block, active
-- modules, targeted block -- survives. The verification pass carries its own
-- prompt, generates no candidates, and is left alone.
do $$
begin
  update private.analysis_v4_configs
  set config = config || jsonb_build_object(
        'gemini3_prompt_version', 'v4-gemini3-core-v1',
        'gemini3_prompt_sha256',
          '8ce1f1933ffb0d8cc431badfd904b7af99d53315c25c0b1215a1e2df54cf2318'
      ) - 'gemini3_prompt_addendum_sha256',
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v33'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v1'
    and config->>'gemini3_prompt_sha256' =
      '8ce1f1933ffb0d8cc431badfd904b7af99d53315c25c0b1215a1e2df54cf2318'
    and config->>'primary_model' = 'gemini-3.5-flash-lite';
  if not found then
    raise exception 'gemini3 core prompt did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
