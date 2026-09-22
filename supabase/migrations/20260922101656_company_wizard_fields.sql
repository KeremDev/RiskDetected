-- Company wizard fields are optional so existing records remain valid.
alter table public.companies
  add column if not exists city text,
  add column if not exists phone text,
  add column if not exists nace_code text,
  add column if not exists workplace_registry_no text,
  add column if not exists workplace_profile jsonb not null default '{}'::jsonb,
  add column if not exists responsible_contacts jsonb not null default '[]'::jsonb;
