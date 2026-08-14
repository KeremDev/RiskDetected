-- DEC-10 (Android master plan): Android gets its own legal document text, not iOS's, because it
-- names different platform mechanics (Google Play vs App Store, FCM vs APNs, no Apple Sign-In).
-- `legal_document_set` values are computed server-side by a trigger
-- (private.enforce_profile_localization_pair_v1, migration 20260801214500) that today hardcodes
-- 'tr-current' for every app_language='tr' row -- platform-blind, and it fires for every live iOS
-- profile too. This migration adds a platform signal and branches the trigger on it, changing
-- behavior ONLY when client_platform='android' is explicitly set; every existing/iOS row (NULL or
-- 'ios') keeps producing 'tr-current' exactly as before -- verified by the pgTAP test in this same
-- migration's companion test file before this is ever pushed past staging.
--
-- Same additive/nullable/NOT VALID pattern as 20260806224500_android_client_platform_columns.sql
-- (analyses/ai_usage_logs) -- profiles never got that column, so it's added here instead of
-- duplicating a third copy of the same convention.

alter table public.profiles
  add column if not exists client_platform text;
alter table public.profiles
  add constraint profiles_client_platform_check
    check (client_platform is null or client_platform in ('ios', 'android'))
    not valid;

comment on column public.profiles.client_platform is
  'ios | android | NULL (predates this column, or set before the client started sending it). '
  'Same convention as public.analyses.client_platform (20260806224500). Read by '
  'private.enforce_profile_localization_pair_v1 to pick the Turkish legal_document_set.';

-- 20260801170000_client_field_authority_hardening.sql column-scoped the authenticated role's
-- insert/update grants on public.profiles down to an explicit column list -- a brand-new column
-- is NOT writable by the client until it's added to that list too, or every client write that
-- includes client_platform (which is the entire point of this migration) fails closed with a
-- permission error instead of the intended CHECK/trigger behavior. Additive grant, same two
-- statements' shape as that migration used for every other column in the list.
grant insert (client_platform) on public.profiles to authenticated;
grant update (client_platform) on public.profiles to authenticated;

-- Widen the two legal_document_set CHECK constraints to admit the new Android set. Additive:
-- both constraints already allowed exactly ('tr-current', 'en-global-v1'); this only adds a third
-- value, nothing existing is removed or re-validated.
alter table public.profiles
  drop constraint if exists profiles_legal_document_set_check;
alter table public.profiles
  add constraint profiles_legal_document_set_check
  check (
    legal_document_set is null
    or legal_document_set in ('tr-current', 'en-global-v1', 'tr-android-v1')
  );

alter table public.consents
  drop constraint if exists consents_legal_document_set_check;
alter table public.consents
  add constraint consents_legal_document_set_check
  check (
    legal_document_set is null
    or legal_document_set in ('tr-current', 'en-global-v1', 'tr-android-v1')
  );

-- Replace the trigger function: only the Turkish branch's legal_document_set assignment changes
-- (one line, case expression on client_platform). English branch, jurisdiction/locale/safety
-- profile derivation for both branches, and the trigger's column list are untouched.
create or replace function private.enforce_profile_localization_pair_v1()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.app_language = 'en' then
    case new.safety_profile_id
      when 'en-gb-generic-v1' then
        new.preferred_content_locale := 'en-GB';
        new.work_jurisdiction_country := 'GB';
      when 'en-us-generic-v1' then
        new.preferred_content_locale := 'en-US';
        new.work_jurisdiction_country := 'US';
      when 'en-au-generic-v1' then
        new.preferred_content_locale := 'en-AU';
        new.work_jurisdiction_country := 'AU';
      when 'en-ca-generic-v1' then
        new.preferred_content_locale := 'en-CA';
        new.work_jurisdiction_country := 'CA';
      when 'en-intl-generic-v1' then
        new.preferred_content_locale := 'en-001';
        new.work_jurisdiction_country := 'INTL';
      else
        new.safety_profile_id := 'en-intl-generic-v1';
        new.preferred_content_locale := 'en-001';
        new.work_jurisdiction_country := 'INTL';
        new.work_jurisdiction_region := null;
    end case;

    new.safety_profile_version := 1;
    new.legal_document_set := 'en-global-v1';
  elsif new.app_language = 'tr' then
    new.preferred_content_locale := 'tr-TR';
    new.work_jurisdiction_country := 'TR';
    new.work_jurisdiction_region := null;
    new.safety_profile_id := 'tr-tr-current-v1';
    new.safety_profile_version := 1;
    new.legal_document_set := case
      when new.client_platform = 'android' then 'tr-android-v1'
      else 'tr-current'
    end;
  end if;

  return new;
end
$function$;

-- Re-create with client_platform added to the "update of" column list so a later update that
-- only touches client_platform (without also touching app_language) still re-derives
-- legal_document_set. INSERT already fires unconditionally regardless of this list -- the
-- primary path (Android's initial profile upsert sending app_language+client_platform together)
-- worked correctly even before this addition.
drop trigger if exists profiles_localization_pair_guard_v1
  on public.profiles;
create trigger profiles_localization_pair_guard_v1
before insert or update of
  app_language,
  preferred_content_locale,
  work_jurisdiction_country,
  work_jurisdiction_region,
  safety_profile_id,
  safety_profile_version,
  legal_document_set,
  client_platform
on public.profiles
for each row
execute function private.enforce_profile_localization_pair_v1();
