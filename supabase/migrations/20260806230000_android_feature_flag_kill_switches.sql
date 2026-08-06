-- ADR-005 (master plan): multi-layered Android kill switch — no single "Android on" flag.
-- This is the piece the owner asked for directly: a mechanism so that deploying Android-
-- enablement backend code (F1-F4, E8 already deployed-ready) carries zero live-user risk
-- independent of *when* it's deployed, because every Android capability stays closed at the
-- flag layer until explicitly turned on later, one capability at a time.
--
-- These rows are inert on their own — nothing in analyze/app-release-policy/etc. reads them
-- yet (that wiring happens per-feature as each Faz 3+ capability actually ships). They exist
-- now so the *pattern* is established before any Android client code exists to need it, per
-- Bölüm D of the plan (contracts/flags come before implementation, not after).

insert into public.app_feature_flags (key, value) values
  ('android_client_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null,
    'note', 'Master switch: no Android client may treat itself as authorized to operate until this is on. Every other android_* flag below is meaningless while this is off.'
  )),
  ('android_auth_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null
  )),
  ('android_analysis_submit_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null
  )),
  ('android_payments_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null
  )),
  ('android_notifications_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null
  )),
  ('android_pdf_reports_enabled', jsonb_build_object(
    'kill_switch', true,
    'rollout_mode', 'off',
    'enabled_android_version_codes', jsonb_build_array(),
    'min_android_version_code', null
  )),
  ('android_release_policy', jsonb_build_object(
    'minimum_supported_build', 1,
    'latest_build', 1,
    'hard_update_enabled', false,
    'soft_update_enabled', false,
    'app_store_url', '',
    'message_tr', 'Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.',
    'message_en', 'A new version is available. Please update the app to continue.',
    'policy_version', 'pending-play-listing'
  ))
on conflict (key) do nothing;
