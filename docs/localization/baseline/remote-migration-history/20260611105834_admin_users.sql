create table if not exists public.admin_users (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'owner',
  is_active boolean not null default true,
  mfa_required boolean not null default true,
  allowed_scopes text[] not null default array['*'],
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  last_login_at timestamptz,

  constraint admin_users_role_check
    check (role in ('owner', 'support', 'finance', 'analyst', 'legal_ops'))
);

create unique index if not exists admin_users_user_id_idx
  on public.admin_users(user_id);

alter table public.admin_users enable row level security;

revoke all on table public.admin_users from anon;
revoke all on table public.admin_users from authenticated;

grant select, insert, update, delete on table public.admin_users to service_role;;
