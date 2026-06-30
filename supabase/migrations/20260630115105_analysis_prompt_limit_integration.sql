-- Analysis prompt/limit integration.
-- Expand-only: adds verification metadata and raises photo finding limits
-- for build-gated clients without enabling legacy flat feature flags.

alter table public.findings
  add column if not exists needs_field_verification boolean not null default false;

update public.plan_capability_rules
set max_findings_per_photo = 13,
    max_findings_per_analysis = 65,
    updated_at = now()
where plan in ('plus', 'pro');

update public.app_feature_flags
set value = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          value,
          '{target_findings_per_photo_min}',
          '9'::jsonb,
          true
        ),
        '{target_findings_per_photo_max}',
        '13'::jsonb,
        true
      ),
      '{target_findings_total_max}',
      '65'::jsonb,
      true
    ),
    '{max_findings_per_photo}',
    '13'::jsonb,
    true
  ),
  updated_at = now()
where key = 'multi_photo_analysis';
