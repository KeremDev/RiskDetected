begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(32);

select has_table(
  'private',
  'notification_template_localizations',
  '1 exact-locale notification child table exists'
);
select has_table(
  'private',
  'notification_localization_failures',
  '2 localization failure telemetry table exists'
);
select has_column(
  'private',
  'notification_template_localizations',
  'checksum',
  '3 localization checksum exists'
);
select has_trigger(
  'public',
  'reports',
  'reports_localization_snapshot_guard_v1',
  '4 reports derive immutable localization'
);
select has_trigger(
  'private',
  'notification_jobs',
  'notification_jobs_localization_guard_v1',
  '5 notification jobs resolve locale at creation'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.notification_template_localizations'::regclass
  ),
  '6 notification localizations have RLS'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'private.notification_template_localizations',
    'select'
  ),
  '7 authenticated cannot read private localized templates'
);
select ok(
  (
    select count(*) = 10
    from private.notification_template_localizations l
    join private.notification_templates t on t.id = l.template_id
    where t.key in (
        'first_analysis_reminder_v1',
        'inactivity_reminder_v1'
      )
      and l.locale in ('en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA')
      and l.review_status = 'approved'
      and l.reviewer_name = 'Kerem'
      and l.reviewer_qualification
        = 'İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.'
      and l.reviewed_copy_sha256
        = '5660f3a69595a0d8b80057fe2a5a0fb97c9393a003ff2bd72ad8208646955c87'
      and l.review_evidence_sha256
        = 'abfbf34bbfcd59e72ac06658ab84970d0429cc1d2020102d866ae48544921158'
      and l.checksum ~ '^[0-9a-f]{64}$'
  ),
  '8 owner-approved English notification copy is bound to review evidence'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '00000000-0000-4000-8000-000000000a01'::uuid,
    'delivery-gb@example.invalid',
    'authenticated',
    'authenticated',
    now(),
    now()
  ),
  (
    '00000000-0000-4000-8000-000000000a02'::uuid,
    'delivery-au@example.invalid',
    'authenticated',
    'authenticated',
    now(),
    now()
  );

insert into public.profiles (
  id,
  email,
  app_language,
  preferred_content_locale,
  work_jurisdiction_country,
  safety_profile_id,
  safety_profile_version,
  legal_document_set
)
values
  (
    '00000000-0000-4000-8000-000000000a01'::uuid,
    'delivery-gb@example.invalid',
    'en',
    'en-GB',
    'GB',
    'en-gb-generic-v1',
    1,
    'en-global-v1'
  ),
  (
    '00000000-0000-4000-8000-000000000a02'::uuid,
    'delivery-au@example.invalid',
    'en',
    'en-AU',
    'AU',
    'en-au-generic-v1',
    1,
    'en-global-v1'
  )
on conflict (id) do update
set
  email = excluded.email,
  app_language = excluded.app_language,
  preferred_content_locale = excluded.preferred_content_locale,
  work_jurisdiction_country = excluded.work_jurisdiction_country,
  safety_profile_id = excluded.safety_profile_id,
  safety_profile_version = excluded.safety_profile_version,
  legal_document_set = excluded.legal_document_set;

insert into public.analyses (
  id,
  user_id,
  kind,
  status,
  photo_count,
  primary_method,
  output_language,
  output_locale,
  work_jurisdiction_country,
  safety_profile_id,
  safety_profile_version,
  regulatory_reference_policy,
  prompt_profile_version,
  localization_snapshot
)
values (
  '00000000-0000-4000-8000-000000000a11'::uuid,
  '00000000-0000-4000-8000-000000000a01'::uuid,
  'photo',
  'completed',
  1,
  'fine_kinney',
  'en',
  'en-GB',
  'GB',
  'en-gb-generic-v1',
  1,
  'none',
  'isg-photo-policy-v2026-07-single-multi-targets',
  jsonb_build_object(
    'schema_version', 1,
    'output_language', 'en',
    'output_locale', 'en-GB',
    'work_jurisdiction_country', 'GB',
    'work_jurisdiction_region', null,
    'safety_profile_id', 'en-gb-generic-v1',
    'safety_profile_version', 1,
    'regulatory_reference_policy', 'none',
    'prompt_profile_version',
      'isg-photo-policy-v2026-07-single-multi-targets',
    'method', 'fine_kinney',
    'legal_document_set', 'en-global-v1',
    'legislation_canvas_enabled', false,
    'structured_regulatory_references_enabled', false,
    'manifest_version', 1,
    'manifest_source_sha256',
      '3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932',
    'source', 'explicit_request'
  )
);

select throws_ok(
  $$
    insert into public.reports (
      id, analysis_id, user_id, document_no, storage_path, method, file_name,
      report_language
    )
    values (
      '00000000-0000-4000-8000-000000000a21'::uuid,
      '00000000-0000-4000-8000-000000000a11'::uuid,
      '00000000-0000-4000-8000-000000000a01'::uuid,
      'L10N-DELIVERY-MISMATCH',
      'test/l10n-delivery-mismatch.pdf',
      'fine_kinney',
      'l10n-delivery-mismatch.pdf',
      'tr'
    )
  $$,
  '23514',
  'REPORT_LANGUAGE_MISMATCH',
  '9 mismatched report language fails closed'
);

