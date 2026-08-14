-- Narrow legal document reads to the known public markdown manifest files.
-- This keeps app downloads working without allowing broad bucket listing.

drop policy if exists "Public read legal documents" on storage.objects;
create policy "Public read legal documents"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'legal-documents'
    and name in (
      'manifest.json',
      'tr/Kullanim-Kosullari.md',
      'tr/Gizlilik-Politikasi.md',
      'tr/KVKK-Aydinlatma-ve-Acik-Riza-Metni.md',
      'tr/Acik-Riza-Beyani.md'
    )
  );

select pg_notify('pgrst', 'reload schema');
