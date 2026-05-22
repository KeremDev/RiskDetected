-- Keep company reads simple and owner-scoped.
--
-- Paid-plan enforcement stays on INSERT/UPDATE through the existing policies
-- and private.enforce_company_write_rules() trigger. SELECT should not fail if
-- subscription state is temporarily stale or the policy helper cannot be
-- evaluated by PostgREST; Free users still cannot create or mutate companies.
drop policy if exists companies_select_paid_own on public.companies;
create policy companies_select_own
  on public.companies for select to authenticated
  using (auth.uid() = user_id);

select pg_notify('pgrst', 'reload schema');
