begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(45);

select has_column('public', 'analyses', 'app_language', '1 analyses app language exists');
select has_column('public', 'analyses', 'client_build', '2 analyses client build exists');
select has_column(
  'public',
  'analyses',
  'language_contract_repair_used',
  '3 analyses repair telemetry exists'
);
select has_column(
  'public',
  'analyses',
  'forbidden_claim_validation_status',
  '4 analyses forbidden-claim status exists'
);
select has_column('public', 'ai_usage_logs', 'app_language', '5 usage app language exists');
select has_column(
  'public',
  'ai_usage_logs',
  'safety_profile_version',
  '6 usage safety profile version exists'
);
select has_column(
  'public',
  'ai_usage_logs',
  'prompt_profile_version',
  '7 usage prompt profile version exists'
);
select has_column('public', 'ai_usage_logs', 'client_build', '8 usage client build exists');
select has_column(
  'public',
  'ai_usage_logs',
  'language_contract_repair_used',
  '9 usage repair telemetry exists'
);
select has_column(
  'public',
  'ai_usage_logs',
  'forbidden_claim_validation_status',
  '10 usage forbidden-claim status exists'
);

select has_trigger(
  'public',
  'analyses',
  'analyses_sync_localization_telemetry',
  '11 analysis aggregate telemetry is synchronized atomically'
);
select ok(
  to_regprocedure('private.tg_sync_analysis_localization_telemetry()') is not null,
  '12 private telemetry trigger function exists'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_app_language_check'
  ),
  '13 analyses app language constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_client_build_check'
  ),
  '14 analyses client build constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_forbidden_claim_validation_status_check'
  ),
  '15 analyses forbidden-claim status constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_app_language_check'
  ),
  '16 usage app language constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_safety_profile_version_check'
  ),
  '17 usage safety profile version constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_client_build_check'
  ),
  '18 usage client build constraint exists'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_forbidden_claim_validation_status_check'
  ),
  '19 usage forbidden-claim status constraint exists'
);

select has_index(
  'public',
  'analyses',
  'analyses_localization_release_metrics_idx',
  '20 bounded analysis release metrics index exists'
);
select has_index(
  'public',
  'ai_usage_logs',
  'ai_usage_logs_localization_release_metrics_idx',
  '21 bounded usage release metrics index exists'
);

select is(
  (
    select value ->> 'rollout_mode'
    from public.app_feature_flags
    where key = 'localization_v2'
  ),
  'off',
  '22 localization v2 starts off'
);
select is(
  (
    select value ->> 'rollout_mode'
    from public.app_feature_flags
    where key = 'english_product_enabled'
  ),
  'off',
  '23 English product starts off'
);
select is(
  (
    select count(*)::integer
    from public.app_feature_flags
    where key in (
      'localization_v2',
      'english_product_enabled',
      'global_localization_wave1',
      'safety_profile_en_intl_enabled',
      'safety_profile_en_gb_enabled',
      'safety_profile_en_us_enabled',
      'safety_profile_en_au_enabled',
      'safety_profile_en_ca_enabled',
      'localization_queue_payload_v1',
      'ai_language_guard_enabled',
      'ai_country_term_guard_enabled',
      'english_report_enabled',
      'english_notifications_enabled'
    )
      and value ->> 'rollout_mode' = 'off'
  ),
  13,
  '24 all localization release flags remain off'
);
select is(
  (
    select count(*)::integer
    from public.app_feature_flags
    where key in (
      'localization_v2',
      'english_product_enabled',
      'global_localization_wave1',
      'safety_profile_en_intl_enabled',
      'safety_profile_en_gb_enabled',
      'safety_profile_en_us_enabled',
      'safety_profile_en_au_enabled',
      'safety_profile_en_ca_enabled',
      'localization_queue_payload_v1',
      'ai_language_guard_enabled',
      'ai_country_term_guard_enabled',
      'english_report_enabled',
      'english_notifications_enabled'
    )
      and jsonb_typeof(value -> 'enabled_user_hashes') = 'array'
      and jsonb_typeof(value -> 'enabled_ios_builds') = 'array'
      and value ? 'min_ios_build'
      and value -> 'kill_switch' = 'false'::jsonb
  ),
  13,
  '25 every release flag has a fail-closed build gate and kill switch'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000b01'::uuid,
  'release-telemetry@example.invalid',
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
values (
  '00000000-0000-4000-8000-000000000b01'::uuid,
  'release-telemetry@example.invalid',
  'tr',
  'tr-TR',
  'TR',
  'tr-legacy-v1',
  1,
  'tr-current'
)
on conflict (id) do update
set
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
  raw_ai_response
)
values (
  '00000000-0000-4000-8000-000000000b02'::uuid,
  '00000000-0000-4000-8000-000000000b01'::uuid,
  'photo',
  'completed',
  1,
  jsonb_build_object(
    '_input_audit',
    jsonb_build_object(
      'app_language', 'en',
      'client_build', '78',
      'language_validation_status', 'repaired',
      'language_validation_attempts', 2,
      'language_validation_code', 'OUTPUT_LANGUAGE_ENGLISH_REQUIRED',
      'language_contract_repair_used', true,
      'forbidden_claim_validation_status', 'repaired'
    )
  )
);

