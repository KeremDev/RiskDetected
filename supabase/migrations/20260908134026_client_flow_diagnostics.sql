-- First-party operational diagnostics. Never use usage_events (quota accounting).
-- Filename aligned with the verified production migration history after MCP deployment.
create table public.client_flow_events (
  client_event_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  platform text not null check (platform in ('ios','android')),
  app_version text not null check (length(app_version) between 1 and 32),
  app_build text not null check (length(app_build) between 1 and 16),
  stage text not null check (stage in ('home','photo_picker','photo_import','photo_ready','analysis_cta','analysis_validation','analysis_prepare','analysis_create','analysis_upload','analysis_submit','analysis_result','billing_launch','billing_result')),
  outcome text not null check (outcome in ('started','completed','cancelled','blocked','failed','pending')),
  reason text not null default 'none' check (reason in ('none','unknown','auth','quota','safety_profile','photo_limit','no_photo','permission','io','network','timeout','runtime_gate','membership','activity_inactive','already_running','store','backend')),
  photo_count integer not null default 0 check (photo_count between 0 and 3),
  client_occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.client_flow_events enable row level security;
revoke all on public.client_flow_events from public, anon, authenticated;
grant select, insert on public.client_flow_events to authenticated;
grant all on public.client_flow_events to service_role;
create policy client_flow_insert_owner on public.client_flow_events for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy client_flow_read_owner on public.client_flow_events for select to authenticated
  using ((select auth.uid()) = user_id);
create index client_flow_events_user_time on public.client_flow_events(user_id, created_at desc);
create index client_flow_events_retention on public.client_flow_events(created_at);
comment on table public.client_flow_events is 'Untrusted client diagnostics, not purchase/quota authority. Allowlisted fields only; no image, content, raw error, advertising ID or payment details.';
select cron.schedule('client-flow-events-retention', '35 3 * * *',
  $$delete from public.client_flow_events where created_at < now() - interval '30 days'$$);