select lives_ok(
  $$
    insert into public.reports (
      id, analysis_id, user_id, document_no, storage_path, method, file_name,
      report_language
    )
    values (
      '00000000-0000-4000-8000-000000000a22'::uuid,
      '00000000-0000-4000-8000-000000000a11'::uuid,
      '00000000-0000-4000-8000-000000000a01'::uuid,
      'L10N-DELIVERY-OK',
      'test/l10n-delivery-ok.pdf',
      'fine_kinney',
      'l10n-delivery-ok.pdf',
      'en'
    )
  $$,
  '10 matching report language is accepted'
);

select ok(
  (
    select report_language = 'en'
      and report_locale = 'en-GB'
      and safety_profile_id = 'en-gb-generic-v1'
      and not regulatory_sections_enabled
      and localization_snapshot ->> 'output_language' = 'en'
    from public.reports
    where id = '00000000-0000-4000-8000-000000000a22'::uuid
  ),
  '11 report metadata is copied from the analysis snapshot'
);

select throws_ok(
  $$
    update public.reports
    set report_locale = 'en-US'
    where id = '00000000-0000-4000-8000-000000000a22'::uuid
  $$,
  '23514',
  'REPORT_LOCALIZATION_SNAPSHOT_IMMUTABLE',
  '12 report localization cannot be changed later'
);

insert into private.notification_campaigns (
  id,
  name,
  template_id,
  title,
  body,
  destination
)
select
  '00000000-0000-4000-8000-000000000a31'::uuid,
  'Localization delivery test',
  t.id,
  'Ignored parent title',
  'Ignored parent body',
  'new_analysis'
from private.notification_templates t
where t.key = 'first_analysis_reminder_v1';

update private.notification_template_localizations l
set review_status = 'draft'
from private.notification_templates t
where t.id = l.template_id
  and t.key = 'first_analysis_reminder_v1'
  and l.locale = 'en-GB';

select lives_ok(
  $$
    insert into private.notification_jobs (
      id, user_id, campaign_id, template_id, kind, episode_key, dedupe_key,
      timezone, title, body, destination
    )
    select
      '00000000-0000-4000-8000-000000000a41'::uuid,
      '00000000-0000-4000-8000-000000000a01'::uuid,
      '00000000-0000-4000-8000-000000000a31'::uuid,
      t.id,
      'manual_app_reminder',
      'gb-draft',
      'delivery-gb-draft',
      'Europe/London',
      'Must not be delivered',
      'Must not be delivered',
      'new_analysis'
    from private.notification_templates t
    where t.key = 'first_analysis_reminder_v1'
  $$,
  '13 missing approved exact locale is persisted as failed'
);

select is(
  (
    select status
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000a41'::uuid
  ),
  'failed',
  '14 unapproved exact-locale copy blocks delivery'
);

select ok(
  exists (
    select 1
    from private.notification_localization_failures
    where job_id = '00000000-0000-4000-8000-000000000a41'::uuid
      and requested_locale = 'en-GB'
      and error_code = 'TEMPLATE_EXACT_LOCALE_MISSING'
  ),
  '15 blocked exact-locale resolution emits telemetry'
);

update private.notification_template_localizations l
set
  review_status = 'approved',
  reviewer_name = 'Kerem',
  reviewer_qualification
    = 'İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.',
  reviewed_copy_sha256
    = '5660f3a69595a0d8b80057fe2a5a0fb97c9393a003ff2bd72ad8208646955c87',
  review_evidence_sha256
    = 'abfbf34bbfcd59e72ac06658ab84970d0429cc1d2020102d866ae48544921158'
from private.notification_templates t
where t.id = l.template_id
  and t.key = 'first_analysis_reminder_v1'
  and l.locale = 'en-GB';

select lives_ok(
  $$
    insert into private.notification_jobs (
      id, user_id, campaign_id, template_id, kind, episode_key, dedupe_key,
      timezone, title, body, destination
    )
    select
      '00000000-0000-4000-8000-000000000a42'::uuid,
      '00000000-0000-4000-8000-000000000a01'::uuid,
      '00000000-0000-4000-8000-000000000a31'::uuid,
      t.id,
      'manual_app_reminder',
      'gb-approved',
      'delivery-gb-approved',
      'Europe/London',
      'Ignored',
      'Ignored',
      'new_analysis'
    from private.notification_templates t
    where t.key = 'first_analysis_reminder_v1'
  $$,
  '16 approved exact-locale job is created'
);

select ok(
  (
    select status = 'pending'
      and language = 'en'
      and locale = 'en-GB'
      and template_locale = 'en-GB'
      and template_localization_id is not null
      and title = 'Your first analysis is waiting'
      and localization_snapshot ->> 'content_mode'
        = 'exact_locale_template'
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000a42'::uuid
  ),
  '17 exact-locale content and immutable resolution are captured'
);

