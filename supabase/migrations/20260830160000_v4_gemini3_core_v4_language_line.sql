-- v4-gemini3-core-v4: the Turkish rule reaches the calls that carry their own prompt.
--
-- v35 fixed the coverage contract and the primary pass went clean: analysis
-- caabfd66 produced four scored findings, all of them real -- the unguarded
-- slab edge at critical, the cable in standing water now at high rather than
-- medium after the new severity anchor, the floor clutter, and the worker
-- carrying long material that only gemini-2.5-flash had ever found. Correct
-- Turkish throughout, no fabrications, and not one "değerlendirilemedi" line.
--
-- The verification pass then failed on provider_output_language_invalid. That
-- is the diacritic gate added in v34 doing its job: the second look came back
-- with the diacritics stripped, and it can add candidates that reach the
-- reader, so rejecting it is right.
--
-- But the rule had never been given to it. promptFor substitutes the Gemini 3
-- core wherever V4_PROMPT_COMMON appears, and the verification pass and the
-- language-correction call carry their own prompts instead -- so the
-- substitution, and with it the Turkish-characters rule, never reached either.
-- The gate was enforcing an instruction the model had not received, and the
-- cost was the whole second look.
--
-- Those calls now get that one rule appended. Not the whole core: its candidate
-- and coverage sections describe work they do not do. Hashed together with the
-- core so both move under one version, and gemini-2.5-flash still gets neither,
-- under test.
do $$
begin
  update private.analysis_v4_configs
  set config = config || jsonb_build_object(
        'gemini3_prompt_version', 'v4-gemini3-core-v4',
        'gemini3_prompt_sha256',
          '394f5026da26d3bd73e30d7168e1a8fae44dfb9d7fb9858aa2ec807225107678'
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v35'
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 =
      '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e'
    and config->>'gemini3_prompt_version' = 'v4-gemini3-core-v4'
    and config->>'gemini3_prompt_sha256' =
      '394f5026da26d3bd73e30d7168e1a8fae44dfb9d7fb9858aa2ec807225107678';
  if not found then
    raise exception 'core v4 did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
