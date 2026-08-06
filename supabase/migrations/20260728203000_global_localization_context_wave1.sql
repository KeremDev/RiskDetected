-- Phase 2: additive global-localization context storage.
--
-- All new business columns intentionally remain nullable during dual-read.
-- Existing records receive a bounded, idempotent Turkish legacy backfill.
-- Tightening nullability is a later migration after rollout telemetry.

alter table public.profiles
  add column if not exists app_language text,
  add column if not exists preferred_content_locale text,
  add column if not exists work_jurisdiction_country text,
  add column if not exists work_jurisdiction_region text,
  add column if not exists safety_profile_id text,
  add column if not exists safety_profile_version integer,
  add column if not exists legal_document_set text;

alter table public.analyses
  add column if not exists output_language text,
  add column if not exists output_locale text,
  add column if not exists work_jurisdiction_country text,
  add column if not exists work_jurisdiction_region text,
  add column if not exists safety_profile_id text,
  add column if not exists safety_profile_version integer,
  add column if not exists regulatory_reference_policy text,
  add column if not exists prompt_profile_version text,
  add column if not exists localization_snapshot jsonb,
  add column if not exists language_validation_status text,
  add column if not exists language_validation_attempts integer,
  add column if not exists language_validation_code text;

alter table public.reports
  add column if not exists report_language text,
  add column if not exists report_locale text,
  add column if not exists safety_profile_id text,
  add column if not exists safety_profile_version integer,
  add column if not exists regulatory_sections_enabled boolean,
  add column if not exists localization_snapshot jsonb;

alter table public.ai_usage_logs
  add column if not exists output_language text,
  add column if not exists output_locale text,
  add column if not exists work_jurisdiction_country text,
  add column if not exists safety_profile_id text,
  add column if not exists language_validation_status text,
  add column if not exists language_validation_attempts integer,
  add column if not exists language_validation_code text;

alter table public.notification_events
  add column if not exists language text,
  add column if not exists locale text,
  add column if not exists localization_snapshot jsonb,
  add column if not exists template_locale text,
  add column if not exists template_localization_id uuid;

alter table private.notification_jobs
  add column if not exists language text,
  add column if not exists locale text,
  add column if not exists localization_snapshot jsonb,
  add column if not exists template_locale text,
  add column if not exists template_localization_id uuid;

