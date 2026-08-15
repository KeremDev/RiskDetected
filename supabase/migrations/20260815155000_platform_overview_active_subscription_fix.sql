begin;

-- Store attribution in the overview represents current subscriptions. RevenueCat keeps the
-- last store on inactive rows, so counting every row would inflate App Store/Google Play totals.
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


commit;
