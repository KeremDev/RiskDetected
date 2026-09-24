-- Replace placeholders before applying in production:
-- AUTH_USER_UUID_HERE = Supabase auth.users.id for the admin account
-- ADMIN_EMAIL_HERE    = admin email address

insert into public.admin_users (user_id, email, role, is_active, mfa_required)
values ('09bfd048-0bfe-451d-9633-0488c94596e6', 'kayalar.kerem@gmail.com', 'owner', true, true)
on conflict (email) do update
set user_id = excluded.user_id,
    role = 'owner',
    is_active = true,
    mfa_required = true;
