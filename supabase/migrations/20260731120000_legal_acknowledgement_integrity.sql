-- Bind English legal acknowledgements to the exact owner-approved documents.
--
-- Existing Turkish clients continue to use the legacy table path. Any
-- acknowledgement for the English document set is fail-closed against this
-- server-owned registry, whether it arrives through the RPC or a direct write.

create table if not exists private.approved_legal_documents (
  document_set_id text not null,
  document_locale text not null,
  document_kind text not null,
  version text not null,
  document_checksum text not null,
  change_type text not null,
  reviewer_name text not null,
  reviewer_qualification text not null,
  reviewed_at timestamptz not null,
  approval_record_sha256 text not null,
  created_at timestamptz not null default now(),
  primary key (document_set_id, document_locale, document_kind, version),
  unique (document_kind, version),
  constraint approved_legal_documents_set_check
    check (document_set_id in ('tr-current', 'en-global-v1')),
  constraint approved_legal_documents_locale_check
    check (document_locale in ('tr', 'en')),
  constraint approved_legal_documents_kind_check
    check (document_kind in ('terms', 'privacy', 'kvkk', 'consent')),
  constraint approved_legal_documents_checksum_check
    check (document_checksum ~ '^[0-9a-f]{64}$'),
  constraint approved_legal_documents_change_type_check
    check (
      change_type in (
        'info',
        'material_terms',
        'material_privacy',
        'explicit_consent'
      )
    ),
  constraint approved_legal_documents_approval_hash_check
    check (approval_record_sha256 ~ '^[0-9a-f]{64}$')
);

alter table private.approved_legal_documents enable row level security;
revoke all on private.approved_legal_documents
  from public, anon, authenticated;
grant select on private.approved_legal_documents to service_role;

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
    'en-global-v1',
    'en',
    'terms',
    'terms-en-2026-07-31.1',
    '49a9b3f164b9dc8048453be930509aa334a854834c2abfa0cd8b11fd67ef6efa',
    'material_terms',
    'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-07-31T08:02:40Z'::timestamptz,
    '54ade7d6aae5615bcd5a1ce2f3191c1fecb77d9080ff61edf88b948afe129161'
  ),
  (
    'en-global-v1',
    'en',
    'privacy',
    'privacy-en-2026-07-31.1',
    'ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4',
    'material_privacy',
    'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-07-31T08:02:40Z'::timestamptz,
    '54ade7d6aae5615bcd5a1ce2f3191c1fecb77d9080ff61edf88b948afe129161'
  ),
  (
    'en-global-v1',
    'en',
    'consent',
    'ai-data-en-2026-07-31.1',
    'a8c9873f57228a36a4ede597e33648ff9251f9c814f1d1afc3e912c82ae08e1b',
    'explicit_consent',
    'Kerem',
    'Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.',
    '2026-07-31T08:02:40Z'::timestamptz,
    '54ade7d6aae5615bcd5a1ce2f3191c1fecb77d9080ff61edf88b948afe129161'
  )
on conflict (document_set_id, document_locale, document_kind, version)
do update set
  document_checksum = excluded.document_checksum,
  change_type = excluded.change_type,
  reviewer_name = excluded.reviewer_name,
  reviewer_qualification = excluded.reviewer_qualification,
  reviewed_at = excluded.reviewed_at,
  approval_record_sha256 = excluded.approval_record_sha256;

alter table public.legal_document_acknowledgements
  drop constraint if exists legal_document_acknowledgements_change_type_check;
alter table public.legal_document_acknowledgements
  add constraint legal_document_acknowledgements_change_type_check
  check (
    change_type in (
      'info',
      'material_terms',
      'material_privacy',
      'explicit_consent'
    )
  );

create or replace function private.enforce_legal_acknowledgement_integrity_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_approved private.approved_legal_documents%rowtype;
begin
  select approved.*
  into v_approved
  from private.approved_legal_documents approved
  where approved.document_kind = new.document_kind
    and approved.version = new.version;

  if found then
    if new.document_set_id is distinct from v_approved.document_set_id
       or new.document_locale is distinct from v_approved.document_locale
       or new.document_checksum is distinct from v_approved.document_checksum
       or new.change_type is distinct from v_approved.change_type then
      raise exception using
        errcode = '22023',
        message = 'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_MISMATCH';
    end if;
  elsif new.document_set_id = 'en-global-v1'
        or new.document_locale = 'en' then
    raise exception using
      errcode = '22023',
      message = 'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_NOT_APPROVED';
  end if;

  return new;
