-- Restrict authenticated clients to the fields used by the shipping iOS
-- contract, bind photo metadata to its owner/analysis path, and provide an
-- atomic finding-mutation primitive for the privileged Edge Function.
--
-- service_role keeps full access. Existing rows are not rewritten.

begin;

create or replace function public.guard_authenticated_analysis_write()
returns trigger
language plpgsql
set search_path = public, auth, pg_temp
as $$
declare
  company_is_owned boolean;
  valid_failure_transition boolean;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if auth.uid() is null or new.user_id <> auth.uid() then
    raise exception 'analysis_owner_mismatch' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending' then
      raise exception 'analysis_initial_status_must_be_pending'
        using errcode = '42501';
    end if;
    return new;
  end if;

  valid_failure_transition :=
    old.status = 'pending' and new.status = 'failed';
  if (
    new.status is distinct from old.status
    or new.status_message is distinct from old.status_message
  ) and not valid_failure_transition then
    raise exception 'analysis_status_is_server_owned'
      using errcode = '42501';
  end if;

  if new.company_id is distinct from old.company_id
     and new.company_id is not null then
    select exists (
      select 1
      from public.companies c
      where c.id = new.company_id
        and c.user_id = auth.uid()
    ) into company_is_owned;
    if not company_is_owned then
      raise exception 'analysis_company_owner_mismatch'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists analyses_authenticated_write_guard
  on public.analyses;
create trigger analyses_authenticated_write_guard
  before insert or update on public.analyses
  for each row
  execute function public.guard_authenticated_analysis_write();

create or replace function public.guard_authenticated_photo_write()
returns trigger
language plpgsql
set search_path = public, auth, pg_temp
as $$
declare
  expected_prefix text;
  object_name text;
  analysis_is_owned boolean;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if auth.uid() is null or new.user_id <> auth.uid() then
    raise exception 'photo_owner_mismatch' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.analyses a
    where a.id = new.analysis_id
      and a.user_id = auth.uid()
  ) into analysis_is_owned;
  if not analysis_is_owned then
    raise exception 'photo_analysis_owner_mismatch' using errcode = '42501';
  end if;

  expected_prefix :=
    lower(auth.uid()::text) || '/' || lower(new.analysis_id::text) || '/';
  if left(lower(new.storage_path), length(expected_prefix)) <>
      expected_prefix then
    raise exception 'photo_storage_path_owner_mismatch'
      using errcode = '42501';
  end if;

  object_name := substring(new.storage_path from length(expected_prefix) + 1);
  if object_name = '' or position('/' in object_name) > 0 then
    raise exception 'photo_storage_path_shape_invalid'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and (
    new.user_id is distinct from old.user_id
    or new.analysis_id is distinct from old.analysis_id
    or new.storage_path is distinct from old.storage_path
    or new.retention_expires_at is distinct from old.retention_expires_at
    or new.retention_policy is distinct from old.retention_policy
    or new.ai_scene_summary is distinct from old.ai_scene_summary
  ) then
    raise exception 'photo_server_fields_are_immutable'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists photos_authenticated_write_guard
  on public.photos;
create trigger photos_authenticated_write_guard
  before insert or update on public.photos
  for each row
  execute function public.guard_authenticated_photo_write();

create or replace function public.force_authenticated_profile_free_tier()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user = 'authenticated' then
    new.tier := 'free';
    new.subscription_period := null;
    new.subscription_renewal_at := null;
    new.daily_quota_used := 0;
    new.daily_quota_reset_at := current_date;
    new.welcome_email_sent_at := null;
    new.welcome_email_status := null;
    new.welcome_email_error := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_authenticated_insert_guard
  on public.profiles;
create trigger profiles_authenticated_insert_guard
  before insert on public.profiles
  for each row
  execute function public.force_authenticated_profile_free_tier();

revoke all on table public.analyses from anon, authenticated;
grant select, delete on table public.analyses to authenticated;
grant insert (
  id,
  user_id,
  title,
  kind,
  canvas,
  text_input,
  status,
  primary_method,
  company_id,
  analysis_sector,
  analysis_sector_source,
  analysis_sector_prompt_version
) on table public.analyses to authenticated;
grant update (
  company_id,
  status,
  status_message
) on table public.analyses to authenticated;

revoke all on table public.photos from anon, authenticated;
grant select, delete on table public.photos to authenticated;
grant insert (
  analysis_id,
  user_id,
  storage_path,
  width,
  height,
  size_bytes,
  mime_type,
  annotations,
  exif,
  sequence_index,
  client_photo_id,
  is_primary,
  original_filename,
  byte_size,
  thumbnail_storage_path,
  annotation_storage_path,
  user_caption,
  upload_payload_version,
  compression_metadata
) on table public.photos to authenticated;
grant update (
  annotations,
  annotation_storage_path,
  user_caption
) on table public.photos to authenticated;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (
  id,
  email,
  full_name,
  initials,
  title,
  certificate_number,
  company_name,
  company_logo_url,
  phone,
  tier,
  preferred_method,
  avatar_url,
  app_language,
  preferred_content_locale,
  work_jurisdiction_country,
  work_jurisdiction_region,
  safety_profile_id,
  safety_profile_version,
  legal_document_set
) on table public.profiles to authenticated;
grant update (
  id,
  email,
  full_name,
  initials,
  title,
  certificate_number,
  company_name,
  company_logo_url,
  phone,
  preferred_method,
  avatar_url,
  app_language,
  preferred_content_locale,
  work_jurisdiction_country,
  work_jurisdiction_region,
  safety_profile_id,
  safety_profile_version,
  legal_document_set
) on table public.profiles to authenticated;

