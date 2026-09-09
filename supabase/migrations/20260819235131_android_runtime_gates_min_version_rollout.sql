-- Canonical timestamp aligned with the production migration history.
-- Android runtime kapilari: version_allowlist -> min_version.
--
-- Alti kapinin (client, auth, analysis_submit, payments, notifications,
-- pdf_reports) hepsi `version_allowlist` modunda ve listesi [2,3,4,5] idi. Liste her
-- yeni surumde elle genisletilmek zorundaydi; versionCode 6 yuklendigi anda ana
-- anahtar `android_client_enabled` "version_not_allowed" doner, o da kalan besini
-- `client_disabled` yapardi. Yani uygulama acilir acilmaz auth, analiz gonderimi,
-- odemeler, bildirimler ve PDF raporlarin tamami kapali gelirdi.
--
-- Ayni tuzak iOS tarafinda `multi_photo_analysis` kapisinda yasandi: allowlist build
-- 81'de kalmis, 82 ve 83 canliya bu liste guncellenmeden cikmis, bulgu duzenleme ve
-- silme canli kullanicilarda 423 ile reddedilmisti. Cozum orada da min_build'e
-- gecmekti (bkz. 20260819150951).
--
-- Esik 2: versionCode 1 Play App Signing'i etkinlestirmek icin kullanilan tek seferlik
-- yuklemeydi ve bugunku allowlist'te de yok. min_version 2 bugunku davranisi birebir
-- korur, 6 ve sonrasini kalicilikla acar.
--
-- `enabled_android_version_codes` silinmiyor: min_version modunda degerlendirici o
-- alani hic okumuyor (bkz. supabase/functions/_shared/android-runtime-gates.ts) ve
-- geri donmek gerekirse liste yerinde duruyor.

do $android_runtime_gates_min_version$
declare
  v_key text;
  v_value jsonb;
  v_mode text;
  v_keys constant text[] := array[
    'android_client_enabled',
    'android_auth_enabled',
    'android_analysis_submit_enabled',
    'android_payments_enabled',
    'android_notifications_enabled',
    'android_pdf_reports_enabled'
  ];
begin
  foreach v_key in array v_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key
    for update;

    if v_value is null then
      raise exception 'android runtime gate % is missing', v_key;
    end if;

    -- Fail closed: kapi beklenmedik bir moddaysa ya da kill switch aciksa dokunma.
    v_mode := coalesce(v_value ->> 'rollout_mode', 'off');
    if v_mode not in ('version_allowlist', 'build_allowlist', 'allowlist',
                      'min_version', 'min_build') then
      raise exception 'refusing to switch % from rollout_mode %', v_key, v_mode;
    end if;
    if coalesce((v_value ->> 'kill_switch')::boolean, true) then
      raise exception 'refusing to widen % while kill_switch is on', v_key;
    end if;

    update public.app_feature_flags
    set value = v_value || jsonb_build_object(
          'rollout_mode', 'min_version',
          'min_android_version_code', 2
        ),
        updated_at = now()
    where key = v_key;
  end loop;

  foreach v_key in array v_keys loop
    select value into v_value
    from public.app_feature_flags
    where key = v_key;

    if v_value ->> 'rollout_mode' is distinct from 'min_version'
       or (v_value ->> 'min_android_version_code')::integer is distinct from 2
       or coalesce((v_value ->> 'kill_switch')::boolean, true) then
      raise exception '% min_version switch did not apply', v_key;
    end if;
  end loop;
end;
$android_runtime_gates_min_version$;
