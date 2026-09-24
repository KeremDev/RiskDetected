-- Keep free/paid quota usage durable when users delete their own analyses or
-- reports. User content remains deletable; usage ledgers are removed only when
-- the auth user itself is deleted.

create unique index if not exists usage_events_report_feature_unique
  on public.usage_events (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial');

insert into public.usage_events (
  user_id,
  feature,
  event_type,
  source_id,
  metadata,
  created_at
)
select
  a.user_id,
  case
    when a.analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end,
  'completed',
  a.id,
  jsonb_build_object(
    'source', 'backfill_completed_analysis',
    'analysis_mode', coalesce(a.analysis_mode, 'standard'),
    'status', a.status
  ),
  coalesce(a.completed_at, a.created_at)
from public.analyses a
where a.status = 'completed'
  and a.user_id is not null
on conflict (user_id, feature, source_id)
where source_id is not null
  and feature in ('analysis_standard', 'analysis_detailed')
do nothing;

insert into public.usage_events (
  user_id,
  feature,
  event_type,
  source_id,
  metadata,
  created_at
)
select
  r.user_id,
  case
    when coalesce(private.user_plan_tier(r.user_id), 'free') = 'free'
      and (
        coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(r.format, '') = 'xlsx'
      )
      then 'report_risk_analysis_trial'
    else 'report_standard'
  end,
  'completed',
  r.id,
  jsonb_build_object(
    'source', 'backfill_report',
    'format', r.format,
    'kind', r.kind,
    'method', r.method
  ),
  r.created_at
from public.reports r
where r.user_id is not null
on conflict (user_id, feature, source_id)
where source_id is not null
  and feature in ('report_standard', 'report_risk_analysis_trial')
do nothing;

create or replace function public.ensure_analysis_usage_event_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  quota_feature text;
begin
  if old.user_id is null or old.status <> 'completed' then
    return old;
  end if;

  quota_feature := case
    when old.analysis_mode = 'detailed' then 'analysis_detailed'
    else 'analysis_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'analysis_delete_tombstone',
      'analysis_mode', coalesce(old.analysis_mode, 'standard'),
      'status', old.status
    ),
    coalesce(old.completed_at, old.created_at)
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('analysis_standard', 'analysis_detailed')
  do nothing;

  return old;
end;
$$;

drop trigger if exists analyses_keep_usage_on_delete on public.analyses;
create trigger analyses_keep_usage_on_delete
  before delete on public.analyses
  for each row
  execute function public.ensure_analysis_usage_event_on_delete();

create or replace function public.ensure_report_usage_event_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  tier text;
  is_risk_analysis_report boolean;
  quota_feature text;
