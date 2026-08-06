CREATE OR REPLACE FUNCTION public.admin_dashboard_daily_series(p_days integer DEFAULT 30)
 RETURNS TABLE(day date, new_users bigint, analyses bigint, completed_analyses bigint, reports bigint, ai_calls bigint, ai_tokens bigint, support_requests bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select (
      (now() at time zone 'Europe/Istanbul')::date
      - (greatest(1, least(p_days, 90)) - 1)
    )::date as start_day,
    (now() at time zone 'Europe/Istanbul')::date as end_day
  ),
  days as (
    select generate_series(
      (select start_day from bounds),
      (select end_day from bounds),
      interval '1 day'
    )::date as day
  ),
  users_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from profiles, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  analyses_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from analyses, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  completed_by_day as (
    select (completed_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from analyses, bounds
    where completed_at is not null
      and (completed_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  reports_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from reports, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  ai_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day,
           count(*)::bigint as calls,
           coalesce(sum(total_tokens), 0)::bigint as tokens
    from ai_usage_logs, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  ),
  support_by_day as (
    select (created_at at time zone 'Europe/Istanbul')::date as day, count(*)::bigint as cnt
    from support_requests, bounds
    where (created_at at time zone 'Europe/Istanbul')::date >= bounds.start_day
    group by 1
  )
  select
    d.day,
    coalesce(u.cnt, 0),
    coalesce(a.cnt, 0),
    coalesce(c.cnt, 0),
    coalesce(r.cnt, 0),
    coalesce(ai.calls, 0),
    coalesce(ai.tokens, 0),
    coalesce(s.cnt, 0)
  from days d
  left join users_by_day u on u.day = d.day
  left join analyses_by_day a on a.day = d.day
  left join completed_by_day c on c.day = d.day
  left join reports_by_day r on r.day = d.day
  left join ai_by_day ai on ai.day = d.day
  left join support_by_day s on s.day = d.day
  order by d.day;
$function$;;
