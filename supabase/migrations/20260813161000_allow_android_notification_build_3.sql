-- Keep the already-submitted build 2 enabled while admitting the parity build 3.
update public.app_feature_flags
set value = jsonb_set(
      jsonb_set(value, '{kill_switch}', 'false'::jsonb, true),
      '{enabled_android_version_codes}',
      '[2,3]'::jsonb,
      true
    ),
    updated_at = now()
where key = 'android_notifications_enabled';
