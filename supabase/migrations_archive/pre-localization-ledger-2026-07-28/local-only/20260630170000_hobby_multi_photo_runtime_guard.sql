-- Temporary runtime guard for build 74 on Supabase Hobby.
-- Keep paid multi-photo enabled, but cap the selectable count to 2 until the
-- long-running worker runs on infrastructure that can reliably handle 5 photos.

update public.app_feature_flags
set value =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(value, '{}'::jsonb),
        '{max_photo_count_plus}',
        '2'::jsonb,
        true
      ),
      '{max_photo_count_pro}',
      '2'::jsonb,
      true
    ),
    '{runtime_guard_note}',
    to_jsonb('Build 74 Hobby runtime guard: paid multi-photo capped at 2 until long-running analysis worker capacity is upgraded.'::text),
    true
  )
where key = 'multi_photo_analysis';

select pg_notify('pgrst', 'reload schema');
