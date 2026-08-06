begin;

create extension if not exists pgtap with schema extensions;

select plan(88);

select has_column('public', 'profiles', 'app_language', 'profiles app language exists');
select has_column('public', 'profiles', 'preferred_content_locale', 'profiles content locale exists');
select has_column('public', 'profiles', 'work_jurisdiction_country', 'profiles country exists');
select has_column('public', 'profiles', 'work_jurisdiction_region', 'profiles region exists');
select has_column('public', 'profiles', 'safety_profile_id', 'profiles safety profile exists');
select has_column('public', 'profiles', 'safety_profile_version', 'profiles safety profile version exists');
select has_column('public', 'profiles', 'legal_document_set', 'profiles legal set exists');

select has_column('public', 'analyses', 'output_language', 'analyses output language exists');
select has_column('public', 'analyses', 'output_locale', 'analyses output locale exists');
select has_column('public', 'analyses', 'work_jurisdiction_country', 'analyses country exists');
select has_column('public', 'analyses', 'work_jurisdiction_region', 'analyses region exists');
select has_column('public', 'analyses', 'safety_profile_id', 'analyses safety profile exists');
select has_column('public', 'analyses', 'safety_profile_version', 'analyses safety profile version exists');
select has_column('public', 'analyses', 'regulatory_reference_policy', 'analyses regulatory policy exists');
select has_column('public', 'analyses', 'prompt_profile_version', 'analyses prompt profile version exists');
select has_column('public', 'analyses', 'localization_snapshot', 'analyses localization snapshot exists');
select has_column('public', 'analyses', 'language_validation_status', 'analyses language validation status exists');
select has_column('public', 'analyses', 'language_validation_attempts', 'analyses language validation attempts exists');
select has_column('public', 'analyses', 'language_validation_code', 'analyses language validation code exists');

select has_column('public', 'reports', 'report_language', 'reports language exists');
select has_column('public', 'reports', 'report_locale', 'reports locale exists');
select has_column('public', 'reports', 'safety_profile_id', 'reports safety profile exists');
select has_column('public', 'reports', 'safety_profile_version', 'reports safety profile version exists');
select has_column('public', 'reports', 'regulatory_sections_enabled', 'reports regulatory switch exists');
select has_column('public', 'reports', 'localization_snapshot', 'reports localization snapshot exists');

select has_column('public', 'ai_usage_logs', 'output_language', 'usage output language exists');
select has_column('public', 'ai_usage_logs', 'output_locale', 'usage output locale exists');
select has_column('public', 'ai_usage_logs', 'work_jurisdiction_country', 'usage country exists');
select has_column('public', 'ai_usage_logs', 'safety_profile_id', 'usage safety profile exists');
select has_column('public', 'ai_usage_logs', 'language_validation_status', 'usage language validation status exists');
select has_column('public', 'ai_usage_logs', 'language_validation_attempts', 'usage language validation attempts exists');
select has_column('public', 'ai_usage_logs', 'language_validation_code', 'usage language validation code exists');

select has_column('public', 'notification_events', 'language', 'notification event language exists');
select has_column('public', 'notification_events', 'locale', 'notification event locale exists');
select has_column('public', 'notification_events', 'localization_snapshot', 'notification event snapshot exists');
select has_column('public', 'notification_events', 'template_locale', 'notification event template locale exists');
select has_column('public', 'notification_events', 'template_localization_id', 'notification event template localization exists');

select has_column('private', 'notification_jobs', 'language', 'notification job language exists');
select has_column('private', 'notification_jobs', 'locale', 'notification job locale exists');
select has_column('private', 'notification_jobs', 'localization_snapshot', 'notification job snapshot exists');
select has_column('private', 'notification_jobs', 'template_locale', 'notification job template locale exists');
select has_column('private', 'notification_jobs', 'template_localization_id', 'notification job template localization exists');

select has_column('public', 'support_requests', 'app_language', 'support app language exists');
select has_column('public', 'support_requests', 'content_locale', 'support content locale exists');
select has_column('public', 'support_requests', 'user_message_language', 'support message language exists');
select has_column('public', 'support_requests', 'preferred_response_language', 'support response language exists');

select has_function(
  'private',
  'enforce_analysis_localization_snapshot_v1',
  array[]::text[],
  'analysis localization immutability function exists'
);
select has_trigger(
  'public',
  'analyses',
  'analyses_localization_snapshot_guard_v1',
  'analysis localization immutability trigger exists'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_localization_snapshot_shape_check'
  ),
  'analysis snapshot shape constraint exists'
);

