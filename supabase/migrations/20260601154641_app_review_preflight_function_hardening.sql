-- App Review preflight hardening.
-- Keep trigger/helper functions out of public RPC reach and pin function
-- search_path values so execution cannot be influenced by caller role state.

revoke execute on function public.enforce_report_plan_limits() from public, anon, authenticated;
revoke execute on function public.set_photo_retention_fields() from public, anon, authenticated;

grant execute on function public.enforce_report_plan_limits() to service_role;
grant execute on function public.set_photo_retention_fields() to service_role;

alter function public.set_updated_at()
  set search_path = public, pg_temp;

alter function private.pp_title_key_for_mdp(integer)
  set search_path = private, public, pg_temp;

alter function private.pp_title_label(text)
  set search_path = private, public, pg_temp;

alter function private.pp_competency_label(text)
  set search_path = private, public, pg_temp;

alter function private.pp_risk_rank(text)
  set search_path = private, public, pg_temp;

alter function private.pp_highest_risk_level(text, text)
  set search_path = private, public, pg_temp;

alter function private.pp_contains_any(text, text[])
  set search_path = private, public, pg_temp;
