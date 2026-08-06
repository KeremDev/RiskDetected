# Faz 3 Tamamlama Denetimi — 2026-07-28

## Kapı sonucu

**Faz 3: TAMAMLANDI**

Bu karar execution planındaki “iOS localization altyapısı ve ülke güvenlik
deneyimi” fazının teknik kabulüdür. Faz 4 AI prompt/output localization işi bu
denetimden önce başlatılmadı.

Production migration uygulanmadı, Edge Function deploy edilmedi, feature flag
değiştirilmedi ve App Store Connect mutasyonu yapılmadı.

## String Catalog denetimi — PASS

Planın istediği tam 11 katalog `tr` source language ve `tr`/`en` parity ile
oluşturuldu:

| Katalog | Key |
| --- | ---: |
| `Analysis.xcstrings` | 555 |
| `Auth.xcstrings` | 96 |
| `InfoPlist.xcstrings` | 3 |
| `Legal.xcstrings` | 32 |
| `Localizable.xcstrings` | 676 |
| `Notifications.xcstrings` | 7 |
| `Onboarding.xcstrings` | 294 |
| `Paywall.xcstrings` | 101 |
| `ProfessionalProgress.xcstrings` | 115 |
| `Reports.xcstrings` | 174 |
| `SafetyTerminology.xcstrings` | 15 |
| **Toplam** | **2.068** |

Her shipping key:

- Türkçe ve İngilizce değer taşır;
- context comment ve placeholder metadata taşır;
- placeholder tip/sayı eşitliğini korur;
- plural gereken yerde native `one`/`other` variation kullanır;
- Swift fallback değeriyle Türkçe katalog değerini bire bir eşler.

`scripts/localization_catalog_tests.mjs` sonucu 16/16 PASS'tir.

## Native uygulama dili — PASS

- `Bundle.main.preferredLocalizations` tek UI dili otoritesidir.
- `tr` ve `en` bundle localization olarak tanımlıdır.
- `developmentRegion = tr` korunmuştur.
- `AppleLanguages` yazımı yoktur.
- Bundle swizzle veya locale override hack'i yoktur.
- Profildeki “Dil” yüzeyi `UIApplication.openSettingsURLString` ile native
  uygulama ayarına gider.
- UI dili ile safety/content profile ayrı domain alanlarıdır.
- Uygulama active olduğunda `refreshNativeLanguageContext()` çalışır ve native
  dil değişimini backend profile context'ine senkronize eder.

Cold-launch İngilizce UI testleri uygulamayı native language launch
argümanlarıyla sıfırdan başlatır. English onboarding ve English main akışları
bu şekilde doğrulandı.

## Eksik key Release blocker — PASS

Uygulama target'ına `Localization release gate` build phase'i eklendi.

- Debug build'de davranış değiştirmez.
- Release build'de 16 katalog/native/jurisdiction kapısını çalıştırır.
- Missing key, `tr`/`en` parity, placeholder, fallback, forbidden claim veya
  native architecture ihlali build'i non-zero exit ile durdurur.
- Xcode user-script sandbox açık bırakıldı.
- Okunan 209 kanıt dosyası
  `Config/LocalizationReleaseGateInputs.xcfilelist` ile açık input'tur.
- Dizinler ayrıca traversal input'u olarak tanımlıdır; liste dışı yeni bir
  kaynak sessizce atlanmak yerine sandbox hatasıyla Release build'i durdurur.

Final Release simulator build:

- warning: 0
- error: 0
- log:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-07-28T21-03-13-066Z_pid73592_6162b156.log`

Final Debug simulator build:

- warning: 0
- error: 0
- log:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-07-28T21-04-37-538Z_pid73592_6577a4d3.log`

## Onboarding ve profil — PASS

Türkçe akış:

- A/B/C İSG uzmanlığı korunur.
- Tehlike sınıfı korunur.
- Mevcut sektör/frekans/kişisel plan/auth akışı korunur.

İngilizce akış:

- A/B/C ve OSGB gösterilmez.
- Yerine professional role seçimi gelir.
- Şirket tehlike sınıfı gösterilmez.
- Safety terminology seçimi zorunludur.
- International, UK, US, AU ve CA açık kullanıcı seçimiyle sunulur.
- Ülke/profile storefront, locale veya cihazdan inferred edilmez.
- Açıklamalar compliance sertifikası iddiası taşımaz.

Profilde native uygulama dili ve safety profile ayrı kontrollerdir. Safety
profile değişimi yalnız yeni analiz request snapshot'ını etkiler; tarihsel
analizler yeniden yazılmaz.

## P0/P1 UI yüzeyleri — PASS

Root/update/error, auth/onboarding, home/photo, analysis, result/finding,
report/share, paywall/subscription, profile/company/preferences,
history/filter, legal/support/notifications yüzeyleri semantic catalog
key'lerine taşındı.

İçerik envanteri:

- toplam kalan içerik borcu: 1.583;
- iOS UI borcu: 0;
- sahipsiz P0/P1: 0;
- hard-coded guard baseline: 1.619;
- current: 1.583;
- yeni hard-coded aday: 0.

Kalan 1.583 kayıt Faz 4/5/7 kapsamında olan backend, legal, PDF, XLSX,
push/email ve ASC yüzeyleridir; Faz 3 iOS UI borcu değildir.

## Formatlama ve teknik kimlikler — PASS

- Date/number/percentage/currency/measurement gösterimleri locale-aware
  formatter kullanır.
- Paywall StoreKit/RevenueCat localized price string'ini aynen korur.
- Rapor dosya adları güvenli, deterministik ve locale-aware üretilir.
- `tr_TR` yalnız Türkiye'ye özgü iş sözleşmelerinde kalır.
- UI test ve accessibility identifier'ları çevrilebilir metin değildir;
  archive/filter/analysis kimlikleri dil bağımsız hale getirildi.

## Eski içerik — PASS

İngilizce UI'da tarihsel Türkçe analiz:

- `Original content: Turkish` badge'i gösterir;
- sistem ve kullanıcı alanlarını otomatik çevirmeye çalışmaz;
- edit ekranında non-blocking language mismatch uyarısı gösterir;
- İngilizce export seçeneği sunmaz.

Kullanıcının title ve notları özgün haliyle korunur.

## Human-review shipping kapıları — PASS

Bu faz hiçbir insan onayını uydurmadı:

- Professional Progress İngilizce shipping
  `RDProfessionalProgressLocalizationReview.englishShippingApproved = false`
  ile kapalıdır.
- 115 Professional Progress key'inin tamamı
  `shipping: native_language_and_safety_review_required` taşır.
- İngilizce legal belgeler Faz 5 legal/counsel onayı gelene kadar güvenli
  “unavailable” yüzeyi gösterir.
- Safety-sensitive English catalog değerleri machine draft durumundadır ve
  review submission kapısını geçmeden release edilemez.

## Dynamic Type, VoiceOver ve UI regresyonu — PASS

Hedefli Faz 3 UI kapıları:

- English onboarding explicit safety profile;
- English non-TR legislation gizleme;
- en büyük Dynamic Type;
- pseudolocalization;
- paywall localized price cümleleri;
- report archive stable identifier'ları;
- onboarding geçişi sırasında güvenli hittability bekleme.

Onboarding geçiş testi ile İngilizce role/safety testi üçer tekrar çalıştırıldı:
6/6 PASS.

Final tam UI sonucu:

- toplam: 43
- pass: 42
- planlı skip: 1
- failure: 0
- expected failure: 0
- süre: 464,105 saniye

Planlı skip:
`testE2ERealThreePhotoAnalysisCompletes()`; gerçek provider ve açık
`RD_E2E_REAL_3_PHOTO_ANALYSIS=1` dış test ortamı gerektirir.

Final `.xcresult`:
`/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-07-28T20-49-25-330Z_pid73592_71ac5bd6.xcresult`.

## Faz 3 çıkış kriteri

| Kriter | Sonuç |
| --- | --- |
| Türkçe ve İngilizce tüm P0/P1 UI yüzeyleri | PASS |
| English sistem metinlerinde Türkçe leak yok | PASS |
| Dynamic Type ana akışı | PASS |
| VoiceOver/stable accessibility ana akışı | PASS |
| Native per-app language cold launch context sync | PASS |

## Production ve faz sınırı

- `supabase db push` çalıştırılmadı.
- Production DDL/DML/backfill uygulanmadı.
- Edge Function deploy edilmedi.
- Production feature flag değeri değiştirilmedi.
- App Store Connect mutation yapılmadı.
- İnsan language/safety/legal/product approval durumu yükseltilmedi.
- Faz 4 AI prompt, validator, repair ve fallback uygulaması başlatılmadı.

## Bir sonraki izinli adım

Yalnız Faz 4 — AI prompt contract, output doğrulama ve repair açılabilir.
Faz 5, Faz 4'ün bütün iş listesi ve çıkış kriterleri ayrı bir tamamlama
denetiminde PASS olmadan başlatılamaz.

Ayrıntılı makine kanıtı:
`docs/localization/phase-3/PHASE_3_TEST_MANIFEST_2026-07-28.json`.

