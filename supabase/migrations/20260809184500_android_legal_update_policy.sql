-- Android-only legal-update policy and acknowledgement registry.
--
-- This is additive and inert by default: app-release-policy reads the new flag only for
-- client_platform='android', and enabled=false means no Android build can be blocked until legal
-- operations explicitly publishes a later material policy. iOS keeps its existing document set,
-- release flag and acknowledgement behavior unchanged.

alter table private.approved_legal_documents
  drop constraint if exists approved_legal_documents_set_check;
alter table private.approved_legal_documents
  add constraint approved_legal_documents_set_check
  check (document_set_id in ('tr-current', 'en-global-v1', 'tr-android-v1'));

-- Do not register these documents in private.approved_legal_documents yet. The checked-in
-- approval record is deliberately pending until the public privacy/deletion URLs are verified
-- and the owner or qualified legal reviewer records a real decision. A follow-up migration must
-- insert the four approved rows from that signed record; fabricating reviewer metadata here would
-- make the release evidence misleading.

insert into public.app_feature_flags (key, value)
values (
  'android_legal_policy',
  jsonb_build_object(
    'schema_version', 1,
    'enabled', false,
    'document_set_id', 'tr-android-v1',
    'manifest_checksum', 'aaa169338de3d9425e76cc4d8b9e98047847934c39cf646cb4f87f708c63cfec',
    'policy_version', 'android-legal-2026-08-09',
    'message_tr', 'Hukuki metinlerimiz güncellendi. Devam etmeden önce güncel metinleri inceleyin.',
    'documents', jsonb_build_array(
      jsonb_build_object(
        'kind', 'terms',
        'version', 'terms-android-2026-08-09',
        'checksum', 'aebbb01c27012192ddf36669b73036889fe8d1f4266a08326aa96e248829e749',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'privacy',
        'version', 'privacy-android-2026-08-09',
        'checksum', 'ac811bcf95946e4251ebdbf3d2bd71622e94e3753fc0ca68b1fbaeccb9817672',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'kvkk',
        'version', 'kvkk-android-2026-08-09',
        'checksum', '7cf16880546a414df03202ea1fd09ff0d7aafa48c9f1adb89f62d897741bb297',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'consent',
        'version', 'consent-android-2026-08-09',
        'checksum', '53b380da568e67d6d7406f2a8bad0787b45ddcd2fdf0485f1aaec8f3e517a5c2',
        'change_type', 'info'
      )
    )
  )
)
on conflict (key) do nothing;