select ok((select relrowsecurity from pg_class where oid = 'public.analyses'::regclass), 'analyses RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'profiles RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.reports'::regclass), 'reports RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.ai_usage_logs'::regclass), 'usage logs RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.notification_events'::regclass), 'notification events RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.support_requests'::regclass), 'support requests RLS remains enabled');
select ok((select relrowsecurity from pg_class where oid = 'private.notification_jobs'::regclass), 'private notification jobs RLS remains enabled');
select ok(
  not has_table_privilege('anon', 'private.notification_jobs', 'select'),
  'anon cannot read private notification jobs'
);

select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'global_localization_wave1'), 'off', 'global localization starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'safety_profile_en_intl_enabled'), 'off', 'international profile starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'safety_profile_en_gb_enabled'), 'off', 'UK profile starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'safety_profile_en_us_enabled'), 'off', 'US profile starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'safety_profile_en_au_enabled'), 'off', 'AU profile starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'safety_profile_en_ca_enabled'), 'off', 'CA profile starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'localization_queue_payload_v1'), 'off', 'queue snapshot transition starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'ai_language_guard_enabled'), 'off', 'AI language guard starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'ai_country_term_guard_enabled'), 'off', 'AI country guard starts off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'english_report_enabled'), 'off', 'English reports start off');
select is((select value->>'rollout_mode' from public.app_feature_flags where key = 'english_notifications_enabled'), 'off', 'English notifications start off');

