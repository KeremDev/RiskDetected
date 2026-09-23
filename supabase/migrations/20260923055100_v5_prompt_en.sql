-- English analyses on the free engine were answered in Turkish.
--
-- analyze-v4's v5 path sent every analysis the Turkish prompt, whose only
-- nod to English was a closing "Çıktı dili: en." line. ea39b232 (en-US) and
-- 2f496b0a (en-GB) published every finding in Turkish, citing Turkish
-- regulation. analyze-v4 now carries an English prompt (v5-prompt-en.ts) with
-- no legal references, as every English safety profile requires
-- (regulatory_reference_policy = 'none').
--
-- The English prompt runs only when the route snapshot pins its hash, so this
-- key is what switches it on. The Turkish v5_prompt_sha256 is untouched.
-- Deploy analyze-v4 first; an older build ignores the key.
update private.analysis_v4_configs
set config = config || jsonb_build_object(
  'v5_prompt_en_version', 'v7-free-core-multidisciplinary-en-v1',
  'v5_prompt_en_sha256',
    '59f5a590e068627c4452d79d64bfb43bc1f065833a72a3ee2c7788ff707125f4'
), updated_at = now()
where is_active is true and engine_version = 'vnext-v4';
