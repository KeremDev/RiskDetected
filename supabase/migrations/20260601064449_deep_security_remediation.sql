-- Deep security scan remediation:
-- - make analysis quota reservation idempotent for queued worker retries
-- - add durable support request rate limiting
-- - narrow client-writable tables to the intended app surface

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
      'event_type', existing_event_type
    );
  end if;

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.event_type in ('reserved', 'completed')
    and ue.created_at >= period_start;

  select used_count + count(*)
    into used_count
  from public.analyses a
  where a.user_id = p_user_id
    and a.status = 'completed'
    and a.analysis_mode = case
      when quota_feature = 'analysis_detailed' then 'detailed'
      else 'standard'
    end
    and a.created_at >= period_start
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

revoke all on function public.reserve_analysis_quota(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.reserve_analysis_quota(uuid, uuid, text)
  to service_role;

create schema if not exists private;

create table if not exists private.support_request_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  hour_window_start timestamptz not null,
  hour_count integer not null default 0 check (hour_count >= 0),
  day_window_start timestamptz not null,
  day_count integer not null default 0 check (day_count >= 0),
  updated_at timestamptz not null default now()
);

create or replace function public.check_support_request_rate_limit(
  p_user_id uuid,
  p_hour_limit integer default 5,
  p_day_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_now timestamptz := now();
  v_hour_start timestamptz := date_trunc('hour', now());
  v_day_start timestamptz := date_trunc('day', now());
  v_row private.support_request_rate_limits%rowtype;
  v_retry integer;
begin
  if p_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'code', 'validation_failed',
      'retry_after_seconds', 60
    );
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text || ':support_rate_limit'));

  insert into private.support_request_rate_limits (
    user_id,
    hour_window_start,
    hour_count,
    day_window_start,
    day_count
  ) values (
    p_user_id,
    v_hour_start,
    0,
    v_day_start,
    0
  )
  on conflict (user_id) do nothing;

  select *
    into v_row
  from private.support_request_rate_limits
  where user_id = p_user_id
  for update;

  if v_row.hour_window_start < v_hour_start then
    v_row.hour_window_start := v_hour_start;
    v_row.hour_count := 0;
  end if;

  if v_row.day_window_start < v_day_start then
    v_row.day_window_start := v_day_start;
    v_row.day_count := 0;
  end if;

  if v_row.hour_count >= greatest(p_hour_limit, 1) then
    v_retry := greatest(
      60,
      ceil(extract(epoch from (v_row.hour_window_start + interval '1 hour' - v_now)))::integer
    );
    update private.support_request_rate_limits
    set hour_window_start = v_row.hour_window_start,
        hour_count = v_row.hour_count,
        day_window_start = v_row.day_window_start,
        day_count = v_row.day_count,
        updated_at = v_now
    where user_id = p_user_id;
    return jsonb_build_object(
      'ok', false,
      'code', 'support_hourly_rate_limited',
      'retry_after_seconds', v_retry
    );
  end if;

  if v_row.day_count >= greatest(p_day_limit, 1) then
    v_retry := greatest(
      60,
      ceil(extract(epoch from (v_row.day_window_start + interval '1 day' - v_now)))::integer
    );
    update private.support_request_rate_limits
    set hour_window_start = v_row.hour_window_start,
        hour_count = v_row.hour_count,
        day_window_start = v_row.day_window_start,
        day_count = v_row.day_count,
        updated_at = v_now
    where user_id = p_user_id;
    return jsonb_build_object(
      'ok', false,
      'code', 'support_daily_rate_limited',
      'retry_after_seconds', v_retry
    );
  end if;

  update private.support_request_rate_limits
  set hour_window_start = v_row.hour_window_start,
      hour_count = v_row.hour_count + 1,
      day_window_start = v_row.day_window_start,
      day_count = v_row.day_count + 1,
      updated_at = v_now
  where user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'hour_limit', greatest(p_hour_limit, 1),
    'hour_used', v_row.hour_count + 1,
    'day_limit', greatest(p_day_limit, 1),
    'day_used', v_row.day_count + 1
  );
end;
$$;

revoke all on function public.check_support_request_rate_limit(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.check_support_request_rate_limit(uuid, integer, integer)
  to service_role;

alter table public.analyses enable row level security;
drop policy if exists analyses_insert_own on public.analyses;
drop policy if exists analyses_update_own on public.analyses;
drop policy if exists "Users update own analyses" on public.analyses;
create policy analyses_insert_own
  on public.analyses for insert to authenticated
  with check (auth.uid() = user_id and status = 'pending');
create policy analyses_update_own_editable_fields
  on public.analyses for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
revoke all on public.analyses from authenticated;
grant select, delete on public.analyses to authenticated;
grant insert (
  id,
  user_id,
  kind,
  canvas,
  title,
  text_input,
  company_id,
  status
) on public.analyses to authenticated;
grant update (company_id) on public.analyses to authenticated;

alter table public.findings enable row level security;
drop policy if exists findings_insert_own on public.findings;
drop policy if exists findings_update_own on public.findings;
drop policy if exists findings_delete_own on public.findings;
drop policy if exists "Users insert own findings" on public.findings;
drop policy if exists "Users update own findings" on public.findings;
drop policy if exists "Users delete own findings" on public.findings;
revoke all on public.findings from authenticated;
grant select on public.findings to authenticated;

alter table public.reports enable row level security;
drop policy if exists reports_insert_own on public.reports;
drop policy if exists reports_update_own on public.reports;
drop policy if exists "Users insert own reports" on public.reports;
drop policy if exists "Users update own reports" on public.reports;
revoke all on public.reports from authenticated;
grant select, delete on public.reports to authenticated;

select pg_notify('pgrst', 'reload schema');
