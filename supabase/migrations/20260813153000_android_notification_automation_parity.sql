-- Android parity for the shared notification automation eligibility engine.
-- Platform-specific authorization prevents a denial on one platform from disabling the
-- other platform's transport while the legacy aggregate columns keep rule SQL compatible.

alter table public.user_engagement_state
  add column if not exists ios_authorization_status text,
  add column if not exists android_authorization_status text,
  add column if not exists ios_last_foreground_at timestamptz,
  add column if not exists android_last_foreground_at timestamptz;

alter table public.user_engagement_state
  drop constraint if exists user_engagement_ios_authorization_status_check,
  drop constraint if exists user_engagement_android_authorization_status_check;

alter table public.user_engagement_state
  add constraint user_engagement_ios_authorization_status_check
    check (ios_authorization_status is null or ios_authorization_status in (
      'not_determined', 'denied', 'authorized', 'provisional', 'ephemeral'
    )),
  add constraint user_engagement_android_authorization_status_check
    check (android_authorization_status is null or android_authorization_status in (
      'not_determined', 'denied', 'authorized', 'provisional', 'ephemeral'
    ));

-- Every pre-existing heartbeat was written by NotificationService.swift. Android had no RPC
-- caller before this migration, so this backfill is deterministic rather than heuristic.
update public.user_engagement_state
set ios_authorization_status = authorization_status,
    ios_last_foreground_at = last_foreground_at
where ios_authorization_status is null
  and android_authorization_status is null;

create or replace function public.record_user_engagement_state_v1(
  p_timezone text,
  p_locale text default null,
  p_authorization_status text default 'not_determined',
  p_app_version text default null,
  p_app_build text default null
)
returns public.user_engagement_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text := btrim(coalesce(p_timezone, ''));
  v_status text := lower(btrim(coalesce(p_authorization_status, '')));
  v_now timestamptz := now();
  v_existing public.user_engagement_state;
  v_row public.user_engagement_state;
begin
  if v_user_id is null then raise exception 'auth_required' using errcode = '28000'; end if;
  if v_timezone = '' or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = v_timezone
  ) then raise exception 'invalid_timezone' using errcode = '22023'; end if;
  if v_status not in ('not_determined', 'denied', 'authorized', 'provisional', 'ephemeral') then
    raise exception 'invalid_authorization_status' using errcode = '22023';
  end if;

  select * into v_existing from public.user_engagement_state where user_id = v_user_id;
  if found and v_existing.ios_authorization_status = v_status
     and v_existing.updated_at > v_now - interval '1 minute' then
    return v_existing;
  end if;

  insert into public.user_engagement_state (
    user_id, last_foreground_at, timezone, locale, authorization_status,
    authorization_synced_at, app_version, app_build, created_at, updated_at,
    ios_authorization_status, ios_last_foreground_at
  ) values (
    v_user_id, v_now, v_timezone, nullif(left(btrim(coalesce(p_locale, '')), 35), ''),
    v_status, v_now, nullif(left(btrim(coalesce(p_app_version, '')), 40), ''),
    nullif(left(btrim(coalesce(p_app_build, '')), 40), ''), v_now, v_now, v_status, v_now
  )
  on conflict (user_id) do update set
    ios_last_foreground_at = case
      when public.user_engagement_state.ios_last_foreground_at is null
        or public.user_engagement_state.ios_last_foreground_at <= v_now - interval '6 hours'
      then v_now else public.user_engagement_state.ios_last_foreground_at end,
    last_foreground_at = greatest(
      case when public.user_engagement_state.ios_last_foreground_at is null
        or public.user_engagement_state.ios_last_foreground_at <= v_now - interval '6 hours'
        then v_now else public.user_engagement_state.ios_last_foreground_at end,
      coalesce(public.user_engagement_state.android_last_foreground_at, '-infinity'::timestamptz)
    ),
    timezone = excluded.timezone,
    locale = excluded.locale,
    ios_authorization_status = v_status,
    authorization_status = case
      when v_status in ('authorized', 'provisional', 'ephemeral') then v_status
      when public.user_engagement_state.android_authorization_status in
        ('authorized', 'provisional', 'ephemeral')
        then public.user_engagement_state.android_authorization_status
      when v_status = 'denied' or public.user_engagement_state.android_authorization_status = 'denied'
        then 'denied'
      else 'not_determined'
    end,
    authorization_synced_at = v_now,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    updated_at = v_now
  returning * into v_row;

  if v_status = 'denied' then
    update public.push_device_tokens
    set notifications_enabled = false,
        last_failure_at = v_now,
        last_failure_reason = 'system_authorization_denied'
    where user_id = v_user_id and provider = 'apns' and notifications_enabled = true;
  end if;
  return v_row;
