alter table public.analysis_photo_summaries
  add column if not exists coverage_status text,
  add column if not exists coverage_gap_reason text,
  add column if not exists target_findings_min integer,
  add column if not exists target_findings_max integer;

update public.app_feature_flags
set value = jsonb_set(
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(
              value,
              '{features,multi_photo_coverage_v2}',
              'true'::jsonb,
              true
            ),
            '{enable_multi_photo_coverage_v2}',
            'false'::jsonb,
            true
          ),
          '{target_findings_per_photo_min}',
          '5'::jsonb,
          true
        ),
        '{target_findings_per_photo_max}',
        '8'::jsonb,
        true
      ),
      '{target_findings_total_max}',
      '40'::jsonb,
      true
    ),
    '{coverage_repair_enabled}',
    'true'::jsonb,
    true
  ),
  '{coverage_rollout_note}',
  to_jsonb('Requires client_capabilities.multi_photo_coverage_v2=true; legacy builds stay on hazards[] flow.'::text),
  true
)
where key = 'multi_photo_analysis';
