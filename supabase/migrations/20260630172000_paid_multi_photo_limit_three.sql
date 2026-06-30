-- Product rule: paid plans support up to 3 photos per analysis.
-- This keeps multi-photo analysis enabled while bounding AI runtime and output
-- size consistently for iOS, backend capability checks, and prompts.

update public.app_feature_flags
set value =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(value, '{}'::jsonb),
          '{max_photo_count_plus}',
          '3'::jsonb,
          true
        ),
        '{max_photo_count_pro}',
        '3'::jsonb,
        true
      ),
      '{target_findings_total_max}',
      '39'::jsonb,
      true
    ),
    '{runtime_guard_note}',
    to_jsonb('Paid multi-photo product limit: Plus/Pro max 3 photos per analysis.'::text),
    true
  )
where key = 'multi_photo_analysis';

update public.plan_capability_rules
set max_photos_per_analysis = 3,
    visible_photo_slots_in_ui = 3,
    max_findings_per_photo = 13,
    max_findings_per_analysis = 39
where plan in ('plus', 'pro');

select pg_notify('pgrst', 'reload schema');
