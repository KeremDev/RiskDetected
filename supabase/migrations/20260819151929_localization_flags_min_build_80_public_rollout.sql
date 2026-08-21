-- Canonical timestamp aligned with the production migration history.
-- Wave 1 lokalizasyon bayraklarini yayin oncesi kohorttan cikarip herkese acar.
--
-- Onceki durum: 13 bayrak `allowlist` modunda ve `enabled_user_hashes` tek bir
-- hash tasiyordu, yani Ingilizce yuzey hic yayina alinmamisti. `enabled_ios_builds`
-- dizisi bu modda hic okunmuyordu (localizationFlagEnabled: modlar birbirini
-- disliyor), dolayisiyla build 81'de kalmis olmasi bir sey bozmuyordu.
--
-- Bu migration tek basina yeterli DEGILDIR: `preReleaseLocalizationFlagEnabled`
-- mod ne olursa olsun kohort kontrolu yaptigi icin, ayni surumde
-- `_shared/localization-context-resolver.ts` guncellendi ve `analyze` fonksiyonu
-- yeniden dagitildi. Orada `on` ve `min_build` yayin modu sayilir; `allowlist` ve
-- `build_allowlist` ise yayin oncesi kalir ve kohort istemeye devam eder.
--
-- Kohort listeleri bilerek silinmiyor: bayrak ileride `allowlist` moduna geri
-- alinirsa gozden gecirme kohortu oldugu gibi calisir.
--
-- Fresh/local replay `off` durumunda baslar (bkz. 20260802214159): oradaki
-- gozden gecirme kohortu operasyonel olarak acilmisti, migration zincirinde
-- degil. Bu migration de ayni emsali izliyor -- `off` bayraklari dokunmadan
-- birakiyor, zinciri tekrar oynatilamaz hale getirmek yerine.

do $localization_min_build$
declare
  v_keys constant text[] := array[
    'localization_v2',
    'english_product_enabled',
    'global_localization_wave1',
    'safety_profile_en_intl_enabled',
    'safety_profile_en_gb_enabled',
    'safety_profile_en_us_enabled',
    'safety_profile_en_au_enabled',
    'safety_profile_en_ca_enabled',
    'localization_queue_payload_v1',
    'ai_language_guard_enabled',
    'ai_country_term_guard_enabled',
    'english_report_enabled',
    'english_notifications_enabled'
  ];
  v_count integer;
begin
  select count(*) into v_count
  from public.app_feature_flags
  where key = any(v_keys);
  if v_count <> cardinality(v_keys) then
    raise exception 'expected % localization flags, found %',
      cardinality(v_keys), v_count;
  end if;

  if exists (
    select 1 from public.app_feature_flags
    where key = any(v_keys)
      and coalesce((value ->> 'kill_switch')::boolean, true)
  ) then
    raise exception 'refusing to release a localization flag whose kill switch is on';
  end if;

  if exists (
    select 1 from public.app_feature_flags
    where key = any(v_keys)
      and coalesce(value ->> 'rollout_mode', 'off')
          not in ('off', 'allowlist', 'build_allowlist', 'min_build')
  ) then
    raise exception 'refusing to release a localization flag from an unexpected rollout mode';
  end if;

  update public.app_feature_flags
  set value = value || jsonb_build_object(
        'rollout_mode', 'min_build',
        'min_ios_build', 80,
        'public_rollout_started_at', now()
      ),
      updated_at = now()
  where key = any(v_keys)
    and coalesce(value ->> 'rollout_mode', 'off') <> 'off';

  if exists (
    select 1 from public.app_feature_flags
    where key = any(v_keys)
      and coalesce(value ->> 'rollout_mode', 'off') <> 'off'
      and (
        value ->> 'rollout_mode' is distinct from 'min_build'
        or (value ->> 'min_ios_build')::integer is distinct from 80
      )
  ) then
    raise exception 'localization min_build switch did not apply to every flag';
  end if;
end;
$localization_min_build$;
