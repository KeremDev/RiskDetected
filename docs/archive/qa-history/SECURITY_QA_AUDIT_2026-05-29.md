# RiskDetected — iOS Güvenlik & Yayın Denetimi
**Tarih:** 2026-05-29 · **Denetlenen:** `App/` (Swift, ~33.5k satır), `supabase/functions/*`, `Config/`, entitlements, PrivacyInfo
**Rol:** Kıdemli iOS güvenlik mühendisi / Swift reviewer / QA lead / App Store Review uzmanı
**Not:** Bulgular gerçek kod kanıtına dayanır. Doğrulayamadığım yerleri açıkça "DOĞRULANMASI GEREKİYOR" diye işaretledim. Bu denetim çalışan bir build, Instruments profili veya canlı RLS testi içermez — statik inceleme + backend kaynak okumasıdır.

---

## 1. Executive Summary

**Genel risk seviyesi: MEDIUM** (mimari sağlam, backend güvenliği iyi; ancak en az bir kesin App Store ret sebebi ve birkaç doğrulanması gereken nokta var.)

**Yayına hazır mı? HAYIR — P0'lar çözülmeden submit etme.** Backend auth/RLS tarafı olgun, sırlar sızmıyor, sign-in akışı doğru. Asıl risk client tarafındaki paywall uyumu ve hesap silme akışında.

**En kritik 5 problem:**

1. **Onboarding paywall'da Şartlar/Gizlilik linkleri ölü, "Geri Yükle" butonu satın alma tetikliyor** — kesin App Store 3.1.2 reddi + finansal hata. (`OnboardingViewV2.swift:149-164`)
2. **Hesap silme gerçek silme değil, "talep" kaydı** — Apple 5.1.1(v) uygulama içi gerçek hesap silme ister; asenkron admin kuyruğu ret sebebi olabilir. (`AnalysisService.requestAccountDeletion`)
3. **`supabase/config.toml` repo'da yok → Edge Function'ların `verify_jwt` ayarı garanti altında değil.** `analyze` kod içinde token doğruluyor ama deploy ayarı declarative değil; yanlış deploy'da bazı fonksiyonlar açık kalabilir. (DOĞRULANMASI GEREKİYOR)
4. **`backups/.../secrets-list.json` repo'ya commit edilmiş** — içerik plaintext değil (SHA-256 digest), ama sır envanteri/isimleri ve Firebase project hash'i versiyonlanmış halde durması gereksiz risk; `backups/` git'ten çıkarılmalı.
5. **Foto analizinde inline base64 + 5 dk polling** — büyük bellek tüketimi ve zayıf ağda kötü UX/kullanıcı kafa karışıklığı; ana thread'i kilitlemiyor ama edge-case crash/bellek baskısı riski var.

---

## 2. Critical Issues

### C-1 · Onboarding paywall: ölü yasal linkler + yanlış "Geri Yükle" davranışı  🔴 P0
- **Dosya/fonksiyon:** `App/Views/Onboarding/V2/OnboardingViewV2.swift:149-164` (canlı akış). Aynı hata `App/Views/Onboarding/V2/Screens/OnboardingPaywallV2View.swift:10-12` (legacy).
- **Problem:** `OBTimelinePaywallView` butonları görünür (`OBTimelinePaywallView.swift:104/114/124` → `onRestore/onTerms/onPrivacy`), ama onboarding'de:
  - `onTerms: {}` → Şartlar linki **hiçbir şey yapmıyor**
  - `onPrivacy: {}` → Gizlilik linki **hiçbir şey yapmıyor**
  - `onRestore: { onPurchase(state.selectedPlan) … }` → "Satın alımları geri yükle" butonu **restore değil yeni satın alma** başlatıyor.
