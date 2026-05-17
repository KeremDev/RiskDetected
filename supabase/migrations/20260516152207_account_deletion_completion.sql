-- Privileged account deletion completion support.
--
-- The iOS app can only create an account_deletion_requests row. The actual
-- destructive completion is performed by the `account-deletion-complete` Edge
-- Function with service-role credentials.

alter table public.account_deletion_requests
  drop constraint if exists account_deletion_requests_user_id_fkey;

alter table public.account_deletion_requests
  alter column user_id drop not null;

alter table public.account_deletion_requests
  add constraint account_deletion_requests_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

alter table public.account_deletion_requests
  add column if not exists processing_started_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists processed_by text,
  add column if not exists completion_support_id text,
  add column if not exists completion_error text,
  add column if not exists target_user_id uuid,
  add column if not exists target_email text,
  add column if not exists target_user_hash text,
  add column if not exists deleted_photo_objects int not null default 0,
  add column if not exists deleted_report_objects int not null default 0,
  add column if not exists deleted_logo_objects int not null default 0,
  add column if not exists auth_user_deleted boolean not null default false;

update public.account_deletion_requests
set target_user_id = coalesce(target_user_id, user_id),
    target_email = coalesce(target_email, email),
    target_user_hash = coalesce(target_user_hash, md5(user_id::text))
where target_user_id is null
  and user_id is not null;

create index if not exists account_deletion_requests_target_user_idx
  on public.account_deletion_requests (target_user_id, created_at desc);

create index if not exists account_deletion_requests_completion_status_idx
  on public.account_deletion_requests (status, processing_started_at, completed_at);

select pg_notify('pgrst', 'reload schema');
