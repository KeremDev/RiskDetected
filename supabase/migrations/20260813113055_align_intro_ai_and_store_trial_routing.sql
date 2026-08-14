-- Keep App Store and Google Play subscription identity explicit so trial
-- cancellation routing can be verified from RevenueCat's store truth.
begin;

alter table public.user_subscriptions
  add column if not exists store text,
  add column if not exists base_plan_id text,
  add column if not exists offer_id text,
  add column if not exists store_transaction_id text,
  add column if not exists period_type text;

create index if not exists user_subscriptions_store_product_idx
  on public.user_subscriptions (store, product_id, base_plan_id)
  where tier in ('plus', 'pro');

-- The quota reservation lock is also the authority for the one-time paid-AI
-- introduction. Looking this up in a separate query would let two concurrent
-- first submissions both consume the paid route.
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
