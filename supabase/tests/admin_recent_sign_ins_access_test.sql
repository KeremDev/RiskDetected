begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(5);

select has_function(
  'public',
  'admin_recent_sign_ins',
  array['integer'],
  '1 admin recent sign-ins function exists'
);

select ok(
  not has_function_privilege(
    'public',
    'public.admin_recent_sign_ins(integer)',
    'execute'
  ),
  '2 PUBLIC cannot execute admin recent sign-ins'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_recent_sign_ins(integer)',
    'execute'
  ),
  '3 anon cannot execute admin recent sign-ins'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_recent_sign_ins(integer)',
    'execute'
  ),
  '4 authenticated cannot execute admin recent sign-ins'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.admin_recent_sign_ins(integer)',
    'execute'
  ),
  '5 service role retains admin recent sign-ins access'
);

select * from extensions.finish();
rollback;
