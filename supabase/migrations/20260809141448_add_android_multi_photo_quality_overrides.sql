-- Add Android-only quality rollout controls without changing any iOS key or value. Empty/null
-- defaults are deliberately closed; staging may opt a versionCode in independently while the
-- production row remains inert until the Android canary starts.
update public.app_feature_flags
set value = value || jsonb_build_object(
  'multi_photo_layer_audit_enabled_android_builds',
    coalesce(value -> 'multi_photo_layer_audit_enabled_android_builds', '[]'::jsonb),
  'multi_photo_layer_audit_min_android_build',
    coalesce(value -> 'multi_photo_layer_audit_min_android_build', 'null'::jsonb),
  'multi_photo_thinking_budget_android_build_overrides',
    coalesce(value -> 'multi_photo_thinking_budget_android_build_overrides', '{}'::jsonb),
  'multi_photo_thinking_budget_min_android_build',
    coalesce(value -> 'multi_photo_thinking_budget_min_android_build', 'null'::jsonb),
  'multi_photo_thinking_budget_min_android_build_value',
    coalesce(value -> 'multi_photo_thinking_budget_min_android_build_value', 'null'::jsonb)
)
where key = 'multi_photo_analysis';
