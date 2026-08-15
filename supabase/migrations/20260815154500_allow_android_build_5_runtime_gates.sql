-- Admit the next Android closed-test build without changing iOS runtime flags.
-- Keep the active closed-test builds available so testers can update normally.

update public.app_feature_flags
set value = value || jsonb_build_object(
      'kill_switch', false,
      'rollout_mode', 'version_allowlist',
      'enabled_android_version_codes', jsonb_build_array(2, 3, 4, 5)
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

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_android_builds}',
      (
        select jsonb_agg(build_number order by build_number::integer)
        from (
          select distinct build_number
          from jsonb_array_elements_text(
            coalesce(value -> 'enabled_android_builds', '[]'::jsonb)
          ) as existing(build_number)
          where build_number ~ '^[0-9]+$'
          union
          select '4'
          union
          select '5'
        ) as allowed
      ),
      true
    ),
    updated_at = now()
where key = 'multi_photo_analysis';

update public.app_feature_flags
set value = jsonb_set(
      jsonb_set(value, '{latest_build}', '5'::jsonb, true),
      '{policy_version}',
      to_jsonb('closed-test-1.5.3-vc5'::text),
      true
    ),
    updated_at = now()
where key = 'android_release_policy';