begin
  if old.user_id is null then
    return old;
  end if;

  tier := coalesce(private.user_plan_tier(old.user_id), 'free');
  is_risk_analysis_report :=
    coalesce(old.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(old.format, '') = 'xlsx';
  quota_feature := case
    when tier = 'free' and is_risk_analysis_report
      then 'report_risk_analysis_trial'
    else 'report_standard'
  end;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata,
    created_at
  ) values (
    old.user_id,
    quota_feature,
    'completed',
    old.id,
    jsonb_build_object(
      'source', 'report_delete_tombstone',
      'format', old.format,
      'kind', old.kind,
      'method', old.method
    ),
    old.created_at
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial')
  do nothing;

  return old;
end;
$$;

drop trigger if exists reports_keep_usage_on_delete on public.reports;
create trigger reports_keep_usage_on_delete
  before delete on public.reports
  for each row
  execute function public.ensure_report_usage_event_on_delete();

create or replace function public.enforce_report_plan_limits()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  tier text;
  monthly_limit integer;
  day_start timestamptz;
  day_end timestamptz;
  month_start timestamptz;
  month_end timestamptz;
  used_count integer;
  risk_trial_used integer;
  is_risk_analysis_report boolean;
  quota_feature text;
begin
  tier := coalesce(private.user_plan_tier(new.user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);
  is_risk_analysis_report :=
    coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(new.format, '') = 'xlsx';

  day_start := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  day_end := day_start + interval '1 day';
  month_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
  month_end := month_start + interval '1 month';

  if tier = 'free' then
    perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':free_report_quota:' || day_start::text));

    if is_risk_analysis_report then
      quota_feature := 'report_risk_analysis_trial';

      select count(*)
        into risk_trial_used
      from public.usage_events ue
      where ue.user_id = new.user_id
        and ue.feature = quota_feature
        and ue.event_type = 'completed';

      select risk_trial_used + count(*)
        into risk_trial_used
      from public.reports r
      where r.user_id = new.user_id
        and (
          coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
          or coalesce(r.format, '') = 'xlsx'
        )
        and not exists (
          select 1
          from public.usage_events ue
          where ue.user_id = r.user_id
            and ue.source_id = r.id
            and ue.feature = quota_feature
        );

      if risk_trial_used >= 1 then
        raise exception 'free_risk_analysis_trial_exhausted:1/1'
          using errcode = 'P0001',
                hint = 'Free users can create one risk analysis table as a trial.';
      end if;
    else
      quota_feature := 'report_standard';

      select count(*)
        into used_count
      from public.usage_events ue
      where ue.user_id = new.user_id
        and ue.feature = quota_feature
        and ue.event_type = 'completed'
        and ue.created_at >= day_start
        and ue.created_at < day_end;

      select used_count + count(*)
        into used_count
      from public.reports r
      where r.user_id = new.user_id
        and r.created_at >= day_start
        and r.created_at < day_end
        and not (
          coalesce(r.kind, '') in ('riskAnalysis', 'risk_analysis')
          or coalesce(r.format, '') = 'xlsx'
        )
        and not exists (
          select 1
          from public.usage_events ue
          where ue.user_id = r.user_id
            and ue.source_id = r.id
            and ue.feature = quota_feature
        );

      if used_count >= 1 then
        raise exception 'report_quota_exceeded:1/1'
          using errcode = 'P0001',
                hint = 'Free standard report quota renews daily.';
      end if;
    end if;

    insert into public.usage_events (
      user_id,
      feature,
      event_type,
      source_id,
      metadata
    ) values (
      new.user_id,
      quota_feature,
      'completed',
      new.id,
      jsonb_build_object(
        'source', 'report_insert',
        'tier', tier,
        'format', new.format,
        'kind', new.kind,
        'method', new.method,
        'period_start', case when quota_feature = 'report_standard' then day_start else null end
      )
    )
    on conflict (user_id, feature, source_id)
    where source_id is not null
      and feature in ('report_standard', 'report_risk_analysis_trial')
    do nothing;

    return new;
  end if;

  if monthly_limit is null then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':report_quota:' || month_start::text));
  quota_feature := 'report_standard';

  select count(*)
    into used_count
  from public.usage_events ue
  where ue.user_id = new.user_id
    and ue.feature = quota_feature
    and ue.event_type = 'completed'
    and ue.created_at >= month_start
    and ue.created_at < month_end;

  select used_count + count(*)
    into used_count
  from public.reports r
  where r.user_id = new.user_id
    and r.created_at >= month_start
    and r.created_at < month_end
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = r.user_id
        and ue.source_id = r.id
        and ue.feature = quota_feature
    );

  if used_count >= monthly_limit then
    raise exception 'report_quota_exceeded:%/%', monthly_limit, monthly_limit
      using errcode = 'P0001',
            hint = 'Upgrade plan or wait until the next monthly quota period.';
  end if;

  insert into public.usage_events (
    user_id,
    feature,
    event_type,
    source_id,
    metadata
  ) values (
    new.user_id,
    quota_feature,
    'completed',
    new.id,
    jsonb_build_object(
      'source', 'report_insert',
      'tier', tier,
      'format', new.format,
      'kind', new.kind,
      'method', new.method,
      'period_start', month_start
    )
  )
  on conflict (user_id, feature, source_id)
  where source_id is not null
    and feature in ('report_standard', 'report_risk_analysis_trial')
  do nothing;

  return new;
end;
$$;

revoke execute on function public.ensure_analysis_usage_event_on_delete()
  from public, anon, authenticated;
revoke execute on function public.ensure_report_usage_event_on_delete()
  from public, anon, authenticated;
revoke execute on function public.enforce_report_plan_limits()
  from public, anon, authenticated;
grant execute on function public.ensure_analysis_usage_event_on_delete()
  to service_role;
grant execute on function public.ensure_report_usage_event_on_delete()
  to service_role;
grant execute on function public.enforce_report_plan_limits()
  to service_role;

select pg_notify('pgrst', 'reload schema');
