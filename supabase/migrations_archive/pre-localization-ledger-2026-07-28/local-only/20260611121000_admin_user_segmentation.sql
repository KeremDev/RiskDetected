-- V17: Admin user segmentation (power users + churn risk)

create or replace function public.admin_user_segments_summary()
returns table (
  power_users bigint,
  churn_risk_paid bigint,
  churn_risk_inactive bigint,
  dormant bigint,
  activated bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select
      now() - interval '30 days' as d30,
      now() - interval '90 days' as d90
  ),
  last_activity as (
    select user_id, max(ts) as last_ts
    from (
      select user_id, created_at as ts from public.analyses
      union all
      select user_id, created_at from public.reports
      union all
      select user_id, created_at from public.ai_usage_logs
      union all
      select user_id, created_at from public.usage_events
    ) events
    group by user_id
  ),
  activity_30d as (
    select user_id, count(*)::bigint as events_30d
    from (
      select user_id from public.analyses
      where status = 'completed' and created_at >= (select d30 from bounds)
      union all
      select user_id from public.reports
      where created_at >= (select d30 from bounds)
      union all
      select user_id from public.ai_usage_logs
      where created_at >= (select d30 from bounds)
    ) recent
    group by user_id
  ),
  completed_ever as (
    select distinct user_id
    from public.analyses
    where status = 'completed'
  ),
  classified as (
    select
      p.id,
      case
        when coalesce(a30.events_30d, 0) >= 8
          or (
            select count(*)
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
              and ax.created_at >= (select d30 from bounds)
          ) >= 5
          or (
            select count(*)
            from public.reports rx
            where rx.user_id = p.id
              and rx.created_at >= (select d30 from bounds)
          ) >= 3
          then 'power_user'
        when p.tier in ('plus', 'pro')
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          and la.last_ts is not null
          and la.last_ts >= (select d90 from bounds)
          then 'churn_risk_paid'
        when p.tier = 'free'
          and ce.user_id is not null
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          then 'churn_risk_inactive'
        when p.created_at < (select d30 from bounds)
          and ce.user_id is null
          then 'dormant'
        else null
      end as segment
    from public.profiles p
    left join last_activity la on la.user_id = p.id
    left join activity_30d a30 on a30.user_id = p.id
    left join completed_ever ce on ce.user_id = p.id
  )
  select
    count(*) filter (where c.segment = 'power_user')::bigint as power_users,
    count(*) filter (where c.segment = 'churn_risk_paid')::bigint as churn_risk_paid,
    count(*) filter (where c.segment = 'churn_risk_inactive')::bigint as churn_risk_inactive,
    count(*) filter (where c.segment = 'dormant')::bigint as dormant,
    (select count(*)::bigint from completed_ever) as activated
  from classified c;
$$;

create or replace function public.admin_user_segments_list(
  p_segment text,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  email text,
  full_name text,
  tier text,
  last_activity_at timestamptz,
  activity_score_30d bigint,
  completed_analyses_30d bigint,
  reports_30d bigint,
  subscription_status text,
  segment text
)
language sql
stable
security definer
set search_path = public
as $$
  with bounds as (
    select
      now() - interval '30 days' as d30,
      now() - interval '90 days' as d90
  ),
  last_activity as (
    select user_id, max(ts) as last_ts
    from (
      select user_id, created_at as ts from public.analyses
      union all
      select user_id, created_at from public.reports
      union all
      select user_id, created_at from public.ai_usage_logs
      union all
      select user_id, created_at from public.usage_events
    ) events
    group by user_id
  ),
  metrics as (
    select
      p.id as user_id,
      p.email,
      p.full_name,
      p.tier,
      p.created_at,
      la.last_ts as last_activity_at,
      (
        select count(*)::bigint
        from public.analyses ax
        where ax.user_id = p.id
          and ax.status = 'completed'
          and ax.created_at >= (select d30 from bounds)
      ) as completed_analyses_30d,
      (
        select count(*)::bigint
        from public.reports rx
        where rx.user_id = p.id
          and rx.created_at >= (select d30 from bounds)
      ) as reports_30d,
      (
        select count(*)::bigint
        from public.ai_usage_logs al
        where al.user_id = p.id
          and al.created_at >= (select d30 from bounds)
      ) as ai_calls_30d,
      us.status as subscription_status,
      case
        when (
          (
            select count(*)
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
              and ax.created_at >= (select d30 from bounds)
          ) >= 5
          or (
            select count(*)
            from public.reports rx
            where rx.user_id = p.id
              and rx.created_at >= (select d30 from bounds)
          ) >= 3
          or (
            (
              select count(*)
              from public.analyses ax
              where ax.user_id = p.id
                and ax.status = 'completed'
                and ax.created_at >= (select d30 from bounds)
            ) * 3
            + (
              select count(*)
              from public.reports rx
              where rx.user_id = p.id
                and rx.created_at >= (select d30 from bounds)
            ) * 2
            + (
              select count(*)
              from public.ai_usage_logs al
              where al.user_id = p.id
                and al.created_at >= (select d30 from bounds)
            )
          ) >= 8
        ) then 'power_user'
        when p.tier in ('plus', 'pro')
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          and la.last_ts is not null
          and la.last_ts >= (select d90 from bounds)
          then 'churn_risk_paid'
        when p.tier = 'free'
          and exists (
            select 1
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
          )
          and coalesce(la.last_ts, p.created_at) < (select d30 from bounds)
          then 'churn_risk_inactive'
        when p.created_at < (select d30 from bounds)
          and not exists (
            select 1
            from public.analyses ax
            where ax.user_id = p.id
              and ax.status = 'completed'
          )
          then 'dormant'
        else null
      end as segment
    from public.profiles p
    left join last_activity la on la.user_id = p.id
    left join public.user_subscriptions us on us.user_id = p.id
  )
  select
    m.user_id,
    m.email,
    m.full_name,
    m.tier,
    m.last_activity_at,
    (m.completed_analyses_30d * 3 + m.reports_30d * 2 + m.ai_calls_30d) as activity_score_30d,
    m.completed_analyses_30d,
    m.reports_30d,
    coalesce(m.subscription_status, 'missing') as subscription_status,
    m.segment
  from metrics m
  where m.segment = p_segment
  order by
    case p_segment
      when 'power_user' then m.completed_analyses_30d * 3 + m.reports_30d * 2 + m.ai_calls_30d
      else 0
    end desc,
    m.last_activity_at asc nulls last
  limit greatest(1, least(coalesce(p_limit, 20), 50))
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.admin_user_segments_summary() from public;
revoke all on function public.admin_user_segments_list(text, integer, integer) from public;

grant execute on function public.admin_user_segments_summary() to service_role;
grant execute on function public.admin_user_segments_list(text, integer, integer) to service_role;
