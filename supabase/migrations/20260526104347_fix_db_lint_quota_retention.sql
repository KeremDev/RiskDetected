-- Fix DB lint failures found while validating Professional Progress.
-- These are pre-existing functions, but keeping global lint clean prevents
-- unrelated backend defects from hiding future progress-module regressions.

create or replace function public.check_and_consume_quota(p_user_id uuid)
returns table(allowed boolean, remaining int, tier subscription_tier)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier subscription_tier;
  v_used int;
  v_reset date;
  v_limit int := 5;
begin
  select p.tier, p.daily_quota_used, p.daily_quota_reset_at
    into v_tier, v_used, v_reset
  from public.profiles p
  where p.id = p_user_id
  for update;

  if not found then
    return query select false, 0, 'free'::subscription_tier;
    return;
  end if;

  if v_tier = 'pro' then
    return query select true, 9999, v_tier;
    return;
  end if;

  if v_reset < current_date then
    update public.profiles p
       set daily_quota_used = 0,
           daily_quota_reset_at = current_date
     where p.id = p_user_id;
    v_used := 0;
  end if;

  if v_used >= v_limit then
    return query select false, 0, v_tier;
    return;
  end if;

  update public.profiles p
     set daily_quota_used = p.daily_quota_used + 1
   where p.id = p_user_id;

  return query select true, (v_limit - v_used - 1), v_tier;
end;
$$;

revoke all on function public.check_and_consume_quota(uuid) from public, anon, authenticated;
grant execute on function public.check_and_consume_quota(uuid) to service_role;

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

  with expired_photos as materialized (
    select id, storage_path
    from public.photos
    where retention_expires_at is not null
      and retention_expires_at < now()
    order by retention_expires_at
    limit batch_size
  ), cleared_findings as (
    update public.findings f
    set photo_id = null
    from expired_photos p
    where f.photo_id = p.id
    returning f.id
  ), deleted_photos as (
    delete from public.photos ph
    using expired_photos p
    where ph.id = p.id
    returning ph.id
  )
  select
    (select count(*) from expired_photos),
    (select count(*) from deleted_photos)
  into storage_pending_count, photo_count;

  expired_raw_ai := raw_count;
  expired_photo_rows := photo_count;
  storage_objects_requiring_api_delete := storage_pending_count;
  return next;
end;
$$;

revoke all on function private.cleanup_expired_retention(integer) from public, anon, authenticated;

select pg_notify('pgrst', 'reload schema');
