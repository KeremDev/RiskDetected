# RiskDetected 1.2.4 (77) — App Review ve Yayın Teslimi

Hazırlık tarihi: 25 Temmuz 2026
Yayın doğrulama tarihi: 26 Temmuz 2026

## Durum

- App Store Connect sürümü: `1.2.4`
- Build: `77`
- App Store Connect durumu: `READY_FOR_DISTRIBUTION`
- App Store durumu: `READY_FOR_SALE`
- Review durumu: `COMPLETE`
- Build işleme durumu: `VALID`
- App Review engeli: `0`
- Zorunlu olmayan uyarı: Dört abonelik için opsiyonel tanıtım görseli

Build App Store Connect'e yüklenmiş, `1.2.4` sürümüne bağlanmış, Apple
incelemesinden geçmiş ve Türkiye App Store'da yayınlanmıştır.

## Release dosyaları

- Archive: `output/app-review-build-77/RiskDetected-1.2.4-77.xcarchive`
- IPA: `output/app-review-build-77/RiskDetected-1.2.4-77.ipa`
- IPA SHA-256: `4490f39a6d56abeb5333ccf5ecdabada5d84305a47ecdc53b5251b04cea59aa8`
- Preflight kanıtı: `output/app-review-build-77/App_Review_Preflight_Evidence_2026-07-25.md`
- Export ayarı: `Config/AppStoreExportOptions.plist`

İmzalı uygulama doğrulamaları:

- Bundle ID: `com.riskdetected.app`
- Sürüm/build: `1.2.4 (77)`
- Minimum iOS: `16.0`
- Dağıtım entitlement'ı: `aps-environment=production`
- Sign in with Apple entitlement'ı mevcut
- `get-task-allow=false`
- Privacy manifest mevcut
- Codesign doğrulaması başarılı
- Export compliance: muaf olmayan şifreleme kullanılmıyor

## Production backend durumu

### Notification otomasyonu

- `engagement_notification_automation.rollout_mode=off`
- `rollout_percentage=0`
- `kill_switch=false`
- Başlangıç kuralları `shadow`
- Aktif notification job/delivery yok
- Cron 15 dakikada bir çalışıyor ancak rollout kapalı olduğu için kullanıcıya otomatik engagement bildirimi göndermiyor

Bu ayar App Store build'inin notification izin, tercih, heartbeat ve açılma takibi parçalarını güvenli biçimde yayınlar. Otomatik gönderimler ayrı production gözlemi ve kontrollü rollout sonrasında açılmalıdır.

### Analiz ve çoklu fotoğraf

- Build `77`, `multi_photo_analysis.enabled_ios_builds` listesine eklenmiştir.
- Fotoğraf limitleri değişmemiştir: Free `1`, Plus `3`, Pro `3`.
- `analysis_pipeline_v2=on`
- `analysis_ambiguous_dispatch_guard=on`
- `cancelled_plus_trial_free_routing=on`
- `multi_photo_exact_coverage_schema=on`

Notification rollout ayarları analiz route'u, AI anahtar yönlendirmesi, bulgu finalizasyonu veya rapor üretimini değiştirmez.

### iOS release policy

Yayın doğrulandıktan sonra release policy production'da güncellenmiştir:

- `latest_build=77`
- `policy_version=build-77-appstore`
- `soft_update_enabled=true`
- `hard_update_enabled=false`
- `minimum_supported_build=62`

Bu yapı eski kullanıcılara yumuşak güncelleme uyarısı gösterebilir ancak zorunlu
güncelleme uygulamaz.

## Deploy edilen backend bileşenleri

- `send-push-notification` v43
- `process-notification-automation` v1
- `manage-notification-automation` v1
- `analyze` v134
- `process-analysis-jobs` v24
- `register-report` v18
- `generate-excel-report` v68

Uygulanan release migration'ları:

- `20260725192642_notification_automation_operations_center.sql`
- `20260725192933_harden_admin_recent_sign_ins_access.sql`
- `20260725193327_allow_multi_photo_build_77.sql`
- `20260726152710_publish_ios_build_77_release_policy.sql`

## Test özeti

- Deno testleri: `173/173` başarılı
- pgTAP: `135/135` başarılı
- Release-kritik UI testleri: `3/3` başarılı
- Purchase error classifier testi: başarılı
- İlgili Edge Function type-check: başarılı
- Değiştirilen TypeScript dosyalarında format kontrolü: başarılı
- Release archive: başarılı
- App Store IPA export: başarılı
- App Store Connect upload/processing: başarılı
- App Store validation: `0 error`, `0 blocking`, `4 non-blocking warning`
- Analiz readiness kontrolü: `23 PASS`, `0 FAIL`

Tam UI paketinin ilk çalışması 300 saniyelik araç timeout'una ulaştı; bu bir test assertion hatası değildi. Release ile doğrudan ilişkili üç UI senaryosu ayrıca izole edilerek başarıyla çalıştırıldı.

## Tamamlanan App Store kontrolleri

- Build `77`, sürüm `1.2.4` ve public Türkiye storefront doğrulandı.
- Review submission `COMPLETE`.
- Public mağaza sürümü `1.2.4`.
- Yaş derecelendirmesi sosyal medya soruları cevaplandı.
- Türkçe subtitle değişikliği bilinçli shared App Information değişikliği olarak gönderildi.

## Yayın sonrası

- İlk 24–48 saatte analiz, rapor, abonelik ve push hata oranlarını izle.
- Build 77 foreground heartbeat/adoption verisinin oluşmasını bekle.
- Notification otomasyonunu doğrudan `on` yapma; önce internal allowlist/shadow metriklerini değerlendir.
- Notification rollout açılırken transactional analiz/rapor/trial bildirimlerinin izole kaldığını delivery tablolarından doğrula.
- Abonelik tanıtım görselleri isteğe bağlıdır; App Review gönderimini engellemez.
