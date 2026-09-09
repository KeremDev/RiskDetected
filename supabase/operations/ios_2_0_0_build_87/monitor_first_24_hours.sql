begin;
set local transaction read only;

with recent_analyses as (
  select a.*, r.config_snapshot
  from public.analyses a
  left join private.analysis_engine_routes r on r.analysis_id = a.id
  where a.client_platform = 'ios'
    and a.client_build = '87'
    and created_at >= now() - interval '24 hours'
), route_counts as (
  select
    count(*)::integer as analyses,
    count(*) filter (
      where config_snapshot->>'engine_variant' = 'vnext-v4'
    )::integer as v4_routes,
    count(*) filter (
      where config_snapshot is null
    )::integer as missing_routes,
    count(*) filter (where status::text = 'failed')::integer as failed_analyses
  from recent_analyses
), report_counts as (
  select
    count(*) filter (where event_name = 'report_created')::integer as created,
    count(*) filter (where event_name = 'report_downloaded')::integer as downloaded,
    count(*) filter (where event_name = 'report_download_failed')::integer as download_failed
  from private.report_activity_events
  where client_platform = 'ios'
    and client_app_build = '87'
    and created_at >= now() - interval '24 hours'
)
select
  route_counts.analyses,
  route_counts.v4_routes,
  route_counts.missing_routes,
  route_counts.failed_analyses,
  case when route_counts.analyses = 0 then null
       else round(100.0 * route_counts.v4_routes / route_counts.analyses, 2)
  end as v4_route_percent,
  report_counts.created as created_reports,
  report_counts.downloaded as downloaded_reports,
  report_counts.download_failed as failed_report_downloads
from route_counts, report_counts;

rollback;
