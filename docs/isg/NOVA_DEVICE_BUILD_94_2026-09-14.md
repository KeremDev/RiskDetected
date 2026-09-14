# NOVA telefon teslimi — 2.0.3 (94)

14 Eylül 2026. Kullanıcının açık telefon kurulum talebi üzerine.

- iPhone Kerem / iPhone 17 Pro Max üzerindeki `com.riskdetected.app` 2.0.3 (93) korunarak 2.0.3 (94) ile güncellendi; uninstall yapılmadı.
- Cihaz build’i ve `codesign --verify --deep --strict` başarılı.
- Uygulama cihazda başlatıldı; `devicectl` sürüm kontrolü `2.0.3 / 94`.
- Build; tüm accordion’ların kapalı başlaması, sağda renkli Eksik/Tamamlandı rozeti, firma kartı skor halkası, içerik ölçümlü popup, görev alanı ve firma güncelle/sil görsel önizlemelerini içerir.
- Bu sürümde yeni görsel alanların backend bağlantısı yapılmadı; canlı veriler, izinler ve migration değişmedi. Görev/güncelle/sil işlemleri görsel önizlemedir.

## Kanıtlar

- `output/isg/pilot/DeviceBuild94.xcresult`
- `output/isg/pilot/device-build-94.log`
- `output/isg/pilot/device-install-94.json`
- `output/isg/pilot/device-launch-94.json`
