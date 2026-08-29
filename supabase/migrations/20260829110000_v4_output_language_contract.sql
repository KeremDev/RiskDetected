-- v4-vision-core-v9 / claim-routing-v19: enforce the Turkish output contract.
--
-- Analysis 8747d7c1 published an English safety report to a tr-TR reader:
--   "Missing toeboard on elevated platform guardrail"
--   "Unguarded rotating machinery parts"
-- with the sentence template welded around English fragments -- "Bu durum
-- contact with exposed rotating parts yoluyla entanglement or crushing injury
-- sonucuna neden olabilir." All five primary candidates came back in English.
--
-- v4 states the output language in the prompt and then never checks it.
-- language_validation_status has read "not_evaluated" on every run this engine
-- has ever done. The shared validator would not have caught it either: its
-- language check looks for incompatible SCRIPTS -- Han, Cyrillic, Arabic -- and
-- English is Latin like Turkish.
--
-- A page of Turkish safety text with no ç, ğ, ı, ö, ş or ü, carrying English
-- function words, is not Turkish. That check now runs on every provider answer
-- for a Turkish analysis and a failure is retryable, like a schema failure, so
-- the existing retry path re-asks with the contract restated. Short text is
-- never judged -- a label like "motor kaplini" can legitimately carry no
-- diacritic, and a false alarm would burn a retry on a correct answer.
--
-- The correction text reaches the provider, so it joins the hashed bundle
-- alongside the coverage-repair text rather than sitting outside the integrity
-- contract.
--
-- Note for the next bump: V4_PROMPT_COMMON embeds V4_PROMPT_VERSION ("SÜRÜM:
-- ..."), so the version and the bundle hash move together. Bump the version
-- constant first, then read the hash. Reading it first yields a value that is
-- already stale -- which looked like a flaky cache for three rounds and was not.
do $$
declare
  v_sha constant text :=
    '41008e19f4b4e95f79fb2f6e8630c118ad71bed4f350420a42715a60cb1da656';
begin
  update private.analysis_v4_configs
  set prompt_version = 'v4-vision-core-v9',
      prompt_sha256 = v_sha,
      router_version = 'claim-routing-v19',
      config = config
        || jsonb_build_object(
             'prompt_version', 'v4-vision-core-v9',
             'prompt_sha256', v_sha,
             'prompt_bundle_sha256', v_sha,
             'router_version', 'claim-routing-v19',
             'output_language_contract_enforced', true,
             'output_language_contract_version', 1,
             'public_output_language_contract_version', 2
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v9'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v19'
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 prompt/router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
