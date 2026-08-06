-- Enable the one-pass 12-layer audit for single-photo analyses only.
-- Multi-photo remains on the legacy schema until live single-photo metrics pass.

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(value, '{}'::jsonb),
          '{single_photo_layer_audit_enabled}',
          'true'::jsonb,
          true
        ),
        '{multi_photo_layer_audit_enabled}',
        'false'::jsonb,
        true
      ),
      '{single_photo_thinking_budget}',
      '6144'::jsonb,
      true
    ),
    '{multi_photo_thinking_budget}',
    '3072'::jsonb,
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';
