-- Keep profile localization fields internally consistent. English users who
-- enter through standalone authentication (without onboarding answers) get
-- the approved International terminology profile. Explicit onboarding/profile
-- selections for GB, US, AU, or CA remain unchanged.

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
    new.legal_document_set := 'tr-current';
  end if;

  return new;
end
$function$;

revoke all on function private.enforce_profile_localization_pair_v1()
  from public, anon, authenticated;

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
  legal_document_set
on public.profiles
for each row
execute function private.enforce_profile_localization_pair_v1();
