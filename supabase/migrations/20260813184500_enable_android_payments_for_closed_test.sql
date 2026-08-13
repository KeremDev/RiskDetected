-- Closed-test purchase validation requires the Android payment client to reach RevenueCat.
-- Keep the rollout explicitly restricted to the two enrolled Play builds; iOS is untouched.

update public.app_feature_flags
set value = jsonb_set(
      jsonb_set(
        jsonb_set(value, '{kill_switch}', 'false'::jsonb, true),
        '{rollout_mode}',
        to_jsonb('version_allowlist'::text),
        true
      ),
      '{enabled_android_version_codes}',
      '[2,3]'::jsonb,
      true
    ),
    updated_at = now()
where key = 'android_payments_enabled';
