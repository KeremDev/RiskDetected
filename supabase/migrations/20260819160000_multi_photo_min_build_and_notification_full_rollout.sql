-- 1) multi_photo_analysis: build_allowlist -> min_build.
--
-- Allowlist her iOS build'inde elle genisletilmek zorundaydi ve build 81'de kalmisti.
-- 1.3.2 (82) ve 1.3.3 (83) App Store'a bu liste guncellenmeden cikti; ayni kapi
-- `editable_findings` ozelligini de tasidigi icin bulgu duzenleme VE silme, canli
-- kullanicilarda dahil, 423 ile reddedildi. min_build modu bu bakim yukunu kaldirir:
-- iOS 80 ve uzeri, Android 3 ve uzeri kalicilikla acik olur.
--
-- Android icin min_android_build acikca yazilir; min_build modunda Android tarafi
-- min_android_build'e bakar ve alan yoksa fail-closed davranip mevcut 3/4/5
-- allowlist'ini kaybederdi.
--
-- 2) engagement_notification_automation: %5 -> %100.
--
-- Kill switch, allowlist ve gozlem alanlari korunur; yalnizca yuzde ve asama etiketi
-- degisir.

do $multi_photo_min_build$
declare
  v_value jsonb;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'multi_photo_analysis'
  for update;

  if v_value is null then
    raise exception 'multi_photo_analysis feature flag is missing';
  end if;

  -- Fail closed: kapi beklenmedik bir moddaysa ya da kill switch aciksa dokunma.
  if coalesce(v_value ->> 'rollout_mode', 'off')
       not in ('build_allowlist', 'min_build') then
    raise exception
      'refusing to switch multi_photo_analysis from rollout_mode %',
      coalesce(v_value ->> 'rollout_mode', 'off');
  end if;
  if coalesce((v_value ->> 'kill_switch')::boolean, true) then
    raise exception 'refusing to widen multi_photo_analysis while kill_switch is on';
  end if;

  update public.app_feature_flags
  set value = v_value || jsonb_build_object(
        'rollout_mode', 'min_build',
        'min_ios_build', 80,
        'min_android_build', 3
      ),
      updated_at = now()
  where key = 'multi_photo_analysis';

  select value into v_value
  from public.app_feature_flags
  where key = 'multi_photo_analysis';

  if v_value ->> 'rollout_mode' is distinct from 'min_build'
     or (v_value ->> 'min_ios_build')::integer is distinct from 80
     or (v_value ->> 'min_android_build')::integer is distinct from 3 then
    raise exception 'multi_photo_analysis min_build switch did not apply';
  end if;
end;
$multi_photo_min_build$;

do $notification_full_rollout$
declare
  v_value jsonb;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'engagement_notification_automation'
  for update;

  if v_value is null then
    raise exception 'engagement_notification_automation feature flag is missing';
  end if;

  -- private.notification_feature_flag() bu uc alani dogrular; sozlesmeyi bozmadan ilerle.
  if coalesce(v_value ->> 'rollout_mode', '') not in ('off', 'allowlist', 'on')
     or jsonb_typeof(v_value -> 'enabled_user_hashes') is distinct from 'array'
     or jsonb_typeof(v_value -> 'kill_switch') is distinct from 'boolean' then
    raise exception 'invalid_notification_feature_flag';
  end if;
  if coalesce((v_value ->> 'kill_switch')::boolean, true) then
    raise exception 'refusing to widen notification automation while kill_switch is on';
  end if;

  update public.app_feature_flags
  set value = v_value || jsonb_build_object(
        'rollout_mode', 'on',
        'rollout_percentage', 100,
        'live_rollout_stage', '100_percent',
        'live_rollout_full_at', now()
      ),
      updated_at = now()
  where key = 'engagement_notification_automation';

  select value into v_value
  from public.app_feature_flags
  where key = 'engagement_notification_automation';

  if (v_value ->> 'rollout_percentage')::integer is distinct from 100
     or v_value ->> 'rollout_mode' is distinct from 'on' then
    raise exception 'notification automation full rollout did not apply';
  end if;
end;
$notification_full_rollout$;