select throws_ok(
  $$
    update private.notification_jobs
    set title = 'Changed after resolution'
    where id = '00000000-0000-4000-8000-000000000a42'::uuid
  $$,
  '23514',
  'NOTIFICATION_LOCALIZATION_SNAPSHOT_IMMUTABLE',
  '18 resolved notification content is immutable'
);

update private.notification_template_localizations l
set review_status = 'draft'
from private.notification_templates t
where t.id = l.template_id
  and t.key = 'first_analysis_reminder_v1'
  and l.locale = 'en-AU';

insert into private.notification_jobs (
  id, user_id, campaign_id, template_id, kind, episode_key, dedupe_key,
  timezone, title, body, destination
)
select
  '00000000-0000-4000-8000-000000000a43'::uuid,
  '00000000-0000-4000-8000-000000000a02'::uuid,
  '00000000-0000-4000-8000-000000000a31'::uuid,
  t.id,
  'manual_app_reminder',
  'au-no-fallback',
  'delivery-au-no-fallback',
      'Australia/Sydney',
      'Must not use en-GB',
      'Must not use en-GB',
      'new_analysis'
from private.notification_templates t
where t.key = 'first_analysis_reminder_v1';

select ok(
  (
    select status = 'failed'
      and locale = 'en-AU'
      and template_localization_id is null
      and last_error_code = 'TEMPLATE_EXACT_LOCALE_MISSING'
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000a43'::uuid
  ),
  '19 resolver never falls back from missing en-AU to approved en-GB'
);

select has_column(
  'public',
  'consents',
  'legal_document_set',
  '20 consent audit stores the exact legal document set'
);
select has_column(
  'public',
  'consents',
  'legal_locale',
  '21 consent audit stores the exact legal locale'
);
select has_column(
  'public',
  'consents',
  'legal_set_manifest_checksum',
  '22 consent audit stores the legal-set checksum'
);
select has_column(
  'public',
  'legal_document_acknowledgements',
  'document_set_id',
  '23 document acknowledgement stores its set'
);
select has_column(
  'public',
  'legal_document_acknowledgements',
  'document_locale',
  '24 document acknowledgement stores its locale'
);
select has_column(
  'public',
  'legal_document_acknowledgements',
  'document_checksum',
  '25 document acknowledgement stores its checksum'
);

select has_table(
  'private',
  'approved_legal_documents',
  '26 approved legal document registry exists'
);
select ok(
  to_regprocedure(
    'public.acknowledge_legal_document_v1(text,text,text,text,text,text,text,text,text,text)'
  ) is not null,
  '27 server-authoritative legal acknowledgement RPC exists'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000a01',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select lives_ok(
  $$
    select public.acknowledge_legal_document_v1(
      'privacy',
      'privacy-en-2026-07-31.1',
      'material_privacy',
      'en-global-v1',
      'en',
      'ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4',
      'continued_use_accepted',
      'legal_update_notice',
      '1.3.0',
      'test-device'
    )
  $$,
  '28 exact approved legal acknowledgement succeeds'
);
select ok(
  (
    select document_set_id = 'en-global-v1'
      and document_locale = 'en'
      and change_type = 'material_privacy'
      and document_checksum
        = 'ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4'
      and seen_at is not null
      and continued_use_accepted_at is not null
    from public.legal_document_acknowledgements
    where user_id = '00000000-0000-4000-8000-000000000a01'::uuid
      and document_kind = 'privacy'
      and version = 'privacy-en-2026-07-31.1'
  ),
  '29 canonical legal metadata is persisted atomically'
);
select throws_ok(
  $$
    select public.acknowledge_legal_document_v1(
      'terms',
      'terms-en-2026-07-31.1',
      'material_terms',
      'en-global-v1',
      'en',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'continued_use_accepted',
      'legal_update_notice',
      '1.3.0',
      'test-device'
    )
  $$,
  '22023',
  'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_MISMATCH',
  '30 forged legal checksum is rejected'
);
select throws_ok(
  $$
    select public.acknowledge_legal_document_v1(
      'terms',
      'terms-en-2026-07-31.1',
      'info',
      'en-global-v1',
      'en',
      '49a9b3f164b9dc8048453be930509aa334a854834c2abfa0cd8b11fd67ef6efa',
      'continued_use_accepted',
      'legal_update_notice',
      '1.3.0',
      'test-device'
    )
  $$,
  '22023',
  'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_MISMATCH',
  '31 forged legal change type is rejected'
);
select throws_ok(
  $$
    insert into public.legal_document_acknowledgements (
      user_id,
      document_kind,
      version,
      change_type,
      document_set_id,
      document_locale,
      document_checksum,
      source
    )
    values (
      '00000000-0000-4000-8000-000000000a01'::uuid,
      'terms',
      'terms-en-2026-07-31.1',
      'material_terms',
      'en-global-v1',
      'en',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'direct_forgery'
    )
  $$,
  '22023',
  'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_MISMATCH',
  '32 direct canonical-version forgery is rejected by the trigger'
);

select * from extensions.finish();
rollback;
