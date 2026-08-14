-- Phase 5: localized reports and exact-locale notification delivery.
--
-- This migration is additive and idempotent. It does not enable notification
-- automation or change the existing kill switch.

alter table public.profiles
  drop constraint if exists profiles_welcome_email_status_check;
alter table public.profiles
  add constraint profiles_welcome_email_status_check
  check (
    welcome_email_status is null
    or welcome_email_status in (
      'sending',
      'sent',
      'email_failed',
      'localization_failed'
    )
  );

-- Legal acceptance audit: every new localized acceptance can identify its
-- exact document set and checksum. Existing rows remain valid history.
alter table public.consents
  add column if not exists legal_document_set text,
  add column if not exists legal_locale text,
  add column if not exists legal_set_manifest_checksum text;

alter table public.consents
  drop constraint if exists consents_legal_document_set_check,
  add constraint consents_legal_document_set_check
    check (
      legal_document_set is null
      or legal_document_set in ('tr-current', 'en-global-v1')
    ),
  drop constraint if exists consents_legal_locale_check,
  add constraint consents_legal_locale_check
    check (legal_locale is null or legal_locale in ('tr', 'en')),
  drop constraint if exists consents_legal_manifest_checksum_check,
  add constraint consents_legal_manifest_checksum_check
    check (
      legal_set_manifest_checksum is null
      or legal_set_manifest_checksum ~ '^[0-9a-f]{64}$'
    );

alter table public.legal_document_acknowledgements
  add column if not exists document_set_id text,
  add column if not exists document_locale text,
  add column if not exists document_checksum text;

alter table public.legal_document_acknowledgements
  drop constraint if exists legal_ack_document_set_check,
  add constraint legal_ack_document_set_check
    check (
      document_set_id is null
      or document_set_id in ('tr-current', 'en-global-v1')
    ),
  drop constraint if exists legal_ack_document_locale_check,
  add constraint legal_ack_document_locale_check
    check (document_locale is null or document_locale in ('tr', 'en')),
  drop constraint if exists legal_ack_document_checksum_check,
  add constraint legal_ack_document_checksum_check
    check (
      document_checksum is null
      or document_checksum ~ '^[0-9a-f]{64}$'
    );

-- ---------------------------------------------------------------------------
-- Reports: the completed analysis snapshot is the only language authority.
-- ---------------------------------------------------------------------------

create or replace function private.enforce_report_localization_snapshot_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_snapshot jsonb;
  v_language text;
  v_locale text;
  v_profile_id text;
  v_profile_version integer;
  v_regulatory_enabled boolean;
begin
  if tg_op = 'UPDATE' and old.localization_snapshot is not null and (
    new.analysis_id is distinct from old.analysis_id
    or new.report_language is distinct from old.report_language
    or new.report_locale is distinct from old.report_locale
    or new.safety_profile_id is distinct from old.safety_profile_id
    or new.safety_profile_version is distinct from old.safety_profile_version
    or new.regulatory_sections_enabled
      is distinct from old.regulatory_sections_enabled
    or new.localization_snapshot is distinct from old.localization_snapshot
  ) then
    raise exception using
      errcode = '23514',
      message = 'REPORT_LOCALIZATION_SNAPSHOT_IMMUTABLE';
  end if;

  if tg_op = 'UPDATE' then
    return new;
  end if;

  select a.localization_snapshot
  into v_snapshot
  from public.analyses a
  where a.id = new.analysis_id;

  if v_snapshot is null
     or jsonb_typeof(v_snapshot) <> 'object'
     or v_snapshot ->> 'schema_version' <> '1' then
    raise exception using
      errcode = '23514',
      message = 'REPORT_LOCALIZATION_SNAPSHOT_MISSING';
  end if;

  v_language := v_snapshot ->> 'output_language';
  v_locale := v_snapshot ->> 'output_locale';
  v_profile_id := v_snapshot ->> 'safety_profile_id';
  v_profile_version :=
    nullif(v_snapshot ->> 'safety_profile_version', '')::integer;
  v_regulatory_enabled :=
    coalesce(
      (v_snapshot ->> 'structured_regulatory_references_enabled')::boolean,
      false
    )
    and coalesce(v_snapshot ->> 'work_jurisdiction_country', '') = 'TR'
    and v_language = 'tr';

  if v_language not in ('tr', 'en')
     or v_locale is null
     or v_profile_id is null
     or v_profile_version is null then
    raise exception using
      errcode = '23514',
      message = 'REPORT_LOCALIZATION_SNAPSHOT_INVALID';
  end if;

  if new.report_language is not null
     and new.report_language <> v_language then
    raise exception using
      errcode = '23514',
      message = 'REPORT_LANGUAGE_MISMATCH';
  end if;

  new.report_language := v_language;
  new.report_locale := v_locale;
  new.safety_profile_id := v_profile_id;
  new.safety_profile_version := v_profile_version;
  new.regulatory_sections_enabled := v_regulatory_enabled;
  new.localization_snapshot := v_snapshot;
  return new;
