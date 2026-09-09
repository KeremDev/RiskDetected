-- User-level report creation and download ledger.
-- Successful report creation is captured server-side from public.reports so it
-- cannot be skipped by a client crash. Downloads are appended through the
-- authenticated RPC after the file reaches the device.

create table if not exists private.report_activity_events (
  id bigint generated always as identity primary key,
  client_event_id uuid,
  user_id uuid not null references auth.users(id) on delete cascade,
  analysis_id uuid references public.analyses(id) on delete set null,
  report_id uuid references public.reports(id) on delete set null,
  event_name text not null check (event_name in (
    'report_created', 'report_downloaded', 'report_download_failed'
  )),
  report_scope text not null check (report_scope in (
    'standard', 'risk_analysis', 'expert_recommendations',
    'approved_notebook', 'legacy_combined'
  )),
  report_format text not null check (report_format in ('pdf', 'xlsx', 'unknown')),
  report_kind text not null,
  method text,
  title_snapshot text,
  company_id uuid references public.companies(id) on delete set null,
  selected_item_count integer not null default 0
    check (selected_item_count >= 0),
  plan_snapshot text,
  source_surface text not null default 'unknown' check (source_surface in (
    'result_hub', 'result_detail', 'reports_archive', 'home', 'unknown'
  )),
  client_platform text,
  client_app_version text,
  client_app_build text,
  request_id text,
  support_id text,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

alter table private.report_activity_events enable row level security;
revoke all on table private.report_activity_events
  from public, anon, authenticated;
grant select, insert, update, delete on table private.report_activity_events
  to service_role;
grant usage, select on sequence private.report_activity_events_id_seq
  to service_role;

create unique index if not exists report_activity_client_event_unique_idx
  on private.report_activity_events (user_id, client_event_id)
  where client_event_id is not null;
create unique index if not exists report_activity_created_once_idx
  on private.report_activity_events (report_id)
  where event_name = 'report_created' and report_id is not null;
create index if not exists report_activity_user_created_idx
  on private.report_activity_events (user_id, created_at desc);
create index if not exists report_activity_scope_event_created_idx
  on private.report_activity_events (report_scope, event_name, created_at desc);
create index if not exists report_activity_report_created_idx
  on private.report_activity_events (report_id, created_at desc)
  where report_id is not null;

create or replace function private.report_activity_scope_v1(
  p_content_scope text,
  p_kind text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_content_scope in (
      'risk_analysis', 'expert_recommendations', 'approved_notebook'
    ) then p_content_scope
    when p_kind in ('riskAnalysis', 'risk_analysis') then 'risk_analysis'
    when p_content_scope = 'legacy_combined' then 'legacy_combined'
    else 'standard'
  end;
$$;

revoke all on function private.report_activity_scope_v1(text, text)
  from public, anon, authenticated;

create or replace function private.capture_report_created_activity_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.report_activity_events (
    user_id,
    analysis_id,
    report_id,
    event_name,
    report_scope,
    report_format,
    report_kind,
    method,
    title_snapshot,
    company_id,
    selected_item_count,
    plan_snapshot,
    source_surface,
    client_platform,
    request_id,
    support_id,
    metadata,
    created_at
  ) values (
    new.user_id,
    new.analysis_id,
    new.id,
    'report_created',
    private.report_activity_scope_v1(new.content_scope, new.kind),
    case when new.format in ('pdf', 'xlsx') then new.format else 'unknown' end,
    new.kind,
    new.method,
    new.title,
    new.company_id,
    greatest(coalesce(new.selection_count, 0), 0),
    new.entitlement_tier_snapshot,
    case
      when new.content_scope in (
        'risk_analysis', 'expert_recommendations', 'approved_notebook'
      ) then 'result_hub'
      else 'unknown'
    end,
    new.client_platform,
    new.request_id,
    new.support_id,
    jsonb_build_object(
      'document_no', new.document_no,
      'report_language', new.report_language,
      'report_locale', new.report_locale,
      'export_intent_id', new.export_intent_id
    ),
    new.created_at
  )
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function private.capture_report_created_activity_v1()
  from public, anon, authenticated;

drop trigger if exists reports_capture_activity_created_v1 on public.reports;
create trigger reports_capture_activity_created_v1
after insert on public.reports
for each row execute function private.capture_report_created_activity_v1();

-- Preserve successful report creation history that predates this ledger.
insert into private.report_activity_events (
  user_id,
  analysis_id,
  report_id,
  event_name,
  report_scope,
  report_format,
  report_kind,
  method,
  title_snapshot,
  company_id,
  selected_item_count,
  plan_snapshot,
  source_surface,
  client_platform,
  request_id,
  support_id,
  metadata,
  created_at
)
select
  r.user_id,
  r.analysis_id,
  r.id,
  'report_created',
  private.report_activity_scope_v1(r.content_scope, r.kind),
  case when r.format in ('pdf', 'xlsx') then r.format else 'unknown' end,
  r.kind,
  r.method,
  r.title,
  r.company_id,
  greatest(coalesce(r.selection_count, 0), 0),
  r.entitlement_tier_snapshot,
  case
    when r.content_scope in (
      'risk_analysis', 'expert_recommendations', 'approved_notebook'
    ) then 'result_hub'
    else 'unknown'
  end,
  r.client_platform,
  r.request_id,
  r.support_id,
  jsonb_build_object(
    'historical_backfill', true,
    'document_no', r.document_no,
    'report_language', r.report_language,
    'report_locale', r.report_locale,
    'export_intent_id', r.export_intent_id
  ),
  r.created_at
from public.reports r
on conflict do nothing;

create or replace function public.record_report_activity_event_v1(
  p_client_event_id uuid,
  p_event_name text,
  p_report_id uuid,
  p_source_surface text default 'unknown',
  p_client_platform text default null,
  p_client_app_version text default null,
  p_client_app_build text default null,
  p_request_id text default null,
  p_support_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_report public.reports%rowtype;
  v_event_id bigint;
begin
  if v_user_id is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_client_event_id is null then
    raise exception 'client_event_id_required' using errcode = '22023';
  end if;
  if p_event_name not in ('report_downloaded', 'report_download_failed') then
    raise exception 'invalid_report_event_name' using errcode = '22023';
  end if;
  if p_source_surface not in (
    'result_hub', 'result_detail', 'reports_archive', 'home', 'unknown'
  ) then
    raise exception 'invalid_report_source_surface' using errcode = '22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'invalid_report_event_metadata' using errcode = '22023';
  end if;

  select r.* into v_report
  from public.reports r
  where r.id = p_report_id
    and r.user_id = v_user_id;
  if not found then
    raise exception 'report_not_found' using errcode = 'P0002';
  end if;

  insert into private.report_activity_events (
    client_event_id,
    user_id,
    analysis_id,
    report_id,
    event_name,
    report_scope,
    report_format,
    report_kind,
    method,
    title_snapshot,
    company_id,
    selected_item_count,
    plan_snapshot,
    source_surface,
    client_platform,
    client_app_version,
    client_app_build,
    request_id,
    support_id,
    metadata
  ) values (
    p_client_event_id,
    v_user_id,
    v_report.analysis_id,
    v_report.id,
    p_event_name,
    private.report_activity_scope_v1(v_report.content_scope, v_report.kind),
    case when v_report.format in ('pdf', 'xlsx') then v_report.format else 'unknown' end,
    v_report.kind,
    v_report.method,
    v_report.title,
    v_report.company_id,
    greatest(coalesce(v_report.selection_count, 0), 0),
    coalesce(
      v_report.entitlement_tier_snapshot,
      (select p.tier::text from public.profiles p where p.id = v_user_id)
    ),
    p_source_surface,
    coalesce(p_client_platform, v_report.client_platform),
    p_client_app_version,
    p_client_app_build,
    coalesce(p_request_id, v_report.request_id),
    coalesce(p_support_id, v_report.support_id),
    p_metadata
  )
  on conflict (user_id, client_event_id)
    where client_event_id is not null
  do update set
    metadata = private.report_activity_events.metadata || excluded.metadata
  returning id into v_event_id;

  return v_event_id;
end;
$$;

revoke all on function public.record_report_activity_event_v1(
  uuid, text, uuid, text, text, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.record_report_activity_event_v1(
  uuid, text, uuid, text, text, text, text, text, text, jsonb
) to authenticated, service_role;

create or replace function public.admin_report_activity_v1(
  p_days integer default 30,
  p_limit integer default 200,
  p_offset integer default 0,
  p_user_id uuid default null,
  p_event_name text default null,
  p_report_scope text default null
)
returns table (
  event_id bigint,
  event_at timestamptz,
  user_id uuid,
  user_email text,
  user_full_name text,
  event_name text,
  event_label text,
  report_id uuid,
  analysis_id uuid,
  report_scope text,
  report_type_label text,
  report_format text,
  report_kind text,
  method text,
  report_title text,
  selected_item_count integer,
  plan_snapshot text,
  source_surface text,
  client_platform text,
  request_id text,
  support_id text,
  metadata jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    e.id,
    e.created_at,
    e.user_id,
    p.email,
    p.full_name,
    e.event_name,
    case e.event_name
      when 'report_created' then 'Rapor oluşturdu'
      when 'report_downloaded' then 'Rapor indirdi'
      when 'report_download_failed' then 'Rapor indirme hatası'
      else e.event_name
    end,
    e.report_id,
    e.analysis_id,
    e.report_scope,
    case e.report_scope
      when 'risk_analysis' then 'Risk Analizi'
      when 'expert_recommendations' then 'Uzman Görüşü'
      when 'approved_notebook' then 'Onaylı Defter'
      when 'standard' then 'Standart Rapor'
      else 'Birleşik/Eski Rapor'
    end,
    e.report_format,
    e.report_kind,
    e.method,
    e.title_snapshot,
    e.selected_item_count,
    e.plan_snapshot,
    e.source_surface,
    e.client_platform,
    e.request_id,
    e.support_id,
    e.metadata
  from private.report_activity_events e
  left join public.profiles p on p.id = e.user_id
  where e.created_at >= now() - make_interval(
      days => greatest(1, least(coalesce(p_days, 30), 3650))
    )
    and (p_user_id is null or e.user_id = p_user_id)
    and (p_event_name is null or e.event_name = p_event_name)
    and (p_report_scope is null or e.report_scope = p_report_scope)
  order by e.created_at desc, e.id desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000))
  offset greatest(0, coalesce(p_offset, 0));
$$;

revoke all on function public.admin_report_activity_v1(
  integer, integer, integer, uuid, text, text
) from public, anon, authenticated;
grant execute on function public.admin_report_activity_v1(
  integer, integer, integer, uuid, text, text
) to service_role;

comment on table private.report_activity_events is
  'Per-user immutable report creation/download activity ledger for product analytics and support.';
