begin;

-- Platform analytics is deliberately independent from profiles.client_platform.
-- The legacy column participates in legal-document selection and must not be
-- repurposed as a mutable "last used platform" signal.
alter table public.profiles
  add column if not exists signup_platform text,
  add column if not exists signup_platform_source text,
  add column if not exists signup_platform_recorded_at timestamptz,
  add column if not exists last_seen_platform text,
  add column if not exists last_seen_platform_at timestamptz,
  add column if not exists platform_attribution_version smallint;

-- Rows which existed before this migration must never acquire a signup platform
-- merely because the user later installs a telemetry-capable build.
update public.profiles
set platform_attribution_version = 0
where platform_attribution_version is null;

update public.profiles
set signup_platform_source = 'unknown'
where signup_platform_source is null;

alter table public.profiles
  alter column platform_attribution_version set default 1,
  alter column platform_attribution_version set not null,
  alter column signup_platform_source set default 'unknown',
  alter column signup_platform_source set not null;

alter table public.profiles
  drop constraint if exists profiles_signup_platform_check,
  add constraint profiles_signup_platform_check
    check (signup_platform is null or signup_platform in ('ios', 'android')),
  drop constraint if exists profiles_last_seen_platform_check,
  add constraint profiles_last_seen_platform_check
    check (last_seen_platform is null or last_seen_platform in ('ios', 'android')),
  drop constraint if exists profiles_signup_platform_source_check,
  add constraint profiles_signup_platform_source_check
    check (signup_platform_source in ('unknown', 'first_authenticated_observation', 'inferred_activity')),
  drop constraint if exists profiles_platform_attribution_version_check,
  add constraint profiles_platform_attribution_version_check
    check (platform_attribution_version in (0, 1)),
  drop constraint if exists profiles_signup_platform_timestamp_check,
  add constraint profiles_signup_platform_timestamp_check
    check (
      (signup_platform is null and signup_platform_recorded_at is null)
      or (signup_platform is not null and signup_platform_recorded_at is not null)
    ),
  drop constraint if exists profiles_last_seen_platform_timestamp_check,
  add constraint profiles_last_seen_platform_timestamp_check
    check (
      (last_seen_platform is null and last_seen_platform_at is null)
      or (last_seen_platform is not null and last_seen_platform_at is not null)
    );

comment on column public.profiles.signup_platform is
  'Immutable first trusted mobile platform observation. Independent from profiles.client_platform, which owns legal-document selection.';
comment on column public.profiles.platform_attribution_version is
  '0 for profiles predating platform analytics; 1 for profiles created after this migration.';
comment on column public.profiles.last_seen_platform is
  'Most recently observed mobile platform. Analytics only; never used for authorization, entitlement, quota, or legal-document selection.';

-- Do not expose the new profile fields for direct client mutation. Existing
-- column-scoped grants intentionally remain unchanged.
revoke insert (
  signup_platform,
  signup_platform_source,
  signup_platform_recorded_at,
  last_seen_platform,
  last_seen_platform_at,
  platform_attribution_version
) on public.profiles from authenticated;
revoke update (
  signup_platform,
  signup_platform_source,
  signup_platform_recorded_at,
  last_seen_platform,
  last_seen_platform_at,
  platform_attribution_version
) on public.profiles from authenticated;

create table if not exists public.user_platform_daily_activity (
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  activity_day date not null,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  app_version text,
  app_build text,
  observation_count integer not null default 1 check (observation_count > 0),
  primary key (user_id, platform, activity_day),
  constraint user_platform_daily_activity_time_check
    check (last_seen_at >= first_seen_at),
  constraint user_platform_daily_activity_app_version_check
    check (app_version is null or app_version ~ '^[0-9A-Za-z][0-9A-Za-z._+\-]{0,39}$'),
  constraint user_platform_daily_activity_app_build_check
    check (app_build is null or app_build ~ '^[0-9]{1,20}$')
);

alter table public.user_platform_daily_activity enable row level security;
revoke all on public.user_platform_daily_activity from public, anon, authenticated;
grant select, insert, update, delete on public.user_platform_daily_activity to service_role;

create index if not exists user_platform_daily_activity_platform_day_idx
  on public.user_platform_daily_activity (platform, activity_day desc);
create index if not exists profiles_signup_platform_created_idx
  on public.profiles (signup_platform, created_at desc);
create index if not exists profiles_last_seen_platform_at_idx
  on public.profiles (last_seen_platform, last_seen_platform_at desc);

alter table public.reports
  add column if not exists client_platform text;
alter table public.reports
  drop constraint if exists reports_client_platform_check,
  add constraint reports_client_platform_check
    check (client_platform is null or client_platform in ('ios', 'android'));

