# NOVA telefon teslimi — 2.0.3 (93)

14 Eylül 2026. Kullanıcının açık telefon kurulumu talebi üzerine.

- iPhone Kerem / iPhone 17 Pro Max üzerindeki 2.0.3 (92), uninstall yapılmadan 2.0.3 (93) ile güncellendi.
- `com.riskdetected.app`; özel Debug `NOVA_PILOT_BUILD`, aynı pilot hesap, açık tema. Simülatör fixture argümanı olmadan başlatıldı.
- Tam cihaz Xcode build PASS ve `codesign --verify --deep --strict` PASS. Kurulum ve cihaz process launch başarılı.
- Önceki turdaki kompakt formlar, klavye kapatma/kutlama, firma accordion sayfası ve başlık bazlı skor modeli dahil. Kaynakların son simülatör kabulü 6 XCUI PASS.
- Dosya/Evrak girişleri henüz pasif; logo, belge, atama ve diğer yeni modüllerin canlı bağlantıları eksik. Tam veri yokken skor — gösterilir. Kurulum bu modüllerin tamamlandığı anlamına gelmez.
- Canlı migration, allowlist, kota ve rollout değiştirilmedi. Gerçek kullanıcı girişi/kayıt işlemi ajan tarafından yapılmadı.

## Kanıtlar

- `output/isg/pilot/DeviceBuild93Workspace.xcresult`
- `output/isg/pilot/device-build-93-workspace.log`
- `output/isg/pilot/device-install-93.json`
- `output/isg/pilot/device-launch-93.json`

Kalan kapsam: [Firma çalışma alanı](COMPANY_WORKSPACE_SPEC_2026-09-14.md), [önceki UI açık işleri](UI_ITERATION_2026-09-14.md).
