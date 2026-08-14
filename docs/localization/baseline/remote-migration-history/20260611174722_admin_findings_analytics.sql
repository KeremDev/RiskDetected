-- V22: Admin findings & risk analytics

create or replace function public.admin_findings_analytics(p_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with params as (
    select greatest(1, least(coalesce(p_days, 30), 90))::integer as days
  ),
  bounds as (
    select days, (now() - (days || ' days')::interval) as since
    from params
  ),
  scoped as (
    select f.*
    from public.findings f
    cross join bounds b
    where f.created_at >= b.since
  ),
  summary as (
    select
      count(*)::bigint as total_findings,
      count(*) filter (where not is_resolved)::bigint as unresolved_findings,
      count(*) filter (where is_resolved)::bigint as resolved_findings,
      count(*) filter (where photo_id is not null)::bigint as with_photo,
      count(*) filter (where bounding_box is not null)::bigint as with_bounding_box,
      round(avg(fk_score)::numeric, 2) as avg_fk_score,
      round(avg(m5_score)::numeric, 2) as avg_m5_score,
      count(distinct analysis_id)::bigint as analyses_with_findings
    from scoped
  ),
  fk_bands as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('band', band, 'count', cnt)
        order by
          case band
            when 'critical' then 1
            when 'high' then 2
            when 'medium' then 3
            when 'low' then 4
            else 5
          end
      ),
      '[]'::jsonb
    ) as data
    from (
      select fk_band::text as band, count(*)::bigint as cnt
      from scoped
      group by fk_band
    ) t
  ),
  m5_bands as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('band', band, 'count', cnt)
        order by
          case band
            when 'critical' then 1
            when 'high' then 2
            when 'medium' then 3
            when 'low' then 4
            else 5
          end
      ),
      '[]'::jsonb
    ) as data
    from (
      select m5_band::text as band, count(*)::bigint as cnt
      from scoped
      group by m5_band
    ) t
  ),
  top_categories as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'category', category,
          'count', cnt,
          'criticalCount', critical_cnt,
          'unresolvedCount', unresolved_cnt
        )
        order by cnt desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(category), ''), 'Belirtilmemiş') as category,
        count(*)::bigint as cnt,
        count(*) filter (where fk_band = 'critical' or m5_band = 'critical')::bigint as critical_cnt,
        count(*) filter (where not is_resolved)::bigint as unresolved_cnt
      from scoped
      group by 1
      order by cnt desc
      limit 12
    ) t
  ),
  responsible_backlog as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('responsible', responsible, 'unresolved', unresolved)
        order by unresolved desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(responsible), ''), 'Belirtilmemiş') as responsible,
        count(*)::bigint as unresolved
      from scoped
      where not is_resolved
      group by 1
      order by unresolved desc
      limit 10
    ) t
  ),
  deadline_breakdown as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('deadline', deadline, 'count', cnt, 'unresolved', unresolved)
        order by cnt desc
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        coalesce(nullif(trim(deadline), ''), 'Belirtilmemiş') as deadline,
        count(*)::bigint as cnt,
        count(*) filter (where not is_resolved)::bigint as unresolved
      from scoped
      group by 1
      order by cnt desc
      limit 10
    ) t
  ),
  daily_trend as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'day', day,
          'total', total,
          'unresolved', unresolved,
          'critical', critical
        )
        order by day
      ),
      '[]'::jsonb
    ) as data
    from (
      select
        created_at::date as day,
        count(*)::bigint as total,
        count(*) filter (where not is_resolved)::bigint as unresolved,
        count(*) filter (where fk_band = 'critical' or m5_band = 'critical')::bigint as critical
      from scoped
      group by 1
      order by 1
    ) t
  )
  select jsonb_build_object(
    'days', (select days from bounds),
    'summary', (
      select jsonb_build_object(
        'totalFindings', total_findings,
        'unresolvedFindings', unresolved_findings,
        'resolvedFindings', resolved_findings,
        'withPhoto', with_photo,
        'withBoundingBox', with_bounding_box,
        'avgFkScore', avg_fk_score,
        'avgM5Score', avg_m5_score,
        'analysesWithFindings', analyses_with_findings
      )
      from summary
    ),
    'fkBands', (select data from fk_bands),
    'm5Bands', (select data from m5_bands),
    'topCategories', (select data from top_categories),
    'responsibleBacklog', (select data from responsible_backlog),
    'deadlineBreakdown', (select data from deadline_breakdown),
    'dailyTrend', (select data from daily_trend)
  );
$$;;
