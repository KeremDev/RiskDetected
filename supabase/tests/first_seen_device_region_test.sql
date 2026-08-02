begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

select has_column(
  'public',
  'profiles',
  'first_seen_device_region_code',
  'profiles stores the first observed device region'
);
select has_column(
  'public',
  'profiles',
  'first_seen_device_region_at',
  'profiles stores the first observed device region timestamp'
);
select col_type_is(
  'public',
  'profiles',
  'first_seen_device_region_code',
  'text',
  'device region uses a text country code'
);
select col_type_is(
  'public',
  'profiles',
  'first_seen_device_region_at',
  'timestamp with time zone',
  'device region capture time uses timestamptz'
);
select has_function(
  'public',
  'record_first_seen_device_region_v1',
  array['text'],
  'first observed device region RPC exists'
);
select function_privs_are(
  'public',
  'record_first_seen_device_region_v1',
  array['text'],
  'authenticated',
  array['EXECUTE'],
  'authenticated users can execute the device region RPC'
);
select function_privs_are(
  'public',
  'record_first_seen_device_region_v1',
  array['text'],
  'anon',
  array[]::text[],
  'anonymous users cannot execute the device region RPC'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'first_seen_device_region_code',
    'update'
  ),
  'authenticated users cannot update the region column directly'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'first_seen_device_region_at',
    'update'
  ),
  'authenticated users cannot update the capture timestamp directly'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'first_seen_device_region_code',
    'insert'
  ),
  'authenticated users cannot insert the region column directly'
);
select ok(
  not has_column_privilege(
    'authenticated',
    'public.profiles',
    'first_seen_device_region_at',
    'insert'
  ),
  'authenticated users cannot insert the capture timestamp directly'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  (
    '00000000-0000-4000-8000-000000003101'::uuid,
    'device-region-one@example.invalid',
    'authenticated',
    'authenticated',
    now(),
    now()
  ),
  (
    '00000000-0000-4000-8000-000000003102'::uuid,
    'device-region-two@example.invalid',
    'authenticated',
    'authenticated',
    now(),
    now()
  );

set local role authenticated;
set local "request.jwt.claim.sub" =
  '00000000-0000-4000-8000-000000003101';
set local "request.jwt.claim.role" = 'authenticated';

select is(
  public.record_first_seen_device_region_v1(' au '),
  'AU',
  'the RPC normalizes and records an alpha-2 region code'
);
select is(
  (
    select first_seen_device_region_code
    from public.profiles
    where id = '00000000-0000-4000-8000-000000003101'::uuid
  ),
  'AU',
  'the authenticated user records only their own profile region'
);
select ok(
  (
    select first_seen_device_region_at is not null
    from public.profiles
    where id = '00000000-0000-4000-8000-000000003101'::uuid
  ),
  'the first capture records a timestamp'
);
select is(
  public.record_first_seen_device_region_v1('CA'),
  'AU',
  'a later device region does not overwrite the first value'
);
select throws_ok(
  $$ select public.record_first_seen_device_region_v1('001') $$,
  '22023',
  'invalid_device_region_code',
  'numeric regions are rejected'
);
select throws_ok(
  $$ select public.record_first_seen_device_region_v1('') $$,
  '22023',
  'invalid_device_region_code',
  'empty regions are rejected'
);

reset role;
select is(
  (
    select first_seen_device_region_code
    from public.profiles
    where id = '00000000-0000-4000-8000-000000003102'::uuid
  ),
  null,
  'another user profile remains unchanged'
);
set local "request.jwt.claim.sub" = '';
set local "request.jwt.claim.role" = '';
select throws_ok(
  $$ select public.record_first_seen_device_region_v1('GB') $$,
  '28000',
  'auth_required',
  'the RPC rejects calls without an authenticated user'
);

select * from finish();
rollback;
