-- The result hub Edge Function calls this RPC with the service role. The
-- private schema intentionally grants no direct usage, so an invoker-rights
-- SQL function fails with 42501 before it can read the owner allowlist.
create or replace function public.result_hub_allowlist_decision(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.analysis_result_hub_allowlist a
    where a.user_id = p_user_id and a.enabled
  );
$$;

revoke all on function public.result_hub_allowlist_decision(uuid)
  from public, anon, authenticated;
grant execute on function public.result_hub_allowlist_decision(uuid)
  to service_role;

comment on function public.result_hub_allowlist_decision(uuid) is
  'Service-only result hub rollout decision; SECURITY DEFINER is required because the source allowlist is private.';

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'result_hub_allowlist_decision'
      and p.prosecdef
  ) then
    raise exception 'result_hub_allowlist_decision must be security definer';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.result_hub_allowlist_decision(uuid)',
    'execute'
  ) then
    raise exception 'authenticated must not execute result_hub_allowlist_decision';
  end if;
end;
$$;

select pg_notify('pgrst', 'reload schema');
