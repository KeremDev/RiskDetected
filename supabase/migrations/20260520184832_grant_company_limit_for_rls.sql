-- RLS policies on public.companies call this security-definer helper.
-- Authenticated users need EXECUTE permission for the policy expression to run.
grant execute on function private.company_limit_for_user(uuid) to authenticated;
