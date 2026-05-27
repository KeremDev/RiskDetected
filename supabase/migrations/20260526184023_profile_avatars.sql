-- User profile avatar storage.

alter table public.profiles
  add column if not exists avatar_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 3145728, array['image/jpeg'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users read own avatar files" on storage.objects;
create policy "Users read own avatar files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users insert own avatar files" on storage.objects;
create policy "Users insert own avatar files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users update own avatar files" on storage.objects;
create policy "Users update own avatar files"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

drop policy if exists "Users delete own avatar files" on storage.objects;
create policy "Users delete own avatar files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = auth.uid()::text
  );

alter table public.account_deletion_requests
  add column if not exists deleted_avatar_objects int not null default 0;
