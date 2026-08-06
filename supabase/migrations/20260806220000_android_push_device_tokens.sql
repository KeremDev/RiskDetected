-- Android platform support for push_device_tokens (review doc F1 + F2, blockers).
--
-- F1: platform CHECK only allowed 'ios' — an FCM token insert from Android would fail with
--     23514 check_violation on first attempt. Widen it to allow 'android' too.
--
-- F2: environment CHECK only allows 'sandbox'/'production' — that's APNs semantics (sandbox
--     vs production APNs gateway). FCM has no equivalent split; environment there is just
--     which Firebase project the token belongs to. Rather than widen `environment` and blur
--     its APNs meaning, add a separate nullable `provider_environment` column for Android and
--     leave `environment` untouched — every existing APNs query/index keeps working unchanged.
--
-- Additive only: no existing row's platform/environment value is touched, no column dropped.

alter table public.push_device_tokens
  drop constraint if exists push_device_tokens_platform_check;
alter table public.push_device_tokens
  add constraint push_device_tokens_platform_check
  check (platform in ('ios', 'android'));

alter table public.push_device_tokens
  add column if not exists provider text not null default 'apns'
    check (provider in ('apns', 'fcm'));

alter table public.push_device_tokens
  add column if not exists provider_environment text;

alter table public.push_device_tokens
  add column if not exists application_id text;

alter table public.push_device_tokens
  add column if not exists installation_id uuid;

alter table public.push_device_tokens
  add column if not exists client_build text;

comment on column public.push_device_tokens.provider is
  'Push transport for this token: apns (iOS) or fcm (Android). Default apns preserves every existing row''s meaning unchanged.';
comment on column public.push_device_tokens.provider_environment is
  'Android/FCM-only: which Firebase project this token belongs to (e.g. firebase project alias). NULL for iOS rows — environment (sandbox/production) already carries that meaning for APNs and is left untouched.';
comment on column public.push_device_tokens.client_build is
  'iOS build number or Android versionCode as a string, same convention as analyses.client_build (analyses_client_build_check regex).';
