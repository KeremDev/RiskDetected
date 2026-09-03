-- Locale-specific Android legal policy for the approved English global document set.
-- It is registered disabled, matching the Turkish policy's fail-closed rollout: operations can
-- enable it only after the Android build carrying the exact manifest is available to testers.

insert into public.app_feature_flags (key, value)
values (
  'android_legal_policy_en',
  jsonb_build_object(
    'schema_version', 1,
    'enabled', false,
    'document_set_id', 'en-global-v1',
    'manifest_checksum', '6b30e321170934890adbbbd747be09fb1f3c8959026cf8bb856d086901d8d704',
    'policy_version', 'android-legal-en-2026-07-31.1',
    'message_tr', 'Hukuki metinlerimiz güncellendi. Devam etmeden önce güncel metinleri inceleyin.',
    'message_en', 'Our legal documents have been updated. Review them before continuing.',
    'documents', jsonb_build_array(
      jsonb_build_object(
        'kind', 'terms',
        'version', 'terms-en-2026-07-31.1',
        'checksum', '49a9b3f164b9dc8048453be930509aa334a854834c2abfa0cd8b11fd67ef6efa',
        'change_type', 'material_terms'
      ),
      jsonb_build_object(
        'kind', 'privacy',
        'version', 'privacy-en-2026-07-31.1',
        'checksum', 'ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4',
        'change_type', 'material_privacy'
      ),
      jsonb_build_object(
        'kind', 'consent',
        'version', 'ai-data-en-2026-07-31.1',
        'checksum', 'a8c9873f57228a36a4ede597e33648ff9251f9c814f1d1afc3e912c82ae08e1b',
        'change_type', 'explicit_consent'
      )
    )
  )
)
on conflict (key) do nothing;
