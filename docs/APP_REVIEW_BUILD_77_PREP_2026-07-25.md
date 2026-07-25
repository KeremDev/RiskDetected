# RiskDetected 1.2.4 (77) — App Review Hazırlık Teslimi

Tarih: 25 Temmuz 2026

## Durum

- App Store Connect sürümü: `1.2.4`
- Build: `77`
- App Store Connect durumu: `PREPARE_FOR_SUBMISSION`
- Review durumu: `NOT_SUBMITTED`
- Build işleme durumu: `VALID`
- App Review engeli: `0`
- Zorunlu olmayan uyarı: Dört abonelik için opsiyonel tanıtım görseli

Build App Store Connect'e yüklenmiş ve `1.2.4` sürümüne bağlanmıştır. Review submission oluşturulmamış ve Apple incelemesine gönderilmemiştir.

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

`ios_release_policy.latest_build` şimdilik `76` olarak tutulmuştur. Build 77 henüz App Store'da canlı olmadığı için bunu erken yükseltmek mevcut kullanıcılara yanlış güncelleme bildirimi gösterebilir.

`1.2.4 (77)` App Store'da yayınlandıktan sonra:

1. `latest_build=77` yapılmalı.
2. Policy version build 77'yi ifade edecek şekilde güncellenmeli.
3. `minimum_supported_build`, `hard_update` ve mevcut destek politikası ayrıca değişiklik talep edilmedikçe korunmalı.

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

## Göndermeden önce sahibi tarafından yapılacak son kontroller

1. App Store Connect'te `1.2.4` sayfasını ve seçili build `77` bilgisini görsel olarak doğrula.
2. Ekran görüntülerinin doğru cihaz setleri ve güncel metinlerle göründüğünü kontrol et.
3. App Privacy cevaplarının yayınlanmış olduğunu App Store Connect arayüzünden doğrula. API bu yayın durumunu kesin olarak raporlamıyor.
4. Türkçe açıklama, What's New ve Review Notes alanlarını son kez oku.
5. Review demo hesabını ve notlarda anlatılan giriş/abonelik akışını özel olarak doğrula.
6. İstersen build 77'yi gerçek cihaz/TestFlight üzerinden son kez smoke et.
7. Kontroller tamamlanınca App Store Connect arayüzünden review'e ekleme ve gönderme işlemini kullanıcı olarak yap.

## Yayın sonrası

- Build canlı olduktan sonra `ios_release_policy.latest_build=77` güncellemesini uygula.
- Notification otomasyonunu doğrudan `on` yapma; önce internal allowlist/shadow metriklerini değerlendir.
- Notification rollout açılırken transactional analiz/rapor/trial bildirimlerinin izole kaldığını delivery tablolarından doğrula.
- Abonelik tanıtım görselleri isteğe bağlıdır; App Review gönderimini engellemez.
