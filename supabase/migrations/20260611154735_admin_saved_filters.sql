create table if not exists public.admin_saved_filters (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  resource text not null,
  name text not null,
  filter_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint admin_saved_filters_resource_check
    check (
      resource in (
        'users',
        'analyses',
        'reports',
        'subscriptions',
        'support',
        'deletion',
        'audit-logs'
      )
    )
);

create unique index if not exists admin_saved_filters_admin_resource_name_idx
  on public.admin_saved_filters(admin_user_id, resource, name);

create index if not exists admin_saved_filters_admin_resource_idx
  on public.admin_saved_filters(admin_user_id, resource);

alter table public.admin_saved_filters enable row level security;

revoke all on table public.admin_saved_filters from anon;
revoke all on table public.admin_saved_filters from authenticated;

grant select, insert, update, delete on table public.admin_saved_filters to service_role;;
