-- User-facing account/data deletion request log.
-- Actual Supabase Auth user deletion must be performed by a privileged backend/admin flow.

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'cancelled', 'rejected')),
  requested_scope text not null default 'account_and_data'
    check (requested_scope in ('account_and_data', 'data_only')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_deletion_requests enable row level security;

drop policy if exists "Users read own deletion requests" on public.account_deletion_requests;
create policy "Users read own deletion requests"
  on public.account_deletion_requests for select
  using (auth.uid() = user_id);

drop policy if exists "Users create own deletion requests" on public.account_deletion_requests;
create policy "Users create own deletion requests"
  on public.account_deletion_requests for insert
  with check (auth.uid() = user_id);

grant select, insert on public.account_deletion_requests to authenticated;

create index if not exists account_deletion_requests_user_created_idx
  on public.account_deletion_requests (user_id, created_at desc);

create index if not exists account_deletion_requests_status_created_idx
  on public.account_deletion_requests (status, created_at desc);

select pg_notify('pgrst', 'reload schema');
