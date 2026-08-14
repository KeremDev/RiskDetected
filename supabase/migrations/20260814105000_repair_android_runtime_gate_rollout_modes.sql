-- Repair the live closed-test runtime gates created before rollout_mode was enabled for every
-- Android capability. This is deliberately Android-only: iOS policy and feature flags are not
-- read or modified here.

update public.app_feature_flags
set value = value || jsonb_build_object(
      'kill_switch', false,
      'rollout_mode', 'version_allowlist',
      'enabled_android_version_codes', jsonb_build_array(2, 3)
    ),
    updated_at = now()
where key in (
  'android_client_enabled',
  'android_auth_enabled',
  'android_analysis_submit_enabled',
  'android_payments_enabled',
  'android_notifications_enabled',
  'android_pdf_reports_enabled'
);
