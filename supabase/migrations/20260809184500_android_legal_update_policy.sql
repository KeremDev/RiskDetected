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
    'tr-android-v1', 'tr', 'terms', 'terms-android-2026-08-07',
    '0d55c5cb1257afea527a1fd49633fcbbdd3e561ef6d63c6739f6d9b372703db8',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-08T00:00:00Z'::timestamptz,
    '96b0d2f805f2eac6e46b8709d779a81e7e4d91874203f896f3dbe94a84811ee1'
  ),
  (
    'tr-android-v1', 'tr', 'privacy', 'privacy-android-2026-08-07',
    '72a4f78f1abbfb64c03b0a932cfe48a3bafe711a7aa1395fa1f0217cf58c44ce',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-08T00:00:00Z'::timestamptz,
    '96b0d2f805f2eac6e46b8709d779a81e7e4d91874203f896f3dbe94a84811ee1'
  ),
  (
    'tr-android-v1', 'tr', 'kvkk', 'kvkk-android-2026-08-07',
    'a60c019472990142f1ad0642678a7086f9459d5e583b97fa647a13b52575a730',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-08T00:00:00Z'::timestamptz,
    '96b0d2f805f2eac6e46b8709d779a81e7e4d91874203f896f3dbe94a84811ee1'
  ),
  (
    'tr-android-v1', 'tr', 'consent', 'consent-android-2026-08-07',
    '973932b929f6d58b78d63441f45d8b72c2877c3e7ae0177d458b47487d23677f',
    'info', 'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-08-08T00:00:00Z'::timestamptz,
    '96b0d2f805f2eac6e46b8709d779a81e7e4d91874203f896f3dbe94a84811ee1'
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
    'manifest_checksum', 'b56396d22e1d8ca03d8f402f619c7f694acc944a31cc0c592bb041547462f83b',
    'policy_version', 'android-legal-2026-08-07',
    'message_tr', 'Hukuki metinlerimiz güncellendi. Devam etmeden önce güncel metinleri inceleyin.',
    'documents', jsonb_build_array(
      jsonb_build_object(
        'kind', 'terms',
        'version', 'terms-android-2026-08-07',
        'checksum', '0d55c5cb1257afea527a1fd49633fcbbdd3e561ef6d63c6739f6d9b372703db8',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'privacy',
        'version', 'privacy-android-2026-08-07',
        'checksum', '72a4f78f1abbfb64c03b0a932cfe48a3bafe711a7aa1395fa1f0217cf58c44ce',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'kvkk',
        'version', 'kvkk-android-2026-08-07',
        'checksum', 'a60c019472990142f1ad0642678a7086f9459d5e583b97fa647a13b52575a730',
        'change_type', 'info'
      ),
      jsonb_build_object(
        'kind', 'consent',
        'version', 'consent-android-2026-08-07',
        'checksum', '973932b929f6d58b78d63441f45d8b72c2877c3e7ae0177d458b47487d23677f',
        'change_type', 'info'
      )
    )
  )
)
on conflict (key) do nothing;
