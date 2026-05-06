-- User legal consent records.
-- One row per accepted legal version set. This intentionally keeps history.

create table if not exists public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kvkk_version text not null,
  terms_version text not null,
  explicit_consent_version text not null default '',
  accepted_at timestamptz not null default now(),
  source text not null default 'first_analysis',
  app_version text,
  device_id text,
  created_at timestamptz not null default now(),
  unique (
    user_id,
    kvkk_version,
    terms_version,
    explicit_consent_version
  )
);

alter table public.consents enable row level security;

drop policy if exists "Users read own consents" on public.consents;
create policy "Users read own consents"
  on public.consents for select
  to authenticated
  using (auth.uid() is not null and auth.uid() = user_id);

drop policy if exists "Users insert own consents" on public.consents;
create policy "Users insert own consents"
  on public.consents for insert
  to authenticated
  with check (auth.uid() is not null and auth.uid() = user_id);

revoke all on public.consents from anon;
revoke all on public.consents from authenticated;
grant select, insert on public.consents to authenticated;

create index if not exists consents_user_accepted
  on public.consents (user_id, accepted_at desc);

select pg_notify('pgrst', 'reload schema');