- **Risk:** App Store Review Guideline 3.1.2 (auto-renewable subscriptions) — abonelik ekranında işlevsel Terms (EULA) + Privacy Policy linki ve gerçek "Restore Purchases" zorunlu. Üçü de ihlal. Ek olarak: zaten abone olan bir kullanıcı "geri yükle"ye basınca **ikinci kez ücretlendirilir** → iade talepleri, kötü yorumlar, olası 3.1.1 ihlali.
- **Nasıl üretir:** Yeni kullanıcı → onboarding paywall → "Geri yükle" → mevcut aboneliği çağrılmak yerine satın alma sheet'i açılır.
- **Çözüm:** Linkleri ve restore'u gerçek aksiyonlara bağla. `PaywallView`/`InAppPaywallView` zaten doğru yapıyor (restore + `RDConfig.Web.termsURL`/`privacyPolicyURL`), aynı pattern'i taşı.
- **Örnek düzeltme:**
```swift
// OnboardingViewV2.swift  (case 11)
@Environment(\.openURL) private var openURL   // view'ın üstüne ekle

OBTimelinePaywallView(
    onStart: { plan in
        state.selectedPlan = plan
        onPurchase(plan) { finishOnboarding() }
    },
    onRestore: {                       // ✅ gerçek restore
        Task {
            do {
                let s = try await app.restoreSubscriptions()
                if s.tier.isPaid { finishOnboarding() }
            } catch { /* hata mesajı göster */ }
        }
    },
    onTerms:   { openURL(RDConfig.Web.termsURL) },     // ✅
    onPrivacy: { openURL(RDConfig.Web.privacyPolicyURL) }, // ✅
    onDismiss: { finishOnboarding() }
)
```
Legacy `OnboardingPaywallV2View` kullanılmıyorsa **sil** (dead code + aynı tuzak).

---

### C-2 · Hesap silme = "talep", gerçek silme değil  🔴 P0/P1
- **Dosya:** `AnalysisService.requestAccountDeletion(...)` → `account_deletion_requests` tablosuna `insert`. Tamamlama `supabase/functions/account-deletion-complete/index.ts` (service-role / admin secret gerektirir, kullanıcı tetikleyemez).
- **Problem:** Kullanıcı uygulamadan "Hesabı sil"e basınca sadece bir kayıt düşüyor; gerçek silme arka planda admin/cron ile oluyor. UI metni de "Talep oluştur" (`ProfileView.swift:1184`).
- **Risk:** Apple Guideline **5.1.1(v)**: hesap oluşturmaya izin veren uygulama, **uygulama içinden hesap silmeyi başlatıp tamamlamalı**. "Talep et / destek bekle" akışları reddedildi. Bu, hesap oluşturan bir uygulama olduğu için yüksek olasılıklı ret.
- **Çözüm:** Kullanıcı aksiyonuyla senkron silme: ya `account-deletion-complete` mantığını JWT ile çağrılabilir (kullanıcı kendi hesabını silebilir) bir Edge Function'a taşı, ya da auth admin silmesini güvenli şekilde tetikle ve UI'da "hesabın ve verilerin kalıcı silindi" sonucunu göster. Asenkron temizlik kalabilir ama kullanıcıya silme **anında onaylanmalı**.
- **DOĞRULANMASI GEREKİYOR:** `account-deletion-complete` ne sıklıkta/nasıl tetikleniyor (cron var mı)? Kullanıcı self-service silebiliyor mu? Bunu netleştir.

---

### C-3 · Edge Function `verify_jwt` ayarı declarative değil  🟠 P1
- **Kanıt:** Repo'da hiçbir `supabase/config.toml` yok (arama boş döndü). `analyze/index.ts` runtime'da `Authorization` header'ı `supabase.auth.getUser()` ile doğruluyor (✅ iyi) ve `__worker` yolu service-role'a bağlı (✅). Ama platform seviyesinde `verify_jwt` her fonksiyon için garanti değil.
- **Risk:** `config.toml` olmadan deploy, fonksiyon bazında `verify_jwt` davranışını CI/CLI argümanına bırakır. `analyze` kendi içinde korunuyor; ancak `send-welcome-email`, `support-contact`, `generate-excel-report` gibi fonksiyonların hepsi kendi içinde token doğruluyor mu DOĞRULANMALI. Doğrulamayan biri varsa, publishable key'i olan herkes (key zaten client'ta açık) çağırabilir.
- **Çözüm:** `supabase/config.toml`'a her fonksiyon için açık `[functions.<name>] verify_jwt = true` (worker/webhook'lar hariç) ekle ve repo'ya commit et. Webhook'lar (`revenuecat-webhook`) zaten `verify_jwt=false` + kendi `Authorization` header kontrolü ile çalışmalı (kod doğru: `index.ts:221`).

