
-- Storage bucket'ları
-- photos: kullanıcı analiz fotoğrafları (private)
-- reports: PDF/Excel raporları (private)
-- logos: kullanıcı firma logoları (private — Pro)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('photos',  'photos',  false, 20971520,  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']),
  ('reports', 'reports', false, 20971520,  array['application/pdf', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']),
  ('logos',   'logos',   false, 5242880,   array['image/jpeg', 'image/png', 'image/svg+xml'])
on conflict (id) do nothing;

-- Storage policies — bucket içinde {user_id}/... pattern'i
-- Photos
create policy photos_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy photos_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy photos_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy photos_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Reports
create policy reports_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);

create policy reports_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);

create policy reports_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);

-- Logos
create policy logos_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy logos_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy logos_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy logos_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);
;
