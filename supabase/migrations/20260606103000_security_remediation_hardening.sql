-- Security remediation hardening for account deletion request ownership.
--
-- Normal authenticated users may only create deletion requests for their own
-- account. Privileged service-role flows can still update completion metadata,
-- and completed historical rows remain valid even if auth user deletion later
-- sets user_id to null.

alter table public.account_deletion_requests
  drop constraint if exists account_deletion_requests_target_self_check;

alter table public.account_deletion_requests
  add constraint account_deletion_requests_target_self_check
  check (
    target_user_id is null
    or user_id is null
    or target_user_id = user_id
  )
  not valid;

alter policy "Users create own deletion requests"
  on public.account_deletion_requests
  with check (
    (select auth.uid()) = user_id
    and (
      target_user_id is null
      or target_user_id = (select auth.uid())
    )
  );

select pg_notify('pgrst', 'reload schema');
