-- Treat one Android app installation as one active FCM registration.
--
-- FCM can rotate a token without changing the app installation. The original unique key
-- (user_id, token) allowed the rotated token to be inserted next to its stale predecessor,
-- which could deliver a notification twice until FCM eventually rejected the old token.
-- Nullable Android-only columns keep all legacy iOS/APNs rows outside this identity: PostgreSQL
-- unique indexes treat NULL values as distinct, so this is additive for iOS.

with ranked_android_tokens as (
  select
    id,
    row_number() over (
      partition by user_id, provider, application_id, installation_id
      order by last_registered_at desc, updated_at desc, created_at desc, id desc
    ) as row_rank
  from public.push_device_tokens
  where provider = 'fcm'
    and application_id is not null
    and installation_id is not null
)
delete from public.push_device_tokens target
using ranked_android_tokens ranked
where target.id = ranked.id
  and ranked.row_rank > 1;

create unique index if not exists push_device_tokens_android_installation_uidx
  on public.push_device_tokens (user_id, provider, application_id, installation_id);

comment on index public.push_device_tokens_android_installation_uidx is
  'One FCM registration per authenticated user and Android app installation; token rotations update the existing row. NULL Android-only values preserve legacy APNs multiplicity.';