select is(
  (select app_language from public.analyses where id = '00000000-0000-4000-8000-000000000b02'),
  'en',
  '26 trigger extracts aggregate app language'
);
select is(
  (select client_build from public.analyses where id = '00000000-0000-4000-8000-000000000b02'),
  '78',
  '27 trigger extracts aggregate client build'
);
select is(
  (
    select language_contract_repair_used
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  true,
  '28 trigger extracts repair usage'
);
select is(
  (
    select forbidden_claim_validation_status
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  'repaired',
  '29 trigger extracts bounded forbidden-claim outcome'
);

select is(
  (
    select language_validation_status
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  'repaired',
  '40 trigger extracts language-validation status'
);
select is(
  (
    select language_validation_attempts
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  2,
  '41 trigger extracts language-validation attempts'
);
select is(
  (
    select language_validation_code
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  'OUTPUT_LANGUAGE_ENGLISH_REQUIRED',
  '42 trigger extracts bounded language-validation code'
);

select throws_ok(
  $$
    update public.analyses
    set app_language = 'de'
    where id = '00000000-0000-4000-8000-000000000b02'
  $$,
  '23514',
  null,
  '30 invalid analysis language fails closed'
);
select throws_ok(
  $$
    update public.analyses
    set client_build = '77-beta'
    where id = '00000000-0000-4000-8000-000000000b02'
  $$,
  '23514',
  null,
  '31 invalid analysis build fails closed'
);
select throws_ok(
  $$
    insert into public.ai_usage_logs (
      analysis_id,
      user_id,
      model,
      safety_profile_version
    )
    values (
      '00000000-0000-4000-8000-000000000b02'::uuid,
      '00000000-0000-4000-8000-000000000b01'::uuid,
      'release-test-model',
      0
    )
  $$,
  '23514',
  null,
  '32 invalid safety profile version fails closed'
);

update public.analyses
set raw_ai_response = jsonb_build_object(
  '_input_audit',
  jsonb_build_object(
    'app_language', 'de',
    'client_build', '77-beta',
    'language_validation_status', 'unknown',
    'language_validation_attempts', 9,
    'language_validation_code', 'invalid-code',
    'language_contract_repair_used', 'not-a-boolean',
    'forbidden_claim_validation_status', 'unknown'
  )
)
where id = '00000000-0000-4000-8000-000000000b02';

select is(
  (select app_language from public.analyses where id = '00000000-0000-4000-8000-000000000b02'),
  'en',
  '33 invalid audit language cannot overwrite valid telemetry'
);
select is(
  (select client_build from public.analyses where id = '00000000-0000-4000-8000-000000000b02'),
  '78',
  '34 invalid audit build cannot overwrite valid telemetry'
);
select is(
  (
    select language_contract_repair_used
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  true,
  '35 invalid audit repair value cannot overwrite valid telemetry'
);
select is(
  (
    select forbidden_claim_validation_status
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  'repaired',
  '36 invalid audit status cannot overwrite valid telemetry'
);

select ok(
  (
    select language_validation_status = 'repaired'
      and language_validation_attempts = 2
      and language_validation_code = 'OUTPUT_LANGUAGE_ENGLISH_REQUIRED'
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b02'
  ),
  '43 invalid audit validation values cannot overwrite valid telemetry'
);

insert into public.analyses (
  id,
  user_id,
  kind,
  status,
  photo_count,
  raw_ai_response
)
values (
  '00000000-0000-4000-8000-000000000b03'::uuid,
  '00000000-0000-4000-8000-000000000b01'::uuid,
  'photo',
  'completed',
  1,
  jsonb_build_object(
    '_input_audit',
    jsonb_build_object(
      'app_language', 'en',
      'client_build', 'invalid',
      'language_validation_status', 'unknown',
      'language_validation_attempts', 9,
      'language_validation_code', 'invalid-code',
      'language_contract_repair_used', 'invalid',
      'forbidden_claim_validation_status', 'invalid'
    )
  )
);

select is(
  (
    select app_language
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b03'
  ),
  'en',
  '37 partial legacy telemetry keeps the one valid source value'
);
select ok(
  (
    select client_build is null
      and language_contract_repair_used is null
      and forbidden_claim_validation_status is null
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b03'
  ),
  '38 invalid source values remain null'
);
select ok(
  (
    select (
        language_validation_status is null
        or language_validation_status in ('not_evaluated', 'legacy_assumed')
      )
      and coalesce(language_validation_attempts, 0) = 0
      and language_validation_code is null
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b03'
  ),
  '44 invalid validation source values do not escape their bounded defaults'
);
select is(
  (
    select count(*)::integer
    from public.analyses
    where id = '00000000-0000-4000-8000-000000000b03'
      and raw_ai_response is not null
      and jsonb_typeof(raw_ai_response -> '_input_audit') = 'object'
      and (
        (
          app_language is null
          and raw_ai_response -> '_input_audit' ->> 'app_language'
            in ('tr', 'en')
        )
        or (
          client_build is null
          and raw_ai_response -> '_input_audit' ->> 'client_build'
            ~ '^[1-9][0-9]{0,8}$'
        )
        or (
          language_contract_repair_used is null
          and jsonb_typeof(
            raw_ai_response
              -> '_input_audit'
              -> 'language_contract_repair_used'
          ) = 'boolean'
        )
        or (
          forbidden_claim_validation_status is null
          and raw_ai_response
            -> '_input_audit'
            ->> 'forbidden_claim_validation_status'
            in ('not_evaluated', 'passed', 'repaired', 'failed')
        )
      )
  ),
  0,
  '39 backfill excludes terminal partial rows and therefore terminates'
);

select ok(
  pg_get_functiondef(
    'private.tg_sync_analysis_localization_telemetry()'::regprocedure
  ) like '%language_validation_status%',
  '45 trigger definition synchronizes validation telemetry'
);

select * from extensions.finish();
rollback;
