begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(23);

select has_table('public', 'user_ad_attribution', 'attribution table exists');
select has_column('public', 'user_ad_attribution', 'user_id', 'user id exists');
select has_column('public', 'user_ad_attribution', 'platform', 'platform exists');
select has_column('public', 'user_ad_attribution', 'provider', 'provider exists');
select has_column('public', 'user_ad_attribution', 'campaign_name', 'campaign exists');
select has_column('public', 'user_ad_attribution', 'keyword_name', 'keyword exists');
select has_column('public', 'user_ad_attribution', 'sync_status', 'sync status exists');
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_ad_attribution'::regclass),
  'RLS is enabled'
);
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_ad_attribution'
      and policyname = 'user_ad_attribution_clients_deny_all'
      and permissive = 'RESTRICTIVE'
  ),
  'client access has an explicit restrictive deny policy'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_ad_attribution', 'select'),
  'authenticated cannot read attribution'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_ad_attribution', 'insert'),
  'authenticated cannot insert attribution'
);
select ok(
  not has_table_privilege('anon', 'public.user_ad_attribution', 'select'),
  'anon cannot read attribution'
);
select ok(
  not has_table_privilege('public', 'public.user_ad_attribution', 'select'),
  'PUBLIC cannot read attribution'
);
select ok(
  has_table_privilege('service_role', 'public.user_ad_attribution', 'select'),
  'service role can read attribution'
);
select ok(
  has_table_privilege('service_role', 'public.user_ad_attribution', 'insert'),
  'service role can insert attribution'
);
select hasnt_column('public', 'user_ad_attribution', 'email', 'email is not stored');
select hasnt_column('public', 'user_ad_attribution', 'phone', 'phone is not stored');
select hasnt_column('public', 'user_ad_attribution', 'idfa', 'IDFA is not stored');
select hasnt_column('public', 'user_ad_attribution', 'raw_attributes', 'raw attributes are not stored');

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000004201',
  'apple-ads-attribution@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.user_ad_attribution (
  user_id, platform, provider, media_source, sync_status
) values (
  '00000000-0000-4000-8000-000000004201',
  'ios',
  'apple_ads',
  'Apple Search Ads',
  'attributed'
);

select throws_ok(
  $$
    insert into public.user_ad_attribution (user_id, platform)
    values ('00000000-0000-4000-8000-000000004201', 'ios')
  $$,
  '23505', null,
  'user and platform are unique'
);

select throws_ok(
  $$
    insert into public.user_ad_attribution (user_id, platform)
    values ('00000000-0000-4000-8000-000000004201', 'web')
  $$,
  '23514', null,
  'unknown platforms are rejected'
);

select throws_ok(
  $$
    update public.user_ad_attribution
    set sync_status = 'organic'
    where user_id = '00000000-0000-4000-8000-000000004201'
  $$,
  '23514', null,
  'organic cannot be inferred as a sync status'
);

delete from auth.users
where id = '00000000-0000-4000-8000-000000004201';

select is(
  (select count(*)::integer from public.user_ad_attribution
    where user_id = '00000000-0000-4000-8000-000000004201'),
  0,
  'account deletion cascades to attribution'
);

select * from extensions.finish();
rollback;
