-- Fix subscription truth and make analysis quota reservation atomic.
--
-- Backend entitlement must come from an active RevenueCat-synced subscription.
-- profiles.tier remains a UI/cache field only and is no longer a paid fallback
-- for backend limits.

create unique index if not exists usage_events_analysis_feature_unique
  on public.usage_events (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed');
create or replace function private.user_plan_tier(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce((
    select us.tier
    from public.user_subscriptions us
    where us.user_id = p_user_id
      and us.tier in ('plus', 'pro')
      and us.status in ('active', 'trialing', 'grace_period')
      and (us.current_period_ends_at is null or us.current_period_ends_at > now())
    order by case us.tier when 'pro' then 2 when 'plus' then 1 else 0 end desc,
             us.updated_at desc
    limit 1
  ), 'free');
$$;
revoke all on function private.user_plan_tier(uuid) from public, anon, authenticated;
create or replace function public.reserve_analysis_quota(
  p_user_id uuid,
  p_analysis_id uuid,
  p_analysis_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  user_tier text;
  quota_feature text;
  quota_limit integer;
  period_start timestamptz;
  used_count integer;
begin
  if p_user_id is null or p_analysis_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'validation_failed',
      'message', 'Analiz kotası için kullanıcı ve analiz zorunludur.'
    );
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text || ':analysis_quota'));

  user_tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  quota_feature := case
    when p_analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end;

  if user_tier = 'free' then
    if quota_feature <> 'analysis_standard' then
      return jsonb_build_object(
        'ok', false,
        'code', 'plan_required',
        'tier', user_tier,
        'message', 'Detaylı analiz Plus veya Pro üyelik gerektirir.'
      );
    end if;
    quota_limit := 3;
    period_start := null;
  elsif user_tier = 'plus' and quota_feature = 'analysis_standard' then
    quota_limit := 15;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'plus' and quota_feature = 'analysis_detailed' then
    quota_limit := 2;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_standard' then
    quota_limit := 60;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_detailed' then
    quota_limit := 10;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  else
    quota_limit := 0;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  end if;

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.event_type in ('reserved', 'completed')
    and (period_start is null or ue.created_at >= period_start);

  select used_count + count(*)
    into used_count
  from public.analyses a
  where a.user_id = p_user_id
    and a.status = 'completed'
    and a.analysis_mode = case
      when quota_feature = 'analysis_detailed' then 'detailed'
      else 'standard'
    end
    and (period_start is null or a.created_at >= period_start)
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = a.user_id
        and ue.source_id = a.id
        and ue.feature = quota_feature
    );

  if used_count >= quota_limit then
    return jsonb_build_object(
      'ok', false,
      'code', 'quota_exceeded',
      'tier', user_tier,
      'feature', quota_feature,
      'limit', quota_limit,
      'used', used_count,
      'message', case
        when user_tier = 'free' then 'Toplam 3 ücretsiz analiz hakkın doldu.'
        when quota_feature = 'analysis_detailed' then 'Günlük detaylı analiz kotan doldu (' || quota_limit || '/gün).'
        else 'Günlük analiz kotan doldu (' || quota_limit || '/gün).'
      end
    );
  end if;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata
  ) values (
    p_user_id,
    quota_feature,
    'reserved',
    p_analysis_id,
    jsonb_build_object(
      'analysis_mode', p_analysis_mode,
      'tier', user_tier,
      'limit', quota_limit,
      'period_start', period_start
    )
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed')
  do nothing;

  return jsonb_build_object(
    'ok', true,
    'tier', user_tier,
    'feature', quota_feature,
    'limit', quota_limit,
    'used', used_count + 1
  );
end;
$$;
revoke all on function public.reserve_analysis_quota(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.reserve_analysis_quota(uuid, uuid, text) to service_role;
select pg_notify('pgrst', 'reload schema');
