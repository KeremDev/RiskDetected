-- Track which Gemini API key alias handled a request without storing raw keys.

alter table public.ai_usage_logs
  add column if not exists api_key_alias text,
  add column if not exists attempt_count integer;

create index if not exists ai_usage_logs_api_key_alias
  on public.ai_usage_logs (api_key_alias)
  where api_key_alias is not null;
