-- Consolidate duplicate permissive profile policies without changing the mobile ownership rule.
-- Both iOS and Android remain able to select/update only auth.uid() = profiles.id; authenticated
-- insert is preserved for the existing profile recovery/upsert path.

alter table public.profiles enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists "Users update own profile" on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists "Users insert own profile" on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy profiles_insert_own
  on public.profiles
  for insert
  to authenticated
  with check ((select auth.uid()) = id);

revoke all on public.profiles from anon;

select pg_notify('pgrst', 'reload schema');
