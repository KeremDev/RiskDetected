-- Enable the compact single-photo 12-layer schema and evidence guard together.
-- The existing 6144 single-photo thinking budget and all multi-photo settings stay unchanged.

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(
      coalesce(value, '{}'::jsonb),
      '{single_photo_compact_layer_schema_enabled}',
      'true'::jsonb,
      true
    ),
    '{single_photo_evidence_guard_enabled}',
    'true'::jsonb,
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';
