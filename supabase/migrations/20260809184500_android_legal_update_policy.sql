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

insert into private.approved_legal_documents (
  document_set_id,
  document_locale,
  document_kind,
  version,
  document_checksum,
  change_type,
  reviewer_name,
  reviewer_qualification,
  reviewed_at,
  approval_record_sha256
)
values
  (
    'tr-android-v1', 'tr', 'terms', 'terms-android-2026-08-09',
    'aebbb01c27012192ddf36669b73036889fe8d1f4266a08326aa96e248829e749',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-09T00:00:00Z'::timestamptz,
    'd8e66c879b7cd5019706790b323f495740b3ba84fbbe8b995b0124e431fae7dc'
  ),
  (
    'tr-android-v1', 'tr', 'privacy', 'privacy-android-2026-08-09',
    'ac811bcf95946e4251ebdbf3d2bd71622e94e3753fc0ca68b1fbaeccb9817672',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-09T00:00:00Z'::timestamptz,
    'd8e66c879b7cd5019706790b323f495740b3ba84fbbe8b995b0124e431fae7dc'
  ),
  (
    'tr-android-v1', 'tr', 'kvkk', 'kvkk-android-2026-08-09',
    '7cf16880546a414df03202ea1fd09ff0d7aafa48c9f1adb89f62d897741bb297',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-09T00:00:00Z'::timestamptz,
    'd8e66c879b7cd5019706790b323f495740b3ba84fbbe8b995b0124e431fae7dc'
  ),
  (
    'tr-android-v1', 'tr', 'consent', 'consent-android-2026-08-09',
    '53b380da568e67d6d7406f2a8bad0787b45ddcd2fdf0485f1aaec8f3e517a5c2',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-09T00:00:00Z'::timestamptz,
    'd8e66c879b7cd5019706790b323f495740b3ba84fbbe8b995b0124e431fae7dc'
  )
on conflict (document_set_id, document_locale, document_kind, version)
do update set
  document_checksum = excluded.document_checksum,
  change_type = excluded.change_type,
  reviewer_name = excluded.reviewer_name,
  reviewer_qualification = excluded.reviewer_qualification,
  reviewed_at = excluded.reviewed_at,
  approval_record_sha256 = excluded.approval_record_sha256;

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