end
$function$;

drop trigger if exists legal_acknowledgement_integrity_v1
  on public.legal_document_acknowledgements;
create trigger legal_acknowledgement_integrity_v1
  before insert or update
  on public.legal_document_acknowledgements
  for each row
  execute function private.enforce_legal_acknowledgement_integrity_v1();

revoke all on function private.enforce_legal_acknowledgement_integrity_v1()
  from public, anon, authenticated;

create or replace function public.acknowledge_legal_document_v1(
  p_document_kind text,
  p_version text,
  p_change_type text,
  p_document_set_id text,
  p_document_locale text,
  p_document_checksum text,
  p_action text,
  p_source text,
  p_app_version text,
  p_device_id text
)
returns public.legal_document_acknowledgements
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_approved private.approved_legal_documents%rowtype;
  v_now timestamptz := now();
  v_result public.legal_document_acknowledgements%rowtype;
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'AUTHENTICATION_REQUIRED';
  end if;
  if p_action not in ('seen', 'continued_use_accepted', 'explicitly_accepted') then
    raise exception using
      errcode = '22023',
      message = 'LEGAL_ACKNOWLEDGEMENT_ACTION_INVALID';
  end if;

  select approved.*
  into v_approved
  from private.approved_legal_documents approved
  where approved.document_set_id = p_document_set_id
    and approved.document_locale = p_document_locale
    and approved.document_kind = p_document_kind
    and approved.version = p_version;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_NOT_APPROVED';
  end if;
  if p_document_checksum is distinct from v_approved.document_checksum
     or p_change_type is distinct from v_approved.change_type then
    raise exception using
      errcode = '22023',
      message = 'LEGAL_ACKNOWLEDGEMENT_DOCUMENT_MISMATCH';
  end if;

  insert into public.legal_document_acknowledgements (
    user_id,
    document_kind,
    version,
    change_type,
    document_set_id,
    document_locale,
    document_checksum,
    seen_at,
    continued_use_accepted_at,
    explicitly_accepted_at,
    source,
    app_version,
    device_id
  )
  values (
    v_user_id,
    v_approved.document_kind,
    v_approved.version,
    v_approved.change_type,
    v_approved.document_set_id,
    v_approved.document_locale,
    v_approved.document_checksum,
    v_now,
    case when p_action = 'continued_use_accepted' then v_now end,
    case when p_action = 'explicitly_accepted' then v_now end,
    left(coalesce(nullif(btrim(p_source), ''), 'legal_update_notice'), 120),
    left(nullif(btrim(p_app_version), ''), 40),
    left(nullif(btrim(p_device_id), ''), 160)
  )
  on conflict (user_id, document_kind, version)
  do update set
    change_type = excluded.change_type,
    document_set_id = excluded.document_set_id,
    document_locale = excluded.document_locale,
    document_checksum = excluded.document_checksum,
    seen_at = coalesce(
      public.legal_document_acknowledgements.seen_at,
      excluded.seen_at
    ),
    continued_use_accepted_at = coalesce(
      public.legal_document_acknowledgements.continued_use_accepted_at,
      excluded.continued_use_accepted_at
    ),
    explicitly_accepted_at = coalesce(
      public.legal_document_acknowledgements.explicitly_accepted_at,
      excluded.explicitly_accepted_at
    ),
    source = excluded.source,
    app_version = excluded.app_version,
    device_id = excluded.device_id
  returning *
  into v_result;

  return v_result;
end
$function$;

revoke all on function public.acknowledge_legal_document_v1(
  text, text, text, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.acknowledge_legal_document_v1(
  text, text, text, text, text, text, text, text, text, text
) to authenticated, service_role;

select pg_notify('pgrst', 'reload schema');