end;
$$;

revoke all on function public.record_user_engagement_state_v1(text, text, text, text, text)
  from public, anon;
grant execute on function public.record_user_engagement_state_v1(text, text, text, text, text)
  to authenticated, service_role;

create or replace function public.record_android_user_engagement_state_v1(
  p_timezone text,
  p_locale text default null,
  p_authorization_status text default 'not_determined',
  p_app_version text default null,
  p_app_build text default null,
  p_application_id text default 'com.riskdetectedan.app'
)
returns public.user_engagement_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text := btrim(coalesce(p_timezone, ''));
  v_status text := lower(btrim(coalesce(p_authorization_status, '')));
  v_application_id text := left(btrim(coalesce(p_application_id, '')), 200);
  v_now timestamptz := now();
  v_existing public.user_engagement_state;
  v_row public.user_engagement_state;
begin
  if v_user_id is null then raise exception 'auth_required' using errcode = '28000'; end if;
  if v_timezone = '' or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = v_timezone
  ) then raise exception 'invalid_timezone' using errcode = '22023'; end if;
  if v_status not in ('not_determined', 'denied', 'authorized', 'provisional', 'ephemeral') then
    raise exception 'invalid_authorization_status' using errcode = '22023';
  end if;
  if v_application_id = '' then raise exception 'invalid_application_id' using errcode = '22023'; end if;

  select * into v_existing from public.user_engagement_state where user_id = v_user_id;
  if found and v_existing.android_authorization_status = v_status
     and v_existing.updated_at > v_now - interval '1 minute' then
    return v_existing;
  end if;

  insert into public.user_engagement_state (
    user_id, last_foreground_at, timezone, locale, authorization_status,
    authorization_synced_at, app_version, app_build, created_at, updated_at,
    android_authorization_status, android_last_foreground_at
  ) values (
    v_user_id, v_now, v_timezone, nullif(left(btrim(coalesce(p_locale, '')), 35), ''),
    v_status, v_now, nullif(left(btrim(coalesce(p_app_version, '')), 40), ''),
    nullif(left(btrim(coalesce(p_app_build, '')), 40), ''), v_now, v_now, v_status, v_now
  )
  on conflict (user_id) do update set
    android_last_foreground_at = case
      when public.user_engagement_state.android_last_foreground_at is null
        or public.user_engagement_state.android_last_foreground_at <= v_now - interval '6 hours'
      then v_now else public.user_engagement_state.android_last_foreground_at end,
    last_foreground_at = greatest(
      case when public.user_engagement_state.android_last_foreground_at is null
        or public.user_engagement_state.android_last_foreground_at <= v_now - interval '6 hours'
        then v_now else public.user_engagement_state.android_last_foreground_at end,
      coalesce(public.user_engagement_state.ios_last_foreground_at, '-infinity'::timestamptz)
    ),
    timezone = excluded.timezone,
    locale = excluded.locale,
    android_authorization_status = v_status,
    authorization_status = case
      when public.user_engagement_state.ios_authorization_status in
        ('authorized', 'provisional', 'ephemeral')
        then public.user_engagement_state.ios_authorization_status
      when v_status in ('authorized', 'provisional', 'ephemeral') then v_status
      when v_status = 'denied' or public.user_engagement_state.ios_authorization_status = 'denied'
        then 'denied'
      else 'not_determined'
    end,
    authorization_synced_at = v_now,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    updated_at = v_now
  returning * into v_row;

  if v_status = 'denied' then
    update public.push_device_tokens
    set notifications_enabled = false,
        last_failure_at = v_now,
        last_failure_reason = 'system_authorization_denied'
    where user_id = v_user_id
      and provider = 'fcm'
      and application_id = v_application_id
      and notifications_enabled = true;
  end if;
  return v_row;
end;
$$;

revoke all on function public.record_android_user_engagement_state_v1(
  text, text, text, text, text, text
) from public, anon;
grant execute on function public.record_android_user_engagement_state_v1(
  text, text, text, text, text, text
) to authenticated, service_role;

comment on function public.record_android_user_engagement_state_v1(text, text, text, text, text, text)
  is 'Records Android notification authorization and foreground state without mutating APNs tokens.';
