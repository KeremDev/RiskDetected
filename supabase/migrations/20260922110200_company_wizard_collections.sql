alter table public.companies
  add column if not exists workplace_profiles jsonb not null default '[]'::jsonb,
  add column if not exists departments jsonb not null default '[]'::jsonb;
