begin;

select plan(9);

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
  'all four Android legal documents are registered'
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

select ok(
  (select bool_and(document_checksum ~ '^[0-9a-f]{64}$') from private.approved_legal_documents where document_set_id = 'tr-android-v1'),
  'Android registry uses valid SHA-256 document checksums'
);

select is(
  (select jsonb_array_length(value -> 'documents') from public.app_feature_flags where key = 'android_legal_policy'),
  4,
  'public sanitized policy has the complete document set'
);

select is(
  (
    select count(*)::integer
    from private.approved_legal_documents
    where document_set_id = 'tr-android-v1'
      and change_type = 'info'
  ),
  4,
  'baseline Android documents do not create a material blocking decision'
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