drop function if exists public.apply_finding_mutation_atomic(
  text,
  uuid,
  uuid,
  uuid,
  integer,
  jsonb,
  text[],
  text,
  text,
  text
);

create function public.apply_finding_mutation_atomic(
  p_action text,
  p_analysis_id uuid,
  p_finding_id uuid,
  p_user_id uuid,
  p_expected_version integer,
  p_update jsonb default '{}'::jsonb,
  p_changed_fields text[] default '{}'::text[],
  p_client_app_version text default null,
  p_request_id text default null,
  p_support_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  before_row public.findings%rowtype;
  after_row public.findings%rowtype;
  unsupported_key text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  if p_action not in ('update', 'delete') then
    raise exception 'invalid_finding_action' using errcode = '22023';
  end if;

  select f.*
    into before_row
  from public.findings f
  where f.id = p_finding_id
    and f.analysis_id = p_analysis_id
    and f.user_id = p_user_id
  for update;

  if not found then
    raise exception 'finding_not_found' using errcode = 'P0002';
  end if;
  if coalesce(before_row.finding_version, 1) <> p_expected_version then
    raise exception 'finding_version_conflict' using errcode = '40001';
  end if;

  if p_action = 'delete' then
    insert into public.finding_edit_events (
      analysis_id,
      finding_id,
      actor_user_id,
      event_type,
      before_snapshot,
      after_snapshot,
      changed_fields,
      finding_version_before,
      finding_version_after,
      client_app_version,
      request_id,
      support_id
    ) values (
      p_analysis_id,
      p_finding_id,
      p_user_id,
      'hard_delete',
      to_jsonb(before_row),
      null,
      array['__deleted__']::text[],
      before_row.finding_version,
      null,
      left(p_client_app_version, 80),
      left(p_request_id, 160),
      left(p_support_id, 160)
    );

    delete from public.findings
    where id = p_finding_id
      and analysis_id = p_analysis_id
      and user_id = p_user_id
      and finding_version = p_expected_version;

    if not found then
      raise exception 'finding_version_conflict' using errcode = '40001';
    end if;

    return jsonb_build_object(
      'action', 'delete',
      'finding_version_before', before_row.finding_version
    );
  end if;

  select key
    into unsupported_key
  from jsonb_object_keys(coalesce(p_update, '{}'::jsonb)) as key
  where key <> all (array[
    'title',
    'category',
    'description',
    'recommended_action',
    'recommended_measures',
    'references_text',
    'root_cause_text',
    'source_photo_indices',
    'fk_probability',
    'fk_frequency',
    'fk_severity',
    'fk_band',
    'm5_probability',
    'm5_severity',
    'm5_band'
  ]::text[])
  limit 1;

  if unsupported_key is not null then
    raise exception 'unsupported_finding_field:%', unsupported_key
      using errcode = '22023';
  end if;

  select *
    into after_row
  from jsonb_populate_record(before_row, coalesce(p_update, '{}'::jsonb));
  after_row.last_user_edit_at := now();
  after_row.last_user_edit_by := p_user_id;
  after_row.user_edit_count := coalesce(before_row.user_edit_count, 0) + 1;
  after_row.finding_version := before_row.finding_version + 1;

  update public.findings
  set
    title = after_row.title,
    category = after_row.category,
    description = after_row.description,
    recommended_action = after_row.recommended_action,
    recommended_measures = after_row.recommended_measures,
    references_text = after_row.references_text,
    root_cause_text = after_row.root_cause_text,
    source_photo_indices = after_row.source_photo_indices,
    fk_probability = after_row.fk_probability,
    fk_frequency = after_row.fk_frequency,
    fk_severity = after_row.fk_severity,
    fk_band = after_row.fk_band,
    m5_probability = after_row.m5_probability,
    m5_severity = after_row.m5_severity,
    m5_band = after_row.m5_band,
    last_user_edit_at = after_row.last_user_edit_at,
    last_user_edit_by = after_row.last_user_edit_by,
    user_edit_count = after_row.user_edit_count,
    finding_version = after_row.finding_version,
    updated_at = now()
  where id = p_finding_id
    and analysis_id = p_analysis_id
    and user_id = p_user_id
    and finding_version = p_expected_version
  returning * into after_row;

  if not found then
    raise exception 'finding_version_conflict' using errcode = '40001';
  end if;

  insert into public.finding_edit_events (
    analysis_id,
    finding_id,
    actor_user_id,
    event_type,
    before_snapshot,
    after_snapshot,
    changed_fields,
    finding_version_before,
    finding_version_after,
    client_app_version,
    request_id,
    support_id
  ) values (
    p_analysis_id,
    p_finding_id,
    p_user_id,
    'update',
    to_jsonb(before_row),
    to_jsonb(after_row),
    coalesce(p_changed_fields, '{}'::text[]),
    before_row.finding_version,
    after_row.finding_version,
    left(p_client_app_version, 80),
    left(p_request_id, 160),
    left(p_support_id, 160)
  );

  return to_jsonb(after_row);
end;
$$;

revoke all on function public.apply_finding_mutation_atomic(
  text,
  uuid,
  uuid,
  uuid,
  integer,
  jsonb,
  text[],
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.apply_finding_mutation_atomic(
  text,
  uuid,
  uuid,
  uuid,
  integer,
  jsonb,
  text[],
  text,
  text,
  text
) to service_role;

select pg_notify('pgrst', 'reload schema');

commit;