end
$function$;

drop trigger if exists reports_localization_snapshot_guard_v1
  on public.reports;
create trigger reports_localization_snapshot_guard_v1
before insert or update on public.reports
for each row
execute function private.enforce_report_localization_snapshot_v1();

-- ---------------------------------------------------------------------------
-- Notifications: parent identity plus immutable exact-locale content.
-- ---------------------------------------------------------------------------

create table if not exists private.notification_template_localizations (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null
    references private.notification_templates(id) on delete cascade,
  locale text not null,
  title text not null,
  body text not null,
  review_status text not null default 'draft',
  checksum text not null,
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewer_name text,
  reviewer_qualification text,
  reviewed_copy_sha256 text,
  review_evidence_sha256 text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_template_localizations_locale_check
    check (
      locale in ('tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA')
    ),
  constraint notification_template_localizations_title_check
    check (char_length(title) between 1 and 80),
  constraint notification_template_localizations_body_check
    check (char_length(body) between 1 and 240),
  constraint notification_template_localizations_review_status_check
    check (review_status in ('draft', 'in_review', 'approved', 'rejected')),
  constraint notification_template_localizations_checksum_check
    check (checksum ~ '^[0-9a-f]{64}$'),
  constraint notification_template_localizations_reviewer_name_check
    check (
      reviewer_name is null
      or char_length(btrim(reviewer_name)) between 1 and 120
    ),
  constraint notification_template_localizations_reviewer_qualification_check
    check (
      reviewer_qualification is null
      or char_length(btrim(reviewer_qualification)) between 1 and 240
    ),
  constraint notification_template_localizations_reviewed_copy_check
    check (
      reviewed_copy_sha256 is null
      or reviewed_copy_sha256 ~ '^[0-9a-f]{64}$'
    ),
  constraint notification_template_localizations_review_evidence_check
    check (
      review_evidence_sha256 is null
      or review_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
  unique (template_id, locale)
);

alter table private.notification_template_localizations
  add column if not exists reviewer_name text,
  add column if not exists reviewer_qualification text,
  add column if not exists reviewed_copy_sha256 text,
  add column if not exists review_evidence_sha256 text;

alter table private.notification_template_localizations
  drop constraint if exists
    notification_template_localizations_english_approval_evidence_check;
alter table private.notification_template_localizations
  add constraint
    notification_template_localizations_english_approval_evidence_check
  check (
    review_status <> 'approved'
    or locale = 'tr-TR'
    or (
      char_length(btrim(reviewer_name)) between 1 and 120
      and char_length(btrim(reviewer_qualification)) between 1 and 240
      and reviewed_copy_sha256 ~ '^[0-9a-f]{64}$'
      and review_evidence_sha256 ~ '^[0-9a-f]{64}$'
      and reviewed_at is not null
    )
  );

create index if not exists notification_template_localizations_review_idx
  on private.notification_template_localizations (
    locale,
    review_status,
    template_id
  );

alter table private.notification_template_localizations
  enable row level security;
revoke all on table private.notification_template_localizations
  from public, anon, authenticated;
grant select, insert, update, delete
  on table private.notification_template_localizations
  to service_role;

alter table private.notification_jobs
  drop constraint if exists notification_jobs_template_localization_fk;
alter table private.notification_jobs
  add constraint notification_jobs_template_localization_fk
  foreign key (template_localization_id)
  references private.notification_template_localizations(id)
  on delete set null;

alter table public.notification_events
  drop constraint if exists notification_events_template_localization_fk;
alter table public.notification_events
  add constraint notification_events_template_localization_fk
  foreign key (template_localization_id)
  references private.notification_template_localizations(id)
  on delete set null;

create table if not exists private.notification_localization_failures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id uuid,
  template_id uuid references private.notification_templates(id)
    on delete set null,
  requested_locale text not null,
  error_code text not null,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint notification_localization_failures_locale_check
    check (
      requested_locale in (
        'tr-TR', 'en-001', 'en-GB', 'en-US', 'en-AU', 'en-CA'
      )
    ),
  constraint notification_localization_failures_context_check
    check (jsonb_typeof(context) = 'object')
);