alter table public.support_requests
  add column if not exists app_language text,
  add column if not exists content_locale text,
  add column if not exists user_message_language text,
  add column if not exists preferred_response_language text;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_app_language_check'
  ) then
    alter table public.profiles
      add constraint profiles_app_language_check
      check (app_language is null or app_language in ('tr', 'en')) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_preferred_content_locale_check'
  ) then
    alter table public.profiles
      add constraint profiles_preferred_content_locale_check
      check (
        preferred_content_locale is null
        or preferred_content_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_work_jurisdiction_country_check'
  ) then
    alter table public.profiles
      add constraint profiles_work_jurisdiction_country_check
      check (
        work_jurisdiction_country is null
        or work_jurisdiction_country in ('TR', 'INTL', 'GB', 'US', 'AU', 'CA')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_safety_profile_version_check'
  ) then
    alter table public.profiles
      add constraint profiles_safety_profile_version_check
      check (safety_profile_version is null or safety_profile_version > 0)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_legal_document_set_check'
  ) then
    alter table public.profiles
      add constraint profiles_legal_document_set_check
      check (
        legal_document_set is null
        or legal_document_set in ('tr-current', 'en-global-v1')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_output_language_check'
  ) then
    alter table public.analyses
      add constraint analyses_output_language_check
      check (output_language is null or output_language in ('tr', 'en'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_output_locale_check'
  ) then
    alter table public.analyses
      add constraint analyses_output_locale_check
      check (
        output_locale is null
        or output_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_work_jurisdiction_country_check'
  ) then
    alter table public.analyses
      add constraint analyses_work_jurisdiction_country_check
      check (
        work_jurisdiction_country is null
        or work_jurisdiction_country in ('TR', 'INTL', 'GB', 'US', 'AU', 'CA')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_safety_profile_version_check'
  ) then
    alter table public.analyses
      add constraint analyses_safety_profile_version_check
      check (safety_profile_version is null or safety_profile_version > 0)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_regulatory_reference_policy_check'
  ) then
    alter table public.analyses
      add constraint analyses_regulatory_reference_policy_check
      check (
        regulatory_reference_policy is null
        or regulatory_reference_policy in (
          'tr_current', 'none', 'explicit_question_only'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_language_validation_status_check'
  ) then
    alter table public.analyses
      add constraint analyses_language_validation_status_check
      check (
        language_validation_status is null
        or language_validation_status in (
          'not_evaluated', 'legacy_assumed', 'passed', 'repaired', 'failed'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_language_validation_attempts_check'
  ) then
    alter table public.analyses
      add constraint analyses_language_validation_attempts_check
      check (
        language_validation_attempts is null
        or language_validation_attempts between 0 and 2
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.analyses'::regclass
      and conname = 'analyses_localization_snapshot_shape_check'
  ) then
    alter table public.analyses
      add constraint analyses_localization_snapshot_shape_check
      check (
        localization_snapshot is null
        or (
          jsonb_typeof(localization_snapshot) = 'object'
          and localization_snapshot ->> 'schema_version' = '1'
          and localization_snapshot ?& array[
            'output_language',
            'output_locale',
            'work_jurisdiction_country',
            'work_jurisdiction_region',
            'safety_profile_id',
            'safety_profile_version',
            'regulatory_reference_policy',
            'prompt_profile_version',
            'method',
            'legal_document_set',
            'manifest_version',
            'manifest_source_sha256',
            'source'
          ]
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_report_language_check'
  ) then
    alter table public.reports
      add constraint reports_report_language_check
      check (report_language is null or report_language in ('tr', 'en'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_safety_profile_version_check'
  ) then
    alter table public.reports
      add constraint reports_safety_profile_version_check
      check (safety_profile_version is null or safety_profile_version > 0)
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_report_locale_check'
  ) then
    alter table public.reports
      add constraint reports_report_locale_check
      check (
        report_locale is null
        or report_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_localization_snapshot_shape_check'
  ) then
    alter table public.reports
      add constraint reports_localization_snapshot_shape_check
      check (
        localization_snapshot is null
        or (
          jsonb_typeof(localization_snapshot) = 'object'
          and localization_snapshot ->> 'schema_version' = '1'
          and localization_snapshot ?& array[
            'output_language',
            'output_locale',
            'work_jurisdiction_country',
            'work_jurisdiction_region',
            'safety_profile_id',
            'safety_profile_version',
            'regulatory_reference_policy',
            'prompt_profile_version',
            'method',
            'legal_document_set',
            'manifest_version',
            'manifest_source_sha256',
            'source'
          ]
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_output_language_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_output_language_check
      check (output_language is null or output_language in ('tr', 'en'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_output_locale_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_output_locale_check
      check (
        output_locale is null
        or output_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_work_jurisdiction_country_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_work_jurisdiction_country_check
      check (
        work_jurisdiction_country is null
        or work_jurisdiction_country in ('TR', 'INTL', 'GB', 'US', 'AU', 'CA')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_language_validation_status_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_language_validation_status_check
      check (
        language_validation_status is null
        or language_validation_status in (
          'not_evaluated', 'legacy_assumed', 'passed', 'repaired', 'failed'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.ai_usage_logs'::regclass
      and conname = 'ai_usage_logs_language_validation_attempts_check'
  ) then
    alter table public.ai_usage_logs
      add constraint ai_usage_logs_language_validation_attempts_check
      check (
        language_validation_attempts is null
        or language_validation_attempts between 0 and 2
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_events'::regclass
      and conname = 'notification_events_language_check'
  ) then
    alter table public.notification_events
      add constraint notification_events_language_check
      check (language is null or language in ('tr', 'en')) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_events'::regclass
      and conname = 'notification_events_locale_check'
  ) then
    alter table public.notification_events
      add constraint notification_events_locale_check
      check (
        locale is null
        or locale in ('tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_events'::regclass
      and conname = 'notification_events_template_locale_check'
  ) then
    alter table public.notification_events
      add constraint notification_events_template_locale_check
      check (
        template_locale is null
        or template_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'private.notification_jobs'::regclass
      and conname = 'notification_jobs_language_check'
  ) then
    alter table private.notification_jobs
      add constraint notification_jobs_language_check
      check (language is null or language in ('tr', 'en')) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'private.notification_jobs'::regclass
      and conname = 'notification_jobs_locale_check'
  ) then
    alter table private.notification_jobs
      add constraint notification_jobs_locale_check
      check (
        locale is null
        or locale in ('tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'private.notification_jobs'::regclass
      and conname = 'notification_jobs_template_locale_check'
  ) then
    alter table private.notification_jobs
      add constraint notification_jobs_template_locale_check
      check (
        template_locale is null
        or template_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.support_requests'::regclass
      and conname = 'support_requests_app_language_check'
  ) then
    alter table public.support_requests
      add constraint support_requests_app_language_check
      check (app_language is null or app_language in ('tr', 'en')) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.support_requests'::regclass
      and conname = 'support_requests_content_locale_check'
  ) then
    alter table public.support_requests
      add constraint support_requests_content_locale_check
      check (
        content_locale is null
        or content_locale in (
          'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
        )
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.support_requests'::regclass
      and conname = 'support_requests_user_message_language_check'
  ) then
    alter table public.support_requests
      add constraint support_requests_user_message_language_check
      check (
        user_message_language is null
        or user_message_language in ('tr', 'en', 'und')
      ) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.support_requests'::regclass
      and conname = 'support_requests_preferred_response_language_check'
  ) then
    alter table public.support_requests
      add constraint support_requests_preferred_response_language_check
      check (
        preferred_response_language is null
        or preferred_response_language in ('tr', 'en')
      ) not valid;
  end if;
end
$constraints$;

create or replace function private.enforce_analysis_localization_snapshot_v1()
returns trigger
language plpgsql
security invoker
set search_path = public, private, auth
as $function$
declare
  v_trusted_writer boolean :=
    current_user in ('postgres', 'service_role', 'supabase_admin')
    or coalesce(auth.role(), '') = 'service_role';
begin
  if tg_op = 'INSERT' and new.localization_snapshot is not null
     and not v_trusted_writer then
    raise exception using
      errcode = '42501',
      message = 'LOCALIZATION_SNAPSHOT_SERVICE_ROLE_REQUIRED';
  end if;

  if tg_op = 'UPDATE' then
    if old.localization_snapshot is null
       and new.localization_snapshot is not null
       and not v_trusted_writer then
      raise exception using
        errcode = '42501',
        message = 'LOCALIZATION_SNAPSHOT_SERVICE_ROLE_REQUIRED';
    end if;

    if old.localization_snapshot is not null and (
      new.localization_snapshot is distinct from old.localization_snapshot
      or new.output_language is distinct from old.output_language
      or new.output_locale is distinct from old.output_locale
      or new.work_jurisdiction_country
        is distinct from old.work_jurisdiction_country
      or new.work_jurisdiction_region
        is distinct from old.work_jurisdiction_region
      or new.safety_profile_id is distinct from old.safety_profile_id
      or new.safety_profile_version
        is distinct from old.safety_profile_version
      or new.regulatory_reference_policy
        is distinct from old.regulatory_reference_policy
      or new.prompt_profile_version
        is distinct from old.prompt_profile_version
      or new.primary_method is distinct from old.primary_method
    ) then
      raise exception using
        errcode = '23514',
        message = 'LOCALIZATION_SNAPSHOT_IMMUTABLE';
    end if;
  end if;

  if new.localization_snapshot is not null and (
    new.output_language is distinct from
      (new.localization_snapshot ->> 'output_language')
    or new.output_locale is distinct from
      (new.localization_snapshot ->> 'output_locale')
    or new.work_jurisdiction_country is distinct from
      (new.localization_snapshot ->> 'work_jurisdiction_country')
    or new.work_jurisdiction_region is distinct from
      nullif(new.localization_snapshot ->> 'work_jurisdiction_region', '')
    or new.safety_profile_id is distinct from
      (new.localization_snapshot ->> 'safety_profile_id')
    or new.safety_profile_version is distinct from
      (new.localization_snapshot ->> 'safety_profile_version')::integer
    or new.regulatory_reference_policy is distinct from
      (new.localization_snapshot ->> 'regulatory_reference_policy')
    or new.prompt_profile_version is distinct from
      (new.localization_snapshot ->> 'prompt_profile_version')
    or new.primary_method::text is distinct from
      (new.localization_snapshot ->> 'method')
  ) then
    raise exception using
      errcode = '23514',
      message = 'LOCALIZATION_SNAPSHOT_COLUMNS_MISMATCH';
  end if;

  return new;
end
$function$;

drop trigger if exists analyses_localization_snapshot_guard_v1
  on public.analyses;
create trigger analyses_localization_snapshot_guard_v1
before insert or update on public.analyses
for each row
execute function private.enforce_analysis_localization_snapshot_v1();

-- Bounded legacy backfill. Each loop updates at most 500 records, only where
-- at least one legacy localization value is absent.
do $backfill_profiles$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select ctid
      from public.profiles
      where app_language is null
         or preferred_content_locale is null
         or work_jurisdiction_country is null
         or safety_profile_id is null
         or safety_profile_version is null
         or legal_document_set is null
      limit 500
      for update skip locked
    )
    update public.profiles p
    set
      app_language = coalesce(p.app_language, 'tr'),
      preferred_content_locale = coalesce(p.preferred_content_locale, 'tr-TR'),
      work_jurisdiction_country =
        coalesce(p.work_jurisdiction_country, 'TR'),
      safety_profile_id =
        coalesce(p.safety_profile_id, 'tr-tr-current-v1'),
      safety_profile_version = coalesce(p.safety_profile_version, 1),
      legal_document_set = coalesce(p.legal_document_set, 'tr-current')
    from batch
    where p.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'profiles localization backfill rows=%', v_total;
end
$backfill_profiles$;

do $backfill_analyses$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select ctid
      from public.analyses
      where output_language is null
         or output_locale is null
         or work_jurisdiction_country is null
         or safety_profile_id is null
         or safety_profile_version is null
         or regulatory_reference_policy is null
         or prompt_profile_version is null
         or localization_snapshot is null
         or language_validation_status is null
         or language_validation_attempts is null
      limit 500
      for update skip locked
    )
    update public.analyses a
    set
      output_language = coalesce(a.output_language, 'tr'),
      output_locale = coalesce(a.output_locale, 'tr-TR'),
      work_jurisdiction_country =
        coalesce(a.work_jurisdiction_country, 'TR'),
      safety_profile_id =
        coalesce(a.safety_profile_id, 'tr-tr-current-v1'),
      safety_profile_version = coalesce(a.safety_profile_version, 1),
      regulatory_reference_policy =
        coalesce(a.regulatory_reference_policy, 'tr_current'),
      prompt_profile_version = coalesce(
        a.prompt_profile_version,
        'isg-photo-policy-v2026-07-single-multi-targets'
      ),
      localization_snapshot = coalesce(
        a.localization_snapshot,
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
          'method', a.primary_method::text,
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
        coalesce(a.language_validation_status, 'legacy_assumed'),
      language_validation_attempts =
        coalesce(a.language_validation_attempts, 0),
      language_validation_code =
        coalesce(a.language_validation_code, 'legacy_tr_backfill')
    from batch
    where a.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'analyses localization backfill rows=%', v_total;
end
$backfill_analyses$;

do $backfill_reports$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select r.ctid, a.localization_snapshot
      from public.reports r
      join public.analyses a on a.id = r.analysis_id
      where r.report_language is null
         or r.report_locale is null
         or r.safety_profile_id is null
         or r.safety_profile_version is null
         or r.regulatory_sections_enabled is null
         or r.localization_snapshot is null
      limit 500
      for update of r skip locked
    )
    update public.reports r
    set
      report_language = coalesce(r.report_language, 'tr'),
      report_locale = coalesce(r.report_locale, 'tr-TR'),
      safety_profile_id =
        coalesce(r.safety_profile_id, 'tr-tr-current-v1'),
      safety_profile_version = coalesce(r.safety_profile_version, 1),
      regulatory_sections_enabled =
        coalesce(r.regulatory_sections_enabled, true),
      localization_snapshot =
        coalesce(r.localization_snapshot, batch.localization_snapshot)
    from batch
    where r.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'reports localization backfill rows=%', v_total;
end
$backfill_reports$;

do $backfill_ai_usage_logs$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select l.ctid, a.output_language, a.output_locale,
             a.work_jurisdiction_country, a.safety_profile_id
      from public.ai_usage_logs l
      left join public.analyses a on a.id = l.analysis_id
      where l.output_language is null
         or l.output_locale is null
         or l.work_jurisdiction_country is null
         or l.safety_profile_id is null
         or l.language_validation_status is null
         or l.language_validation_attempts is null
      limit 500
      for update of l skip locked
    )
    update public.ai_usage_logs l
    set
      output_language =
        coalesce(l.output_language, batch.output_language, 'tr'),
      output_locale = coalesce(l.output_locale, batch.output_locale, 'tr-TR'),
      work_jurisdiction_country = coalesce(
        l.work_jurisdiction_country,
        batch.work_jurisdiction_country,
        'TR'
      ),
      safety_profile_id = coalesce(
        l.safety_profile_id,
        batch.safety_profile_id,
        'tr-tr-current-v1'
      ),
      language_validation_status =
        coalesce(l.language_validation_status, 'legacy_assumed'),
      language_validation_attempts =
        coalesce(l.language_validation_attempts, 0),
      language_validation_code =
        coalesce(l.language_validation_code, 'legacy_tr_backfill')
    from batch
    where l.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'ai_usage_logs localization backfill rows=%', v_total;
end
$backfill_ai_usage_logs$;

do $backfill_notification_events$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select ctid
      from public.notification_events
      where language is null
         or locale is null
         or localization_snapshot is null
         or template_locale is null
      limit 500
      for update skip locked
    )
    update public.notification_events e
    set
      language = coalesce(e.language, 'tr'),
      locale = coalesce(e.locale, 'tr-TR'),
      localization_snapshot = coalesce(
        e.localization_snapshot,
        jsonb_build_object(
          'schema_version', 1,
          'language', 'tr',
          'locale', 'tr-TR',
          'safety_profile_id', 'tr-tr-current-v1',
          'safety_profile_version', 1,
          'source', 'legacy_tr_backfill'
        )
      ),
      template_locale = coalesce(e.template_locale, 'tr-TR')
    from batch
    where e.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'notification_events localization backfill rows=%', v_total;
end
$backfill_notification_events$;

do $backfill_notification_jobs$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select ctid
      from private.notification_jobs
      where language is null
         or locale is null
         or localization_snapshot is null
         or template_locale is null
      limit 500
      for update skip locked
    )
    update private.notification_jobs j
    set
      language = coalesce(j.language, 'tr'),
      locale = coalesce(j.locale, 'tr-TR'),
      localization_snapshot = coalesce(
        j.localization_snapshot,
        jsonb_build_object(
          'schema_version', 1,
          'language', 'tr',
          'locale', 'tr-TR',
          'safety_profile_id', 'tr-tr-current-v1',
          'safety_profile_version', 1,
          'source', 'legacy_tr_backfill'
        )
      ),
      template_locale = coalesce(j.template_locale, 'tr-TR')
    from batch
    where j.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'notification_jobs localization backfill rows=%', v_total;
end
$backfill_notification_jobs$;

do $backfill_support_requests$
declare
  v_rows integer;
  v_total bigint := 0;
begin
  loop
    with batch as (
      select ctid
      from public.support_requests
      where app_language is null
         or content_locale is null
         or preferred_response_language is null
      limit 500
      for update skip locked
    )
    update public.support_requests s
    set
      app_language = coalesce(s.app_language, 'tr'),
      content_locale = coalesce(s.content_locale, 'tr-TR'),
      preferred_response_language =
        coalesce(s.preferred_response_language, 'tr')
    from batch
    where s.ctid = batch.ctid;

    get diagnostics v_rows = row_count;
    v_total := v_total + v_rows;
    exit when v_rows = 0;
  end loop;
  raise notice 'support_requests localization backfill rows=%', v_total;
end
$backfill_support_requests$;

create index if not exists analyses_user_safety_profile_created_idx
  on public.analyses (user_id, safety_profile_id, created_at desc);

create index if not exists reports_user_safety_profile_created_idx
  on public.reports (user_id, safety_profile_id, created_at desc);

insert into public.app_feature_flags (key, value)
values
  (
    'global_localization_wave1',
    '{"rollout_mode":"off","enabled_user_hashes":[],"contract_version":1}'::jsonb
  ),
  (
    'safety_profile_en_intl_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'safety_profile_en_gb_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'safety_profile_en_us_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'safety_profile_en_au_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'safety_profile_en_ca_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'localization_queue_payload_v1',
    '{"rollout_mode":"off","enabled_user_hashes":[],"contract_version":1}'::jsonb
  ),
  (
    'ai_language_guard_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'ai_country_term_guard_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'english_report_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  ),
  (
    'english_notifications_enabled',
    '{"rollout_mode":"off","enabled_user_hashes":[]}'::jsonb
  )
on conflict (key) do nothing;

comment on column public.analyses.localization_snapshot is
  'Immutable localization authority for analysis, retry, repair, report and telemetry flows.';
comment on column public.reports.localization_snapshot is
  'Immutable copy of the source analysis localization snapshot.';
comment on column private.notification_jobs.localization_snapshot is
  'Immutable language/profile/template resolution snapshot for a notification job.';

select pg_notify('pgrst', 'reload schema');