select is((select max_photos_per_analysis from public.plan_capability_rules where plan = 'plus'), 3, 'Plus photo limit matches attested production');
select is((select max_findings_per_analysis from public.plan_capability_rules where plan = 'pro'), 39, 'Pro finding limit matches attested production');
select is(
  (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'analyses' and column_name = 'localization_snapshot'),
  'YES',
  'analysis snapshot remains nullable during dual-read'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000901'::uuid,
  'localization-phase2@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.profiles (id, email)
values (
  '00000000-0000-4000-8000-000000000901'::uuid,
  'localization-phase2@example.invalid'
)
on conflict (id) do update
set
  app_language = null,
  preferred_content_locale = null,
  work_jurisdiction_country = null,
  work_jurisdiction_region = null,
  safety_profile_id = null,
  safety_profile_version = null,
  legal_document_set = null;

insert into public.analyses (id, user_id, kind, status, photo_count)
values (
  '00000000-0000-4000-8000-000000000902'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'photo',
  'pending',
  1
);

-- Recreate a pre-delivery legacy row so the context migration's bounded
-- backfill remains testable even though the later strict report guard is
-- present in a full-schema local reset.
alter table public.reports
  disable trigger reports_localization_snapshot_guard_v1;

insert into public.reports (
  id, analysis_id, user_id, document_no, storage_path, method, file_name
)
values (
  '00000000-0000-4000-8000-000000000903'::uuid,
  '00000000-0000-4000-8000-000000000902'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'L10N-TEST-1',
  'test/localization-phase2.pdf',
  'fine_kinney',
  'localization-phase2.pdf'
);

alter table public.reports
  enable trigger reports_localization_snapshot_guard_v1;

insert into public.ai_usage_logs (id, analysis_id, user_id, model)
values (
  '00000000-0000-4000-8000-000000000904'::uuid,
  '00000000-0000-4000-8000-000000000902'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'localization-test-model'
);

insert into public.notification_events (id, user_id, kind, title, body)
values (
  '00000000-0000-4000-8000-000000000905'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'analysis_complete',
  'Test',
  'Test'
);

insert into private.notification_campaigns (
  id, name, title, body, created_by
)
values (
  '00000000-0000-4000-8000-000000000906'::uuid,
  'localization-test',
  'Test',
  'Test',
  '00000000-0000-4000-8000-000000000901'::uuid
);

insert into private.notification_jobs (
  id, user_id, campaign_id, kind, episode_key, dedupe_key,
  timezone, title, body, destination
)
values (
  '00000000-0000-4000-8000-000000000907'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  '00000000-0000-4000-8000-000000000906'::uuid,
  'manual_app_reminder',
  'localization-test',
  'localization-test-000000000907',
  'Europe/Istanbul',
  'Test',
  'Test',
  'home'
);

insert into public.support_requests (
  id, user_id, support_id, subject, message
)
values (
  '00000000-0000-4000-8000-000000000908'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'L10N-TEST-000908',
  'Test',
  'User-authored message'
);

-- The migration replay itself is covered by run_localization_phase6_pgtap.mjs.
-- `supabase test db` streams this test into its database container, so a psql
-- \ir reference to a host migration file is not portable. Exercise the same
-- coalescing behavior against this transaction-scoped legacy fixture instead.
alter table private.notification_jobs
  disable trigger notification_jobs_localization_guard_v1;

update public.profiles
set
  app_language = coalesce(app_language, 'tr'),
  preferred_content_locale = coalesce(preferred_content_locale, 'tr-TR'),
  work_jurisdiction_country = coalesce(work_jurisdiction_country, 'TR'),
  safety_profile_id = coalesce(safety_profile_id, 'tr-tr-current-v1'),
  safety_profile_version = coalesce(safety_profile_version, 1),
  legal_document_set = coalesce(legal_document_set, 'tr-current')
where id = '00000000-0000-4000-8000-000000000901'::uuid;

update public.analyses
set
  output_language = coalesce(output_language, 'tr'),
  output_locale = coalesce(output_locale, 'tr-TR'),
  work_jurisdiction_country = coalesce(work_jurisdiction_country, 'TR'),
  safety_profile_id = coalesce(safety_profile_id, 'tr-tr-current-v1'),
  safety_profile_version = coalesce(safety_profile_version, 1),
  regulatory_reference_policy =
    coalesce(regulatory_reference_policy, 'tr_current'),
  prompt_profile_version = coalesce(
    prompt_profile_version,
    'isg-photo-policy-v2026-07-single-multi-targets'
  ),
  localization_snapshot = coalesce(
    localization_snapshot,
    jsonb_build_object(
      'schema_version', 1,
      'output_language', 'tr',
      'output_locale', 'tr-TR',
      'work_jurisdiction_country', 'TR',
      'work_jurisdiction_region', null,
      'safety_profile_id', 'tr-tr-current-v1',
      'safety_profile_version', 1,
      'regulatory_reference_policy', 'tr_current',
      'prompt_profile_version',
        'isg-photo-policy-v2026-07-single-multi-targets',
      'method', primary_method::text,
      'legal_document_set', 'tr-current',
      'legislation_canvas_enabled', true,
      'structured_regulatory_references_enabled', true,
      'manifest_version', 1,
      'manifest_source_sha256',
        '3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932',
      'source', 'legacy_tr_backfill'
    )
  ),
  language_validation_status =
    coalesce(language_validation_status, 'legacy_assumed'),
  language_validation_attempts = coalesce(language_validation_attempts, 0),
  language_validation_code =
    coalesce(language_validation_code, 'legacy_tr_backfill')
where id = '00000000-0000-4000-8000-000000000902'::uuid;

update public.reports r
set
  report_language = coalesce(r.report_language, 'tr'),
  report_locale = coalesce(r.report_locale, 'tr-TR'),
  safety_profile_id = coalesce(r.safety_profile_id, 'tr-tr-current-v1'),
  safety_profile_version = coalesce(r.safety_profile_version, 1),
  regulatory_sections_enabled =
    coalesce(r.regulatory_sections_enabled, true),
  localization_snapshot =
    coalesce(r.localization_snapshot, a.localization_snapshot)
from public.analyses a
where r.id = '00000000-0000-4000-8000-000000000903'::uuid
  and a.id = r.analysis_id;

update public.ai_usage_logs l
set
  output_language = coalesce(l.output_language, a.output_language, 'tr'),
  output_locale = coalesce(l.output_locale, a.output_locale, 'tr-TR'),
  work_jurisdiction_country = coalesce(
    l.work_jurisdiction_country,
    a.work_jurisdiction_country,
    'TR'
  ),
  safety_profile_id = coalesce(
    l.safety_profile_id,
    a.safety_profile_id,
    'tr-tr-current-v1'
  ),
  language_validation_status =
    coalesce(l.language_validation_status, 'legacy_assumed'),
  language_validation_attempts =
    coalesce(l.language_validation_attempts, 0),
  language_validation_code =
    coalesce(l.language_validation_code, 'legacy_tr_backfill')
from public.analyses a
where l.id = '00000000-0000-4000-8000-000000000904'::uuid
  and a.id = l.analysis_id;

update public.notification_events
set
  language = coalesce(language, 'tr'),
  locale = coalesce(locale, 'tr-TR'),
  localization_snapshot = coalesce(
    localization_snapshot,
    jsonb_build_object(
      'schema_version', 1,
      'language', 'tr',
      'locale', 'tr-TR',
      'safety_profile_id', 'tr-tr-current-v1',
      'safety_profile_version', 1,
      'source', 'legacy_tr_backfill'
    )
  ),
  template_locale = coalesce(template_locale, 'tr-TR')
where id = '00000000-0000-4000-8000-000000000905'::uuid;

update private.notification_jobs
set
  language = coalesce(language, 'tr'),
  locale = coalesce(locale, 'tr-TR'),
  localization_snapshot = coalesce(
    localization_snapshot,
    jsonb_build_object(
      'schema_version', 1,
      'language', 'tr',
      'locale', 'tr-TR',
      'safety_profile_id', 'tr-tr-current-v1',
      'safety_profile_version', 1,
      'source', 'legacy_tr_backfill'
    )
  ),
  template_locale = coalesce(template_locale, 'tr-TR')
where id = '00000000-0000-4000-8000-000000000907'::uuid;

update public.support_requests
set
  app_language = coalesce(app_language, 'tr'),
  content_locale = coalesce(content_locale, 'tr-TR'),
  preferred_response_language =
    coalesce(preferred_response_language, 'tr')
where id = '00000000-0000-4000-8000-000000000908'::uuid;

alter table private.notification_jobs
  enable trigger notification_jobs_localization_guard_v1;

select ok(
  (
    select app_language = 'tr'
      and preferred_content_locale = 'tr-TR'
      and work_jurisdiction_country = 'TR'
      and safety_profile_id = 'tr-tr-current-v1'
      and safety_profile_version = 1
      and legal_document_set = 'tr-current'
    from public.profiles
    where id = '00000000-0000-4000-8000-000000000901'::uuid
  ),
  'legacy profile receives Turkish defaults'
);
select ok(
  (
    select output_language = 'tr'
      and output_locale = 'tr-TR'
      and work_jurisdiction_country = 'TR'
      and safety_profile_id = 'tr-tr-current-v1'
      and safety_profile_version = 1
      and regulatory_reference_policy = 'tr_current'
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  ),
  'legacy analysis receives Turkish scalar context'
);
select ok(
  (
    select localization_snapshot ?& array[
      'schema_version', 'output_language', 'output_locale',
      'work_jurisdiction_country', 'work_jurisdiction_region',
      'safety_profile_id', 'safety_profile_version',
      'regulatory_reference_policy', 'prompt_profile_version', 'method',
      'legal_document_set', 'manifest_version', 'manifest_source_sha256',
      'source'
    ]
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  ),
  'legacy analysis snapshot contains every authority key'
);
select ok(
  (
    select report_language = 'tr'
      and report_locale = 'tr-TR'
      and localization_snapshot is not null
    from public.reports
    where id = '00000000-0000-4000-8000-000000000903'::uuid
  ),
  'legacy report copies Turkish analysis snapshot'
);
select ok(
  (
    select output_language = 'tr'
      and output_locale = 'tr-TR'
      and safety_profile_id = 'tr-tr-current-v1'
    from public.ai_usage_logs
    where id = '00000000-0000-4000-8000-000000000904'::uuid
  ),
  'legacy AI usage receives Turkish telemetry context'
);
select ok(
  (
    select language = 'tr'
      and locale = 'tr-TR'
      and template_locale = 'tr-TR'
      and localization_snapshot is not null
    from public.notification_events
    where id = '00000000-0000-4000-8000-000000000905'::uuid
  ),
  'legacy notification event receives Turkish context'
);
select ok(
  (
    select language = 'tr'
      and locale = 'tr-TR'
      and template_locale = 'tr-TR'
      and localization_snapshot is not null
    from private.notification_jobs
    where id = '00000000-0000-4000-8000-000000000907'::uuid
  ),
  'legacy private notification job receives Turkish context'
);
select ok(
  (
    select app_language = 'tr'
      and content_locale = 'tr-TR'
      and preferred_response_language = 'tr'
    from public.support_requests
    where id = '00000000-0000-4000-8000-000000000908'::uuid
  ),
  'legacy support request receives system language defaults'
);
select is(
  (
    select user_message_language
    from public.support_requests
    where id = '00000000-0000-4000-8000-000000000908'::uuid
  ),
  null,
  'user-authored support message language is not inferred'
);

insert into public.analyses (
  id, user_id, kind, status, photo_count, primary_method
)
values (
  '00000000-0000-4000-8000-000000000909'::uuid,
  '00000000-0000-4000-8000-000000000901'::uuid,
  'photo',
  'pending',
  1,
  'matrix_5x5'
);

select is(
  (
    select localization_snapshot
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000909'::uuid
  ),
  null,
  'old-build analysis insert remains valid with nullable localization'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000901',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$
    update public.analyses
    set
      output_language = 'en',
      output_locale = 'en-US',
      work_jurisdiction_country = 'US',
      safety_profile_id = 'en-us-generic-v1',
      safety_profile_version = 1,
      regulatory_reference_policy = 'none',
      prompt_profile_version =
        'isg-photo-policy-v2026-07-single-multi-targets',
      localization_snapshot = jsonb_build_object(
        'schema_version', 1,
        'output_language', 'en',
        'output_locale', 'en-US',
        'work_jurisdiction_country', 'US',
        'work_jurisdiction_region', null,
        'safety_profile_id', 'en-us-generic-v1',
        'safety_profile_version', 1,
        'regulatory_reference_policy', 'none',
        'prompt_profile_version',
          'isg-photo-policy-v2026-07-single-multi-targets',
        'method', 'matrix_5x5',
        'legal_document_set', 'en-global-v1',
        'manifest_version', 1,
        'manifest_source_sha256',
          '3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932',
        'source', 'explicit_request'
      )
    where id = '00000000-0000-4000-8000-000000000909'::uuid
  $$,
  '42501',
  'permission denied for table analyses',
  'authenticated client cannot establish the authoritative snapshot'
);

reset role;

select throws_ok(
  $$
    update public.analyses
    set output_locale = 'en-US'
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  $$,
  '23514',
  'LOCALIZATION_SNAPSHOT_IMMUTABLE',
  'persisted snapshot scalar fields are immutable'
);

select lives_ok(
  $$
    update public.analyses
    set
      language_validation_status = 'passed',
      language_validation_attempts = 1,
      language_validation_code = null
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  $$,
  'language validation telemetry can advance without mutating context'
);

select throws_ok(
  $$
    update public.analyses
    set
      output_language = 'en',
      output_locale = 'en-US',
      work_jurisdiction_country = 'US',
      safety_profile_id = 'en-us-generic-v1',
      safety_profile_version = 1,
      regulatory_reference_policy = 'none',
      prompt_profile_version =
        'isg-photo-policy-v2026-07-single-multi-targets',
      localization_snapshot = '{"schema_version":1}'::jsonb
    where id = '00000000-0000-4000-8000-000000000909'::uuid
  $$,
  '23514',
  null,
  'malformed authoritative snapshots are rejected'
);

select throws_ok(
  $$
    update public.analyses
    set language_validation_attempts = 3
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  $$,
  '23514',
  null,
  'language validation attempts are bounded'
);

select throws_ok(
  $$
    update public.analyses
    set primary_method = 'matrix_5x5'
    where id = '00000000-0000-4000-8000-000000000902'::uuid
  $$,
  '23514',
  'LOCALIZATION_SNAPSHOT_IMMUTABLE',
  'analysis method is immutable after snapshot persistence'
);

select throws_ok(
  $$
    update public.analyses
    set
      output_language = 'tr',
      output_locale = 'en-US',
      work_jurisdiction_country = 'US',
      safety_profile_id = 'en-us-generic-v1',
      safety_profile_version = 1,
      regulatory_reference_policy = 'none',
      prompt_profile_version =
        'isg-photo-policy-v2026-07-single-multi-targets',
      localization_snapshot = jsonb_build_object(
        'schema_version', 1,
        'output_language', 'en',
        'output_locale', 'en-US',
        'work_jurisdiction_country', 'US',
        'work_jurisdiction_region', null,
        'safety_profile_id', 'en-us-generic-v1',
        'safety_profile_version', 1,
        'regulatory_reference_policy', 'none',
        'prompt_profile_version',
          'isg-photo-policy-v2026-07-single-multi-targets',
        'method', 'matrix_5x5',
        'legal_document_set', 'en-global-v1',
        'manifest_version', 1,
        'manifest_source_sha256',
          '3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932',
        'source', 'explicit_request'
      )
    where id = '00000000-0000-4000-8000-000000000909'::uuid
  $$,
  '23514',
  'LOCALIZATION_SNAPSHOT_COLUMNS_MISMATCH',
  'snapshot and denormalized columns must agree'
);

select * from finish();
rollback;
