-- V19: Admin cohort retention analytics

create or replace function public.admin_cohort_summary(p_weeks integer default 12)
returns table (
  cohort_week date,
  cohort_size bigint,
  activated_7d bigint,
  activated_30d bigint,
  paid_30d bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select greatest(4, least(coalesce(p_weeks, 12), 26))::integer as weeks
  ),
  cohorts as (
    select
      p.id as user_id,
      p.created_at,
      (date_trunc('week', p.created_at at time zone 'Europe/Istanbul'))::date as cohort_week
    from public.profiles p
    where p.created_at >= (
      date_trunc('week', now() at time zone 'Europe/Istanbul')::date
      - ((select weeks from params) * interval '7 days')
    )
  ),
  first_activation as (
    select
      a.user_id,
      min(coalesce(a.completed_at, a.created_at)) as first_active_at
    from public.analyses a
    where a.status = 'completed'
    group by a.user_id
  ),
  paid_within_30d as (
    select distinct c.user_id
    from cohorts c
    join public.user_subscriptions us on us.user_id = c.user_id
    where us.created_at <= c.created_at + interval '30 days'
      and us.status in ('active', 'trialing', 'past_due')
  )
  select
    c.cohort_week,
    count(distinct c.user_id)::bigint as cohort_size,
    count(distinct c.user_id) filter (
      where fa.first_active_at is not null
        and fa.first_active_at <= c.created_at + interval '7 days'
    )::bigint as activated_7d,
    count(distinct c.user_id) filter (
      where fa.first_active_at is not null
        and fa.first_active_at <= c.created_at + interval '30 days'
    )::bigint as activated_30d,
    count(distinct c.user_id) filter (
      where pw.user_id is not null
    )::bigint as paid_30d
  from cohorts c
  left join first_activation fa on fa.user_id = c.user_id
  left join paid_within_30d pw on pw.user_id = c.user_id
  group by c.cohort_week
  order by c.cohort_week desc;
$$;

create or replace function public.admin_cohort_retention_matrix(
  p_weeks integer default 8,
  p_periods integer default 6
)
returns table (
  cohort_week date,
  period_index integer,
  active_users bigint,
  cohort_size bigint,
  retention_rate numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select
      greatest(4, least(coalesce(p_weeks, 8), 16))::integer as weeks,
      greatest(1, least(coalesce(p_periods, 6), 8))::integer as periods
  ),
  cohorts as (
    select
      p.id as user_id,
      (date_trunc('week', p.created_at at time zone 'Europe/Istanbul'))::date as cohort_week
    from public.profiles p
    where p.created_at >= (
      date_trunc('week', now() at time zone 'Europe/Istanbul')::date
      - ((select weeks from params) * interval '7 days')
    )
  ),
  cohort_sizes as (
    select cohort_week, count(*)::bigint as cohort_size
    from cohorts
    group by cohort_week
  ),
  periods as (
    select generate_series(0, (select periods from params) - 1) as period_index
  ),
  activity_weeks as (
    select
      e.user_id,
      (date_trunc('week', e.ts at time zone 'Europe/Istanbul'))::date as activity_week
    from (
      select user_id, coalesce(completed_at, created_at) as ts
      from public.analyses
      where status = 'completed'
      union all
      select user_id, created_at from public.reports
    ) e
  ),
  matrix as (
    select
      c.cohort_week,
      p.period_index,
      count(distinct c.user_id) filter (where aw.user_id is not null)::bigint as active_users
    from cohorts c
    cross join periods p
    left join activity_weeks aw on aw.user_id = c.user_id
      and aw.activity_week = c.cohort_week + (p.period_index * 7)
    group by c.cohort_week, p.period_index
  )
  select
    m.cohort_week,
    m.period_index,
    m.active_users,
    cs.cohort_size,
    case
      when cs.cohort_size > 0
        then round((m.active_users::numeric / cs.cohort_size::numeric) * 100, 1)
      else 0
    end as retention_rate
  from matrix m
  join cohort_sizes cs on cs.cohort_week = m.cohort_week
  order by m.cohort_week desc, m.period_index asc;
$$;

revoke all on function public.admin_cohort_summary(integer) from public;
revoke all on function public.admin_cohort_retention_matrix(integer, integer) from public;

grant execute on function public.admin_cohort_summary(integer) to service_role;
grant execute on function public.admin_cohort_retention_matrix(integer, integer) to service_role;;
