# RiskDetected 1.3.0 (80) — Production Release Kaydı

Doğrulama tarihi: 2 Ağustos 2026

## App Store durumu

- App Store uygulama kimliği: `6769498181`
- Bundle ID: `com.riskdetected.app`
- Sürüm: `1.3.0`
- Build: `80`
- Version ID: `9a2f5061-8992-4957-a9e8-7b8a96747323`
- Build ID: `71cc9591-32b9-4fee-b6c4-8c4d30713b23`
- Submission ID: `25adf0dc-eae0-4616-b667-96aa244638f8`
- Review durumu: `COMPLETE`
- Version durumu: `READY_FOR_DISTRIBUTION`
- App Review engeli: `0`

Manuel App Store release işlemi proje sahibi tarafından tamamlandı. Bu kayıt
oluşturulurken `asc review status --app 6769498181` ile dağıtım durumu yeniden
okundu.

## Global localization aktivasyonu

Build 80, aşağıdaki 13 production localization flag'inin
`enabled_ios_builds` allowlist'ine eklendi:

- `localization_v2`
- `english_product_enabled`
- `global_localization_wave1`
- `safety_profile_en_intl_enabled`
- `safety_profile_en_gb_enabled`
- `safety_profile_en_us_enabled`
- `safety_profile_en_au_enabled`
- `safety_profile_en_ca_enabled`
- `localization_queue_payload_v1`
- `ai_language_guard_enabled`
- `ai_country_term_guard_enabled`
- `english_report_enabled`
- `english_notifications_enabled`

Production readback sonucu:

- Flag sayısı: `13`
- Build 80 açık flag sayısı: `13`
- `rollout_mode=allowlist` flag sayısı: `13`
- Aktif kill switch sayısı: `0`
- Mevcut reviewer hash allowlist'leri korundu.
- Eski App Store build'leri genel Build 80 allowlist aktivasyonuna dahil edilmedi.

## Bildirim otomasyonu aktivasyonu

`engagement_notification_automation` gerçek production gönderimine kontrollü
olarak açıldı:

- `rollout_mode=on`
- `rollout_percentage=5`
- `live_rollout_stage=5_percent`
- `kill_switch=false`
- `first_analysis_after_24h=active`
- `inactivity_after_5d=active`
- 15 dakikalık production cron aktif
- Son 24 saatlik doğrulamada cron hatası: `0`

Bu sistem iOS build numarasıyla değil kullanıcı hash bucket'ı, bildirim izni,
`app_reminders` tercihi, yerel saat, aktivite ve gönderim cap'leriyle
sınırlandırılır. Bu nedenle notification automation için Build 80 allowlist
değişikliği yapılmadı.

Bir sonraki kontrollü rollout aşamaları ayrı production kararıdır:
`%5 → %25 → %100`.

## Multi-photo durumu

`multi_photo_analysis` production readback sonucu:

- `rollout_mode=build_allowlist`
- Build `80` allowlist'te
- `kill_switch=false`
- Free: en fazla `1` fotoğraf
- Plus: en fazla `3` fotoğraf
- Pro: en fazla `3` fotoğraf

## Yayın öncesi ve aktivasyon doğrulamaları

- Wave 1 completion matrix: `37/37`
- Phase 6 Node testleri: `35/35`
- Phase 6 Deno testleri: `73/73`
- Phase 6 pgTAP: `45/45`
- Localization profil testleri: `17/17`
- Localization katalog gate'leri: `23/23`
- Localization AI testleri: `63/63`
- Notification activation odaklı testler: `18/18`
- Canlı Phase 5 external gate: geçti
- Build 77 ve Build 80 e-posta OTP istekleri: doğrulandı

## Operasyon sınırları

- Bu kayıt App Store release işlemini tekrar çalıştırmaz.
- Bu kayıt yeni bir Supabase mutation uygulamaz; doğrulanmış production
  durumunu belgeler.
- Localization rollback, Build `80` değerinin 13 localization
  `enabled_ios_builds` listesinden atomik olarak çıkarılmasıyla yapılır.
- Notification automation rollback, global kill switch veya
  `rollout_mode=off` ile; kural bazında ise `paused` durumuyla yapılır.
- Notification rollout yüzdesi ayrı read-after-write doğrulaması olmadan
  yükseltilmemelidir.
