-- Supabase deprecated auth.role(). Preserve the service-role-only RPC guard
-- while reading the PostgREST JWT request context directly.

do $$
declare
  function_oid oid;
  function_ddl text;
  old_guard constant text := 'coalesce(auth.role(), '''')';
  new_guard constant text :=
    'coalesce(' ||
    'nullif(current_setting(''request.jwt.claims'', true), '''')::jsonb ->> ''role'', ' ||
    'nullif(current_setting(''request.jwt.claim.role'', true), ''''), ' ||
    ''''')';
begin
  function_oid :=
    'public.apply_finding_mutation_atomic(text,uuid,uuid,uuid,integer,jsonb,text[],text,text,text)'
      ::regprocedure::oid;
  select pg_get_functiondef(function_oid) into function_ddl;

  if position(old_guard in function_ddl) = 0 then
    raise exception 'expected deprecated finding RPC role guard was not found';
  end if;

  execute replace(function_ddl, old_guard, new_guard);
end;
$$;

revoke all on function public.apply_finding_mutation_atomic(
  text,
  uuid,
  uuid,
  uuid,
  integer,
  jsonb,
  text[],
  text,
  text,
  text
) from public, anon, authenticated;
grant execute on function public.apply_finding_mutation_atomic(
  text,
  uuid,
  uuid,
  uuid,
  integer,
  jsonb,
  text[],
  text,
  text,
  text
) to service_role;

select pg_notify('pgrst', 'reload schema');
