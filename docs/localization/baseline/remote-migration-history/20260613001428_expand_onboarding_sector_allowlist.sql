-- Applied via local migration file 20260613031500_expand_onboarding_sector_allowlist.sql

alter table public.user_onboarding_answers
  drop constraint if exists user_onboarding_answers_sectors_check;

alter table public.user_onboarding_answers
  add constraint user_onboarding_answers_sectors_check
  check (
    sectors <@ array[
      'construction', 'manufacturing', 'energy', 'mining', 'office', 'other',
      'logistics_warehouse', 'chemical_laboratory', 'healthcare', 'food_production',
      'agriculture_livestock', 'retail', 'municipal_field_services', 'education', 'hospitality'
    ]::text[]
    and cardinality(sectors) <= 15
  );;