---

### C-4 · `backups/` git'e commit edilmiş, sır envanteri içeriyor  🟠 P1
- **Dosya:** `backups/geri-donus-20260511-221030/supabase/secrets-list.json`
- **Problem:** `value` alanları **plaintext değil, 64-hex SHA-256 digest** (Supabase `secrets list` çıktısı). Yani gerçek anahtar sızmıyor — bu önemli, panik yok. Ancak: tüm sır isimleri, `FIREBASE_PROJECT_ID`, güncelleme zaman damgaları repoda. `.gitignore` `supabase/.temp/` hariç tutuyor ama `backups/`'ı tutmuyor.
- **Risk:** Bilgi sızıntısı (hangi sırlar var, ne zaman döndü). Asıl risk: ileride biri buraya yanlışlıkla plaintext bir yedek koyabilir.
- **Çözüm:** `.gitignore`'a `backups/` ekle, mevcut dosyayı git geçmişinden temizle (`git rm --cached`, gerekiyorsa filter-repo). RDConfig içindeki publishable key & RevenueCat key'i client-public, sızıntı değil — yorumlardaki açıklama doğru.

---

### C-5 · Foto analizi: inline base64 + bellek baskısı  🟠 P1
- **Dosya:** `AnalysisService.makeInlineJPEGParts` / `inlineJPEGPart` (satır 1047-1085), `runPhotoAnalysis`.
- **Problem:** Fotoğraflar Storage yerine base64 olarak Edge Function body'sine gömülüyor (RLS upload akışı kırıldığı için, yorum satır 94). Her foto ≤1.5MB, toplam ≤4.5MB sınırı var (iyi), ama base64 ~%33 şişer ve tüm görseller bellekte aynı anda `String` olarak tutuluyor. Detached task'ta yapılıyor (✅ main thread serbest), ama 3+ yüksek çözünürlüklü fotoda eski cihazlarda bellek tepe noktası riski.
- **Risk:** Düşük RAM'li cihazda OOM/jetsam crash; ayrıca 300 sn polling (`waitForCompletedResult`) sırasında uygulama foreground kalmazsa kullanıcı belirsizlikte kalır.
- **Çözüm:** Orta vade: Storage RLS'i düzeltip imzalı upload'a dön (base64 inline'ı sadece fallback yap). Kısa vade: aynı anda tutulan base64 string sayısını sınırla (stream/sıralı encode), `autoreleasepool` kullan, ve foto sayısını UI'da net sınırla.

---

## 3. Security Audit

**Genel: BACKEND GÜVENLİĞİ İYİ.** Sırlar server-side `Deno.env`'de, RLS yaygın, auth doğru.

- **API key / secret / token sızıntısı:** Client'ta sadece **public** key'ler var: Supabase publishable key (`RDConfig.swift:23`), RevenueCat public SDK key (`:42`), Google client/server ID (`Info.plist:44-47`). Hepsi tasarımca client-public. **Gemini/Groq/service-role/APNs anahtarları kodda YOK** — yalnızca `Deno.env.get(...)` ile server'da. ✅ İyi.
- **Keychain:** Uygulama Supabase-Swift SDK'sının default oturum saklamasına güveniyor. Apple platformlarında supabase-swift default'u Keychain tabanlıdır — ama **DOĞRULANMALI**: `SupabaseClientOptions` içinde özel `localStorage` verilmemiş, yani SDK default'u geçerli. Manuel token saklaması yok (iyi).
- **UserDefaults'ta hassas veri:** Yok. Sadece tema/dil/onboarding flag (`AppState.swift:61-64`) ve kota görüntü cache'i (`HomeView.swift:1442-1452`). PII/token yok. ✅
- **HTTPS / cert pinning:** Tüm trafik Supabase HTTPS üzerinden. Cleartext HTTP, `NSAllowsArbitraryLoads` yok. ✅ Cert pinning yok — bu sağlık/finans seviyesi olmayan bir uygulama için kabul edilebilir; istersen pinning bir sertleştirme (P3) olur.
- **Auth/session:** `validSession` expiry kontrolü yapıyor (`AuthService.swift:402`), stale session temizleniyor (`clearStaleLocalSession`). Apple/Google idToken + **nonce + SHA256** doğru uygulanmış (`AppleSignInService`, `GoogleSignInService`). ✅ Sağlam.
- **JWT/token refresh:** Supabase SDK otomatik refresh yapıyor; uygulama `authStateChanges` dinliyor (`AuthService.swift:383`). ✅
- **Input validation:** Metin girişi 10–100 karakter sınırı (`AnalysisService:39,124-128`); foto boyut/payload sınırı var. Asıl yetki/kota kontrolü **server-side** (`analyze` `PLAN_LIMITS`). ✅
- **Deep link güvenliği:** `onOpenURL` → `GoogleSignInService.handle` → `SupabaseService.handleAuthURL` (`RiskDetectedApp.swift:17-21`). OAuth PKCE callback (`io.supabase.riskdetected://`). Custom scheme hijack teorik riski var ama token PKCE ile korunuyor; ekstra validation gerekmiyor. ✅
- **Logging'de PII/secret:** `OSLog` kullanımı **örnek niteliğinde iyi** — email `privacy: .private(mask: .hash)`, storage path'ler `.private(mask: .hash)`, support/request ID'ler `.public`. `print()`/`NSLog` yok. ✅
- **Jailbreak/root detection:** Yok. Bu uygulama için gerekli değil (P3, opsiyonel).
- **WebView:** **Hiç WKWebView/SFSafariViewController yok.** ✅ WebView attack surface sıfır.
- **Third-party SDK:** Supabase, RevenueCat, GoogleSignIn — hepsi yaygın/güvenilir. Privacy Manifest'leri (SDK'ların kendi `.xcprivacy`'leri) build'de bulunmalı — **DOĞRULANMALI** (özellikle SDK imza/required-reason manifest'leri).
- **Network error handling:** Retry + exponential-ish backoff (`invokeAnalyze` 2 deneme, `storeReport` 3 deneme transient hata filtresiyle). Support ID'li kullanıcı mesajları. ✅ İyi.
- **Backend endpoint varsayımları:** `analyze` token doğruluyor + kota server-side; `revenuecat-webhook` Authorization header kontrollü; silme/temizlik fonksiyonları service-role gerektiriyor. ✅ RLS politikaları 15+ migration'da mevcut (toplam ~70+ policy). **DOĞRULANMALI:** her tablonun RLS'inin `auth.uid() = user_id` ile gerçekten izole ettiği canlı testle teyit edilmeli (statik incelemede policy'ler var ama doğruluğu çalıştırılarak test edilmedi).

---

## 4. Privacy & Compliance

- **Toplanan veriler:** Email, ad, ünvan, sertifika no, firma adı/logosu, telefon, profil foto, saha fotoğrafları, analiz metni, push device token, cihaz modeli/app sürümü, onboarding cevapları, paywall event'leri.
- **PII var mı?** Evet — email, telefon, ad, sertifika no, fotoğraflar. Bunlar Supabase'de saklanıyor.
- **App Tracking Transparency:** `PrivacyInfo.xcprivacy` `NSPrivacyTracking=false`, tracking domain yok. Reklam/cross-app tracking yok → **ATT gerekmiyor.** ✅ Bu doğru görünüyor (üçüncü-parti reklam SDK'sı yok).
- **İzin gerekçeleri:** `NSCameraUsageDescription` ve `NSPhotoLibraryUsageDescription` var ve **anlamlı/spesifik** (Türkçe, kullanım amacı net). ✅ Bildirim izni runtime'da isteniyor. **Eksik kontrol:** Sadece bu iki izin tanımlı — mikrofon/konum kullanılmıyorsa sorun yok (kodda kullanım görmedim ✅).
- **Privacy Manifest / Required Reason API:** `PrivacyInfo.xcprivacy` mevcut ve UserDefaults için `CA92.1` reason'ı bildiriyor. ✅ **DOĞRULANMALI:** Uygulama `Bundle.main.infoDictionary` dışında file timestamp / disk space / system boot time API'leri kullanıyorsa onların reason'ları da eklenmeli; ayrıca üçüncü-parti SDK manifest'leri pakette olmalı.
- **Privacy Policy'de açıklanması gerekenler:** Kamera/galeri kullanımı, AI işleme (Gemini/Groq'a foto/metin gönderimi — **üçüncü taraf AI işlemcisi olarak açıkça belirtilmeli**), push token, RevenueCat (satın alma), veri saklama süresi, KVKK/GDPR hakları. AI'ye veri gönderimi politikada net değilse eklenmeli.
- **Veri silme/export/consent:**
  - Export: `exportUserData` JSON üretiyor ✅
  - Silme: C-2'deki sorun (talep tabanlı) ⚠️
  - Consent: `consents` migration + `LegalAcceptanceService` mevcut ✅ — **DOĞRULANMALI** akışın onboarding'de gerçekten gösterildiği.

---

## 5. App Store Review Audit

- **Safety (1.x):** Kullanıcı üretilen içerik (foto/metin AI'ye gidiyor) var ama paylaşımlı sosyal içerik yok → UGC moderasyon/report/block **gerekmiyor** (içerik sadece kullanıcının kendisine ait). ✅
- **Performance (2.x):** Minimum functionality riski **DÜŞÜK** — gerçek AI analizi + PDF/Excel rapor + abonelik katmanları var, "ince web sarmalı" değil. ✅ 2.1: demo hesabı App Review'a verilmeli (login arkasında).
- **Business (3.x):**
  - **3.1.2 — KESİN SORUN:** Onboarding paywall'da Terms/Privacy linkleri ölü + Restore çalışmıyor (C-1). 🔴
  - IAP: RevenueCat üzerinden auto-renewable. `PaywallView`/`InAppPaywallView` disclosure + restore doğru. Fiyat/süre/oto-yenileme metni var (`PaywallView.swift:715-717`).
  - **3.1.1:** Dijital içerik IAP ile satılıyor ✅ (harici ödeme yönlendirmesi yok).
- **Design (4.x):**
  - **4.0 Sign in with Apple:** Google + Apple birlikte sunuluyor, entitlement var → ✅ zorunluluk karşılanıyor.
  - iPad: Orientation tüm yönler destekli; **DOĞRULANMALI** layout iPad'de bozuk değil (UI testi).
- **Legal (5.x):**
  - **5.1.1(v) — SORUN:** Uygulama içi gerçek hesap silme (C-2). 🔴
  - **5.1.1 veri toplama:** Privacy policy + consent var.
  - KVKK linki mevcut (`RDConfig.Web.kvkkURL`).
- **Metadata/screenshots/onboarding:** `AppStoreScreenshots/` ile üretiliyor — **DOĞRULANMALI** ekran görüntüleri gerçek uygulamayı yansıtıyor (yanıltıcı değil) ve onboarding'deki "trial/timeline" ekranları gerçek fiyatlandırmayla tutarlı.
- **En olası ret sebepleri:** (1) 3.1.2 paywall linkleri/restore, (2) 5.1.1(v) hesap silme, (3) AI veri işlemenin privacy policy'de eksikliği, (4) App Review için demo hesabı verilmemesi.

---

## 6. Code Quality

**Genel kalite YÜKSEK.** Tutarlı MVVM-ish servis katmanı, güçlü hata tipleri, iyi OSLog hijyeni, neredeyse hiç `try!`/`force-unwrap` yok.

- **Swift best practices:** `final class`, `enum` config, `Encodable` payload struct'ları + `CodingKeys`, `@MainActor` izolasyonu doğru. ✅
- **SwiftUI lifecycle:** `@StateObject appState`, `@Published` state. Onboarding `bootstrap()` içinde `Task.sleep(800ms)` — splash için kabul ama kırılgan (aşağı bkz B-edge).
- **Mimari/DI:** Servisler `.shared` singleton ama `AppState.init(auth:subscriptions:)` ve `SubscriptionManaging` protokolü test için injection'a izin veriyor. ✅ İyi denge.
- **Error handling:** Örnek niteliğinde — kategorize `LocalizedError`, support ID'li mesajlar, transient retry. ✅
- **async/await & Task cancellation:** `waitForCompletedResult` `Task.checkCancellation()` kullanıyor ✅. `AuthService.stateTask` `deinit`'te cancel ediliyor ✅.
- **Memory/retain cycle:** `startObservingAuthChanges` `[weak self]` kullanıyor ✅. RevenueCat delegate `nonisolated` + `Task { @MainActor in shared… }` — `shared` üzerinden eriştiği için cycle yok ama bağımlılığı singleton'a sabitliyor (minor).
- **Thread safety:** `@MainActor` izolasyonu net; encode işi `Task.detached`'e taşınmış ✅.
- **Force unwrap/fatalError/try!:** `try!` yok. `fatalError` sadece `SecRandomCopyBytes` başarısızlığında (2 yer) — kabul edilebilir (pratikte olmaz). `RDConfig` URL'lerinde `URL(string:)!` — sabit literal, güvenli.
- **Nonce charset bug (P3):** Hem Apple hem Google nonce charset'inde **"W" harfi eksik** (`...STUVXYZ...`). Klasik Firebase örnek hatası. Güvenliği bozmaz (32 karakter × 64'lük alfabe hâlâ bol entropi) ama temizlenmeli.
- **Naming/folder:** Tutarlı, okunabilir, Türkçe yorumlar açıklayıcı. ✅
- **Test edilebilirlik:** Protokol + DI var ama görünür unit test az (bkz §9). `AnalysisService` 1726 satır — bölünebilir (P2).
- **Dead code:** `OnboardingPaywallV2View` kullanılmıyor görünüyor ve hatalı (C-1) — sil.

---

## 7. Bug & Edge Case Review

- **B-1 (P1) — Onboarding restore = satın alma:** C-1. Edge: zaten abone kullanıcı yeniden ücretlenir.
- **B-2 (P2) — `bootstrap()` 800ms sabit sleep:** Yavaş ağda profil/offering yüklenmeden `flow=.main` olabilir; ağ tamamen yoksa `bootstrap` içindeki `await`'ler hata yutup main'e düşüyor (kullanıcı boş/eksik state görebilir). Offline'da auth refresh başarısızsa davranış DOĞRULANMALI.
- **B-3 (P2) — Foto analizi foreground bağımlı 300sn polling:** Uygulama arka plana atılırsa `waitForCompletedResult` askıda kalır; "bildirim göndereceğiz" mesajı var ama push gelmezse kullanıcı sonucu Geçmiş'ten manuel bulmalı. Background task / push-driven sonuç akışı netleştirilmeli.
- **B-4 (P2) — Kota görüntü cache'i UserDefaults'ta:** `HomeView:1442` kotayı UserDefaults'a yazıyor (sadece görüntü). Gerçek enforcement server'da olduğu için bypass değil, ama kullanıcı eski cache görebilir → yanıltıcı "hakkın doldu/var" gösterimi. Sunucu yanıtını tek doğruluk kaynağı yap.
- **B-5 (P3) — Empty/loading/error state:** Servis katmanı zengin hata mesajı üretiyor; **DOĞRULANMALI** her View bunları gösteriyor (özellikle History/Reports boş & hata state'leri).
- **Offline/slow network:** Retry var (✅) ama global "internet yok" banner'ı DOĞRULANMALI.
- **Permission denied:** Kamera/galeri reddi sonrası akış DOĞRULANMALI (Settings'e yönlendirme var mı?).
- **Token expired:** `validSession` + SDK refresh ile yönetiliyor ✅.
- **Background/foreground:** `syncCurrentTokenIfPossible` var; analiz polling'i (B-3) zayıf nokta.
- **iPad / ekran boyutları, Dark mode, Localization:** Dark mode `themePreference` ile ✅. Localization: `RDLocalization` + dil tercihi var; **DOĞRULANMALI** tüm string'ler tek dilde hardcode değil (çok sayıda Türkçe literal görülüyor — İngilizce desteği iddia ediliyorsa eksik olabilir).
- **Date/timezone:** `Europe/Istanbul` sabitli kota hesabı (`istanbulStartOfTodayISO`) — yurtdışı kullanıcıda "gün" sınırı TR gününe göre olur; kasıtlıysa OK, değilse edge.
- **Race condition:** `createDefaultProfile` insert↔fetch yarışını ele alıyor (✅ satır 327). Auth observer + manuel refresh çift tetikleme idempotent.

---

## 8. Performance Review

- **Gereksiz render:** `@Published` çok; çoğu state `AppState`'te toplanmış. Büyük View'larda (HomeView ~1450+ satır) gereksiz redraw DOĞRULANMALI (Instruments → SwiftUI view body sayacı).
- **Büyük image/memory:** C-5 — base64 inline en büyük bellek riski. `UIGraphicsImageRenderer` ile resize iyi; `autoreleasepool` eklenmeli.
- **Main thread blocking:** JPEG encode `Task.detached` ✅. PDF üretimi (`PDFReportService`) için DOĞRULANMALI (büyük raporda main'de mi?).
- **Network caching:** Supabase istekleri cache'siz; liste ekranlarında tekrarlı fetch olabilir — `listRecent`/`firstPhotoPaths` çağrı sıklığı DOĞRULANMALI.
- **Startup time:** `bootstrap` 800ms yapay gecikme + zincirleme `await` (identify→sync→refresh→offerings). Soğuk açılışta paralelleştirilebilir (P2).
- **Lazy loading / list perf:** History/Reports `limit` kullanıyor (✅) ama `exportUserData`/`freeRiskAnalysisTrialUsage` `limit:1000` çekiyor — büyük hesapta yavaş (P2).
- **Instruments'la bakılacak yerler:** (1) Foto analizi sırasında Allocations (base64 peak), (2) HomeView Time Profiler, (3) soğuk başlangıç App Launch, (4) PDF üretimi Time Profiler.

---

## 9. Test Plan

**Unit test:**
- `RevenueCatSubscriptionManager.state(from:)` tier çözümleme (plus/pro/free, "başka hesap" reddi `restorePurchases`).
- `AnalysisService` quota/limit yardımcıları, `safeReportFileName` (Türkçe karakter normalize), `functionErrorPayload` parse.
- `AuthService.validSession`, `shouldBackfillFullName`, `initials`.
- Nonce üretimi (charset düzeltmesi sonrası uzunluk/karakter testi).

**UI test (XCUITest — `RiskDetectedUITests` zaten var):**
- Onboarding → paywall → **Terms/Privacy linkleri açılıyor mu, Restore restore mu yapıyor** (C-1 regresyon testi).
- Login (Apple/Google bypass flag'leri mevcut: `RD_UI_TEST_*`).
- Foto/metin analizi → rapor → PDF paylaşımı (fixture: `uiTestResultBundle`).
- Hesap silme akışı (C-2 düzeltmesi sonrası).

**Security test:**
- Her Edge Function'a **token'sız** ve **başka kullanıcının token'ı** ile istek → 401 / RLS reddi doğrulaması (özellikle `analyze`, `generate-excel-report`, `support-contact`, `send-welcome-email`).
- RLS izolasyon testi: kullanıcı A, kullanıcı B'nin `analyses/reports/photos`'una erişemiyor (canlı SQL testi).
- `revenuecat-webhook` yanlış Authorization header ile → 401.
- Storage path traversal: başka kullanıcının `userID/...` path'i indirilemiyor.

**Manuel QA checklist:** offline başlatma, izin reddi, dark mode, iPad layout, slow network (Network Link Conditioner), arka plana atıp analiz sonucu, abonelik satın alma + sandbox restore, dil değişimi, boş/hata state'leri.

**App Store submission checklist:** demo hesabı + App Review notu; privacy policy AI işleme maddesi; App Privacy "Nutrition Label" doldurma (topladığın PII ile tutarlı); Sign in with Apple capability; abonelik metadata (fiyat/süre); export compliance (ITSAppUsesNonExemptEncryption — sadece HTTPS ise exempt, Info.plist'e ekle); screenshots gerçek UI.

---

## 10. Prioritized Action Plan

**P0 — Submit öncesi KESİN:**
- C-1: Onboarding paywall Terms/Privacy linklerini ve gerçek Restore'u bağla; legacy `OnboardingPaywallV2View`'i sil. (3.1.2)
- C-2: Uygulama içi gerçek/senkron hesap silme uygula (kullanıcı tetiklemeli). (5.1.1(v))
- App Review için demo hesabı + privacy policy'ye AI veri işleme maddesi; App Privacy label'ı tamamla.

**P1 — Çok önemli:**
- C-3: `supabase/config.toml` ile her fonksiyonun `verify_jwt` ayarını declarative yap; tüm fonksiyonların kendi auth kontrolünü doğrula.
- C-4: `backups/` git'ten çıkar + geçmişten temizle.
- C-5/B-3: Foto analizi bellek (autoreleasepool/sıralı encode) + arka plan/push-driven sonuç akışı.
- RLS izolasyonunu canlı testle doğrula.
- Keychain oturum saklamasını ve SDK Privacy Manifest'lerini doğrula.

**P2 — İyileştirme:**
- `bootstrap()` startup'ını paralelleştir, 800ms sabit sleep'i kaldır/azalt.
- Kota gösterimini server yanıtına bağla (UserDefaults cache'ini yalnız fallback yap).
- `exportUserData`/quota `limit:1000` sorgularını sayfalandır.
- `AnalysisService`'i (1726 satır) alt servislere böl; unit test kapsamı ekle.
- Empty/loading/error state'lerini her ekranda doğrula; offline banner.

**P3 — Nice to have:**
- Nonce charset "W" düzeltmesi (her iki sign-in servisi).
- İsteğe bağlı: cert pinning, jailbreak detection.
- Localization tamlığı (hardcoded Türkçe string denetimi).
- Timezone'u (Europe/Istanbul) kullanıcı yerelliğiyle değerlendir.

---

### Doğrulanması Gereken Açık Noktalar (varsayım yapmadım)
1. `account-deletion-complete` tetikleme mekanizması (cron/manuel) ve kullanıcı self-service silebiliyor mu?
2. Tüm Edge Function'ların (özellikle `support-contact`, `send-welcome-email`, `generate-excel-report`) kendi içinde JWT doğrulayıp doğrulamadığı + canlı `verify_jwt` deploy ayarı.
3. RLS politikalarının `auth.uid()` ile gerçek izolasyonu (statik olarak var, çalıştırılarak test edilmedi).
4. Supabase oturumunun Keychain'de mi saklandığı (SDK default'una bırakılmış).
5. Üçüncü-parti SDK Privacy Manifest'lerinin build'de bulunup bulunmadığı.
6. iPad layout, offline davranışı, localization tamlığı (çalışan build/Instruments gerektirir).
