-- Tracks report-ready push delivery idempotently per generated report.

alter table public.reports
  add column if not exists report_ready_push_sent_at timestamptz;

create index if not exists reports_ready_push_pending_idx
  on public.reports (created_at desc)
  where report_ready_push_sent_at is null;
