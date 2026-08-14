create table if not exists public.admin_rate_limit_events (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  key_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists admin_rate_limit_events_bucket_key_created_idx
  on public.admin_rate_limit_events (bucket, key_hash, created_at desc);

alter table public.admin_rate_limit_events enable row level security;

revoke all on table public.admin_rate_limit_events from anon;
revoke all on table public.admin_rate_limit_events from authenticated;

grant select, insert, delete on table public.admin_rate_limit_events to service_role;;
