-- RiskDetected retention policy
--
-- Policy:
-- - Analysis photos are retained for 30 days for free users and 365 days for pro users.
-- - PDF reports are retained until the user deletes them.
-- - Raw AI responses are diagnostic/audit data and expire after 30 days.
-- - Analyses and findings stay in place unless the user deletes them.
-- - Storage objects must be deleted through the Storage API; direct DELETE from storage.objects is blocked by Supabase.

alter table public.analyses
  add column if not exists raw_ai_response_expires_at timestamptz;

alter table public.photos
  add column if not exists retention_expires_at timestamptz,
  add column if not exists retention_policy text not null default 'analysis_photo';

create index if not exists analyses_raw_ai_response_expires_idx
  on public.analyses (raw_ai_response_expires_at)
  where raw_ai_response is not null;

create index if not exists photos_retention_expires_idx
  on public.photos (retention_expires_at)
  where retention_expires_at is not null;

create or replace function public.set_analysis_retention_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.raw_ai_response is not null
     and new.raw_ai_response_expires_at is null then
    new.raw_ai_response_expires_at := coalesce(new.completed_at, new.created_at, now()) + interval '30 days';
  end if;

  return new;
end;
$$;

drop trigger if exists analyses_set_retention_fields on public.analyses;
create trigger analyses_set_retention_fields
  before insert or update of raw_ai_response, raw_ai_response_expires_at, completed_at, created_at
  on public.analyses
  for each row
  execute function public.set_analysis_retention_fields();

create or replace function public.set_photo_retention_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  user_tier text;
  retention_days integer;
begin
  select p.tier::text
    into user_tier
  from public.profiles p
  where p.id = new.user_id;

  retention_days := case when user_tier = 'pro' then 365 else 30 end;

  if new.retention_expires_at is null then
    new.retention_expires_at := coalesce(new.created_at, now()) + make_interval(days => retention_days);
  end if;

  if new.retention_policy is null or new.retention_policy = 'analysis_photo' then
    new.retention_policy := case
      when user_tier = 'pro' then 'pro_photo_365d'
      else 'free_photo_30d'
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists photos_set_retention_fields on public.photos;
create trigger photos_set_retention_fields
  before insert or update of user_id, created_at, retention_expires_at, retention_policy
  on public.photos
  for each row
  execute function public.set_photo_retention_fields();

update public.analyses
set raw_ai_response_expires_at = coalesce(completed_at, created_at, now()) + interval '30 days'
where raw_ai_response is not null
  and raw_ai_response_expires_at is null;

update public.photos ph
set retention_expires_at = coalesce(ph.created_at, now()) +
    case when p.tier = 'pro' then interval '365 days' else interval '30 days' end,
    retention_policy = case when p.tier = 'pro' then 'pro_photo_365d' else 'free_photo_30d' end
from public.profiles p
where p.id = ph.user_id
  and ph.retention_expires_at is null;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

drop function if exists private.cleanup_expired_retention(integer);

create or replace function private.cleanup_expired_retention(batch_size integer default 500)
returns table(
  expired_raw_ai integer,
  expired_photo_rows integer,
  storage_objects_requiring_api_delete integer
)
language plpgsql
security definer
set search_path = public, storage, private
as $$
declare
  raw_count integer := 0;
  photo_count integer := 0;
  storage_pending_count integer := 0;
begin
  if batch_size is null or batch_size < 1 then
    batch_size := 500;
  end if;

  with expired as (
    select id
    from public.analyses
    where raw_ai_response is not null
      and raw_ai_response_expires_at is not null
      and raw_ai_response_expires_at < now()
    order by raw_ai_response_expires_at
    limit batch_size
  ), updated as (
    update public.analyses a
    set raw_ai_response = null,
        updated_at = now()
    from expired e
    where a.id = e.id
    returning a.id
  )
  select count(*) into raw_count from updated;

  create temporary table if not exists tmp_expired_retention_photos (
    id uuid primary key,
    storage_path text not null
  ) on commit drop;

  truncate table tmp_expired_retention_photos;

  insert into tmp_expired_retention_photos (id, storage_path)
  select id, storage_path
  from public.photos
  where retention_expires_at is not null
    and retention_expires_at < now()
  order by retention_expires_at
  limit batch_size;

  update public.findings f
  set photo_id = null
  from tmp_expired_retention_photos p
  where f.photo_id = p.id;

  select count(*) into storage_pending_count
  from tmp_expired_retention_photos;

  delete from public.photos ph
  using tmp_expired_retention_photos p
  where ph.id = p.id;
  get diagnostics photo_count = row_count;

  expired_raw_ai := raw_count;
  expired_photo_rows := photo_count;
  storage_objects_requiring_api_delete := storage_pending_count;
  return next;
end;
$$;

revoke all on function private.cleanup_expired_retention(integer) from public, anon, authenticated;

select pg_notify('pgrst', 'reload schema');
