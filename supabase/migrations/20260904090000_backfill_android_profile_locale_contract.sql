-- Backfill the locale contract for Android accounts that never received one.
--
-- send-push-notification refuses to localize (and therefore to send) a transactional
-- notification whose recipient profile has no app_language / preferred_content_locale; the event
-- is recorded as status='skipped', last_error='NOTIFICATION_RECIPIENT_LOCALE_MISSING'. iOS writes
-- both columns during auth, Android only wrote them from the onboarding-answers upsert, so
-- accounts that signed in without completing that step stayed locale-less and silently received
-- no "analiz hazır" / "rapor hazır" / account notification at all.
--
-- profiles.client_platform is filled in the same pass: it exists so
-- private.enforce_profile_localization_pair_v1 can pick the Turkish legal document set
-- ('tr-android-v1' for Android, 'tr-current' otherwise), but no client was writing it, so Android
-- accounts were filed under the iOS document set.
--
-- The client-side repair (ProfileLocalizationRepository, mirroring AuthService.swift) covers new
-- sessions from the next Android build onwards. This migration repairs the accounts that already
-- exist.
--
-- Scope is deliberately narrow and repair-only:
--   * only profiles that actually own an Android (FCM) push token,
--   * only columns that are currently NULL — an existing choice, including English, is kept,
--   * Android ships the Turkish contract (RdClientMetadata.localization()), so a profile with no
--     language at all is written as Turkish; one that already says 'en' keeps 'en'.
-- The localization trigger derives the remaining columns from app_language, so this only has to
-- supply the language, the platform, and a locale for the trigger's non-tr/en fallthrough.
-- Replays as a no-op on a database with no such rows.

do $$
declare
  repaired_count integer;
begin
  with repaired as (
    update public.profiles p
    set
      app_language = coalesce(nullif(btrim(p.app_language), ''), 'tr'),
      preferred_content_locale = coalesce(
        nullif(btrim(p.preferred_content_locale), ''),
        case when lower(nullif(btrim(p.app_language), '')) = 'en' then 'en-001' else 'tr-TR' end
      ),
      client_platform = coalesce(nullif(btrim(p.client_platform), ''), 'android')
    where exists (
      select 1
      from public.push_device_tokens t
      where t.user_id = p.id
        and t.provider = 'fcm'
    )
      and (
        nullif(btrim(p.app_language), '') is null
        or nullif(btrim(p.preferred_content_locale), '') is null
        or nullif(btrim(p.client_platform), '') is null
      )
    returning p.id
  )
  select count(*) into repaired_count from repaired;

  raise notice 'android profile locale backfill repaired % profile(s)', repaired_count;
end;
$$;

-- Guard: no Android push-token owner may be left without the pair the notification localizer
-- requires. Fails the migration loudly instead of leaving the same silent gap behind.
do $$
declare
  remaining_count integer;
begin
  select count(*)
    into remaining_count
  from public.profiles p
  where exists (
    select 1
    from public.push_device_tokens t
    where t.user_id = p.id
      and t.provider = 'fcm'
  )
    and (
      nullif(btrim(p.app_language), '') is null
      or nullif(btrim(p.preferred_content_locale), '') is null
    );

  if remaining_count > 0 then
    raise exception
      'android profile locale backfill left % profile(s) without app_language/preferred_content_locale',
      remaining_count;
  end if;
end;
$$;
