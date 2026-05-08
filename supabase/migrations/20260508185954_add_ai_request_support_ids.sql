-- Adds trace ids and normalized error metadata for AI/support diagnostics.

alter table public.ai_usage_logs
  add column if not exists request_id text,
  add column if not exists support_id text,
  add column if not exists error_code text,
  add column if not exists http_status integer,
  add column if not exists fallback_source text;

create index if not exists ai_usage_logs_request_id
  on public.ai_usage_logs (request_id)
  where request_id is not null;

create index if not exists ai_usage_logs_support_id
  on public.ai_usage_logs (support_id)
  where support_id is not null;
