-- Add paid-plan root cause output and AI usage telemetry fields.

alter table public.findings
  add column if not exists root_cause_text text;

alter table public.ai_usage_logs
  add column if not exists prompt_version text,
  add column if not exists personalization_version text,
  add column if not exists context_hash text,
  add column if not exists cached_tokens integer,
  add column if not exists thoughts_tokens integer,
  add column if not exists total_tokens integer;

create index if not exists ai_usage_logs_prompt_version_created_idx
  on public.ai_usage_logs (prompt_version, created_at desc);

create index if not exists ai_usage_logs_context_hash_created_idx
  on public.ai_usage_logs (context_hash, created_at desc)
  where context_hash is not null;
