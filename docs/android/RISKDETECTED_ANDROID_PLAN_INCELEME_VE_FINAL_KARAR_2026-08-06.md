# RiskDetected Android — Plan İncelemesi ve Final Uygulama Kararı

**Belge sürümü:** 1.0 (final)
**Tarih:** 6 Ağustos 2026 — Europe/Istanbul
**İncelenen belge:** `RISKDETECTED_ANDROID_GUVENLI_GECIS_MASTER_PLANI_2026-08-06.md` (4.071 satır)
**Sistem temeli:** `docs/RISKDETECTED_SISTEM_MIMARI_VE_AKIS_REFERANSI_2026-08-06.md`
**Canlı ürün:** iOS `1.3.1 (81)` · Supabase `ppcrzemgiztzcgddbins`
**Durum:** Bu belge inceleme + düzeltme + final karar setidir. Production deploy, mağaza gönderimi veya flag aktivasyonu yetkisi vermez.

Bu belge orijinal planın **yerine geçmez, üstüne biner**. Çelişki hâlinde bu belge geçerlidir; çünkü buradaki bulgular canlı production şeması, aktif Edge Function kaynağı ve gerçek iOS kodu üzerinden doğrulanmıştır.

---

## İçindekiler

1. [Genel değerlendirme](#1-genel-değerlendirme)
2. [Doğrulama yöntemi](#2-doğrulama-yöntemi)
3. [Bölüm bazlı uyumluluk tablosu](#3-bölüm-bazlı-uyumluluk-tablosu)
4. [Kanıtlanmış bulgular: bloker ve düzeltmeler](#4-kanıtlanmış-bulgular-bloker-ve-düzeltmeler)
5. [Planda düzeltilmesi gereken varsayımlar](#5-planda-düzeltilmesi-gereken-varsayımlar)
6. [Plana eklenmesi gerekenler](#6-plana-eklenmesi-gerekenler)
7. [Plandan çıkarılması veya ertelenmesi gerekenler](#7-plandan-çıkarılması-veya-ertelenmesi-gerekenler)
8. [Final teknoloji kararları](#8-final-teknoloji-kararları)
9. [Revize edilmiş ön koşul kapıları](#9-revize-edilmiş-ön-koşul-kapıları)
10. [Revize edilmiş faz planı](#10-revize-edilmiş-faz-planı)
11. [Backend değişiklik listesi — kesinleşmiş](#11-backend-değişiklik-listesi--kesinleşmiş)
12. [Karar defteri — güncellenmiş](#12-karar-defteri--güncellenmiş)
13. [Risk kaydı](#13-risk-kaydı)
14. [Final onay cümlesi](#14-final-onay-cümlesi)

---

## 1. Genel değerlendirme

**Verdict: Plan onaylanabilir. Mimari yönü doğru, güvenlik disiplini yüksek, ADR'leri isabetli. Ancak olduğu gibi uygulanamaz — 4 hard blocker, 6 hatalı varsayım ve 11 eksik var. Ayrıca kapsam, ürünün bugünkü ölçeği için fazla geniş.**

### Doğru olan ve korunması gerekenler

| Karar | Değerlendirme |
| --- | --- |
| ADR-001 native Kotlin + Compose | **Doğru.** iOS'u cross-platform'a taşımak bugünkü olgunlukta net zarar. KMP'yi dışarıda bırakması isabetli. |
| ADR-002 UI paylaşma, sözleşme paylaş | **Doğru.** Ürün otoritesi zaten backend'de; paylaşılacak değerli katman sözleşme ve fixture. |
| ADR-005 çok katmanlı Android kill switch | **Doğru ve kritik.** Tek "Android açık" flag'i olmaması bu planın en iyi kararlarından biri. |
| ADR-006 iOS'a zarar vermeme / dual-contract | **Doğru.** Additive migration ilkesi bizim mevcut deploy disiplinimizle birebir uyumlu. |
| GATE-00 (build 81 reproducibility) önkoşul yapılması | **Doğru ve zorunlu.** Bizim en yüksek öncelikli açık borcumuz zaten bu. |
| Backend'in tek entitlement otoritesi kalması | **Doğru.** Mevcut invariant'ı koruyor. |
| Safety profile seçiminin kullanıcıya ait kalması | **Doğru.** Storefront/IP çıkarımı yasağı korunmuş. |
| Fotoğraf 1/3/3 sabiti ve legacy `plus_pro_5_photo_limit` adının taşınmaması | **Doğru.** |

### Ana eksiklik

Plan, **iOS kaynak kodunu ve production şemasını okumadan** yazılmış; sistem referans belgesinden türetilmiş. Bu yüzden mimari doğru ama **entegrasyon detayları eksik**. Aşağıdaki 4 blocker plana hiç girmemiş ve ilk Android push/analiz denemesinde runtime hatası üretir.

---

## 2. Doğrulama yöntemi

Bu inceleme sırasında yapılanlar (hepsi read-only):

- Production `pg_constraint` üzerinden `push_device_tokens`, `analyses`, `user_subscriptions` CHECK kısıtları okundu.
- `supabase/functions/analyze/index.ts` client release context ve build allowlist eşleştirme kodu okundu.
- `supabase/functions/app-release-policy/index.ts` request sözleşmesi okundu.
- `supabase/functions/send-push-notification/index.ts` APNs gönderim yapısı incelendi.
- `supabase/functions/revenuecat-webhook/index.ts` store/environment alan kullanımı arandı.
- `App/Services/AuthService.swift` OTP metadata sözleşmesi okundu.
- `supabase/config.toml` Apple/Google provider ve redirect URL yapılandırması okundu.
- `public.user_subscriptions.source` gerçek değer dağılımı sorgulandı.
- Migration geçmişinde `push_device_tokens` üzerindeki tüm değişiklikler tarandı.

**Hiçbir production yazma işlemi yapılmadı.** Flag, ASC, Play, RevenueCat veya kullanıcı verisi değiştirilmedi.

---

## 3. Bölüm bazlı uyumluluk tablosu

| Plan bölümü | Uyum | Not |
| --- | --- | --- |
| 1 Kaynak otoritesi | ✅ Tam | Bizim otorite sıramızla aynı |
| 2 ADR'ler | ✅ Tam | ADR-004 paket adı `[DOĞRULA]` doğru işaretlenmiş |
| 3 Başarı ölçütleri | ✅ Tam | Ölçülebilir |
| 4 Kapsam dışı | ✅ Tam | Doğru sınırlar |
| 5 GATE-00…10 | 🟡 Kısmi | GATE-04 gereğinden ağır (bkz. F8), 3 yeni gate eksik |
| 6 Hedef mimari | ✅ Tam | Diyagram bizim gerçek hattımızla uyumlu |
| 7 Android yığını | 🟡 Kısmi | Navigation 3, Room, pinning kararları değişmeli |
| 8 Repo/modül | 🟡 Kısmi | 19 feature modülü aşırı; sadeleştirilmeli |
| 9 Ortam izolasyonu | ✅ Tam | Variant tablosu doğru |
| 10 Mobil sözleşme | 🔴 Eksik | `client_capabilities` ve OTP metadata sözleşmesi yok (F5, F6) |
| 11 Backend platformlaştırma | 🔴 Eksik | 4 blocker'ın 3'ü bu bölümde eksik (F1, F2, F3) |
| 12 Auth | 🟡 Kısmi | Apple Services ID zaten var — GATE-04 hafifleyebilir (F8) |
| 13 Onboarding | ✅ Tam | Adım tablosu birebir doğru |
| 14 Abonelik | 🟡 Kısmi | `store` alanı eksikliği doğru tespit; `trial_product_id` CHECK'i atlanmış (F7) |
| 15 Fotoğraf | ✅ Tam | Normalizasyon adımları sağlam |
| 16 Sektör/canvas | ✅ Tam | ID'ler birebir doğru |
| 17 Queue/retry | ✅ Tam | Invariant listesi eksiksiz |
| 18 AI/coverage | 🟡 Kısmi | `client_capabilities.multi_photo_coverage_v2` eksik (F5) |
| 19 Bulgular | ✅ Tam | Risk bantları doğru |
| 20 Rapor | 🟡 Kısmi | Doküman numarası/`report_year_counters` sözleşmesi eksik |
| 21 Firma/ilerleme | ✅ Tam | Limitler doğru |
| 22 Bildirim | 🔴 Eksik | Push token CHECK ve delivery RPC engelleri yok (F1, F2, F4) |
| 23 Lokalizasyon/legal | ✅ Tam | Codegen yaklaşımı doğru |
| 24 Erişilebilirlik | 🟡 Kısmi | Tablet/foldable v1 için fazla |
| 25 Güvenlik | 🟡 Kısmi | Pinning ve Integrity v1'de risk/fayda dengesizi |
| 26 Gözlemlenebilirlik | ✅ Tam | Korelasyon alanları doğru |
| 27 Test | ✅ Tam | Kapsamlı; araç seçimi eklenmeli |
| 28 CI/CD | ✅ Tam | Release manifest fikri iyi |
| 29 Play Console | 🟡 Kısmi | Closed testing 14 gün şartı yeterince yukarı taşınmamış |
| 30 Rollout/rollback | ✅ Tam | Katmanlı kill switch mükemmel |
| 31 Fazlar | 🟡 Kısmi | Süre tahmini yok; sıra doğru |
| 32 Backlog | ✅ Tam | Epic yapısı kullanılabilir |
| 33 DoD | ✅ Tam | — |
| 34–35 Agent protokolü | ✅ Tam | Kural seti bizim çalışma disiplinimizle uyumlu |
| 36 Karar defteri | 🟡 Kısmi | 5 karar eksik |
| 37 Invariant'lar | ✅ Tam | 40 madde doğru |
| 38 Platform gereksinimleri | ✅ Tam | Release gününde yeniden doğrulanacak |

---

## 4. Kanıtlanmış bulgular: bloker ve düzeltmeler

Bu bulguların hepsi **canlı production veya repo kaynağından** doğrulandı.

### 🔴 F1 — `push_device_tokens.platform` CHECK kısıtı yalnız `'ios'` kabul ediyor · BLOCKER

Production kısıtı:

```text
push_device_tokens_platform_check
CHECK ((platform = 'ios'::text))
```

Kaynak: `supabase/migrations/20260510002500_push_notifications.sql:8`, hiçbir sonraki migration değiştirmemiş.

**Etki:** Android FCM token kaydı ilk denemede `23514 check_violation` ile başarısız olur. Plan bu tabloya "additive alanlar" eklemeyi öneriyor ama **mevcut kısıtı hiç görmemiş.**

**Düzeltme (Faz 2, additive migration):**

```sql
alter table public.push_device_tokens
  drop constraint push_device_tokens_platform_check;
alter table public.push_device_tokens
  add constraint push_device_tokens_platform_check
  check (platform in ('ios', 'android'));
```

pgTAP testi: mevcut iOS satırlarının etkilenmediği + `'web'` gibi bilinmeyen değerin hâlâ reddedildiği doğrulanmalı.

### 🔴 F2 — `push_device_tokens.environment` CHECK'i FCM ile uyumsuz · BLOCKER

```text
push_device_tokens_environment_check
CHECK ((environment = ANY (ARRAY['sandbox'::text, 'production'::text])))
```

APNs'te `sandbox|production` anlamlıdır; **FCM'de böyle bir ayrım yoktur** — ortam Firebase proje kimliğiyle belirlenir. Plan `environment` alanına "FCM için firebase project alias" yazılmasını öneriyor; bu mevcut CHECK'i doğrudan ihlal eder.

**Düzeltme — iki seçenek, ikincisi tercih edilir:**

1. CHECK'i genişlet (`sandbox|production|fcm_prod|fcm_staging`) → anlamsal kirlilik.
2. **Tercih:** `environment` alanını APNs semantiğinde bırak, Android için `provider_environment text` adında yeni nullable kolon ekle ve Android satırlarında `environment='production'` sabit yaz. Böylece mevcut APNs sorguları ve `send-push-notification` mantığı hiç değişmez.

### 🔴 F3 — Build allowlist eşleştirmesi platform-agnostik: iOS/Android build numarası çakışması · BLOCKER

`supabase/functions/analyze/index.ts` içinde:

```ts
function clientBuildMatches(builds: string[], client: ClientReleaseContext): boolean {
  if (!client.appBuild) return false;
  if (builds.includes(client.appBuild)) return true;
  if (client.appBuildNumber == null) return false;
  return builds
    .map((build) => asOptionalPositiveInt(build))
    .some((build) => build === client.appBuildNumber);
}
```

Fonksiyon `client.platform` değerini **hiç okumuyor**. Bugün 13 lokalizasyon flag'i `enabled_ios_builds: ["80","81"]`, `multi_photo_analysis` ise `["63"…"77","80","81"]` taşıyor.

**Etki:** Android `versionCode` bir gün 63'e ulaştığında, hiçbir karar alınmadan multi-photo ve 12 katmanlı denetim Android'de **sessizce açılır**. Aynı şekilde `versionCode 80/81` tüm lokalizasyon flag'lerini açar. Bu, planın ADR-006 "platform allowlist'leri ayrı" ilkesinin **kod seviyesinde henüz karşılığı olmadığı** anlamına gelir.

**Düzeltme (Faz 2, kod + flag şeması):**

- `clientBuildMatches` platform parametresi alır.
- `platform === "ios"` → `enabled_ios_builds`; `platform === "android"` → `enabled_android_version_codes`; diğer → `false` (fail-closed).
- `min_ios_build` sayısal karşılaştırmaları da aynı şekilde platforma bağlanır.
- Deno testi: `platform=android, build=80` durumunda hiçbir iOS flag'inin açılmadığı kanıtlanır.

**Not:** Bu düzeltme Android kodu yazılmadan önce yapılmalı; bugünkü tek koruma Android'in henüz var olmamasıdır.

### 🔴 F4 — `send-push-notification` tamamen APNs'e gömülü · BLOCKER (mimari)

Kaynakta doğrudan APNs'e bağlı olanlar: `makeProviderToken()` (ES256 JWT), `apnsHost()`, `apns-topic` header'ı, `POST {host}/3/device/{token}` yolu, `apns-delivery.ts` modülü ve `record_notification_delivery_attempt_v1(p_apns_id => …)` RPC parametresi.

Plan "public interface korunarak provider dispatcher eklenir" diyor — doğru hedef, ama iş yükünü küçümsüyor. **Delivery attempt RPC'sinin parametre adı APNs'e özgü**; provider-agnostik hâle getirilmeden FCM message ID kaydedilemez.

**Düzeltme:**

- `record_notification_delivery_attempt_v2(p_provider text, p_provider_message_id text, …)` eklenir; v1 korunur ve v2'ye delege eder (iOS regresyonu sıfır).
- `send-push-notification` içi: `providers/apns.ts` (mevcut kod taşınır, davranış değişmez) + `providers/fcm.ts` + ince bir `dispatch(token)` katmanı.
- Kabul kriteri: refactor sonrası **tek satır APNs davranışı değişmemiş** olmalı; mevcut Deno testleri değişmeden geçmeli.

### 🟠 F5 — `client_capabilities` sözleşmesi planda yok

`analyze` istemciden şu yapıyı okuyor:

```ts
const capabilities = body.client_capabilities && typeof body.client_capabilities === "object"
  ? Object.fromEntries(Object.entries(body.client_capabilities).map(([k, v]) => [k, v === true]))
  : {};
```

Production `multi_photo_analysis` flag notu:

> `Requires client_capabilities.multi_photo_coverage_v2=true; legacy builds stay on hazards[] flow.`

**Etki:** Android bu alanı göndermezse, çoklu fotoğraf analizinde **eski `hazards[]` akışına** düşer; exact coverage ve 12 katmanlı denetim çalışmaz, ama hata da vermez. Sessiz kalite kaybı.

**Düzeltme:** Bölüm 10.1'deki additive alan listesine `client_capabilities` eklenir; Android'in göndereceği anahtar seti Faz 2'de `analyze` kaynağından çıkarılıp `contracts/mobile/api/` altında dondurulur.

### 🟠 F6 — OTP e-posta lokalizasyon metadata'sı planda yok

`App/Services/AuthService.swift:67`:

```swift
try await supabase.auth.signInWithOTP(
    email: …,
    data: [
        "app_language": .string(language.rawValue),
        "content_locale": .string(contentLocale.rawValue),
    ]
)
```

`auth-send-email-hook` bu metadata'ya göre TR/EN şablon seçiyor; metadata yoksa legacy Türkçe bağlama düşüyor (Build 77 uyumluluğu için eklenmişti).

**Etki:** Android bu alanları göndermezse İngilizce kullanıcı **Türkçe OTP e-postası** alır. Play incelemesinde de kötü görünür.

**Düzeltme:** Android OTP çağrısı aynı `data` sözleşmesini gönderir; Deno tarafında EN metadata'lı Android fixture testi eklenir.

### 🟠 F7 — `user_subscriptions.trial_product_id` CHECK'i tek ürüne pinli

```text
user_subscriptions_trial_product_check
CHECK (((trial_product_id IS NULL) OR (trial_product_id = 'riskdetected_plus_yearly'::text)))
```

Planın "dört ayrı Google Play product, iOS ile aynı ID" kararı bu kısıt sayesinde **doğru karar** — ama gerekçesi planda yok. Eğer Play tarafında farklı bir product ID (örn. `riskdetected_plus_yearly_android`) seçilirse, trial yazımı CHECK ihlaliyle patlar ve cancelled-trial route'u sessizce bozulur.

**Düzeltme:** DEC-14 kararına "Play product ID'leri iOS ile **birebir aynı** olmak zorundadır; aksi hâlde `user_subscriptions_trial_product_check` ve `cancelled-plus-trial-routing.ts` birlikte değiştirilmelidir" notu eklenir.

### 🟢 F8 — Apple Services ID zaten yapılandırılmış: GATE-04 sanıldığından hafif

`supabase/config.toml`:

```toml
[auth.external.apple]
enabled = true
client_id = "com.riskdetected.app.service,com.riskdetected.app"
```

```toml
additional_redirect_urls = [ "io.supabase.riskdetected://login-callback", … ]
```

Yani bir Apple **Services ID** (`com.riskdetected.app.service`) ve Supabase'in kabul ettiği ikinci audience zaten tanımlı; custom scheme redirect de kayıtlı.

**Etki:** Planın GATE-04'ü "Apple kimlik eşleşmesi kanıtlanamazsa iOS companion build çıkar" gibi ağır bir B planı öngörüyor. Konfigürasyon zaten hazır olduğu için bu senaryonun olasılığı düşük.

**Düzeltme:** GATE-04 korunur ama sadeleştirilir: önce **production** Apple provider ayarının ve client secret geçerliliğinin read-only doğrulanması, sonra tek bir gerçek Apple-only test hesabıyla Android OAuth denemesi. Companion iOS build maddesi "yalnız test başarısız olursa" şeklinde şarta bağlı kalır (zaten öyle yazılmış, sadece olasılığı düşürüldü).

**Uyarı:** Apple web OAuth client secret'ı en fazla 6 ay geçerlidir. Rotasyon takvimi ve alarmı **Faz 3'te** kurulmalı; süresi dolarsa Android girişi tamamen durur (iOS native giriş etkilenmez).

### 🟢 F9 — `app-release-policy` zaten `client_platform` alıyor

```ts
type ReleasePolicyBody = { client_platform?: unknown; … };
const platform = text(body.client_platform, "unknown", 40).toLowerCase();
```

Android release policy eklemek sanıldığından kolay: request sözleşmesi hazır, yalnız yanıt tarafında platforma göre `ios_release_policy` / `android_release_policy` seçimi gerekiyor.

### 🟢 F10 — `analyses.client_build` regex'i versionCode ile uyumlu

```text
analyses_client_build_check
CHECK (client_build ~ '^[1-9][0-9]{0,8}$')
```

Android `versionCode` (pozitif tamsayı) sorunsuz geçer. Ancak `versionName` (`1.4.0`) bu alana **asla** yazılmamalı — CHECK ihlali olur. Plandaki "client_build string alanı iOS build veya Android versionCode taşır" ifadesi doğru; bu kısıt onu kanıtlıyor.

### 🟠 F11 — `user_subscriptions.source` store bilgisi değil

Production dağılımı: `revenuecat_sync` (79), `revenuecat_verified_event` (15), `revenuecat_transfer` (1). Yani `source` = **ingestion yolu**, mağaza değil. Planın ayrı `store` kolonu önerisi doğru; ancak "mevcut Apple alanları kaldırılmaz" derken `source` alanının store sanılmaması için bu ayrım belgelenmeli.

Ek olarak `revenuecat-webhook/index.ts` içinde `environment` işleniyor ama **`store` alanı hiç okunmuyor**. Store-aware normalizasyon sıfırdan yazılacak.

---

## 5. Planda düzeltilmesi gereken varsayımlar

| # | Plandaki ifade | Gerçek | Aksiyon |
| --- | --- | --- | --- |
| D1 | "`push_device_tokens`'a additive alanlar eklenir" | Tabloda `platform='ios'` CHECK'i var | F1 düzeltmesi zorunlu |
| D2 | "`environment`: FCM için firebase project alias" | CHECK yalnız `sandbox|production` | F2: ayrı `provider_environment` kolonu |
| D3 | "iOS build allowlist ile Android allowlist ayrı tutulacaktır" (ADR-006) | Kodda ayrım yok, `clientBuildMatches` platform körü | F3: kod düzeltmesi Faz 2'de zorunlu |
| D4 | "`send-push-notification` public interface korunarak dispatcher eklenir" | Delivery RPC parametresi `p_apns_id` | F4: RPC v2 gerekli |
| D5 | "Apple Services ID oluşturulmalı" | Zaten yapılandırılmış | F8: GATE-04 hafifletilir, secret rotasyonu öne alınır |
| D6 | "`user_subscriptions` store alanları eklenir, mevcut Apple alanları korunur" | `source` store değil; webhook `store` okumuyor | F11: net kolon + normalizasyon |

---

## 6. Plana eklenmesi gerekenler

### E1 — Google Play Install Referrer (öncelik: yüksek)

Owner reklam veriyor. iOS'ta RevenueCat AdServices attribution açık. Android karşılığı `com.android.installreferrer` + RevenueCat attribution entegrasyonudur. Planda **hiç yok**. Eklenmezse Android kampanya performansı ölçülemez.

Data Safety etkisi: install referrer reklam kimliği değildir, `AD_ID` izni gerektirmez — mevcut "advertising ID toplanmaz" beyanı korunur.

### E2 — Play In-App Review API (öncelik: orta)

iOS'ta 10 değerlendirme var. Play'de `ReviewManager` ile bağlamsal derecelendirme istemi (örn. başarılı 3. rapor sonrası) düşük maliyetli kazanç. Planda yok.

### E3 — Play In-App Updates API (öncelik: orta)

Plan güncelleme uyarısını yalnız backend `android_release_policy` üzerinden kurguluyor. Android'de native `AppUpdateManager` (flexible + immediate) daha iyi UX verir ve store sürümünü gerçek kaynaktan okur. Öneri: **backend policy karar verir, native API sunar** — ikisi birlikte.

### E4 — Play Console closed testing 14 gün şartının yukarı taşınması (öncelik: kritik takvim)

Plan bunu 29.1'de bir cümleyle geçiyor. Eğer Play developer hesabı **kişisel** ve yeni açılmışsa, production erişimi için 12 opt-in tester × kesintisiz 14 gün closed testing şartı uygulanır. Bu **takvimde 2+ hafta** demektir ve geliştirmeye paralel başlatılmazsa doğrudan gecikme yaratır.

**Aksiyon:** DEC-03 (hesap tipi) **Faz 0'da** kararlaştırılır; kişisel hesapsa closed testing Faz 8'i beklemeden, ilk çalışan QA build'iyle başlatılır.

### E5 — Rapor doküman numarası sözleşmesi

`reports` hattında `report_year_counters` / doküman numarası server tarafında üretiliyor. Plan PDF parite testinde "document number eşleşir" diyor ama numarayı kimin ürettiğini tanımlamıyor. Android **kendi numarasını üretmemeli**; `register-report` sözleşmesini kullanmalı. Faz 6 kabul kriterine eklenir.

### E6 — Supabase Auth OTP rate limit kapasitesi

Proje geneli e-posta kotası 2 Ağustos'ta `2/saat → 30/saat` yükseltildi. Android eklenince OTP trafiği artacak. Beta öncesi kota gözden geçirilmeli; aksi hâlde iki platform birbirinin OTP'sini bloke eder.

### E7 — Firebase = yeni veri işleyen (KVKK/GDPR)

Plan Data Safety'yi kapsıyor ama **KVKK aydınlatma metni ve Gizlilik Politikası'na Google/Firebase'in veri işleyen olarak eklenmesi** ayrı bir iş. Bizim legal doküman setimiz versiyonlu ve checksum'lı; yeni sürüm çıkarmak `legal_document_acknowledgements` akışını tetikler — yani **mevcut iOS kullanıcılarına da onay ekranı gösterilir**. Bu etki planlanmalı, sürpriz olmamalı.

### E8 — `analyses` tablosuna `client_platform` kolonu

`analyze` bugün `client_platform` alanını **parse ediyor ama saklamıyor**; `analyses` tablosunda böyle bir kolon yok. Telemetri ve dashboard platform kırılımı için kolon eklenmeli (plan bunu genel olarak söylüyor, ama "zaten parse ediliyor, sadece persist edilmiyor" tespiti yok — iş bu yüzden sanılandan küçük).

### E9 — Ekran görüntüsü test aracı seçimi

Plan "screenshot golden" diyor, araç belirtmiyor. Öneri: **Roborazzi** (JVM üstünde çalışır, emülatör gerektirmez, CI'da hızlı). Alternatif Paparazzi Compose'da daha kısıtlı.

### E10 — Play tarafı ASO takibi

Applyra bizde `ITUNES` store için yapılandırılmış (116 keyword). Play için ayrı bir çözüm gerekiyor. Faz 8'e "Play ASO aracı seçimi" maddesi eklenir; en azından Play Console'un kendi "arama terimleri" raporu baseline alınır.

### E11 — Android uygulama dilinin sunucu profiline yazılması

iOS'ta `profiles.app_language` / `content_locale` güncelleniyor. Android'de per-app language (Android 13+) kullanıcı tarafından ayrı ayarlanabilir; bu değişimin sunucu profiline **hangi anda** yazılacağı tanımlanmalı, aksi hâlde iki platform birbirinin dil tercihini ezer. Öneri: sunucudaki alan "son giriş yapan istemcinin dili" değil, **son açık kullanıcı tercihi** semantiğinde kalsın; belirsizlikte yazma yapılmasın.

---

## 7. Plandan çıkarılması veya ertelenmesi gerekenler

Bu ürün bugün ~98 kullanıcılı, tek geliştiricili bir üründür. Planın kapsamı kurumsal ölçekte yazılmış. Aşağıdakiler **v1'den çıkarılmalı** — hepsi geri eklenebilir.

| # | Madde | Gerekçe | Karar |
| --- | --- | --- | --- |
| Ç1 | **Certificate pinning (Android v1)** | En yüksek "kendini vurma" riski. Pin kırılırsa uygulama ağdan tamamen kopar ve düzeltme yalnız yeni binary ile mümkün — Play rollout'u da yavaş. iOS'ta zaten var, Android'de marjinal fayda. | **v1'den çıkar.** Network Security Config + yalnız HTTPS + sistem CA yeterli. Pinning post-launch, runbook (GATE-10) tamamlandıktan sonra. |
| Ç2 | **Play Integrity (v1)** | Shadow modda bile server doğrulama endpoint'i, nonce yönetimi ve replay testi gerektirir. Bugünkü tehdit profilinde (kota abuse) RLS + server kota zaten koruyor. | **Faz 7'den çıkar, post-launch'a ertele.** |
| Ç3 | **Room (local cache/draft)** | Server otoritesi zaten mutlak; cache'in tek gerçek faydası offline liste görüntüleme. Şema + migration + kullanıcı namespace maliyeti yüksek. | **v1'de kullanma.** Draft için DataStore + app-private dosya yeterli. Room ihtiyacı ölçülürse v2. |
| Ç4 | **19 feature + 13 core modül** | Küçük ekipte Gradle modül patlaması build süresi ve refactor maliyeti yaratır. | **Sadeleştir:** `app`, `core:common`, `core:data` (network+auth+subscription+notifications), `core:designsystem`, `core:testing` + 5–6 feature modülü (`onboarding`, `capture`, `analysis`, `reports`, `profile`, `paywall`). Gerektikçe böl. |
| Ç5 | **`benchmark` modülü + Macrobenchmark (v1)** | Baseline profile faydalı ama Macrobenchmark altyapısı v1 için lüks. | Baseline profile **kalsın**, benchmark modülü **ertele**. |
| Ç6 | **Tablet/foldable two-pane adaptive layout** | iOS ürünü zaten yalnız iPhone. Play'de tablet ekran görüntüsü zorunlu değil. | **v1'de yalnız "bozulmama" hedefi.** Two-pane ertele; Play pre-launch tablet bulguları crash değilse blocker sayılmaz. |
| Ç7 | **Navigation 3** | Plan "GA değilse en güncel kararlı" diyor; belirsizlik bırakıyor. | **Kesinleştir:** type-safe Navigation Compose (kotlinx.serialization route'ları). Alpha/beta navigation kütüphanesi kullanılmaz. |
| Ç8 | **Anında %1→%5→%25→%50→%100 beş aşamalı rollout** | Kullanıcı tabanı küçükken %1 istatistiksel olarak anlamsız (0 kullanıcı). | **Sadeleştir:** closed beta → %20 → %50 → %100, her adımda owner onayı. Server allowlist ilk gerçek kontrol katmanı olarak kalır. |

**Toplam etki:** Bu 8 kalem çıkarıldığında v1 kapsamı tahminen **%30–35 küçülür**, güvenlik duruşunda anlamlı kayıp olmaz (Ç1 ve Ç2 dışındakiler zaten güvenlik dışı; Ç1/Ç2 ise savunma derinliği katmanları — temel korumalar RLS, backend authority ve Play App Signing yerinde kalıyor).

---

## 8. Final teknoloji kararları

Plandaki yığın büyük ölçüde onaylanıyor. Değişenler **kalın** yazıldı.

| Katman | Final karar | Değişiklik gerekçesi |
| --- | --- | --- |
| Dil | Kotlin | — |
| UI | Jetpack Compose + Material 3 | — |
| minSdk / compileSdk / targetSdk | 26 / 36 / 36 | 31 Ağu 2026 Play şartı |
| JDK | 17 | — |
| Mimari | UDF; UI / Data (+gerektiğinde Domain) | — |
| DI | Hilt | — |
| Async | Coroutines + Flow | — |
| Navigation | **Type-safe Navigation Compose (kararlı sürüm)** | Nav3 belirsizliği kaldırıldı (Ç7) |
| Network | Supabase Kotlin, repository arkasında; sürüm pinli | Community-maintained; izolasyon şart |
| JSON | kotlinx.serialization | — |
| Local pref | DataStore | — |
| Secure session | Android Keystore ile şifreli store, backup dışı | — |
| Local DB | **Yok (v1)** | Ç3 |
| Background | WorkManager, yalnız idempotent registration | — |
| Kamera | CameraX | — |
| Galeri | System Photo Picker (geniş izin yok) | Play photo policy riski düşer |
| EXIF | **androidx.exifinterface** | Plan belirtmemişti |
| Görsel | BitmapFactory `inSampleSize` + ImageDecoder; Coil yalnız gösterim | — |
| Abonelik | RevenueCat Android SDK (Billing 8+ tabanı) · **sürüm `[DOĞRULA]`** | Plan `10.15.1` diyor; başlangıçta resmi kararlı sürüm teyit edilmeli |
| Paywall | **Custom Compose** (RevenueCat hazır paywall değil) | iOS `OBTimelinePaywallView` paritesi için |
| Push | FCM HTTP v1 | — |
| Attribution | **Play Install Referrer + RevenueCat** | E1 |
| Store UX | **Play In-App Review + In-App Updates** | E2, E3 |
| Crash | Firebase Crashlytics, PII redaction | Firebase zaten FCM için gerekli |
| Analytics | Firebase Analytics **kullanılmaz**; mevcut first-party event sistemi | Data Safety yüzeyini büyütmemek için |
| Integrity | **v1'de yok**, post-launch shadow | Ç2 |
| Pinning | **v1'de yok**, post-launch + runbook | Ç1 |
| PDF | Android `PdfDocument` tabanlı özel renderer | Üçüncü parti yalnız lisans/CVE incelemesiyle |
| Paylaşım | Sharesheet + dar path'li FileProvider | — |
| Test | JUnit, coroutines-test, Turbine, MockWebServer, Compose UI Test, **Roborazzi** | E9 |
| Statik kalite | Lint, detekt, ktlint, dependency/license/secret scan | — |
| Çıktı | AAB + Play App Signing | — |

### Değerlendirilip reddedilen alternatifler

| Alternatif | Neden reddedildi |
| --- | --- |
| KMP ile ortak domain | Bugünkü olgunlukta iOS tarafında refactor maliyeti getirisinden büyük. Ortaklık ihtiyacı zaten `contracts/` ile karşılanıyor. Post-parite ADR'ye bırakıldı. |
| Flutter / React Native tek kod tabanı | Canlı SwiftUI ürününü yeniden yazmak demek. Kamera, Billing, App Links, Integrity katmanlarında yine native köprü gerekir. |
| Sunucu tarafı kanonik PDF (v1) | Doğru uzun vadeli hedef ama v1'de yeni Edge Function + font/Türkçe karakter riski + iOS hattını değiştirme riski getirir. **v2 ADR tetikleyicisi:** iki renderer arasında parite testi 2 sürüm üst üste kırılırsa server-side PDF'e geçilir. |
| Sentry (Crashlytics yerine) | iOS+Android tek işleyende birleştirme cazip; ancak Firebase FCM için zaten zorunlu, ikinci SDK ve ikinci veri işleyen eklemek Data Safety/KVKK yüzeyini gereksiz büyütür. |
| Google Play "tek product + çoklu base plan" | Mevcut `user_subscriptions_trial_product_check` ve cancelled-trial route'u ürün ID'sine pinli (F7). Dört ayrı product backend riskini minimuma indirir. |

---

## 9. Revize edilmiş ön koşul kapıları

Orijinal GATE-00…10 korunur; aşağıdaki değişiklikler ve eklemeler yapılır.

| Gate | Durum | Değişiklik |
| --- | --- | --- |
| GATE-00 Build 81 reproducibility | Korundu | **Sırasıyla ilk iş.** Bugün canlı sürümün kaynağı commit'li değil. |
| GATE-01 iOS release policy | Korundu | `latest_build 77 → 81`; Android için ayrı `android_release_policy` |
| GATE-02 Onboarding ölçüm + bildirim borcu | Korundu | Adım 10/11 event'leri, `flow_completed_at`, PLUS/PRO bildirim adımı |
| GATE-03 Staging | Korundu | Supabase + Firebase + RevenueCat + Play license tester |
| GATE-04 Cross-platform kimlik | **Hafifletildi** | Services ID zaten var (F8). Önce prod config + client secret doğrulaması, sonra tek gerçek hesap testi |
| GATE-05 Backend platform-aware | **Genişletildi** | F1 + F2 + F3 + E8 bu gate'e dâhil edildi |
| GATE-06 Play katalog + webhook | **Genişletildi** | F7 (product ID birebir aynı) ve F11 (`store` kolonu + webhook normalizasyonu) eklendi |
| GATE-07 Android push | **Genişletildi** | F4 (delivery RPC v2 + dispatcher refactor) eklendi |
| GATE-08 Legal/Data Safety/silme | **Genişletildi** | E7 (Firebase veri işleyen + legal sürüm etkisi iOS'a da yansır) eklendi |
| GATE-09 Plus yıllık trial kararı | Korundu | 30 Eylül 2026 tarihi |
| GATE-10 Pinning runbook | **Ertelendi** | Ç1 gereği v1 kapsamı dışı; post-launch koşulu |
| **GATE-11 (yeni)** Play hesap tipi ve closed testing takvimi | Yeni | E4: kişisel hesapsa 12 tester × 14 gün şartı Faz 0'da başlatılır |
| **GATE-12 (yeni)** Apple web OAuth client secret rotasyon alarmı | Yeni | 6 aylık geçerlilik; süresi dolarsa Android girişi durur |
| **GATE-13 (yeni)** Auth OTP kota kapasitesi | Yeni | E6: iki platformun OTP trafiği tek proje kotasını paylaşır |

---

## 10. Revize edilmiş faz planı

Süreler tek geliştirici + AI ajan desteği varsayımıyla, **kaba** tahmindir; kapı kriterleri süreden önemlidir.

| Faz | Kapsam | Kaba süre | Çıkış kriteri |
| --- | --- | ---: | --- |
| **Faz 0** — Mevcut sistemi sabitle | GATE-00/01/02, GATE-11 başlat, prod snapshot, ADR'ler | 1–2 hafta | Build 81 temiz checkout'tan yeniden üretilebiliyor; iOS release policy güncel; onboarding ölçümü çalışıyor |
| **Faz 1** — Android iskelet + CI | Gradle, variant, DI, tema, sadeleştirilmiş modül seti, CI, environment guard | 1 hafta | Debug/QA staging'e bağlanıyor; release production config olmadan üretilemiyor |
| **Faz 2** — Backend platformlaştırma | **F1, F2, F3, F4(RPC), E8**, `store` kolonu, Android flag'leri (kapalı), Android release policy, dual-contract | 1,5–2 hafta | iOS regresyon yeşil; `platform=android, build=80` hiçbir iOS flag'ini açmıyor; tüm Android flag'leri production'da `false` |
| **Faz 3** — Auth, onboarding, profil, legal | Secure session, Credential Manager, OTP (**F6**), Apple web OAuth (**GATE-12**), identity linking, onboarding 0–11, legal | 2–3 hafta | GATE-04 geçti; duplicate hesap yok; TR/EN tam |
| **Faz 4** — RevenueCat + Play Billing | RC Android app, 4 product (**F7**), offering, paywall, webhook store-awareness (**F11**), cancelled-trial | 2 hafta | Billing matrisi tam; backend otoritesi kanıtlı; ürünler owner onayına kadar yayınlanmamış |
| **Faz 5** — Fotoğraf + analiz | CameraX, Photo Picker, normalize, annotation, sektör/canvas, submit (**F5**), status, result | 2–3 hafta | 1/3/3 sabiti; idempotent submit; exact coverage; TR/EN çıktı |
| **Faz 6** — Rapor, firma, ilerleme | Android PDF, register (**E5**), XLSX, arşiv, firma, progress | 2 hafta | PDF bilgi paritesi; snapshot; kota |
| **Faz 7** — FCM, güvenlik, gözlemlenebilirlik | FCM client + dispatcher (**F4**), kanal, izin, deep link, heartbeat, Crashlytics redaction, R8, dashboard, kill switch provası | 1,5–2 hafta | APNs regresyonu sıfır; FCM matrisi; PII log yok; kill switch prova edildi |
| **Faz 8** — Store + beta | Play Console, App Signing, listing TR/EN, Data Safety (**E7**), silme URL'i, ASO (**E10**), In-App Review/Update (**E2/E3**), Install Referrer (**E1**), closed beta | 1–2 hafta + **closed testing takvimi** | Pre-launch blocker yok; owner policy formlarını onayladı |
| **Faz 9** — Production rollout | Server allowlist → %20 → %50 → %100 | 1–2 hafta | Stabilizasyon; ana sistem referansı Android'i kapsayacak şekilde güncellendi |

**Toplam kaba tahmin: 15–20 hafta.** Kritik yol Faz 0 ve GATE-11'dir; ikisi de geliştirmeden bağımsız olarak **hemen** başlatılabilir.

---

## 11. Backend değişiklik listesi — kesinleşmiş

Faz 2'de yapılacak additive migration'lar (isimler öneri, uygulanmadan önce mevcut şema tekrar okunur):

```text
1. push_device_tokens
   - platform CHECK: ('ios') -> ('ios','android')              [F1]
   - + provider text ('apns'|'fcm'), default 'apns'
   - + provider_environment text null                          [F2]
   - + application_id text null
   - + installation_id uuid null
   - + client_build text null
   - unique(user_id, token) korunur

2. analyses / ai_usage_logs / usage_events / paywall_events / reports
   - + client_platform text null                               [E8]
   - + client_installation_id uuid null
   - iOS backfill kontrollü ve tarih koşullu

3. user_subscriptions / subscription_events
   - + store text ('APP_STORE'|'PLAY_STORE'|'UNKNOWN')         [F11]
   - + base_plan_id text null
   - + offer_id text null
   - + store_transaction_id text null
   - source alanı DEĞİŞMEZ (ingestion yolu anlamı korunur)
   - trial_product_id CHECK'i DEĞİŞMEZ (Play ürün ID'si aynı)  [F7]

4. user_device_installations (yeni tablo)
   - owner-only RLS, server now(), auth.uid()
   - unique(user_id, platform, application_id, installation_id)

5. app_feature_flags
   - + enabled_android_version_codes alanı (mevcut flag'lere)
   - + android_client_enabled / android_auth_enabled /
     android_analysis_submit_enabled / android_payments_enabled /
     android_notifications_enabled / android_pdf_reports_enabled /
     android_release_policy
   - hepsi başlangıçta kapalı

6. record_notification_delivery_attempt_v2(...)               [F4]
   - provider-agnostik message ID
   - v1 korunur ve v2'ye delege eder
```

Kod tarafı:

```text
analyze/index.ts
  - clientBuildMatches(platform-aware)                          [F3]
  - min_ios_build karşılaştırmaları platforma bağlanır
  - client_platform persist edilir                              [E8]
  - client_capabilities sözleşmesi contracts/ altına dondurulur  [F5]

send-push-notification/
  - providers/apns.ts (mevcut kod, davranış değişmez)           [F4]
  - providers/fcm.ts (yeni)
  - dispatch(token) ince katman

revenuecat-webhook/index.ts
  - store alanı okunur ve normalize edilir                      [F11]
  - PLAY_STORE event fixture testleri

app-release-policy/index.ts
  - platform=android -> android_release_policy                  [F9]
```

Her madde için: iOS fixture regresyon testi + Android fixture testi + unknown platform fail-closed testi + rollback notu.

---

## 12. Karar defteri — güncellenmiş

Orijinal DEC-01…15 korunur. Eklenenler:

| ID | Karar | Önerim |
| --- | --- | --- |
| DEC-16 | Certificate pinning v1'de olsun mu? | **Hayır.** Post-launch, runbook tamamlanınca |
| DEC-17 | Play Integrity v1'de olsun mu? | **Hayır.** Post-launch shadow |
| DEC-18 | Local DB (Room) v1'de olsun mu? | **Hayır.** DataStore + dosya yeterli |
| DEC-19 | Modül granülaritesi | **Sadeleştirilmiş set** (~11 modül, 32 değil) |
| DEC-20 | Play In-App Review + In-App Updates | **Evet**, Faz 8 |
| DEC-21 | Install Referrer attribution | **Evet**, Faz 8 (reklam ölçümü için gerekli) |
| DEC-22 | Firebase Analytics | **Hayır.** Yalnız Crashlytics + first-party event |
| DEC-23 | Rollout kademeleri | **beta → %20 → %50 → %100** (küçük kullanıcı tabanı) |
| DEC-24 | Sunucu tarafı kanonik PDF | v1 hayır; parite 2 sürüm üst üste kırılırsa ADR aç |

Ayrıca DEC-14'e zorunlu not: **Google Play product ID'leri iOS ile birebir aynı olmalıdır** (`riskdetected_plus_monthly`, `riskdetected_plus_yearly`, `riskdetected_pro_monthly`, `riskdetected_pro_yearly`) — aksi hâlde `user_subscriptions_trial_product_check` ve cancelled-trial route'u birlikte değişmek zorunda kalır.

---

## 13. Risk kaydı

| Risk | Olasılık | Etki | Azaltma |
| --- | --- | --- | --- |
| Play kişisel hesap → 14 gün closed testing zorunluluğu | Orta | Takvimde 2+ hafta | GATE-11, Faz 0'da başlat |
| Apple web OAuth client secret süresi dolar | Orta | Android girişi tamamen durur | GATE-12 rotasyon alarmı + runbook |
| Build allowlist platform çakışması (F3) fark edilmez | Düşük (düzeltilirse) | Android'de kontrolsüz özellik açılması | Faz 2'de kod düzeltmesi + Deno testi |
| Android FCM token yazılamaz (F1/F2) | Yüksek (düzeltilmezse) | Push hattı hiç çalışmaz | Faz 2 migration |
| Legal doküman sürümü Firebase nedeniyle güncellenir | Yüksek | **iOS kullanıcılarına da onay ekranı çıkar** | Sürüm zamanlaması owner ile planlanır |
| İki renderer PDF paritesi zamanla ayrışır | Orta | Rapor tutarsızlığı | Parite golden testleri + DEC-24 tetikleyicisi |
| iOS'un mevcut açık borçları (build 81 commit'siz) Android işini kirletir | Yüksek | Rollback referansı yok | GATE-00 mutlak önkoşul |
| Kapsam genişliği tek geliştiriciyi boğar | Yüksek | Proje yarıda kalır | Bölüm 7 kapsam kesintileri |
| OTP kotası iki platform arasında paylaşılır | Orta | Giriş yapamama | GATE-13 |

---

## 14. Final onay cümlesi

Orijinal planın 40. bölümündeki cümle korunur; şu iki koşul eklenir:

> Android public yayınına ancak (a) canlı iOS `1.3.1 (81)` kaynağı bir tag'den yeniden üretilebiliyorsa, (b) `platform=android` istekleri hiçbir iOS build allowlist'ini açmıyorsa, (c) Android push token'ları production şemasında geçerli biçimde saklanabiliyorsa, (d) Google Play entitlement'ı backend doğrulaması olmadan hiçbir capability açmıyorsa ve (e) tüm bunlar iOS regresyonu üretmeden kanıtlandıysa geçilir.

Bu maddelerin herhangi biri kanıtsızsa production rollout yapılmaz.

---

## Ek: Bu incelemede kullanılan doğrulama komutları

```bash
node scripts/rd_ops_env.mjs status
```

```sql
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid in ('public.push_device_tokens'::regclass,
                   'public.analyses'::regclass,
                   'public.user_subscriptions'::regclass)
  and contype = 'c'
order by conrelid::text, conname;
```

```bash
grep -n "clientBuildMatches" -A 12 supabase/functions/analyze/index.ts
```

```bash
grep -n "client_capabilities" -A 8 supabase/functions/analyze/index.ts
```

---

**Belge sonu.** Android public release sonrasında bu belge tarihsel inceleme kaydı hâline gelir; otorite güncellenmiş ortak sistem referansına geçer.
