-- Some isolated environments do not carry the optional admin override table
-- used by production population classification. Result-detail reads still
-- need a stable classification contract, so resolve it from durable analysis,
-- engine-route and result-event platform evidence.

create or replace function private.analysis_population_v1(p_analysis_id uuid)
returns table(
  data_class text,
  effective_platform text,
  classification_source text
)
language sql
stable
security definer
set search_path = ''
as $$
  with target as (
    select a.id, lower(nullif(a.client_platform, '')) as platform
    from public.analyses a
    where a.id = p_analysis_id
  ), engine_platform as (
    select lower(nullif(r.config_snapshot->'client_routing'->>'client_platform', '')) as platform
    from private.analysis_engine_runs r
    where r.analysis_id = p_analysis_id
    order by r.started_at desc nulls last
    limit 1
  ), event_platform as (
    select lower(nullif(e.client_platform, '')) as platform
    from private.analysis_result_events e
    where e.analysis_id = p_analysis_id
      and lower(coalesce(e.client_platform, '')) in ('ios', 'android')
    order by e.created_at desc
    limit 1
  ), resolved as (
    select
      case
        when t.platform in ('ios', 'android') then t.platform
        when ep.platform in ('ios', 'android') then ep.platform
        when ev.platform in ('ios', 'android') then ev.platform
        else null
      end as platform,
      case
        when t.platform in ('ios', 'android') then 'analysis.client_platform'
        when ep.platform in ('ios', 'android') then 'engine.client_routing'
        when ev.platform in ('ios', 'android') then 'result_event.client_platform'
        else 'missing_platform'
      end as source
    from target t
    left join engine_platform ep on true
    left join event_platform ev on true
  )
  select
    case when resolved.platform is null then 'test' else 'production' end,
    resolved.platform,
    resolved.source
  from resolved;
$$;

revoke all on function private.analysis_population_v1(uuid)
  from public, anon, authenticated;
grant execute on function private.analysis_population_v1(uuid)
  to service_role;

comment on function private.analysis_population_v1(uuid) is
  'Classifies an analysis from durable platform evidence when no admin population override subsystem is installed.';
