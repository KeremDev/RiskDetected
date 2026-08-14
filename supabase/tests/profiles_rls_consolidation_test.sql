begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(10);

select extensions.is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'profiles'),
  3,
  'profiles has one policy per supported command'
);
select extensions.is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'profiles' and cmd = 'SELECT'),
  1,
  'profiles has one SELECT policy'
);
select extensions.is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'profiles' and cmd = 'UPDATE'),
  1,
  'profiles has one UPDATE policy'
);
select extensions.is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'profiles' and cmd = 'INSERT'),
  1,
  'profiles has one INSERT policy'
);
select extensions.ok(
  (select bool_and(roles = array['authenticated']::name[]) from pg_policies where schemaname = 'public' and tablename = 'profiles'),
  'profile policies are scoped to authenticated users'
);
select extensions.ok(
  (select bool_and(coalesce(qual, with_check) like '%auth.uid()%') from pg_policies where schemaname = 'public' and tablename = 'profiles'),
  'every profile policy derives ownership from auth.uid()'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.profiles', 'SELECT'),
  'anonymous users cannot read profiles'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.profiles', 'INSERT'),
  'anonymous users cannot insert profiles'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.profiles', 'UPDATE'),
  'anonymous users cannot update profiles'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.profiles', 'SELECT')
  and not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
  and not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
  and has_column_privilege('authenticated', 'public.profiles', 'id', 'INSERT')
  and has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE'),
  'authenticated mobile clients keep field-authority-scoped profile privileges'
);

select * from extensions.finish();
rollback;