update public.reports r
set client_platform = a.client_platform
from public.analyses a
where r.analysis_id = a.id
  and r.client_platform is null
  and a.client_platform in ('ios', 'android');

create index if not exists reports_client_platform_created_idx
  on public.reports (client_platform, created_at desc);

comment on column public.reports.client_platform is
  'Platform on which the report was requested. Falls back to the related analysis platform for legacy clients.';

create or replace function public.record_client_platform_v1(
  p_platform text,
  p_app_version text default null,
  p_app_build text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_platform text := lower(btrim(coalesce(p_platform, '')));
  v_app_version text := nullif(btrim(coalesce(p_app_version, '')), '');
  v_app_build text := nullif(btrim(coalesce(p_app_build, '')), '');
  v_now timestamptz := clock_timestamp();
  v_activity_day date := (clock_timestamp() at time zone 'Europe/Istanbul')::date;
  v_attribution_version smallint;
  v_signup_platform text;
  v_last_seen_platform text;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'auth_required';
  end if;
  if v_platform not in ('ios', 'android') then
    raise exception using errcode = '22023', message = 'invalid_client_platform';
  end if;
  if v_app_version is not null and v_app_version !~ '^[0-9A-Za-z][0-9A-Za-z._+\-]{0,39}$' then
    raise exception using errcode = '22023', message = 'invalid_app_version';
  end if;
  if v_app_build is not null and v_app_build !~ '^[0-9]{1,20}$' then
    raise exception using errcode = '22023', message = 'invalid_app_build';
  end if;

  select p.platform_attribution_version, p.signup_platform
    into v_attribution_version, v_signup_platform
  from public.profiles p
  where p.id = v_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'recorded', false,
      'reason', 'profile_not_ready'
    );
  end if;

  update public.profiles p
  set signup_platform = case
        when p.signup_platform is null and v_attribution_version >= 1 then v_platform
        else p.signup_platform
      end,
      signup_platform_source = case
        when p.signup_platform is null and v_attribution_version >= 1
          then 'first_authenticated_observation'
        else p.signup_platform_source
      end,
      signup_platform_recorded_at = case
        when p.signup_platform is null and v_attribution_version >= 1 then v_now
        else p.signup_platform_recorded_at
      end,
      last_seen_platform = v_platform,
      last_seen_platform_at = v_now
  where p.id = v_user_id
  returning p.signup_platform, p.last_seen_platform
    into v_signup_platform, v_last_seen_platform;

  insert into public.user_platform_daily_activity (
    user_id,
    platform,
    activity_day,
    first_seen_at,
    last_seen_at,
    app_version,
    app_build,
    observation_count
  ) values (
    v_user_id,
    v_platform,
    v_activity_day,
    v_now,
    v_now,
    v_app_version,
    v_app_build,
    1
  )
  on conflict (user_id, platform, activity_day) do update
  set last_seen_at = excluded.last_seen_at,
      app_version = coalesce(excluded.app_version, public.user_platform_daily_activity.app_version),
      app_build = coalesce(excluded.app_build, public.user_platform_daily_activity.app_build),
      observation_count = public.user_platform_daily_activity.observation_count + 1;

  return jsonb_build_object(
    'recorded', true,
    'signup_platform', v_signup_platform,
    'last_seen_platform', v_last_seen_platform,
    'activity_day', v_activity_day
  );
end
$function$;

revoke all on function public.record_client_platform_v1(text, text, text)
  from public, anon;
grant execute on function public.record_client_platform_v1(text, text, text)
  to authenticated;

