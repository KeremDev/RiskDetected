create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid references auth.users(id) on delete set null,
  admin_email text,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  ip_hash text,
  user_agent_hash text,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_logs_created_at_idx
  on public.admin_audit_logs(created_at desc);

create index if not exists admin_audit_logs_admin_user_id_idx
  on public.admin_audit_logs(admin_user_id);

create index if not exists admin_audit_logs_action_idx
  on public.admin_audit_logs(action);

create index if not exists admin_audit_logs_target_idx
  on public.admin_audit_logs(target_type, target_id);

alter table public.admin_audit_logs enable row level security;

revoke all on table public.admin_audit_logs from anon;
revoke all on table public.admin_audit_logs from authenticated;

grant select, insert on table public.admin_audit_logs to service_role;;
