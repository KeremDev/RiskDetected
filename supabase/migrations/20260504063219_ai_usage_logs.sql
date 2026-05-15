create table if not exists public.ai_usage_logs (
  id           uuid primary key default gen_random_uuid(),
  analysis_id  uuid references public.analyses(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete cascade not null,
  provider     text not null default 'gemini',
  model        text not null,
  tokens_in    integer not null default 0,
  tokens_out   integer not null default 0,
  duration_ms  integer not null default 0,
  error        text,
  user_plan    text not null default 'free',
  created_at   timestamptz not null default now()
);

alter table public.ai_usage_logs enable row level security;

create policy "Users read own logs"
  on public.ai_usage_logs for select
  using (auth.uid() = user_id);

create index if not exists ai_usage_logs_user_created
  on public.ai_usage_logs (user_id, created_at desc);

create index if not exists ai_usage_logs_analysis
  on public.ai_usage_logs (analysis_id);;
