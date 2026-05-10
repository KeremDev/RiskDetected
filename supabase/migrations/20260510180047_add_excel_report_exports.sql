-- Excel risk analysis exports share the private reports bucket and metadata table.
-- PDF remains unchanged; XLSX files are identified by reports.format = 'xlsx'.

update storage.buckets
set allowed_mime_types = array[
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
],
file_size_limit = greatest(coalesce(file_size_limit, 20971520), 31457280)
where id = 'reports';

alter table public.reports
  add column if not exists format text not null default 'pdf',
  add column if not exists size_bytes integer,
  add column if not exists page_count integer,
  add column if not exists request_id text,
  add column if not exists support_id text;

alter table public.reports
  drop constraint if exists reports_format_check;

alter table public.reports
  add constraint reports_format_check
  check (format in ('pdf', 'xlsx'));

create index if not exists reports_user_format_created
  on public.reports (user_id, format, created_at desc);