create index if not exists notification_localization_failures_created_idx
  on private.notification_localization_failures (created_at desc);

alter table private.notification_localization_failures
  enable row level security;
revoke all on table private.notification_localization_failures
  from public, anon, authenticated;
grant select, insert, update, delete
  on table private.notification_localization_failures
  to service_role;

create or replace function private.set_notification_localization_checksum_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.title := btrim(new.title);
  new.body := btrim(new.body);
  new.checksum := encode(
    extensions.digest(
      convert_to(
        concat_ws(
          E'\n',
          new.template_id::text,
          new.locale,
          new.title,
          new.body
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  new.updated_at := now();
  if new.review_status = 'approved' and new.reviewed_at is null then
    new.reviewed_at := now();
  end if;
  return new;
end
$function$;

drop trigger if exists notification_template_localizations_checksum_v1
  on private.notification_template_localizations;
create trigger notification_template_localizations_checksum_v1
before insert or update
on private.notification_template_localizations
for each row
execute function private.set_notification_localization_checksum_v1();

-- Existing Turkish production copy is retained as the approved tr-TR child.
insert into private.notification_template_localizations (
  template_id,
  locale,
  title,
  body,
  review_status,
  checksum,
  reviewed_at
)
select
  t.id,
  'tr-TR',
  t.title,
  t.body,
  'approved',
  repeat('0', 64),
  now()
from private.notification_templates t
on conflict (template_id, locale) do nothing;

-- Project-owner review approved the immutable English review pack on
-- 2026-07-31. Each exact-locale child carries both the reviewed-copy hash and
-- the separate approval-record hash. Runtime still refuses any missing or
-- non-approved exact locale and never falls back to another locale.
insert into private.notification_template_localizations (
  template_id,
  locale,
  title,
  body,
  review_status,
  checksum,
  reviewer_name,
  reviewer_qualification,
  reviewed_copy_sha256,
  review_evidence_sha256,
  reviewed_at
)
select
  t.id,
  locale_row.locale,
  case t.key
    when 'first_analysis_reminder_v1'
      then 'Your first analysis is waiting'
    when 'inactivity_reminder_v1'
      then 'Do not postpone site risks'
    else t.title
  end,
  case t.key
    when 'first_analysis_reminder_v1'
      then 'Add a site photo and review the risks in a few minutes.'
    when 'inactivity_reminder_v1'
      then 'Add a new site photo, update the risk assessment and review the controls.'
    else t.body
  end,
  'approved',
  repeat('0', 64),
  'Kerem',
  'İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.',
  '5660f3a69595a0d8b80057fe2a5a0fb97c9393a003ff2bd72ad8208646955c87',
  'abfbf34bbfcd59e72ac06658ab84970d0429cc1d2020102d866ae48544921158',
  timestamptz '2026-07-31T06:31:04Z'
from private.notification_templates t
cross join (
  values ('en-001'), ('en-GB'), ('en-US'), ('en-AU'), ('en-CA')
) as locale_row(locale)
where t.key in (
  'first_analysis_reminder_v1',
  'inactivity_reminder_v1'
)
on conflict (template_id, locale) do nothing;

create or replace function private.localize_notification_job_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_language text;
  v_locale text;
  v_localization private.notification_template_localizations;
begin
  if tg_op = 'UPDATE' then
    if old.localization_snapshot is not null and (
      new.language is distinct from old.language
      or new.locale is distinct from old.locale
      or new.localization_snapshot is distinct from old.localization_snapshot
      or new.template_locale is distinct from old.template_locale
      or new.template_localization_id
        is distinct from old.template_localization_id
      or new.title is distinct from old.title
      or new.body is distinct from old.body
    ) then
      raise exception using
        errcode = '23514',
        message = 'NOTIFICATION_LOCALIZATION_SNAPSHOT_IMMUTABLE';
    end if;
    return new;
  end if;

  select
    coalesce(p.app_language, 'tr'),
    coalesce(
      p.preferred_content_locale,
      case when p.app_language = 'en' then 'en-001' else 'tr-TR' end
    )
  into v_language, v_locale
  from public.profiles p
  where p.id = new.user_id;

  if v_language is null or v_locale is null then
    v_language := 'tr';
    v_locale := 'tr-TR';
  end if;

  new.language := v_language;
  new.locale := v_locale;

  if new.kind = 'manual_app_reminder' and new.template_id is null then
    new.template_locale := null;
    new.template_localization_id := null;
    new.localization_snapshot := jsonb_build_object(
      'schema_version', 1,
      'language', v_language,
      'locale', v_locale,
      'content_mode', 'controlled_admin_manual',
      'resolved_at', now()
    );
    return new;
  end if;

  select *
  into v_localization
  from private.notification_template_localizations l
  where l.template_id = new.template_id
    and l.locale = v_locale
    and l.review_status = 'approved';

  if not found then
    new.status := 'failed';
    new.last_error_code := 'TEMPLATE_EXACT_LOCALE_MISSING';
    new.last_error_text := concat(
      'No approved exact-locale template for ',
      v_locale
    );
    new.title := 'LOCALIZATION_BLOCKED';
    new.body := 'Exact-locale notification delivery was blocked.';
    new.template_locale := null;
    new.template_localization_id := null;
    new.localization_snapshot := jsonb_build_object(
      'schema_version', 1,
      'language', v_language,
      'locale', v_locale,
      'content_mode', 'blocked',
      'error_code', 'TEMPLATE_EXACT_LOCALE_MISSING',
      'resolved_at', now()
    );
    insert into private.notification_localization_failures (
      user_id,
      job_id,
      template_id,
      requested_locale,
      error_code,
      context
    )
    values (
      new.user_id,
      new.id,
      new.template_id,
      v_locale,
      'TEMPLATE_EXACT_LOCALE_MISSING',
      jsonb_build_object('kind', new.kind, 'dedupe_key', new.dedupe_key)
    );
    return new;
  end if;

  new.title := v_localization.title;
  new.body := v_localization.body;
  new.template_locale := v_localization.locale;
  new.template_localization_id := v_localization.id;
  new.localization_snapshot := jsonb_build_object(
    'schema_version', 1,
    'language', v_language,
    'locale', v_locale,
    'content_mode', 'exact_locale_template',
    'template_id', new.template_id,
    'template_localization_id', v_localization.id,
    'template_locale', v_localization.locale,
    'template_checksum', v_localization.checksum,
    'resolved_at', now()
  );
  return new;
end
$function$;

drop trigger if exists notification_jobs_localization_guard_v1
  on private.notification_jobs;
create trigger notification_jobs_localization_guard_v1
before insert or update on private.notification_jobs
for each row
execute function private.localize_notification_job_v1();

create or replace function public.notification_job_delivery_content_v1(
  p_job_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
stable
as $function$
  select coalesce(
    (
      select jsonb_build_object(
        'allowed', true,
        'job_id', j.id,
        'user_id', j.user_id,
        'kind', j.kind,
        'title', j.title,
        'body', j.body,
        'language', j.language,
        'locale', j.locale,
        'template_id', j.template_id,
        'template_locale', j.template_locale,
        'template_localization_id', j.template_localization_id,
        'localization_snapshot', j.localization_snapshot
      )
      from private.notification_jobs j
      where j.id = p_job_id
        and j.status = 'claimed'
        and j.localization_snapshot is not null
        and j.localization_snapshot ->> 'content_mode' in (
          'exact_locale_template',
          'controlled_admin_manual'
        )
    ),
    jsonb_build_object(
      'allowed', false,
      'error_code', 'NOTIFICATION_JOB_CONTENT_UNAVAILABLE'
    )
  );
$function$;

revoke all on function public.notification_job_delivery_content_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.notification_job_delivery_content_v1(uuid)
  to service_role;

comment on table private.notification_template_localizations is
  'Exact-locale reviewed notification copy; no cross-locale fallback is permitted.';
comment on column private.notification_jobs.localization_snapshot is
  'Immutable locale/template resolution captured when the job is created.';
