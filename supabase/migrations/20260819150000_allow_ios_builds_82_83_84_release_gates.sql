-- iOS build allowlist'i 82, 83 ve 84'e genisletir.
--
-- Bulgu: allowlist build 81'de kalmis. 1.3.2 (82) ve 1.3.3 (83) App Store'a
-- cikarken hicbir bayrak guncellenmedi, dolayisiyla o build'lerdeki kullanicilar
-- multi_photo_analysis kapisina takiliyor. Ayni kapi `editable_findings`
-- ozelligini de tasidigi icin bulgu duzenleme VE silme 423 ile reddediliyor
-- (mutate-analysis-finding: "Bulgu düzenleme geçici olarak kapalı").
-- 1.3.3 su an READY_FOR_SALE, yani bu canli kullanicilari etkiliyor.
--
-- Rollout modlari, kill switch'ler, gozden gecirme kohortlari, plan limitleri ve
-- iOS release policy'si degismez; yalnizca mevcut allowlist'e üç build eklenir.

do $allow_ios_builds_82_83_84$
declare
  v_new_builds constant text[] := array['82', '83', '84'];
  v_updated integer;
begin
  -- Fail closed: beklenmedik bir rollout modunda sessizce genisletme.
  if exists (
    select 1
    from public.app_feature_flags
    where value ? 'enabled_ios_builds'
      and coalesce(value ->> 'rollout_mode', 'off')
          not in ('allowlist', 'build_allowlist')
  ) then
    raise exception
      'refusing to extend enabled_ios_builds while a flag is outside allowlist rollout';
  end if;

  update public.app_feature_flags
  set value = jsonb_set(
        value,
        '{enabled_ios_builds}',
        (
          select coalesce(jsonb_agg(distinct build order by build), '[]'::jsonb)
          from jsonb_array_elements_text(
            coalesce(value -> 'enabled_ios_builds', '[]'::jsonb)
              || to_jsonb(v_new_builds)
          ) as build
        ),
        true
      ),
      updated_at = now()
  where value ? 'enabled_ios_builds';

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'no feature flag carries enabled_ios_builds';
  end if;

  -- Her bayrak ucunu de tasimali.
  if exists (
    select 1
    from public.app_feature_flags
    where value ? 'enabled_ios_builds'
      and not (
        (value -> 'enabled_ios_builds') ? '82'
        and (value -> 'enabled_ios_builds') ? '83'
        and (value -> 'enabled_ios_builds') ? '84'
      )
  ) then
    raise exception 'enabled_ios_builds extension did not cover every flag';
  end if;
end;
$allow_ios_builds_82_83_84$;
