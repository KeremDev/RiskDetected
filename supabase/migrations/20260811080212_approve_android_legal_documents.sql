-- Owner-approved Android Turkish legal document set.
-- Registration is additive and intentionally does not enable android_legal_policy;
-- acknowledgement enforcement remains controlled by the Android-only runtime gate.

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
    'material_terms', 'Kerem Kayalar',
    'Ürün sahibi ve yetkili karar verici; bağımsız hukuk danışmanlığı değildir.',
    '2026-08-11T08:02:12Z'::timestamptz,
    '528210d9f74f23c05bd03b1b9444b590de75eef27e4c37daf6fa6617f87ab89d'
  ),
  (
    'tr-android-v1', 'tr', 'privacy', 'privacy-android-2026-08-09',
    'ac811bcf95946e4251ebdbf3d2bd71622e94e3753fc0ca68b1fbaeccb9817672',
    'material_privacy', 'Kerem Kayalar',
    'Ürün sahibi ve yetkili karar verici; bağımsız hukuk danışmanlığı değildir.',
    '2026-08-11T08:02:12Z'::timestamptz,
    '528210d9f74f23c05bd03b1b9444b590de75eef27e4c37daf6fa6617f87ab89d'
  ),
  (
    'tr-android-v1', 'tr', 'kvkk', 'kvkk-android-2026-08-09',
    '7cf16880546a414df03202ea1fd09ff0d7aafa48c9f1adb89f62d897741bb297',
    'material_privacy', 'Kerem Kayalar',
    'Ürün sahibi ve yetkili karar verici; bağımsız hukuk danışmanlığı değildir.',
    '2026-08-11T08:02:12Z'::timestamptz,
    '528210d9f74f23c05bd03b1b9444b590de75eef27e4c37daf6fa6617f87ab89d'
  ),
  (
    'tr-android-v1', 'tr', 'consent', 'consent-android-2026-08-09',
    '53b380da568e67d6d7406f2a8bad0787b45ddcd2fdf0485f1aaec8f3e517a5c2',
    'explicit_consent', 'Kerem Kayalar',
    'Ürün sahibi ve yetkili karar verici; bağımsız hukuk danışmanlığı değildir.',
    '2026-08-11T08:02:12Z'::timestamptz,
    '528210d9f74f23c05bd03b1b9444b590de75eef27e4c37daf6fa6617f87ab89d'
  )
on conflict (document_set_id, document_locale, document_kind, version)
do update set
  document_checksum = excluded.document_checksum,
  change_type = excluded.change_type,
  reviewer_name = excluded.reviewer_name,
  reviewer_qualification = excluded.reviewer_qualification,
  reviewed_at = excluded.reviewed_at,
  approval_record_sha256 = excluded.approval_record_sha256;
