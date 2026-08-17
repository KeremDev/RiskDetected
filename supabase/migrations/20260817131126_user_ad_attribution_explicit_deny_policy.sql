-- Keep client access explicitly fail-closed while allowing service_role to
-- continue using its normal RLS bypass for the isolated attribution worker.
drop policy if exists user_ad_attribution_clients_deny_all
  on public.user_ad_attribution;

create policy user_ad_attribution_clients_deny_all
on public.user_ad_attribution
as restrictive
for all
to anon, authenticated
using (false)
with check (false);
