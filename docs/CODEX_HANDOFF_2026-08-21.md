# Codex Handoff — RiskDetected, 2026-08-21

Bu dosya, Codex'in projeye genel olarak hakim olduğu varsayımıyla yazıldı. Projeyi baştan anlatmıyor — **13-21 Ağustos 2026 arasında Claude ile yapılan işleri**, gerekçeleriyle birlikte detaylandırıyor. Amaç: Codex bu değişikliklerin *neden* yapıldığını, hangi kararların bilinçli olduğunu ve hangi işlerin hâlâ açık olduğunu bilsin.

**Çalışma dalı:** `feat/claude-design-paywall` (main'e henüz merge edilmedi, PR [#4](https://github.com/KeremDev/RiskDetected/pull/4) açık, base `codex/android-release-readiness`). Bu dalda 236+ commit var — bu dal fiilen trunk gibi kullanılıyor, tüm release işlemleri buradan yapıldı.

**Şu anki sürüm durumu:**
- iOS: `MARKETING_VERSION 1.3.4`, `CURRENT_PROJECT_VERSION 86` — App Review'da (build 85 ve 86 art arda gönderildi, 86 incelemede)
- Android: `versionCode 6`, `versionName 1.6.0` — Play Console kapalı test kanalında yayında, 14 günlük yeni-hesap test döngüsünün 5. gününde build değişti

---

## 1. Paywall yeniden tasarımı (iOS + Android, 1:1 port)

En büyük iş bloğu buydu. Kaynak: `App/Views/Paywall/Design/PaywallDesignKit.swift` (iOS), mirror: `android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/RdPaywallDesignKit.kt` (Android Compose). Akış dosyası: `App/Views/Paywall/Design/PaywallDesignFlowView.swift`.

### Yapılan değişiklikler (kronolojik, en önemliler)

1. **Kayan özellik şeridi (marquee) eklendi.** 7 yeni etiket: Fine-Kinney, 5x5 Matris, Derin Araştırma, Rapor Özelleştirme, Arşiv Yönetimi, Sorumlu Atama, Odaklı Analiz. Her biri için özel outline ikon çizildi (`PaywallDesignFeatureGlyph` enum: shield, chart, photos, building, gauge, grid, magnifier, sliders, archive, assignee, target — 20×20 viewBox, 1.5pt/dp stroke, dolu değil çizgi ikon).
   - **Şerit paket duyarlı hale getirildi:** PLUS ekranında Magnifier ve Target (PRO'ya özel özellikler) şeritte görünmüyor — `timelineFeatures(for tier:)` filtreliyor (`App/Views/Paywall/Design/PaywallDesignFlowView.swift`). Bu bir uyum düzeltmesiydi: ilk halde PLUS ekranı PRO'ya özel özellikleri reklam ediyordu, kullanıcı fark edip düzelttirdi.
   - PRO ekranında şerit ikonları yeşil, diğerlerinde gri/turuncu.
   - Şerit fontu küçültüldü, bold kaldırıldı (etiket yüksekliğini azaltmak için).

2. **Fiyatlandırma RevenueCat'ten canlı çekiliyor, hardcode yok.**
   - CTA altındaki "Otomatik yenilenir" cümlesine seçili paketin fiyatı ekleniyor (aylık → "249,99 TL/ay", yıllık → "1999.99 TL/yıl").
   - Yıllık kartta aylık eşdeğer fiyat kalın/büyük üstte, yıllık toplam küçük/normal altta gösteriliyor.
   - **Önemli fallback:** `StoreProduct.localizedPricePerMonth` bazı ürünlerde nil dönüyor (subscription period çözülemediğinde). Bu durumda `App/Services/SubscriptionManager.swift` içinde `monthlyEquivalentPrice(for:)` yıllık fiyatı 12'ye bölüp ürünün gerçek `currencyCode`'uyla formatlıyor — kullanıcı isteğiyle eklendi, board üzerinde hardcoded bir sayı yok.
   - Plan kartı fiyat fontu iki kez küçültüldü/inceltildi (kullanıcı "çok dikkat çekici" dedi).

3. **Karşılaştırma tablosu (Plus/Pro vs Free) düzeltmeleri:**
   - Derin Araştırma: PLUS satırında artık **çarpı** (Free'deki gibi) — PLUS aboneliğinde bu özellik yok, önceden yanlışlıkla tik gösteriliyordu.
   - "Öncelikli destek" satırı kaldırıldı, yerine **"Odaklı Analiz"** geldi (PLUS: çarpı, PRO: tik).
   - Tablo başlıklarında PLUS'ın hemen solunda turuncu taç ikonu, PRO'nun yanında yeşil yıldız ikonu (`PaywallDesignComparisonTable.Emblem { none, crown, star }`).
   - Satır yükseklikleri ve fontlar sıkıştırıldı (kullanıcı dikey alan kazanmak istedi): satır `padding(.vertical, 4)`, başlık 12.5, tik/çarpı ikonları küçültüldü.

4. **Timeline (Bugün / 5. Gün / 7. Gün):**
   - Başlık fontları küçültüldü, satır aralıkları sıkıştırıldı.
   - "Bugün" satırının alt metninde PLUS/PRO kelimesinin **hemen solunda** taç ikonu var (ilk denemede taç başlığın altına konmuştu, kullanıcı "PLUS yazısının hemen sol yanına istiyorum" diye düzeltti). iOS'ta `Text` sadece `Image` kabul ettiği için SF Symbol `crown.fill` kullanıldı; Android'de gerçek vektör ikon `InlineTextContent` ile satır içine gömüldü (`appendInlineContent` — boş string `alternateText` crash veriyor, en az bir boşluk gerekiyor, bu bir gotcha).
   - 7. gün başlığı altındaki metin değiştirildi: "Aboneliğiniz başlar. İstediğiniz zaman iptal edebilirsiniz."

5. **Görsel ince ayarlar:** şerit chip arka planı turuncudan açık griye (`chipBg #F4F5F7`, `chipBorder #E3E6EB`) — kullanıcı "turuncu göz yoruyor" dedi. Tik ikonları artık tek tip değil, her etikete özel outline ikon.

6. **Footer linkleri doğrulandı:** Geri Yükle / Koşullar / Gizlilik / İptal Hakkı. Koşullar ve Gizlilik uygulama içi bottom sheet'te açılıyor (harici tarayıcıya çıkmıyor) — test eklendi: `testPaywallFooterLinksOpenInAppLegalSheets`.

### Test/golden durumu
- iOS: `testFeatureMarqueeAppearsOnEveryPaywallVariant`, `testPaywallFooterLinksOpenInAppLegalSheets` eklendi.
- Android: `paywall_feature_marquee_icons_light` golden'ı (Roborazzi) tüm 11 ikonu, turuncu 15dp + yeşil 30dp varyantlarıyla kapsıyor.
- **Bilinen gürültü kaynağı:** `report_source_sheet_plus_risk_settings_light.png` goldeni her kayıtta byte-seviyesinde değişiyor (PNG encoder gürültüsü, gerçek fark yok) — bu golden'a her rastladığında revert edip orijinalin geçtiğini doğrula, gerçek bir regresyon değil.

---

## 2. Onboarding düzeltmeleri

`App/Views/Onboarding/V2/Screens/OBLoadingView.swift`:
- "47 döküman oluşturuldu" → **896** (yanlış sayıydı, düzeltildi — hem "hazırlanıyor" hem "hazırlandı" ekranlarında).
- Yükleme ekranındaki cümleler bitişik yazıyordu ("A Sınıfı Uzmandokumanları oluşturuluyor" gibi). Kök sebep: string concatenation. Çözüm: yer tutucu formatlı string'e geçildi (`RDLocalization.format(..., arguments: [label])`), kelime sırası ve boşluk artık çeviriye ait; vurgulanan kelime `AttributedString.range(of:)` ile runtime'da stilize ediliyor (`highlighting(_:in:)` fonksiyonu). Bu desen projede tekrar eden bir kalıp — literal string concatenation yerine placeholder-format + runtime range styling kullanılıyor, aynı yaklaşımı başka yerlerde de bekle.

---

## 3. iOS release: build 85 → 86 → App Review

- Build 85 ve 86 TestFlight'a yüklendi (`chore(release): record 1.3.4 (85/86) uploaded to TestFlight` commit'leri kanıt).
- 86 App Review'a gönderildi (`chore(release): record 1.3.4 (86) submitted for App Review`).
- App Review Notes ve EN "What's New" metni hazırlandı; **attribution/kaynak belirtmeden** yazıldı (kullanıcının standing kuralı: "app review notlarında ve whatsnew kısmında attribution ile birşey yazmayacağız").
- **⚠️ Açık nokta:** App Store Connect'te İngilizce subscription group + 4 ürün lokalizasyonu hâlâ `PREPARE_FOR_SUBMISSION` durumunda ve **1.3.4'ün review submission'ına dahil edilmedi**. Bu, App Review submission'ının sadece app-version item'ı içermesinden kaynaklanıyor — subscription lokalizasyonları ayrı bir submission gerektiriyor. Yani 1.3.4 onaylanıp yayına girse bile İngilizce abonelik metinleri canlıya çıkmayacak; **ayrı bir subscription submission gerekiyor, henüz yapılmadı.**

---

## 4. Android: min_version geçişi ve versionCode 6 (1.6.0)

### 4a. Kritik bir release-blocker bulundu ve düzeltildi

Altı Android runtime kapısı (`android_client_enabled`, `android_auth_enabled`, `android_analysis_submit_enabled`, `android_payments_enabled`, `android_notifications_enabled`, `android_pdf_reports_enabled`) `version_allowlist` modundaydı, liste `[2,3,4,5]`. versionCode 6 yüklendiği an ana anahtar `android_client_enabled` "version_not_allowed" dönüp **tüm uygulamayı** (auth, analiz gönderimi, ödemeler, bildirimler, PDF) kilitleyecekti — çünkü liste elle genişletilmemişti.

Bu, iOS'ta build 81'de yaşanan aynı tuzağın (allowlist listesi güncellenmeden canlıya çıkma, bulgu düzenleme/silme 423 ile reddedilmesi) Android'deki birebir analoğu. Çözüm iOS'takiyle aynı desen: `min_version`'a geçiş.

- **Migration:** `supabase/migrations/20260820090000_android_runtime_gates_min_version_rollout.sql` — altı kapıyı `rollout_mode: min_version`, `min_android_version_code: 2`'ye çeviriyor. Eşik 2 seçildi çünkü versionCode 1 sadece Play App Signing'i etkinleştirmek için kullanılan tek seferlik yüklemeydi, bugünkü davranışı bozmuyor.
- `enabled_android_version_codes` alanı **silinmedi** — min_version modunda okunmuyor ama geri dönüş gerekirse yerinde duruyor.
- Fail-closed doğrulama: migration, her kapının mevcut modu beklenmedikse veya kill_switch açıksa exception fırlatıp hiçbir şeye dokunmuyor.

### 4b. Versiyon kesimi

`android/app/build.gradle.kts`: `versionCode = 6`, `versionName = "1.6.0"`. `.github/workflows/android-release-candidate.yml` içindeki dört pinned koordinat (versionCode, versionName, iOS MARKETING_VERSION, iOS CURRENT_PROJECT_VERSION) güncellendi — bu workflow, `backend-contracts` job'ında bu dört değeri repo dosyalarıyla `grep -q` ile karşılaştırıp release'in doğru sürümden çıktığını doğruluyor.

### 4c. CI'da bulunan ve düzeltilen üç ayrı hata (Android release pipeline'ı çalıştırırken ortaya çıktı)

`android-release-candidate.yml` workflow'unu `expected_version_code=6` ile tetikleyip signed AAB üretmeye çalışırken art arda üç bağımsız hata çıktı, hepsi düzeltildi:

1. **`deno fmt --check` fail** — `supabase/functions/analyze/localization_phase6_static_test.ts` içinde eski bir format bozukluğu (Android işiyle ilgisi yok, önceki bir commit'ten kalma borç). Fix: `deno fmt` ile düzeltildi, mantık değişmedi. Commit `3e92820c`.

2. **`supabase db start` fail (migration replay edilemiyor)** — `20260819170000_localization_flags_min_build_80_public_rollout.sql` migration'ı prod'da zaten uygulanmıştı (13 lokalizasyon bayrağını `allowlist`'ten `min_build`'e taşıyor), ama migration'ın kendisi taze bir ortamda (`off` durumunda başlayan) flag'leri "beklenmedik rollout mode" diye reddediyordu. Prod'da manuel olarak `allowlist`'e çekilmiş bir gözden geçirme kohortu vardı, migration zincirinde değil — bu yüzden CI'ın `supabase db start` fresh replay'i hiç geçmiyordu, önceden kimse bunu uçtan uca test etmemişti. **Fix:** migration'ın kendi emsalini izleyerek (`20260802214159_allow_build_81_release_features.sql`'deki aynı desen) `off` durumunu meşru bir taze-ortam durumu sayıp dokunmadan geçecek şekilde güncellendi. Commit `df320c1a`.

3. **pgTAP test fail** — yukarıdaki migration'ı düzeltip fresh replay yapınca ortaya çıktı: `supabase/tests/android_feature_flag_kill_switches_test.sql` hâlâ eski `version_allowlist [2,3,4,5]` şeklini bekliyordu, min_version geçişiyle güncellenmemişti. Assertion `min_version` / floor 2'ye güncellendi. Aynı commit `df320c1a`. **575/575 pgTAP testi lokal fresh replay ile doğrulandı, sonra CI'da tekrar doğrulandı.**

Bu üçü de Android sürümüyle doğrudan ilgili değildi — release pipeline'ını ilk kez uçtan uca çalıştırınca ortaya çıkan, önceden CI'da hiç test edilmemiş borçlardı. **Codex için not:** `android-release-candidate.yml` workflow'u artık üç job'da da (backend-contracts, android-quality, signed-aab) yeşil, ama bu iş akışının kendisi yeni test edildiği için başka gizli kırıklar çıkabilir.

### 4d. Build ve yayın

- Workflow `expected_version_code=6` ile tetiklendi, signed AAB üretildi (bundletool validate, JAR imza, 16KB/ELF, secret/PII taramaları geçti).
- AAB indirilip kullanıcıya teslim edildi; **Play Console'a manuel olarak kullanıcı tarafından yüklendi** (repoda Play Developer API/fastlane entegrasyonu yok — bu adım hâlâ tamamen manuel, otomatikleştirilmedi).
- Release notes format sorunu çözüldü: Play Console'un çoklu-dil kutusu `<dil-kodu>...</dil-kodu>` (açı ayraç) formatı bekliyor ama bu uygulamanın Play Store kaydında **tr-TR bir mağaza dili olarak tanımlı değil** — sadece `en-us` kabul edildi. **Açık nokta:** Türkçe mağaza dili Android'e hiç eklenmemiş, iOS'ta var. İstenirse ayrı bir Play Console adımı.
- `android_release_policy` feature flag'i güncellendi: `latest_build 5→6`, `policy_version "closed-test-1.5.3-vc5"→"closed-test-1.6.0-vc6"`. Migration: `supabase/migrations/20260820101141_publish_android_build_6_release_policy.sql`, iOS'taki `publish_ios_build_81_release_policy.sql` deseniyle aynı (fail-closed rollback guard var). Commit `d4ba6d79`.

### 4e. Açık/manuel doğrulama backlog'u

`docs/android/ANDROID_RELEASE_KALAN_ISLER_2026-08-10.md` — **11 Ağustos tarihli, hedef sürümü hâlâ 1.5.0 yazıyor** (şu an 1.6.0'dayız), yani bu dosya güncelliğini yitirmiş durumda, gözden geçirilmeli. İçinde gerçek satın alma testleri, fiziksel cihazda Google Credential Manager girişi, fiziksel Pixel/Samsung testleri, ISG uzmanı kalite onayı gibi kalemler hâlâ açık gözüküyor.

---

## 5. Veri temizliği (prod DB + Storage + RevenueCat)

Kullanıcı isteğiyle yapıldı, DB/kod tarafında iz bırakmıyor ama kaydı burada dursun:

- **8 test hesabı** silindi (DB cascade + Storage objeleri + RevenueCat subscriber kayıtları). Not: RevenueCat `GET /v1/subscribers/{id}` **yoksa oluşturuyor** (201 döndü 5/8'inde) — okuma sırasında yanlışlıkla kayıt oluşturulmuş oldu, hepsi zaten silindiği için net etki sıfır oldu ama gelecekte v2 read-only endpoint kullanılmalı.
- **1 bekleyen (pending) analiz** silindi — gerçek bir kullanıcıya aitti, kullanıcı onayıyla satır tamamen silindi.
- **7 başarısız (failed) analiz** silindi. Silmeden önce yakalanan teşhisler: 3 tanesi `SAFETY_PROFILE_NOT_APPROVED` (8 Ağustos, aynı kullanıcı, 70 saniye içinde) — güvenlik profili sağlama (SHA) tutarsızlığından kaynaklanıyordu, **9 Ağustos'tan beri düzelmiş durumda** (`supabase/functions/_shared/safety-profile-approval.ts` içindeki onaylı SHA snapshot'larla eşleşiyor, o tarihten sonraki her analiz tamamlanmış). 2 tanesi `SAFETY_PROFILE_NOT_ENABLED` — burada bir kopya metin bugı fark edildi ("Support code:" iki kere yazılıyor), düzeltilmedi, sadece not edildi. 1 tanesi kota doluluğu (doğru davranış, bug değil).
- `ensure_analysis_usage_event_on_delete` trigger'ı sadece `completed` analizlerde tetikleniyor, `failed`'da tetiklenmiyor — silme işlemi hiçbir kotayı yanlış etkilemedi, doğrulandı.
- **⚠️ Açık nokta — henüz temizlenmedi:** `photos` storage bucket'ında **6 sahipsiz obje** bulundu (~2 MB): 1 tanesi zaten silinmiş bir kullanıcıya ait, 5 tanesi mevcut bir kullanıcıya ait ama karşılık gelen analiz satırı yok (muhtemelen eski, DB-cascade'in kapsamadığı bir uygulama-içi silme akışından kalma). Kimse erişemiyor ama duruyorlar. Kullanıcıya bildirildi, henüz "temizle" onayı gelmedi.

---

## 6. Sabit kısıtlar (Codex'in de bilmesi gereken standing kurallar)

Kullanıcı bu oturumda birkaç kez açıkça belirtti, her ikisi de hâlâ geçerli:

1. **"App privacy beyanına dokunmayacağız."** — App Store Connect'teki App Privacy formu değiştirilmeyecek.
2. **"App review notlarında ve Whatsnew kısmında attribution ile birşey yazmayacağız."** — Apple'a giden hiçbir metinde AI/Claude/asistan referansı olmayacak.
3. **"Gerçek kullanıcı ile giriş yapmayacağım, o sadece TestFlight aşamasında olacak."** — Prod ortamda gerçek kullanıcı hesabıyla manuel test yapılmıyor, sadece TestFlight build'lerinde.

---

## 7. Değişen/eklenen dosyaların hızlı referansı

| Dosya | Ne değişti |
|---|---|
| `App/Views/Paywall/Design/PaywallDesignKit.swift` | Paywall tasarım kitinin neredeyse tamamı — palet, ikonlar, timeline, karşılaştırma tablosu, footer |
| `android/core/designsystem/.../RdPaywallDesignKit.kt` | iOS design kit'in Compose mirror'ı |
| `App/Views/Paywall/Design/PaywallDesignFlowView.swift` | Paket bazlı şerit filtreleme, fiyat metni, comparison emblem'leri |
| `App/Services/SubscriptionManager.swift` | `monthlyEquivalentPrice` fallback (yıllık/12) |
| `App/Views/Onboarding/V2/Screens/OBLoadingView.swift` | 896 döküman sayısı, placeholder-format + runtime highlighting |
| `supabase/migrations/20260819170000_...` | Localization min_build migration'ı replay-safe hale getirildi |
| `supabase/migrations/20260820090000_...` | Android 6 kapı: version_allowlist → min_version |
| `supabase/migrations/20260820101141_...` | android_release_policy → build 6 |
| `.github/workflows/android-release-candidate.yml` | Pinned versiyon koordinatları güncellendi; ilk kez uçtan uca çalıştırıldı, 3 ayrı borç bulundu/düzeltildi |
| `android/app/build.gradle.kts` | versionCode 6, versionName 1.6.0 |
| `supabase/tests/android_feature_flag_kill_switches_test.sql` | min_version'a göre güncellendi |
| `docs/android/ANDROID_RELEASE_KALAN_ISLER_2026-08-10.md` | **Güncel değil** — hedef sürüm hâlâ 1.5.0 yazıyor, gözden geçirilmeli |

---

## 8. Ek: 20-21 Ağustos — Android 1.6.0 yayını ve analiz doğrulayıcı düzeltmesi

### 8a. versionCode 6 Play'e çıktı

`android-release-candidate` workflow'u `expected_version_code=6` ile çalıştırıldı. **İlk kez uçtan uca çalıştırıldığı için üç ayrı gizli borç ortaya çıktı**, üçü de Android sürümüyle ilgisizdi:

1. `deno fmt --check` — `localization_phase6_static_test.ts` biçim bozukluğu. Commit `3e92820c`.
2. `supabase db start` — `20260819170000` migration'ı prod'da uygulanmıştı ama **taze bir ortamda replay edilemiyordu**: prod'da flag'ler operasyonel olarak `allowlist`'e çekilmişti, migration zincirinde değil, dolayısıyla temiz replay `off` durumunu "beklenmedik rollout mode" diye reddediyordu. `20260802214159`'daki emsal izlenerek `off` meşru taze-ortam durumu sayıldı. Commit `df320c1a`.
3. Aynı replay pgTAP'te ikinci bir bayatlık gösterdi: kill-switch testi hâlâ `version_allowlist [2,3,4,5]` bekliyordu. Aynı commit.

**Codex için ders:** bu workflow yeni test edildiği için başka gizli kırıklar çıkabilir. Ayrıca prod'da elle yapılan flag değişiklikleri migration zincirini replay edilemez hale getiriyor — bu desen tekrar edebilir.

AAB üretildi, imza doğrulandı, **Play Console'a elle yüklendi ve yayınlandı** (repoda Play publish otomasyonu yok). `android_release_policy` güncellendi: `latest_build 5→6`, `policy_version closed-test-1.6.0-vc6`. Migration `20260820101141`, commit `d4ba6d79`.

Release notes formatı: Play Console çoklu-dil kutusu `<dil-kodu>…</dil-kodu>` bekliyor; **tr-TR bu uygulamanın Play mağaza kaydında tanımlı değil**, sadece `en-us` kabul edildi.

### 8b. OUTPUT_LANGUAGE_CONTRACT_FAILED düzeltmesi (commit `9594db7f`, analyze v163)

Bir kullanıcı analizi (`c42b5bc5`, 21 Ağustos) iki denemede de düştü. Üst kod `OUTPUT_LANGUAGE_CONTRACT_FAILED` bir **sarmalayıcı**; gerçek sebep `language_validation_code = PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY` idi. Üç ayrı kusur üst üste binmişti:

**1. Doğrulayıcı, prompt'un kendisiyle çelişiyordu.** Kesinlik deseni *tüm* kullanıcıya görünen alanları tarıyordu. `photoEvidenceContract` modele "belirsizliği `limitations` alanında belirt" diyor; bunun doğal Türkçesi "kesin olarak belirlenememiştir" — doğrulayıcı bu hedge'i kesinlik iddiası sanıyordu. Ayrıca `corrective_action`'daki emir kipi İSG metnini de ("baret kesinlikle kullanılmalıdır") yakalıyordu. Tarama artık yalnız sahne hakkında iddia taşıyan alanlarda: `observed_evidence`, `description`, `root_cause`, `visual_evidence`, `observation`.

**2. `şüphesiz` kuralı ters çalışıyordu.** `\b` `u` bayrağıyla bile ASCII tabanlı; non-ASCII harfle başlayan kelime boşluğa karşı sınır oluşturmuyor. Kural tek başına duran Türkçe kelimeyi hiç yakalamıyor, ASCII köke yapışığını yakalıyordu. Harf-olmayan lookaround'a çevrildi.

**3. Onarım komutu yanlış problemi çözüyordu.** `buildLanguageContractRepairInstruction` hangi katman düşerse düşsün "çıktıyı tamamen Türkçe ver" diyordu. Kanıt hatasında dil zaten doğru olduğu için model aynı cümleyi tekrar üretiyordu. **Üretimdeki her onarım denemesi bu yüzden başarısız oldu (1/1).** Artık validator *koduna* göre rehber üretiyor, suçlu alanı ve metni adıyla veriyor, tam yeniden çeviriyi yalnız dil katmanı düştüğünde istiyor. Metin `serializeUntrustedPromptValue`'dan geçiyor — model çıktısı repair katmanını kapatamaz, testi var.

**4. Teşhis tam da lazım olduğu yolda kayboluyordu.** Katman sonuçları yalnız başarı yolunda kaydediliyordu. Artık catch yolunda da yazılıyor; reddedilen çıktı `_rejected_output` altında saklanıyor — **bilinçli olarak top-level `hazards`/`photo_findings` değil**, ki başarısız satır coverage-repair okuyucusuna (`analyze/index.ts:7749`) kullanılabilir analiz gibi görünmesin.

**Dokunulmayan:** `photoEvidenceContract`'ın kendisi. Prompt'u hizalamak 6 güvenlik profilinin **reviewed golden snapshot'ını** (`fixtures/ai-localization-prompt-golden.json`) geçersiz kılıyor; doğrulayıcı kapsamını daraltmak çelişkiyi zaten çözdüğü için ertelendi.

**Yalnız Edge Function; SQL yok, istemci build'i gerekmez.** Build 83 dahil kurulu tüm uygulamalar faydalanıyor.

### 8c. Lokalizasyon kapıları hakkında Codex'in bilmesi gerekenler

Bu iş sırasında kapı mekanizması ayrıntılı olarak haritalandı:

| Dosya/durum | Kapı etkisi |
|---|---|
| `ai-localization-prompt.ts` | Envanter tarayıcısından **açıkça muaf** (`localization_inventory.mjs:582`) |
| `ai-localization-validation.ts` | Kilitli tabana 0 katkı — regex literal'i tırnaklı olmadığı için görünmez |
| `analyze/index.ts` | 248 backend literal'inin **158'ini** üretiyor — burada yeni metin L10N-005'i kırar |
| Güvenlik profili onay SHA'sı | Yalnız manifest+schema+glossary+profil JSON'ları üzerinden (`generate_localization_profiles.mjs:363`) — bu dosyalar girdi **değil** |

**Kritik kural:** `supabase/functions/` altında bir literal ancak **Türkçe diakritik taşıyorsa** sayılıyor (`localization_inventory.mjs:610`) — **yorumlar dahil**. Bu iş sırasında bir doc-comment'te backtick'le alıntılanan Türkçe kelime L10N-005'i 248→249 yaparak kırdı. Diakritiksiz yazmak veya tırnaksız bırakmak kaçış yolu.

`analyze/index.ts` içinde makineye giden Türkçe prompt metni için `// localization-inventory: machine-prompt-begin` / `-end` işaretçileri var. **Kullanıcıya görünen metin için kullanılmamalı** — o gerçekten yeni bir backend literal'idir ve tabanın yeniden onaylanmasını gerektirir.

---

## 9. Codex için açık iş listesi (öncelik sırasıyla değil)

1. iOS: İngilizce subscription group + 4 ürün lokalizasyonunu App Store Connect'te ayrı bir submission ile göndermek gerekiyor (1.3.4'ün review'ına dahil değildi).
2. `photos` bucket'ındaki 6 sahipsiz obje için temizlik kararı (kullanıcı onayı bekleniyor).
3. **Faz 3 — deterministik fallback.** Onarım da başarısız olursa analizi tamamen düşürmek yerine kod bazlı ayrıştırma: `json_schema` / `forbidden_claim` / `output_language` sert hata kalsın; `UNSUPPORTED_CERTAINTY` bulgudaysa `needs_field_verification=true` ile yumuşasın, özet/limitations'taysa geçsin; `MEASUREMENT_*` / `UNSEEN_FACT` o bulguyu çıkarsın. **Bilinçli olarak ertelendi** — 8b'deki yeni teşhis alanları gerçek vaka biriktirene kadar tasarım tahmin olur. Ayrıca bir İSG ürününde bulguyu sessizce silmek yerine yumuşatmak tercih edilmeli. Yeni kullanıcıya görünen Türkçe metin eklenmemeli (bkz. 8c).
4. Android Play Console mağaza kaydına Türkçe dil eklenmesi (isteğe bağlı, release'i bloklamıyor).
5. `docs/android/ANDROID_RELEASE_KALAN_ISLER_2026-08-10.md` dosyasının 1.6.0'a göre güncellenmesi.
6. Android Play Developer API entegrasyonu (fastlane veya gradle-play-publisher) — şu an AAB indirme + manuel yükleme akışı var, otomatikleştirilebilir.
7. `AnalysisService.swift:2076` — `OUTPUT_LANGUAGE_CONTRACT_FAILED` kullanıcıya "seçilen **çıktı diliyle** tamamlanamadı" diyor. Dil çoğu vakada sorun değil, metin yanıltıcı. İstemci sabiti olduğu için build gerektirir.
8. RevenueCat kopya metin bugı: "Support code:" iki kere yazılıyor (`SAFETY_PROFILE_NOT_ENABLED` hata ekranında) — düzeltilmedi.
9. Android manuel doğrulama backlog'u (`ANDROID_RELEASE_KALAN_ISLER` dosyasındaki açık kalemler): gerçek satın alma, fiziksel cihaz testleri, ISG uzman onayı.
