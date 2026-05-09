-- Profile edit fields + persistent report logo storage.

alter table public.profiles
  add column if not exists full_name text,
  add column if not exists initials text,
  add column if not exists title text,
  add column if not exists certificate_number text,
  add column if not exists company_name text,
  add column if not exists company_logo_url text,
  add column if not exists phone text,
  add column if not exists preferred_method text;

alter table public.profiles enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant select, insert, update on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos', 'logos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users read own logo files" on storage.objects;
create policy "Users read own logo files"
  on storage.objects for select
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users insert own logo files" on storage.objects;
create policy "Users insert own logo files"
  on storage.objects for insert
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users update own logo files" on storage.objects;
create policy "Users update own logo files"
  on storage.objects for update
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users delete own logo files" on storage.objects;
create policy "Users delete own logo files"
  on storage.objects for delete
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );
