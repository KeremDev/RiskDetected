# RiskDetected — iOS Güvenlik & Yayın Denetimi (Düzeltme Sonrası Doğrulama)
**Tarih:** 2026-05-30 · **Önceki rapor:** `SECURITY_QA_AUDIT_2026-05-29.md`
**Kapsam:** Kullanıcının uyguladığı düzeltmelerin kod kanıtıyla yeniden doğrulanması.
**Yöntem:** Statik kod incelemesi + backend kaynak okuması + iOS Simulator build + gerçek cihaz build/install/launch + Supabase certificate pin smoke. Instruments / canlı RLS testi içermez.

---

## 1. Executive Summary — GÜNCEL

**Genel risk seviyesi: LOW–MEDIUM** (önceki: MEDIUM). Submit-engelleyici tüm P0/P1 kod bulguları kapatıldı.

**Yayına hazır mı?** Kod tarafı **EVET** — kalan maddeler yalnızca App Store Connect / canlı hesap tarafında yapılacak doğrulamalar (demo hesabı, App Privacy label, canlı RLS testi).

**Düzeltme skoru: 6/6 P0–P2 + P3 sertleştirmeleri kapandı.**

| Bulgu | Önce | Şimdi |
|---|---|---|
| C-1 Paywall linkleri + Restore (P0) | 🔴 Ölü linkler, restore=satın alma | ✅ Çözüldü |
| C-2 Hesap silme (P0) | 🔴 "Talep" kaydı | ✅ Gerçek in-app silme |
| C-3 `config.toml` / verify_jwt (P1) | 🟠 Yok | ✅ Eklendi |
| C-4 `backups/` sızıntısı (P1) | 🟠 Commit'li | ✅ Gitignore + untracked |
| C-5 Foto base64 bellek (P1/P2) | 🟠 Açık | ✅ Kodla sınırlandırıldı |
| Nonce charset "W" (P3) | 🟡 Eksik | ✅ Düzeltildi |
| Offline banner (B-edge) | ⚠️ Belirsiz | ✅ Eklendi |

---

## 2. Doğrulanan Düzeltmeler (kanıtlı)

### C-1 · Onboarding paywall — ✅ ÇÖZÜLDÜ
- `App/Views/Onboarding/V2/OnboardingViewV2.swift:167-168`
  `onTerms: { openURL(RDConfig.Web.termsURL) }`, `onPrivacy: { openURL(RDConfig.Web.privacyPolicyURL) }` — yasal linkler artık çalışıyor.
- `onRestore: { restorePurchases() }` (satır 164-166) → `restorePurchases()` (satır 193-216) → `onRestorePurchases()` closure → `RootView.swift:26` → `restoreOnboardingPurchases()` → `app.restoreSubscriptions()` (`AppState.swift:226`). **Gerçek restore, yeni satın alma değil.** "Geri yüklenecek aktif abonelik bulunamadı" mesajı doğru.
- Hatalı legacy `OnboardingPaywallV2View.swift` **dosyası silinmiş** (dead code + tuzak kaldırıldı).
- **Sonuç:** App Store Guideline 3.1.2 uyumu sağlandı; çift-ücretlendirme finansal hatası giderildi.

### C-2 · Hesap silme — ✅ ÇÖZÜLDÜ (en kritik)
- Yeni `supabase/functions/request-account-deletion/index.ts`: çağıranın JWT'sini doğruluyor (`supabase.auth.getUser`, satır 161), sonra service-role ile `account-deletion-complete`'i **senkron** çağırıyor (satır 195). Service-role anahtarı asla cihaza gitmiyor.
- `account-deletion-complete/index.ts`: storage prefix'lerini (photos/reports/logos/avatars) siliyor (satır 345-364) **ve `supabase.auth.admin.deleteUser(...)` ile gerçek auth kullanıcısını siliyor** (satır 364). `auth_user_deleted` flag'i dönüyor.
- App tarafı: `AnalysisService.requestAccountDeletion` artık fonksiyonu çağırıp `AccountDeletionRequestResult` dönüyor; `ProfileView.swift:1149-1160` sonuç `shouldClearLocalSession` ise yerel oturumu kapatıyor. UI metni "Hesabımı ve verilerimi sil".
- **Sonuç:** Apple Guideline 5.1.1(v) — kullanıcı tarafından başlatılan, uygulama içinde tamamlanan gerçek hesap+veri silme. Uyumlu.

### C-3 · Edge Function verify_jwt — ✅ ÇÖZÜLDÜ
- `supabase/config.toml` repoya eklendi; her fonksiyon için açık ayar.
- Kullanıcı-yüzlü: `support-contact`, `send-welcome-email`, `generate-excel-report`, `sync-revenuecat-subscription`, `send-report-ready-notification`, `request-account-deletion` → `verify_jwt = true` ✅
- Worker/webhook/cron: `analyze`, `process-analysis-jobs`, `account-deletion-complete`, `retention-cleanup`, `send-push-notification`, `revenuecat-webhook`, `gemini-free-qa-run`, `groq-qa-compare` → `verify_jwt = false` — **doğru ve kasıtlı**: bunlar içeride kendi `getUser`/service-role/Authorization-header doğrulamasını yapıyor (ör. `analyze` `getUser`; `revenuecat-webhook` `REVENUECAT_WEBHOOK_AUTHORIZATION` header kontrolü).

### C-4 · backups/ sızıntısı — ✅ ÇÖZÜLDÜ
- `.gitignore:33` → `backups/` eklendi.
- `git ls-files` artık `secrets-list.json` veya `backups/` altını izlemiyor. (İçerik zaten plaintext değil, SHA-256 digest'ti — yine de doğru temizlik.)

### Nonce charset — ✅ ÇÖZÜLDÜ
- `AppleSignInService.swift:58` ve `GoogleSignInService.swift:104`: eksik "W" eklendi → `...STUVWXYZ...`.

### Offline UX — ✅ EKLENMİŞ
- `RootView.swift:44-46`: `app.flow != .splash && !network.isOnline` iken `OfflineStatusBanner()` gösteriliyor.

---

## 3. Son Tur Doğrulamaları

### C-5 · Foto analizi base64 bellek — ✅ KODLA SINIRLANDIRILDI
- `AnalysisService.makeInlineJPEGParts` artık foto parçalarını sırayla, `autoreleasepool` içinde encode ediyor.
- Toplam payload eklemeden önce projekte ediliyor; 4.5MB sınırı aşılacaksa parça listeye eklenmeden kullanıcıya düşük çözünürlük/daha az fotoğraf mesajı dönüyor.
- Tek foto için `maxInlinePhotoBytes = 1_500_000` ve `maxInlinePhotoBase64Bytes = 2_100_000` sınırları ayrı ayrı uygulanıyor.
- Eski "son çare" davranışı olan `maxInlinePhotoBytes * 2` fallback kaldırıldı; çok büyük görsel artık agresif downscale/quality denemelerinden sonra reddediliyor.
- Submit-engelleyici risk kapandı. Yine de düşük-RAM cihazda Instruments Allocations smoke önerilir.

### Cert pinning / integrity smoke — ✅ KOD + CANLI HASH
- `scripts/verify_supabase_pins.sh` canlı Supabase zincirini doğruladı.
- Eşleşen pin: `HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=`
- Not: Google Trust Services zinciri değişirse `RDConfig.Security.pinnedCertificateSHA256Hashes` operasyonel olarak güncellenmeli.
- Gerçek cihaz: iPhone 14 Pro Max (`Kerem iPhone`) üzerinde build, install ve launch başarılı.
- Gerçek cihaz UI testi: `testProfileShowsDeviceIntegrityWarningWhenFlagged` geçti; integrity uyarı yüzeyi fiziksel cihazda çalışıyor.
- Gerçek cihaz Supabase smoke: `testRealDeviceSupabasePinnedConnection` geçti; iPhone üzerindeki test runner Supabase host'una pinli TLS bağlantısı kurdu.
- Gerçek cihaz full UI suite: `RiskDetectedUITests` tamamı iPhone 14 Pro Max üzerinde geçti; **10 test, 0 failure**.
- Memory warning smoke: `devicectl device process sendMemoryWarning` aynı PID ile iki kez `NSPOSIXErrorDomain 2` döndürdü; app yeniden launch edilebildi. Bu araç/cihaz servis blokajı olarak kaydedildi, app crash gözlenmedi.

### Gerçek cihaz build uyarısı — ✅ DÜZELTİLDİ
- iPhone build sırasında `TrialPreview.imageset` içinde eksik `trial-preview.png` referansı uyarı üretiyordu.
- `App/Assets.xcassets/TrialPreview.imageset/Contents.json` içindeki olmayan dosya referansı kaldırıldı; onboarding zaten asset yoksa SwiftUI fallback preview kullanıyor.
- Düzeltme sonrası gerçek cihaz build tekrar geçti ve `TrialPreview/trial-preview` uyarısı kalmadı.
- Release gerçek cihaz build sırasında iki marketing PNG'si 16-bit olduğu için `libpng` uyarısı üretiyordu.
- `App/Marketing/AppIconConcepts/app-store-search-mockup-light.png` ve `app-store-search-mockup-dark.png` 8-bit RGBA PNG'ye çevrildi; boyut ve alpha korundu.
- Düzeltme sonrası Release gerçek cihaz build tekrar geçti ve `libpng` uyarısı kalmadı.

### Privacy manifest / Release packaging — ✅ DOĞRULANDI
- Release-iphoneos app bundle içinde ana `PrivacyInfo.xcprivacy` mevcut.
- Release app bundle içinde RevenueCat, GoogleSignIn, GTMAppAuth, GTMSessionFetcher, AppAuth, GoogleUtilities, Promises ve swift-crypto privacy manifestleri bulundu.
- Release gerçek cihaz app install + launch başarılı.

### Canlı RLS izolasyonu — ✅ DOĞRULANDI
- `scripts/qa_live_rls_isolation.mjs` ile iki geçici Supabase kullanıcısı oluşturuldu.
- Kullanıcı A kendi `analyses`, `photos`, `reports` satırlarını insert/select yapabildi.
- Kullanıcı B, A'nın aynı satırlarını select ettiğinde 0 satır gördü.
- Kullanıcı B'nin A adına `analyses` insert denemesi RLS ile `403` döndü.
- Geçici auth kullanıcıları cleanup edildi.
- Rapor: `QA/Live_RLS_Isolation_QA_2026-05-29.md` → **12 PASS, 0 FAIL**

### Canlı hesap silme — ✅ DOĞRULANDI
- `request-account-deletion` remote'a deploy edildi.
- `account-deletion-complete` remote'da `--no-verify-jwt` ile redeploy edildi; önceki canlı denemede worker gateway `401` dönüyordu.
- Temp kullanıcıyla JWT üzerinden `request-account-deletion` çağrısı `200` döndü.
- Yanıt: `completed=true`, `auth_user_deleted=true`.
- Temp auth user silindi; eski JWT `/auth/v1/user` çağrısında `403` döndürdü.
- Tokensiz `request-account-deletion` çağrısı `401` döndürdü.
- Rapor: `QA/Account_Deletion_Live_QA_2026-05-30.md`

### Canlı analiz / rapor backend E2E — ✅ DOĞRULANDI
- `node scripts/qa_free_paid_ai_routing.mjs --live-e2e` çalıştırıldı.
- Temp kullanıcıyla analiz kaydı oluşturuldu, `analyze` kuyruğa alındı, worker tetiklendi ve analiz tamamlandı.
- Sonuç: 11 bulgu, `quality_tier=plus`, `ai_execution_route=free_paid_trial`, `api_key_alias=gemini_paid_primary`.
- İkinci free analiz kota koruması beklenen şekilde fail oldu.
- Temp queue ve auth kullanıcı cleanup edildi.
- Rapor: `QA/FreePaidAIRouting_QA_2026-05-29.md` → **40 PASS, 1 WARN, 0 FAIL**

### Gerçek cihaz Plus rapor akışı — ✅ DOĞRULANDI
- Kullanıcı fiziksel cihazda `plus@riskdetected.app` hesabıyla giriş yaptı.
- Canlı abonelik satırı doğrulandı: `tier=plus`, `status=active`, `product_id=riskdetected_plus_monthly`, `entitlement_id=plus`.
- Cihaz üzerinden standart PDF raporu oluşturuldu.
- Yeni rapor canlı `public.reports` tablosuna yazıldı:
  - Report id: `6440bdc4-bcd6-476d-8dfc-3af616731846`
  - Kind/format: `standard/pdf`
  - File size: `862013`
  - Created at: `2026-05-29T23:21:05.783558Z`
- `report_ready` notification event oluştu; payload `destination=reports` ve yeni `report_id` içeriyor.
- Push teslimi bu hesapta gerçekleşmedi; event `skipped`, `last_error=no_active_device_tokens`. Plus demo kullanıcısında sandbox token var, remote sender kendi APNs environment'ına göre aktif token bulamadı. TestFlight/production token veya kontrollü sandbox APNs ortamıyla tekrar delivery testi gerekir.
- Rapor: `QA/Plus_Device_Report_Live_QA_2026-05-30.md`

### Push sandbox/production token ayrımı — ✅ KALICI DÜZELTME DEPLOY EDİLDİ
- `send-push-notification` artık tek global `APNS_ENV` filtresine göre token elemez.
- Kullanıcının tüm aktif tokenları çekiliyor; `sandbox` tokenlar `api.sandbox.push.apple.com`, `production` tokenlar `api.push.apple.com` host'una gönderiliyor.
- Response artık `environments`, `sent_environments` ve `failed_environments` alanlarını döndürüyor.
- `send-report-ready-notification`, `generate-excel-report` ve `analyze` artık sadece push sender `status=sent` döndürürse ilgili `*_push_sent_at` alanını set ediyor. `skipped` veya `failed` durumları artık yanlışlıkla "gönderildi" olarak işaretlenmeyecek.
- Deploy edildi:
  - `send-push-notification --no-verify-jwt`
  - `send-report-ready-notification`
  - `generate-excel-report`
  - `analyze --no-verify-jwt`
- Doğrulama: dört function için `deno check` geçti.
- Canlı smoke tamamlandı: Plus demo hesabıyla yeni standart PDF raporu oluşturuldu ve sandbox APNs delivery `sent` oldu.
- Teslim edilen rapor:
  - Report id: `e32ac161-378c-49c8-a978-d1a3f44a21ea`
  - `kind=standard`, `format=pdf`, `file_size=852956`
  - `report_ready_push_sent_at=2026-05-29T23:30:38.586Z`
- Teslim edilen event:
  - Event id: `a9a9df68-0459-4c37-bb01-cc096c2116d2`
  - `status=sent`, `sent_count=1`, `failure_count=0`, `last_error=null`
  - Token environment: `sandbox`
  - Token `last_success_at=2026-05-29T23:30:37.66Z`

### Push / APNs — ✅ SANDBOX DELIVERY DOĞRULANDI
- `send-push-notification` ACTIVE ve `deno check` geçti.
- APNs secrets remote'da mevcut: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, `APNS_ENV`.
- `push_device_tokens` içinde aktif iOS tokenlar mevcut: sandbox 3, production 3.
- Plus demo kullanıcıyla rapor hazır push trigger'ı önce `no_active_device_tokens` ile skipped olmuştu; bunun kök nedeni tek global APNs environment filtresiydi.
- Kalıcı düzeltmeden sonra aynı gerçek cihaz/sandbox token ile yeni rapor push'u `sent` oldu.
- Doğrudan APNs gönderimi yapılamadı; function service-role Authorization header değerini istiyor ve Supabase CLI/Dashboard secret değerini güvenli olarak göstermiyor.

### TestFlight production push smoke — ✅ BACKEND SENT, ✅ FOREGROUND UI VERIFIED
- Yeni production kullanıcı `kayalar.kerem@gmail.com` ile giriş yapıldı.
- Kullanıcı yıllık Plus satın aldı.
- Kullanıcı analiz yaptı; önce risk analizi PDF, sonra aynı analizden standart PDF oluşturdu.
- Risk analizi PDF oluşturulurken bildirim izni/token yoktu; ilgili `report_ready` event `no_active_device_tokens` ile skipped oldu.
- Standart PDF öncesinde bildirim izni verildi ve production token kaydoldu.
- Standart PDF için backend/APNs sonucu başarılı:
  - Report id: `3410c5c2-dc1a-44e7-93fa-6acd6b8859a6`
  - Event id: `e4e526de-b350-4e1d-a267-258bdb377439`
  - Token id: `8592a94e-6360-4659-b90a-6005aa79fd83`
  - Token environment: `production`
  - Event `status=sent`, `sent_count=1`, `failure_count=0`, `last_error=null`
  - Token `last_success_at=2026-05-29T23:43:54.393Z`
- İlk TestFlight smoke'ta kullanıcı telefonda görünür bildirim görmedi. Kök neden app foreground davranışıydı: `NotificationService.userNotificationCenter(_:willPresent:)` `analysis_complete` ve `report_ready` için `[]` döndürüp banner/sound göstermiyordu.
- Fix: foreground notification presentation artık tüm bildirimler için `[.banner, .sound, .badge]` döndürüyor.
- Doğrulama: gerçek cihaz Debug build fix sonrası **BUILD SUCCEEDED**.
- TestFlight görsel smoke: foreground fix'i içeren yeni TestFlight build'de aynı kullanıcı/aynı analizden standart rapor oluşturuldu; `Rapor Hazır` banner'ı cihazda göründü ve titreşim verdi.

### Analiz / rapor UX son smoke — ✅ DÜZELTİLDİ
- Risk analizi raporunda firma seçim ekranı load error aldığında kullanıcı firma eklemeye zorlanıyordu.
- Fix: firma yükleme hatası blocking alert yerine inline kart olarak gösteriliyor; `allowNoCompany` açıkken "Firma olmadan devam et" yolu her zaman erişilebilir.
- Analiz bekleme ekranında `Analiz hazırlanıyor` kartı gereksizdi ve fotoğraf üstü tarama animasyonu uzun analizlerde durunca ekran donmuş hissi veriyordu.
- Fix: queued progress kartı gizlendi; fotoğraf üstü tarama animasyonu işlem bitene kadar time-driven sürekli akıyor; adım listesi son adımda takılı kalmak yerine canlı döngüde kalıyor.
- Doğrulama: gerçek cihaz Debug build sonrası **BUILD SUCCEEDED**.

### RevenueCat / satın alma — ⚠️ TESTFLIGHT GEREKİR
- Gerçek cihazda paywall görsel UI smoke geçti.
- Xcode-installed build'de package-ready durumunu satın alma sheet'ine kadar otomatik doğrulama güvenilir değil; App Store/TestFlight sandbox purchase/restore hâlâ TestFlight build + sandbox Apple ID ile manuel onay gerektirir.

### iPad kapsamı — ✅ İLK SÜRÜM İÇİN KAPSAM DIŞI
- Xcode target `TARGETED_DEVICE_FAMILY = 1`; ilk sürüm iPhone-only.
- Bu nedenle App Store submission için iPad screenshot/layout zorunluluğu yok. iPad desteği açılırsa ayrı layout/screenshot QA gerekir.

### Build / Store tarafı doğrulamaları (kodla teyit edilemez — sende)
1. **App Review demo hesabı** + Review notu (login arkası içerik).
2. **App Privacy "nutrition label"** App Store Connect'te toplanan PII ile tutarlı doldurulmalı.
3. **Localization tamlığı:** App Store metadata İngilizce iddia etmeyecekse mevcut Türkçe hardcoded stringler kabul edilebilir; İngilizce lokalizasyon açılırsa ayrı string audit gerekir.
4. **TestFlight sandbox purchase/restore:** gerçek satın alma sheet'i ve Apple sandbox onayı TestFlight build ile manuel doğrulanmalı.
5. **APNs gerçek teslimat:** sandbox ve production token için backend/APNs `sent` doğrulandı. Foreground banner fix'i yeni TestFlight build'de görsel olarak doğrulandı.
6. Üçüncü-parti SDK Privacy Manifest'lerinin Xcode Organizer archive privacy report içinde görünmesi. Release app bundle içinde manifestler doğrulandı; Organizer raporu yine submission öncesi görsel kontrol edilmeli.

### Çalıştırılan doğrulamalar
- `xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -destination 'platform=iOS Simulator,id=4A71277B-053D-49CF-8414-57840D9B010A' build CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**
- `xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' build` → **BUILD SUCCEEDED**
- `xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -configuration Release -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' build` → **BUILD SUCCEEDED**
- `xcrun devicectl device install app --device 36B37C26-C0CB-556F-8A6C-3A07FD290F11 .../RiskDetected.app` → **installed**
- `xcrun devicectl device process launch --device 36B37C26-C0CB-556F-8A6C-3A07FD290F11 --terminate-existing com.riskdetected.app` → **launched**
- `xcodebuild ... -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' -only-testing:RiskDetectedUITests/RiskDetectedUITests/testProfileShowsDeviceIntegrityWarningWhenFlagged test` → **passed**
- `xcodebuild ... -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' -only-testing:RiskDetectedUITests/RiskDetectedUITests/testRealDeviceSupabasePinnedConnection test` → **passed**
- `xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' test` → **10 tests, 0 failure**
- Gerçek cihaz seçili App Review smoke paketi:
  `testMainTabsProfileAndDarkModeRenderWithBypass`,
  `testProfileDataControlsAccountDeletionCopyWithBypass`,
  `testProfileShowsDeviceIntegrityWarningWhenFlagged`,
  `testRealDeviceSupabasePinnedConnection`,
  `testTrialInviteAndTimelinePaywallRenderWithAuthBypass` → **5 test, 0 failure**
- `xcrun devicectl device process sendMemoryWarning --pid <RiskDetected PID>` → **blocked by CoreDevice: NSPOSIXErrorDomain 2**, app re-launch başarılı.
- `find .../Release-iphoneos/RiskDetected.app -name PrivacyInfo.xcprivacy` → ana app + üçüncü taraf manifestleri bulundu.
- `node scripts/qa_live_rls_isolation.mjs` → **12 PASS, 0 FAIL**
- `node scripts/qa_free_paid_ai_routing.mjs --live-e2e` → **40 PASS, 1 WARN, 0 FAIL**
- Plus demo gerçek cihaz rapor oluşturma → `reports.id=6440bdc4-bcd6-476d-8dfc-3af616731846`, `kind=standard`, `format=pdf`, subscription `tier=plus/status=active`
- Plus demo report_ready event → `status=skipped`, `last_error=no_active_device_tokens`
- `deno check supabase/functions/send-push-notification/index.ts` → **passed**
- `deno check supabase/functions/send-report-ready-notification/index.ts` → **passed**
- `deno check supabase/functions/generate-excel-report/index.ts` → **passed**
- `deno check supabase/functions/analyze/index.ts` → **passed**
- Push environment-aware deploy:
  `send-push-notification`, `send-report-ready-notification`, `generate-excel-report`, `analyze` → **deployed**
- Plus demo environment-aware APNs smoke → `notification_events.id=a9a9df68-0459-4c37-bb01-cc096c2116d2`, `status=sent`, `sent_count=1`, sandbox token `last_success_at=2026-05-29T23:30:37.66Z`
- TestFlight production APNs smoke → `notification_events.id=e4e526de-b350-4e1d-a267-258bdb377439`, `status=sent`, `sent_count=1`, production token `last_success_at=2026-05-29T23:43:54.393Z`
- TestFlight foreground push visual smoke → `Rapor Hazır` banner appeared on device; vibration observed.
- `xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -destination 'platform=iOS,id=36B37C26-C0CB-556F-8A6C-3A07FD290F11' build` after foreground notification fix → **BUILD SUCCEEDED**
- `supabase functions deploy request-account-deletion --project-ref ppcrzemgiztzcgddbins` → **deployed**
- `supabase functions deploy account-deletion-complete --project-ref ppcrzemgiztzcgddbins --no-verify-jwt` → **deployed**
- Temp user `request-account-deletion` live QA → **completed=true, auth_user_deleted=true**
- Tokensiz `request-account-deletion` → **401**
- `deno check supabase/functions/send-push-notification/index.ts` → **passed**
- Push token inventory → sandbox 3, production 3 active iOS tokens
- `scripts/verify_supabase_pins.sh` → **Pin match**
- `xcrun devicectl list devices` → iPhone 14 Pro Max **available (paired)**.

---

## 4. Sonuç
Kod tabanındaki submit-engelleyici güvenlik, uyum ve fonksiyonel bulgular kapatıldı. Canlı RLS, canlı analiz E2E, canlı hesap silme, sandbox APNs, production APNs backend teslimi ve TestFlight foreground bildirim banner'ı görsel smoke'u doğrulandı. Son UX bulguları olan firmasız rapor devam yolu ve analiz bekleme ekranı canlılık hissi de kodda düzeltildi ve gerçek cihaz build'i geçti.
