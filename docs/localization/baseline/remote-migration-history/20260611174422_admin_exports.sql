-- V21: Admin export audit trail

create table if not exists public.admin_exports (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid references auth.users(id) on delete set null,
  admin_email text,
  resource text not null,
  format text not null,
  reason text not null,
  filter_json jsonb not null default '{}'::jsonb,
  row_count integer not null default 0,
  file_name text not null,
  created_at timestamptz not null default now(),

  constraint admin_exports_format_check check (format in ('csv', 'xlsx')),
  constraint admin_exports_resource_check check (
    resource in ('users', 'analyses', 'reports', 'subscriptions', 'support', 'deletion', 'audit-logs')
  )
);

create index if not exists admin_exports_created_at_idx
  on public.admin_exports(created_at desc);

create index if not exists admin_exports_admin_user_id_idx
  on public.admin_exports(admin_user_id);

alter table public.admin_exports enable row level security;

revoke all on table public.admin_exports from anon;
revoke all on table public.admin_exports from authenticated;

grant select, insert on table public.admin_exports to service_role;;
