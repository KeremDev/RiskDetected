-- Standard reports stop carrying a free-tier quota.
--
-- The free plan's gift is one risk-assessment table (report_risk_analysis_trial, lifetime) and
-- one analysis a day. The standard PDF only re-renders findings the user has already produced
-- under those limits, so a second cap on it blocked exports of work the account had already
-- paid for in quota, and — combined with the risk-table gift being spent — read to the user as
-- "the app locked me out after my first report".
--
-- Risk-assessment tables keep their one-time free gift, and Plus/Pro keep their monthly standard
-- limits from private.report_monthly_limit; only the free daily standard cap is removed.

create or replace function public.check_report_quota_eligibility(
  p_user_id uuid,
  p_kind text,
  p_format text default 'pdf'
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  tier text;
  monthly_limit integer;
  period_start timestamptz;
  period_end timestamptz;
  used_count integer := 0;
  quota_feature text;
  is_risk_analysis_report boolean;
begin
  if p_user_id is null then
    raise exception 'report_quota_user_required' using errcode = '22023';
  end if;

  tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  monthly_limit := private.report_monthly_limit(tier);
  is_risk_analysis_report :=
    coalesce(p_kind, '') in ('riskAnalysis', 'risk_analysis')
    or coalesce(p_format, '') = 'xlsx';

  if tier = 'free' and is_risk_analysis_report then
    quota_feature := 'report_risk_analysis_trial';

    select count(*) into used_count
    from public.usage_events ue
    where ue.user_id = p_user_id
      and ue.feature = quota_feature
      and ue.event_type = 'completed';

    select used_count + count(*) into used_count
    from public.reports r
    where r.user_id = p_user_id
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

    return jsonb_build_object(
      'allowed', used_count < 1,
      'error_code', case when used_count >= 1 then 'free_risk_analysis_trial_exhausted' else null end,
      'limit', 1,
      'used', used_count,
      'period', 'lifetime'
    );
  end if;

  -- Free-tier standard reports are unlimited; the plan is metered on analyses and on the
  -- risk-assessment table, not on re-exporting findings that already exist.
  if tier = 'free' then
    return jsonb_build_object(
      'allowed', true,
      'error_code', null,
      'limit', null,
      'used', 0,
      'period', 'unlimited'
    );
  end if;

  if monthly_limit is not null then
    quota_feature := 'report_standard';
    period_start := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
    period_end := period_start + interval '1 month';
  else
    return jsonb_build_object(
      'allowed', true,
      'error_code', null,
      'limit', null,
      'used', 0,
      'period', 'unlimited'
    );
  end if;

  select count(*) into used_count
  from public.usage_events ue
  where ue.user_id = p_user_id
    and ue.feature = quota_feature
    and ue.event_type = 'completed'
    and ue.created_at >= period_start
    and ue.created_at < period_end;

  select used_count + count(*) into used_count
  from public.reports r
  where r.user_id = p_user_id
    and r.created_at >= period_start
    and r.created_at < period_end
    and not exists (
      select 1
      from public.usage_events ue
      where ue.user_id = r.user_id
        and ue.source_id = r.id
        and ue.feature = quota_feature
    );

  return jsonb_build_object(
    'allowed', used_count < monthly_limit,
    'error_code', case when used_count >= monthly_limit then 'report_quota_exceeded' else null end,
    'limit', monthly_limit,
    'used', used_count,
    'period', 'monthly'
  );
end;
$$;

revoke all on function public.check_report_quota_eligibility(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.check_report_quota_eligibility(uuid, text, text)
  to service_role;

-- The insert trigger enforces the same rule independently of the preflight RPC, so it has to
-- lose the free daily standard cap too — otherwise the preflight says yes and the insert still
-- raises report_quota_exceeded:1/1.
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
      -- Standard reports carry no free-tier quota: the plan is metered on analyses and on the
      -- one-time risk-assessment table, and this export only re-renders findings the account
      -- already produced under those limits. The usage_event below is still written so the
      -- report keeps its durable per-feature record.
      quota_feature := 'report_standard';
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
