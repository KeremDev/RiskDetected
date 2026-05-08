-- Adds trace ids to generated report metadata so PDF/archive issues can be
-- matched with user-facing support codes.

alter table public.reports
  add column if not exists request_id text,
  add column if not exists support_id text;

create index if not exists reports_request_id
  on public.reports (request_id)
  where request_id is not null;

create index if not exists reports_support_id
  on public.reports (support_id)
  where support_id is not null;
