-- Filename timestamp matches the production migration history entry.
-- admin_recent_sign_ins exposes auth email/activity data and is an
-- Operations Center service-role internal. A later function recreation kept
-- explicit anon/authenticated grants in production, so revoke every public
-- Data API role explicitly.

do $$
begin
  if to_regprocedure('public.admin_recent_sign_ins(integer)') is not null then
    revoke all on function public.admin_recent_sign_ins(integer)
      from public, anon, authenticated;
    grant execute on function public.admin_recent_sign_ins(integer)
      to service_role;
  end if;
end
$$;

select pg_notify('pgrst', 'reload schema');
