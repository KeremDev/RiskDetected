-- Covers the F1/F2 additive migration (20260806220000_android_push_device_tokens.sql):
-- existing iOS rows/queries stay valid, Android rows become insertable, unknown platform/
-- provider values still fail closed.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(10);

select has_column('public', 'push_device_tokens', 'provider', 'provider column exists');
select has_column('public', 'push_device_tokens', 'provider_environment', 'provider_environment column exists');
select has_column('public', 'push_device_tokens', 'application_id', 'application_id column exists');
select has_column('public', 'push_device_tokens', 'installation_id', 'installation_id column exists');
select has_column('public', 'push_device_tokens', 'client_build', 'client_build column exists');

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000701'::uuid,
  'android-push-test@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

select lives_ok(
  $$
    insert into public.push_device_tokens (user_id, token, platform, environment)
    values (
      '00000000-0000-4000-8000-000000000701'::uuid,
      'legacy-apns-token',
      'ios',
      'sandbox'
    )
  $$,
  'existing iOS insert shape (no new columns) still works unchanged'
);

select is(
  (
    select provider from public.push_device_tokens
    where user_id = '00000000-0000-4000-8000-000000000701'::uuid
      and token = 'legacy-apns-token'
  ),
  'apns',
  'provider defaults to apns for rows that do not specify it — zero iOS regression'
);

select lives_ok(
  $$
    insert into public.push_device_tokens
      (user_id, token, platform, environment, provider, provider_environment, application_id, client_build)
    values (
      '00000000-0000-4000-8000-000000000701'::uuid,
      'fcm-token-abc',
      'android',
      'production',
      'fcm',
      'riskdetected-android-prod',
      'com.riskdetectedan.app',
      '1'
    )
  $$,
  'Android/FCM row with the full new column set is insertable'
);

select throws_ok(
  $$
    insert into public.push_device_tokens (user_id, token, platform, environment)
    values (
      '00000000-0000-4000-8000-000000000701'::uuid,
      'web-token',
      'web',
      'production'
    )
  $$,
  '23514', null,
  'unknown platform values remain rejected (fail-closed, not just ios/android)'
);

select throws_ok(
  $$
    insert into public.push_device_tokens (user_id, token, platform, environment, provider)
    values (
      '00000000-0000-4000-8000-000000000701'::uuid,
      'bad-provider-token',
      'android',
      'production',
      'webpush'
    )
  $$,
  '23514', null,
  'unknown provider values are rejected'
);

select * from finish();
rollback;
