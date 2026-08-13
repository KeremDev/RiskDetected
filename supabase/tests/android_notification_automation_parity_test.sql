begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(11);

select has_column('public', 'user_engagement_state', 'ios_authorization_status',
  'iOS authorization is stored independently');
select has_column('public', 'user_engagement_state', 'android_authorization_status',
  'Android authorization is stored independently');
select has_column('public', 'user_engagement_state', 'ios_last_foreground_at',
  'iOS foreground heartbeat is stored independently');
select has_column('public', 'user_engagement_state', 'android_last_foreground_at',
  'Android foreground heartbeat is stored independently');
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_android_user_engagement_state_v1(text,text,text,text,text,text)',
    'execute'
  ),
  'authenticated Android client can record its own heartbeat'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_android_user_engagement_state_v1(text,text,text,text,text,text)',
    'execute'
  ),
  'anonymous client cannot record an Android heartbeat'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000751'::uuid,
  'android-automation-parity@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

insert into public.push_device_tokens (
  user_id, token, platform, environment, provider, provider_environment,
  application_id, notifications_enabled
) values
  (
    '00000000-0000-4000-8000-000000000751'::uuid,
    'parity-apns-token', 'ios', 'production', 'apns', null,
    null, true
  ),
  (
    '00000000-0000-4000-8000-000000000751'::uuid,
    'parity-fcm-token', 'android', 'production', 'fcm', 'riskdetected',
    'com.riskdetectedan.app', true
  );

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000751',
  true
);

select lives_ok(
  $$select public.record_android_user_engagement_state_v1(
    'Europe/Istanbul', 'tr-TR', 'denied', '1.5.0', '3', 'com.riskdetectedan.app'
  )$$,
  'valid Android engagement heartbeat succeeds'
);
select is(
  (select android_authorization_status from public.user_engagement_state
    where user_id = '00000000-0000-4000-8000-000000000751'::uuid),
  'denied',
  'Android authorization state is recorded'
);
select is(
  (select notifications_enabled from public.push_device_tokens where token = 'parity-fcm-token'),
  false,
  'Android denial disables the matching FCM token'
);
select is(
  (select notifications_enabled from public.push_device_tokens where token = 'parity-apns-token'),
  true,
  'Android denial does not disable the iOS APNs token'
);

select public.record_user_engagement_state_v1(
  'Europe/Istanbul', 'tr_TR', 'authorized', '1.5.0', '81'
);
select is(
  (select authorization_status from public.user_engagement_state
    where user_id = '00000000-0000-4000-8000-000000000751'::uuid),
  'authorized',
  'legacy aggregate remains authorized when either platform is authorized'
);

select * from extensions.finish();
rollback;
