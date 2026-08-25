-- Administrative, account-scoped analysis quota overrides. The table lives in
-- the private schema and is consumed only by the service-role quota reservation
-- function; it does not change plan entitlements or any other user's limits.
begin;

create table if not exists private.analysis_quota_overrides (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_standard_limit integer,
  daily_detailed_limit integer,
  enabled boolean not null default true,
  expires_at timestamptz,
  reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint analysis_quota_overrides_limit_present check (
    daily_standard_limit is not null or daily_detailed_limit is not null
  ),
  constraint analysis_quota_overrides_standard_limit_range check (
    daily_standard_limit is null or daily_standard_limit between 1 and 100
  ),
  constraint analysis_quota_overrides_detailed_limit_range check (
    daily_detailed_limit is null or daily_detailed_limit between 1 and 100
  ),
  constraint analysis_quota_overrides_reason_not_blank check (
    length(btrim(reason)) between 3 and 500
  )
);

comment on table private.analysis_quota_overrides is
  'Administrative per-user analysis quota overrides; plan entitlements remain authoritative.';

alter table private.analysis_quota_overrides enable row level security;
revoke all on table private.analysis_quota_overrides
  from public, anon, authenticated;

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
  quota_override_limit integer;
  period_start timestamptz;
  used_count integer;
  existing_event_type text;
  prior_analysis_usage_exists boolean;
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

  select
    exists (
      select 1
      from public.usage_events ue
      where ue.user_id = p_user_id
        and ue.feature in ('analysis_standard', 'analysis_detailed')
        and ue.event_type in ('reserved', 'completed')
        and ue.source_id is distinct from p_analysis_id
    )
    or exists (
      select 1
      from public.analyses a
      where a.user_id = p_user_id
        and a.id <> p_analysis_id
        and a.status = 'completed'
    )
    into prior_analysis_usage_exists;

  if user_tier = 'free' then
    if quota_feature <> 'analysis_standard' then
      return jsonb_build_object(
        'ok', false,
        'code', 'plan_required',
        'tier', user_tier,
        'message', 'Detaylı analiz Plus veya Pro üyelik gerektirir.'
      );
    end if;
    quota_limit := 1;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'plus' and quota_feature = 'analysis_standard' then
    quota_limit := 10;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'plus' and quota_feature = 'analysis_detailed' then
    quota_limit := 2;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_standard' then
    quota_limit := 40;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  elsif user_tier = 'pro' and quota_feature = 'analysis_detailed' then
    quota_limit := 10;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  else
    quota_limit := 0;
    period_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  end if;

  select case
      when quota_feature = 'analysis_detailed' then qo.daily_detailed_limit
      else qo.daily_standard_limit
    end
    into quota_override_limit
  from private.analysis_quota_overrides qo
  where qo.user_id = p_user_id
    and qo.enabled
    and (qo.expires_at is null or qo.expires_at > now());

  if quota_override_limit is not null then
    quota_limit := quota_override_limit;
  end if;

  select ue.event_type
    into existing_event_type
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.source_id = p_analysis_id
    and ue.event_type in ('reserved', 'completed')
  limit 1;

  if existing_event_type is not null then
    return jsonb_build_object(
      'ok', true,
      'tier', user_tier,
      'feature', quota_feature,
      'limit', quota_limit,
      'already_reserved', true,
      'event_type', existing_event_type,
      'first_paid_ai_eligible', not prior_analysis_usage_exists
    );
  end if;

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.event_type in ('reserved', 'completed')
    and ue.created_at >= period_start
    and (
      (user_tier = 'free' and ue.feature in ('analysis_standard', 'analysis_detailed'))
      or (user_tier <> 'free' and ue.feature = quota_feature)
    );

  select used_count + count(*)
    into used_count
  from public.analyses a
  where a.user_id = p_user_id
    and a.status = 'completed'
    and a.created_at >= period_start
    and (
      (user_tier = 'free' and coalesce(a.analysis_mode, 'standard') in ('standard', 'detailed'))
      or (
        user_tier <> 'free'
        and coalesce(a.analysis_mode, 'standard') = case
          when quota_feature = 'analysis_detailed' then 'detailed'
          else 'standard'
        end
      )
    )
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = a.user_id
        and ue.source_id = a.id
        and (
          (user_tier = 'free' and ue.feature in ('analysis_standard', 'analysis_detailed'))
          or (user_tier <> 'free' and ue.feature = quota_feature)
        )
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
        when user_tier = 'free' then 'Günde 1 ücretsiz analiz hakkın doldu.'
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
      'period_start', period_start,
      'first_paid_ai_eligible', not prior_analysis_usage_exists
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
    'used', used_count + 1,
    'first_paid_ai_eligible', not prior_analysis_usage_exists
  );
end;
$$;

revoke all on function public.reserve_analysis_quota(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.reserve_analysis_quota(uuid, uuid, text)
  to service_role;

select pg_notify('pgrst', 'reload schema');

commit;
