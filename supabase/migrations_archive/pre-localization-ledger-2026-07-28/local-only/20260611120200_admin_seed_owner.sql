-- Seed the production owner only when the matching auth user already exists.
-- Local/staging resets often do not contain production auth.users rows; in that
-- case this migration must remain a no-op instead of breaking the full chain.
do $$
declare
  v_owner_user_id uuid := '09bfd048-0bfe-451d-9633-0488c94596e6';
  v_owner_email text := 'kayalar.kerem@gmail.com';
begin
  if exists (select 1 from auth.users where id = v_owner_user_id) then
    insert into public.admin_users (user_id, email, role, is_active, mfa_required)
    values (v_owner_user_id, v_owner_email, 'owner', true, true)
    on conflict (email) do update
    set user_id = excluded.user_id,
        role = 'owner',
        is_active = true,
        mfa_required = true;
  else
    raise notice 'Skipping admin owner seed; auth user % is not present.', v_owner_user_id;
  end if;
end
$$;
