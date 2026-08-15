begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(37);

select has_column('public', 'profiles', 'signup_platform', 'signup platform exists');
select has_column('public', 'profiles', 'last_seen_platform', 'last seen platform exists');
select has_column('public', 'profiles', 'platform_attribution_version', 'attribution version exists');
select has_table('public', 'user_platform_daily_activity', 'daily platform activity exists');
select has_column('public', 'reports', 'client_platform', 'report platform exists');
select has_function(
  'public',
  'record_client_platform_v1',
  array['text', 'text', 'text'],
  'public platform RPC exists'
);
select function_privs_are(
  'public', 'record_client_platform_v1', array['text', 'text', 'text'],
  'authenticated', array['EXECUTE'],
  'authenticated users can execute the platform RPC'
);
select function_privs_are(
  'public', 'record_client_platform_v1', array['text', 'text', 'text'],
  'anon', array[]::text[],
  'anonymous users cannot execute the platform RPC'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_platform_daily_activity', 'select'),
  'authenticated users cannot read the activity table directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_platform_daily_activity', 'insert'),
  'authenticated users cannot insert activity directly'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'signup_platform', 'update'),
  'authenticated users cannot overwrite signup platform directly'
);
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'last_seen_platform', 'update'),
  'authenticated users cannot overwrite last seen platform directly'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_platform_daily_activity'::regclass),
  'activity table has RLS enabled'
);
select ok(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'record_client_platform_v1'),
  'platform RPC is security definer so clients need no direct analytics grants'
);
select ok(
  (select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""']
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'record_client_platform_v1'),
  'platform RPC pins an empty search path'
);
select ok(
  (select position('auth.uid()' in pg_get_functiondef(p.oid)) > 0
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'record_client_platform_v1'),
  'platform RPC derives ownership from auth.uid()'
);
select has_function(
  'public', 'admin_platform_overview_v1', array['integer', 'text'],
  'admin platform aggregate RPC exists'
);
select function_privs_are(
  'public', 'admin_platform_overview_v1', array['integer', 'text'],
  'service_role', array['EXECUTE'],
  'service role can execute aggregate RPC'
);
select function_privs_are(
  'public', 'admin_platform_overview_v1', array['integer', 'text'],
  'authenticated', array[]::text[],
  'authenticated clients cannot execute aggregate RPC'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('00000000-0000-4000-8000-000000004101', 'platform-new@example.invalid', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-4000-8000-000000004102', 'platform-legacy@example.invalid', 'authenticated', 'authenticated', now(), now());

update public.profiles
set platform_attribution_version = 0
where id = '00000000-0000-4000-8000-000000004102';

set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-4000-8000-000000004101';
set local "request.jwt.claim.role" = 'authenticated';

select is(
  (public.record_client_platform_v1(' IOS ', '1.3.1', '82')->>'recorded')::boolean,
  true,
  'new user platform observation succeeds'
);
reset role;
select is(
  (select signup_platform from public.profiles where id = '00000000-0000-4000-8000-000000004101'),
  'ios',
  'first observation sets signup platform'
);
select is(
  (select signup_platform_source from public.profiles where id = '00000000-0000-4000-8000-000000004101'),
  'first_authenticated_observation',
  'first observation records its source'
);
select is(
  (select observation_count from public.user_platform_daily_activity
    where user_id = '00000000-0000-4000-8000-000000004101' and platform = 'ios'),
  1,
  'first daily observation creates one row'
);

set local role authenticated;
select lives_ok(
  $$ select public.record_client_platform_v1('android', '1.5.3', '5') $$,
  'a later Android observation succeeds'
);
reset role;
select is(
  (select signup_platform from public.profiles where id = '00000000-0000-4000-8000-000000004101'),
  'ios',
  'later platform does not overwrite signup platform'
);
select is(
  (select last_seen_platform from public.profiles where id = '00000000-0000-4000-8000-000000004101'),
  'android',
  'later platform updates last seen platform'
);
select is(
  (select count(*)::integer from public.user_platform_daily_activity
    where user_id = '00000000-0000-4000-8000-000000004101'),
  2,
  'same account can have daily rows on both platforms'
);
select throws_ok(
  $$ select public.record_client_platform_v1('web', '1.0', '1') $$,
  '22023', 'invalid_client_platform',
  'unknown platforms are rejected'
);
select throws_ok(
  $$ select public.record_client_platform_v1('ios', '1.0', 'build-82') $$,
  '22023', 'invalid_app_build',
  'non-numeric builds are rejected'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '00000000-0000-4000-8000-000000004102';
select lives_ok(
  $$ select public.record_client_platform_v1('android', '1.5.3', '5') $$,
  'legacy profile observation succeeds'
);
reset role;
select is(
  (select signup_platform from public.profiles where id = '00000000-0000-4000-8000-000000004102'),
  null,
  'legacy profile does not acquire a false signup platform'
);
select is(
  (select last_seen_platform from public.profiles where id = '00000000-0000-4000-8000-000000004102'),
  'android',
  'legacy profile still records last seen platform'
);

set local "request.jwt.claim.sub" = '';
set local "request.jwt.claim.role" = '';
select throws_ok(
  $$ select public.record_client_platform_v1('ios', '1.3.1', '82') $$,
  '28000', 'auth_required',
  'unauthenticated invocation is rejected'
);
select is(
  jsonb_typeof(public.admin_platform_overview_v1(30, 'all')),
  'object',
  'admin overview returns aggregate JSON only'
);
update public.user_subscriptions
set status = case
      when user_id = '00000000-0000-4000-8000-000000004101' then 'active'
      else 'inactive'
    end,
    store = case
      when user_id = '00000000-0000-4000-8000-000000004101' then 'PLAY_STORE'
      else 'APP_STORE'
    end
where user_id in (
  '00000000-0000-4000-8000-000000004101',
  '00000000-0000-4000-8000-000000004102'
);
select is(
  (public.admin_platform_overview_v1(30, 'all')->'subscriptions'->>'app_store')::integer,
  0,
  'inactive historical store rows are excluded from current subscription metrics'
);
select throws_ok(
  $$ select public.admin_platform_overview_v1(30, 'ios''; drop table public.profiles; --') $$,
  '22023', 'invalid_platform',
  'aggregate platform input cannot inject SQL'
);
select throws_ok(
  $$ select public.admin_platform_overview_v1(31, 'all') $$,
  '22023', 'invalid_days',
  'aggregate range is allowlisted'
);

select * from extensions.finish();
rollback;
