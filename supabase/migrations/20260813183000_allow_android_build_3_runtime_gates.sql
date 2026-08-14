-- Admit the next Android closed-test build without changing any iOS flag or policy.
-- Build 2 remains valid for the testers already enrolled; every Android capability retains its
-- existing rollout mode and only gains build 3 in the explicit allowlist.

update public.app_feature_flags
set value = jsonb_set(
      jsonb_set(value, '{kill_switch}', 'false'::jsonb, true),
      '{enabled_android_version_codes}',
      '[2,3]'::jsonb,
      true
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

-- The plan/capability resolver and analyze/report snapshot gates use the shared
-- multi_photo_analysis allowlist rather than enabled_android_version_codes. Without this,
-- build 3 can enter the app but paid accounts are still fail-closed to one photo and cannot
-- edit AI findings. Preserve every existing Android build and only append build 3.
update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_android_builds}',
      case
        when coalesce(value -> 'enabled_android_builds', '[]'::jsonb) @> '["3"]'::jsonb
          then coalesce(value -> 'enabled_android_builds', '[]'::jsonb)
        else coalesce(value -> 'enabled_android_builds', '[]'::jsonb) || '["3"]'::jsonb
      end,
      true
    ),
    updated_at = now()
where key = 'multi_photo_analysis';

update public.app_feature_flags
set value = jsonb_set(
      jsonb_set(value, '{latest_build}', '3'::jsonb, true),
      '{policy_version}',
      to_jsonb('closed-test-1.5.1-vc3'::text),
      true
    ),
    updated_at = now()
where key = 'android_release_policy';
