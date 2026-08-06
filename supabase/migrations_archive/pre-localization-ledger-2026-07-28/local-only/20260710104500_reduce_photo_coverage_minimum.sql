-- Quality guard: avoid forcing the model to pad reports with weak duplicates.
-- The analyze function now treats this as a soft audit/fallback value, not a
-- minimum number of findings to generate.

update public.app_feature_flags
set value = jsonb_set(
    value,
    '{target_findings_per_photo_min}',
    '1'::jsonb,
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';
