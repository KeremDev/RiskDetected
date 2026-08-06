-- Covers the F4 RPC (20260806223000_android_notification_delivery_attempt_v2.sql): v1 stays
-- byte-for-byte behaviorally identical (delegates to v2), v2 is provider-aware and fails closed
-- on an unknown provider.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(10);

select has_function(
  'public', 'record_notification_delivery_attempt_v2',
  array['uuid','uuid','uuid','text','integer','text','text','integer','text','text','integer'],
  'record_notification_delivery_attempt_v2 exists with the expected signature'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000801'::uuid,
  'android-push-delivery-test@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

insert into public.push_device_tokens (id, user_id, token, platform, environment, provider)
values (
  '00000000-0000-4000-8000-000000000802'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'ios-token-for-v1-regression',
  'ios',
  'production',
  'apns'
);

insert into public.notification_events (id, user_id, kind, title, body)
values (
  '00000000-0000-4000-8000-000000000803'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'report_ready',
  'title',
  'body'
);

-- v1 call (exact pre-existing external signature) must still succeed and land with
-- provider='apns' + apns_id populated, exactly like before this migration existed.
select lives_ok(
  $$
    select public.record_notification_delivery_attempt_v1(
      '00000000-0000-4000-8000-000000000803'::uuid,
      null,
      '00000000-0000-4000-8000-000000000802'::uuid,
      'production',
      1,
      'accepted',
      200,
      'apns-message-id-123',
      null,
      45
    )
  $$,
  'v1 call with its original signature still succeeds unchanged'
);

select is(
  (
    select provider from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000802'::uuid
      and attempt_number = 1
  ),
  'apns',
  'v1-created row has provider=apns (delegation default)'
);

select is(
  (
    select apns_id from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000802'::uuid
      and attempt_number = 1
  ),
  'apns-message-id-123',
  'v1-created row still writes into the apns_id column, not provider_message_id'
);

select is(
  (
    select provider_message_id from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000802'::uuid
      and attempt_number = 1
  ),
  null,
  'v1-created (apns) row leaves provider_message_id null'
);

-- v2 direct call for an FCM attempt on the same event, a different token/attempt slot.
insert into public.push_device_tokens (id, user_id, token, platform, environment, provider)
values (
  '00000000-0000-4000-8000-000000000804'::uuid,
  '00000000-0000-4000-8000-000000000801'::uuid,
  'fcm-token-for-v2-test',
  'android',
  'production',
  'fcm'
);

select lives_ok(
  $$
    select public.record_notification_delivery_attempt_v2(
      '00000000-0000-4000-8000-000000000803'::uuid,
      null,
      '00000000-0000-4000-8000-000000000804'::uuid,
      'production',
      1,
      'accepted',
      'fcm',
      200,
      'fcm-message-id-456',
      null,
      30
    )
  $$,
  'v2 call with provider=fcm succeeds'
);

select is(
  (
    select provider from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000804'::uuid
      and attempt_number = 1
  ),
  'fcm',
  'fcm-created row has provider=fcm'
);

select is(
  (
    select apns_id from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000804'::uuid
      and attempt_number = 1
  ),
  null,
  'fcm-created row leaves apns_id null (mirror image of the apns case)'
);

select is(
  (
    select provider_message_id from private.notification_delivery_attempts
    where notification_event_id = '00000000-0000-4000-8000-000000000803'::uuid
      and push_device_token_id = '00000000-0000-4000-8000-000000000804'::uuid
      and attempt_number = 1
  ),
  'fcm-message-id-456',
  'fcm-created row writes provider_message_id'
);

select throws_ok(
  $$
    select public.record_notification_delivery_attempt_v2(
      '00000000-0000-4000-8000-000000000803'::uuid,
      null,
      '00000000-0000-4000-8000-000000000804'::uuid,
      'production',
      2,
      'accepted',
      'webpush',
      200,
      'whatever',
      null,
      10
    )
  $$,
  'P0001', null,
  'an unknown provider is rejected (fail-closed, not just apns/fcm)'
);

select * from finish();
rollback;