create or replace function public.admin_platform_overview_v1(
  p_days integer default 30,
  p_platform text default 'all'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_days integer := p_days;
  v_platform text := lower(trim(coalesce(p_platform, 'all')));
  v_start timestamptz;
  v_result jsonb;
begin
  if v_days not in (7, 30, 90) then
    raise exception using errcode = '22023', message = 'invalid_days';
  end if;
  if v_platform not in ('all', 'ios', 'android', 'unknown') then
    raise exception using errcode = '22023', message = 'invalid_platform';
  end if;

  v_start := (
    date_trunc('day', pg_catalog.now() at time zone 'Europe/Istanbul')
    - pg_catalog.make_interval(days => v_days - 1)
  ) at time zone 'Europe/Istanbul';

  with
  profile_scope as (
    select p.*
    from public.profiles p
    where v_platform = 'all'
       or coalesce(p.signup_platform, 'unknown') = v_platform
  ),
  last_seen_scope as (
    select p.*
    from public.profiles p
    where v_platform = 'all'
       or coalesce(p.last_seen_platform, 'unknown') = v_platform
  ),
  active_users as (
    select distinct a.user_id
    from public.user_platform_daily_activity a
    where a.first_seen_at >= v_start
      and (v_platform = 'all' or a.platform = v_platform)
  ),
  cross_platform_users as (
    select a.user_id
    from public.user_platform_daily_activity a
    where a.first_seen_at >= v_start
    group by a.user_id
    having count(distinct a.platform) > 1
  ),
  analysis_scope as (
    select a.*
    from public.analyses a
    where a.created_at >= v_start
      and (v_platform = 'all' or coalesce(a.client_platform, 'unknown') = v_platform)
  ),
  report_scope as (
    select r.*
    from public.reports r
    where r.created_at >= v_start
      and (v_platform = 'all' or coalesce(r.client_platform, 'unknown') = v_platform)
  ),
  ai_scope as (
    select l.*
    from public.ai_usage_logs l
    where l.created_at >= v_start
      and (v_platform = 'all' or coalesce(l.client_platform, 'unknown') = v_platform)
  ),
  subscription_scope as (
    select s.*
    from public.user_subscriptions s
    where s.status in ('active', 'trialing', 'grace_period')
      and (
        v_platform = 'all'
        or case
             when s.store = 'APP_STORE' then 'ios'
             when s.store = 'PLAY_STORE' then 'android'
             else 'unknown'
           end = v_platform
      )
  )
  select jsonb_build_object(
    'period', jsonb_build_object('days', v_days, 'start', v_start, 'end', pg_catalog.now()),
    'platform', v_platform,
    'users', jsonb_build_object(
      'new', (select count(*) from profile_scope p where p.created_at >= v_start),
      'total', (select count(*) from profile_scope),
      'last_seen', (select count(*) from last_seen_scope),
      'active', (select count(*) from active_users),
      'cross_platform', case
        when v_platform = 'unknown' then 0
        else (select count(*) from cross_platform_users)
      end
    ),
    'analyses', jsonb_build_object(
      'total', (select count(*) from analysis_scope),
      'completed', (select count(*) from analysis_scope where status::text = 'completed'),
      'failed', (select count(*) from analysis_scope where status::text = 'failed'),
      'standard', (select count(*) from analysis_scope where analysis_mode = 'standard'),
      'detailed', (select count(*) from analysis_scope where analysis_mode = 'detailed'),
      'fine_kinney', (select count(*) from analysis_scope where primary_method::text = 'fine_kinney'),
      'matrix_5x5', (select count(*) from analysis_scope where primary_method::text = 'matrix_5x5'),
      'single_photo', (select count(*) from analysis_scope where photo_count = 1),
      'multi_photo', (select count(*) from analysis_scope where photo_count > 1),
      'sectors', coalesce((
        select jsonb_object_agg(key, value)
        from (select coalesce(analysis_sector, 'unknown') key, count(*) value from analysis_scope group by 1) x
      ), '{}'::jsonb),
      'canvases', coalesce((
        select jsonb_object_agg(key, value)
        from (select coalesce(canvas::text, 'unknown') key, count(*) value from analysis_scope group by 1) x
      ), '{}'::jsonb)
    ),
    'reports', jsonb_build_object(
      'total', (select count(*) from report_scope),
      'pdf', (select count(*) from report_scope where lower(format) = 'pdf'),
      'xlsx', (select count(*) from report_scope where lower(format) = 'xlsx')
    ),
    'ai', jsonb_build_object(
      'calls', (select count(*) from ai_scope),
      'total_tokens', (select coalesce(sum(total_tokens), 0) from ai_scope),
      'provider_attempt_total_tokens', (select coalesce(sum(provider_attempt_total_tokens), 0) from ai_scope)
    ),
    'subscriptions', jsonb_build_object(
      'free', (select count(*) from last_seen_scope where tier::text = 'free'),
      'plus', (select count(*) from last_seen_scope where tier::text = 'plus'),
      'pro', (select count(*) from last_seen_scope where tier::text = 'pro'),
      'trial', (select count(*) from subscription_scope where trial_ends_at > pg_catalog.now()),
      'app_store', (select count(*) from subscription_scope where store = 'APP_STORE'),
      'google_play', (select count(*) from subscription_scope where store = 'PLAY_STORE'),
      'unknown_store', (select count(*) from subscription_scope where store is null or store not in ('APP_STORE', 'PLAY_STORE'))
    )
  ) into v_result;

  return v_result;
end
$function$;

revoke all on function public.admin_platform_overview_v1(integer, text)
  from public, anon, authenticated;
grant execute on function public.admin_platform_overview_v1(integer, text)
  to service_role;

commit;
