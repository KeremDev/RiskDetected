begin;

select plan(10);

select is(
  (select value ->> 'enabled' from public.app_feature_flags where key = 'android_legal_policy'),
  'false',
  'Android legal-update gate is inert by default'
);

select is(
  (select value ->> 'document_set_id' from public.app_feature_flags where key = 'android_legal_policy'),
  'tr-android-v1',
  'Android policy targets only the Android Turkish document set'
);

select is(
  (select count(*)::integer from private.approved_legal_documents where document_set_id = 'tr-android-v1'),
  4,
  'owner-approved Android legal set is completely registered'
);

select is(
  (select count(*)::integer from private.approved_legal_documents
   where document_set_id = 'tr-android-v1'
     and reviewer_name = 'Kerem Kayalar'
     and approval_record_sha256 = '528210d9f74f23c05bd03b1b9444b590de75eef27e4c37daf6fa6617f87ab89d'),
  4,
  'all Android legal rows are bound to the explicit owner approval record'
);

select is(
  (select count(*)::integer from private.approved_legal_documents
   where document_set_id = 'tr-android-v1'
     and change_type in ('material_terms', 'material_privacy', 'explicit_consent')),
  4,
  'Android documents retain fail-closed material change classifications'
);

select is(
  (select count(*)::integer from private.approved_legal_documents where document_set_id = 'tr-current'),
  0,
  'migration does not add or replace an iOS Turkish registry row'
);

select is(
  (select count(*)::integer from private.approved_legal_documents where document_set_id = 'en-global-v1'),
  3,
  'existing English registry rows remain unchanged'
);

select is(
  (select jsonb_array_length(value -> 'documents') from public.app_feature_flags where key = 'android_legal_policy'),
  4,
  'public sanitized policy has the complete document set'
);

select is(
  (select value ->> 'manifest_checksum' from public.app_feature_flags where key = 'android_legal_policy'),
  'aaa169338de3d9425e76cc4d8b9e98047847934c39cf646cb4f87f708c63cfec',
  'disabled policy still exposes the sanitized bundle checksum for staging verification'
);

select throws_ok(
  $$
    insert into private.approved_legal_documents (
      document_set_id, document_locale, document_kind, version, document_checksum,
      change_type, reviewer_name, reviewer_qualification, reviewed_at,
      approval_record_sha256
    ) values (
      'unknown-set', 'tr', 'terms', 'bad-set-test', repeat('a', 64), 'info',
      'test', 'test', now(), repeat('b', 64)
    )
  $$,
  '23514',
  null,
  'approved document-set constraint stays fail-closed'
);

select * from finish();
rollback;
