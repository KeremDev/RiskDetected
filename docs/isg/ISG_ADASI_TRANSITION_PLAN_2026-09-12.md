# RiskDetected → İSG Adası — ayrıntılı geçiş ve doğrulama planı

Tarih: 12 Eylül 2026 · Durum: planlama tamamlandı, uygulama/yayın başlamadı · Dil: Türkçe

## 0. Bu dosya nasıl kullanılacak?

**13 Eylül son durum — P05 kapandı:** P05'e ait geliştirme ve katmanlı yerel kabul (iki gerçek native SDK→DB zinciri, tarihli/hiyerarşik ekranlar, restart/foreground ve bağımsız SQL doğrulaması) tamamlandı. Canlı migration/rollout ve mağaza yayını yapılmadı. [Kapanış ve fazlar arası kabul sınırları](P05_CLOSURE_2026-09-13.md). Aşağıdaki önceki tarihli paket açıklamaları tarihsel kayıttır.

**13 Eylül kullanıcı değişikliği — P05:** Yeni personelde yalnız ad soyad zorunlu; firma mevcut kapsamdan alınır. Başlangıç/işe giriş ve bitiş/çıkış sorulmaz, bilinmeyen tarih bugüne tamamlanmaz. Departman varsa listeden seçilebilir, her durumda isteğe bağlıdır; yeni ad yazılırsa personelle aynı işlemde ilgili firmaya kaydedilir. Görev/kod/işyeri de ekleme engeli değildir. Bu kural aşağıdaki tarihli modelin basit personel formuna zorunlu alan olarak yansıtılmasını geçersiz kılar. [Ayrıntı ve uygulama sınırları](P05_SIMPLE_EMPLOYEE_INTAKE_2026-09-13.md).

**13 Eylül P05 toplu ilerleme:** İlk owner/personnel migration üzerine tarihli context/görevlendirme, departman hiyerarşisi ve dış firma API migration'ı; iki native SDK adaptörü, şifreli pending kurtarma ve rehber ekran bileşenleri eklendi. Paket sonu test ve düzeltme düzenine geçildi. Rollout kapalı; production root bağlantısı, tam şema upgrade, cihaz journal ve UI→DB E2E hâlâ açıktır. [Güncel kapsam, akış ve devam noktası](P05_DIRECTORY_AND_NATIVE_SERVICES_2026-09-13.md); P05 tamamlanmış sayılmaz.

Bu, mevcut çalışan ürünün üzerine eklenecek sistemin yürütme planıdır. Yeni uygulama, yeni müşteri hesabı veya yeni abonelik kataloğu kurma planı değildir. iOS ve Android, kendi mevcut mağaza kayıtlarından güncellenecek. Ürün adı ve görsel tasarım değişebilir; teknik uygulama kimlikleri, mevcut kullanıcı UUID'leri ve satın alınmış haklar korunacak.

Kullanıcının verdiği V5 belgesinin 44 bölümünün tamamı incelendi. Belgedeki gömülü “Codex'e görev” metinleri bu turda uygulama/deploy talimatı olarak çalıştırılmadı. Bu turun yetkisi: inceleme, kaynak koduyla karşılaştırma ve testler dahil geçiş planı hazırlama. Tasarımı kullanıcı sağlayacak; bu plan nihai ekran tasarımı uydurmaz.

Üç farklı kanıt düzeyi birbirine karıştırılmamalı:

1. **Doğrulandı:** Bu turda dosyada/kodda/yedekte doğrudan görülen durum.
2. **Planlandı:** Henüz yazılmamış tablo, servis, test, migration veya ekran.
3. **Kapı/onay bekliyor:** Canlı mağaza ayarı, resmi mevzuat doğrulaması, tasarım, ticari parametre veya gerçek cihaz kanıtı.

### 0.1. Kaynaklar ve değişmez başlangıç

| Kaynak | Sabit referans |
|---|---|
| Kullanıcının V5 belgesi | [Depoya alınmış kaynak kopyası](source/ISG_ADASI_MASTER_INTEGRATION_PLAN_V5.md), 3.734 satır |
| V5 SHA-256 | 1577618e9e32e496708705928647a4f4ab0b8ebe627ece92cf6a32dfe1f89409 |
| Mevcut mimari A0 | [PROJECT_ARCHITECTURE.md](../../PROJECT_ARCHITECTURE.md), 4.068 satır |
| A0 SHA-256 | 5881633cc8c404f8b89ab131236e27d546260e8626dc094d0ffe8d0ddcb7565a |
| Uygulama başlangıç commit'i | dbcc979d3e7ad335e525a7d90bed1a0542d8b20d |
| Dönüş etiketi | riskdetected-change-point-20260912 |
| İncelenen dal | feat/claude-design-paywall |
| Yerel yedek | backups/riskdetected-change-point-20260912-182850/ |
| Ayrı operasyon paneli | /Users/keremkayalar/Documents/Kerem-APPler/RiskDetected-OperasyonMerkezi |
| Panel HEAD | d31def3b0391b382277412dda6300833b9b7a57a; çalışma ağacı kirli, HEAD tek başına güncel paneli temsil etmiyor |
| Kaynak kabul testleri | [V5_ACCEPTANCE_TEST_REGISTRY.csv](V5_ACCEPTANCE_TEST_REGISTRY.csv): 203 benzersiz, bölümle adlandırılmış senaryo |

Kaynak kopyası değiştirilmez. Revizyon gelirse yeni kaynak/hash ve gereksinim farkı oluşturulur. Bu planın yeni dosyaları başlangıç commit'ine dahil değildir; eski dönüş noktası yerinde kalır. Bu turda yeni commit, push, canlı DDL, mağaza ayarı veya yayın yapılmadı.

### 0.2. Okuma rotası

- Yönetim ve sıra: §§1–4, 15–18.
- Veri/API/domain tasarımı: §§5–11.
- Her varyasyonu nasıl test edeceğiz: §§12–14 ve 203 satırlık kaynak test kaydı.
- Kararlar, riskler, kaynak kapsamı: §§19–21.

## 1. Önerilen geçiş stratejisi

Tek seferde yeniden yazım yerine, mevcut uygulamayı koruyan eklemeli bir dönüşüm uygulanacak:

~~~text
Mevcut ürün + ölçülmüş başlangıç + geri yükleme provası
  → ortak sözleşme / güvenlik / izleme / hak altyapısı
  → şirket-işyeri-personel + dosya-belge + olay-süre altyapısı
  → tek tek tamamlanan İSG modülleri ve iki mobil adaptörü
  → tüm modüller için evrak / import / takip / skor entegrasyonu
  → tasarımın uygulanması + eski sürümden yerinde güncelleme testleri
  → kontrollü mağaza güncellemesi + genel eski abone hak geçişi
  → gözlem / düzeltme / çok sonra ayrı temizlik kararı
~~~

Her dilim kendi migration, API, iOS, Android, test, hata görünürlüğü, erişim kuralı ve kapatma mekanizmasıyla tamamlanır. Sadece ekranı olan, verisi/kuralları/testi olmayan modül “bitti” sayılmaz. Ortak sözleşmenin tek sahibi olur; Swift/Kotlin'de bağımsız iş kuralı icat edilmez.

Üç erken doğrulama kritik yolu kısaltır:

- Mağazada aynı aylık ürün/plan üzerinde bir dönem indirim gerçekten uygulanabiliyor mu? Bunu kampanya UI'sı tamamlandıktan sonra değil, başlangıçta izole bir prova ile öğrenmek gerekir.
- Mevzuat kataloğundaki 2026 hükümleri hangi resmi metin ve yürürlük sürümüyle çalışacak? Belirsiz kural otomatik uygunluk veremez.
- Eski kullanıcıların hakları ve uygulama güncellemesi sırasında oturumları gerçekten korunuyor mu? En sonda sadece temiz kurulum testi yeterli değildir.

## 2. Kodla doğrulanmış mevcut durum ve V5 farkları

### 2.1. Teknoloji ve mevcut varlıklar

| Alan | Görülen mevcut durum | Geçiş kararı |
|---|---|---|
| iOS | SwiftUI; Xcode projesi; minimum iOS 16; kaynak sürüm 2.0.3/build 91 | Native yapı korunur; yeni feature/service katmanları eklenir |
| iOS bağımlılık çözümü | Yerel Package.resolved: RevenueCat 5.72.0, Supabase Swift 2.46.0, Facebook SDK 18.1.1 | Gerçek kilit dosyasının takibi ve tekrarlanabilir çözüm P00'da doğrulanır; sırf dönüşüm için SDK yükseltme yapılmaz |
| Android | Kotlin/Jetpack Compose; minSdk 26, compile/target 37; kaynak 2.0.2/versionCode 14; Java 17 | Native modüler yapı ve ortam ayrımı korunur |
| Android sürüm kataloğu | AGP 9.3.1, Kotlin 2.4.10, Compose BOM 2026.06.01, RevenueCat 10.16.1, Supabase-Kt 3.7.0 | Wrapper'ın gerçek API davranışı bu sürümlerle test edilir |
| Backend | Supabase PostgreSQL/Auth/Storage, Deno Edge Functions; analiz iş kuyruğu/worker'ları | Aynı backend, yeni bounded domain'ler ve ayrı ağır dosya worker'ı |
| Mevcut kaynak envanteri | 27 Edge index.ts; supabase/tests altında 50 dosya; Android test/androidTest altında 54 Kotlin dosyası | Bunlar dosya sayısıdır, test sayısı veya test başarısı değildir |
| Android test altyapısı | JUnit, Robolectric, MockWebServer, Turbine, Compose UI, Roborazzi; iki GitHub workflow | Yeni feature başına genişletilir |
| iOS CI | İncelenen GitHub workflow'larında eşdeğer iOS hattı yok | macOS/Xcode koşucusu ve XCTest/XCUITest hattı kurulması zorunlu |
| Operasyon paneli | React 19, Vite 8, TypeScript 6, TanStack Query, Tailwind 4, shadcn/Radix; Vercel API + Supabase; Cloudflare yönlendirme | Yeni panel kurulmaz; ayrı repo sözleşmesiyle genişletilir |
| Panel güvenlik sözleşmesi | JWT + aal2 MFA + aktif admin_users + backend scope; service role yalnız sunucuda | Yeni kampanya/dosya/telemetry endpoint'lerinde de aynı sınırlar; her endpoint test edilir |

Bu sürümler kaynakta görülen değerlerdir; mağazada şu anda hangi binary'nin dağıtıldığını veya sürümün en güncel olduğunu ispatlamaz. P00 mağaza manifest'i bu farkı kapatır.

### 2.2. Planı değiştiren somut bulgular

| No | Kanıt / dosya | Sonuç ve yapılacak iş |
|---|---|---|
| B01 | RiskDetected.xcodeproj/project.pbxproj: iOS bundle com.riskdetected.app | Yeni ad için bundle değiştirilmez |
| B02 | android/app/build.gradle.kts: Android applicationId/namespace com.riskdetectedan.app | Android ID iOS'tan farklıdır; “eşitleme” kesinlikle yapılmaz |
| B03 | App/Services/AuthService.swift: signInWithPassword zaten mevcut | iOS parola girişini yeniden yazma; kayıt/doğrulama/parola ekleme/recovery yolunu mevcut bootstrap'a bağla |
| B04 | Android AuthRepository: OTP, Google ve Apple yolları mevcut; parola yolu tespit edilmedi | Android parola giriş/kayıt/recovery adaptörü ayrıca gerekir |
| B05 | private.company_limit_for_user: Plus 5, Pro 25; migration ve 12 Eylül SQL snapshot'ında aynı | Yeni aday Plus 3 limiti eski Plus hakkını 5'ten 3'e indiremez; Pro hedef 30 artış olur |
| B06 | company_limit_for_user, enforce_company_write_rules, company RLS ve diğer paid helper'lar mevcut | Gift erişimi sadece istemcide açılmaz; SQL/RPC/Edge'lerin tümü aynı capability kararına bağlanır |
| B07 | Android BillingRepository: aynı tier+ürün için mevcut aboneliği döndürüp checkout'u atlıyor; mevcut replacement genel seçimleri var | İndirim için ayrı offer-context satın alma yolu; normal purchase guard'larını gevşetmeden aynı-plan testi |
| B08 | iOS SubscriptionManager: RC purchase/receipt-owner/sync mevcut | İmza/offer adaptörü bu akışı kullanır; aynı UUID ve receipt-owner doğrulaması korunur |
| B09 | App/Services/RDConfig.swift: prod Supabase varsayılanı + env/bundle override; mevcut legal ve callback URL'leri | Test değişkeni unutulunca production'a düşmeyi engelleyen assert gerekir; marka için callback toplu değişmez |
| B10 | Android debug/qa suffix'leri; debug özel smoke seçeneği suffix'i kaldırabiliyor | CI ve test runner'da release paketine yanlış kurulum/dış bağlantı koruması |
| B11 | scripts/release_staging_guard.mjs | Adındaki staging, Git staging alanını ifade ediyor; gerçek test ortamı izolasyonu sanılmamalı |
| B12 | scripts/run_ui_tests.sh: global killall ve sonuç yolu temizleme davranışı | Yeni otomasyonda PID kapsamlı süreç yönetimi ve benzersiz çıktı dizini; mevcut script körlemesine çalıştırılmaz |
| B13 | reports.analysis_id ve method zorunluluğu; mevcut analiz odaklı raporlama | Yeni eğitim/atama/tutanak için sahte analiz satırı açılmaz; ayrı documents/export modeli |
| B14 | findings.responsible/deadline legacy metin; is_resolved mevcut işaret | Yeni tarihli DÖF/uygunsuzluk lifecycle'ı ayrı; sessiz çift yönlü eşitleme yok |
| B15 | Mevcut notification türleri CHECK + legacy üreticiler | Yeni tipler eski kuyruğa rastgele yazılmaz; producer ownership ve uyumluluk adaptörü |
| B16 | client_flow_events sözleşmesi; panelde mobileTelemetry dahil commitlenmemiş işler | “Mobil sağlık” teknik uygulama sağlığıdır, çalışan sağlık verisi değildir; gönderim öncesi kopuşlar ayrıca izlenir |
| B17 | Panel repo kirli; ana repo etiketi onu kapsamaz | P00'da panelin kullanıcı değişikliklerini koruyan ayrı checkpoint/manifest gerekir; bu tur panel değiştirilmedi |

İlgili kaynaklar: [AuthService](../../App/Services/AuthService.swift), [RDConfig](../../App/Services/RDConfig.swift), [SubscriptionManager](../../App/Services/SubscriptionManager.swift), [Android build](../../android/app/build.gradle.kts), [ilk şirket migration'ı](../../supabase/migrations/20260520154818_add_companies.sql), [şirket V2 kuralları](../../supabase/migrations/20260527212739_add_company_v2_fields.sql), [Android CI](../../.github/workflows/android-ci.yml).

### 2.3. Yedekle ilgili düzeltilmiş kanıt

Yerel yedekte schema/data/roles SQL, Git bundle, kaynak/platform/artifact arşivleri ve Storage dosyaları var. Data SQL'de 131 COPY bloğu; bunların arasında auth.users, auth.identities ve storage.objects da var. auth.users bloğunda 208 satır doğrudan sayıldı. Önceki “Auth kullanıcıları dump'ta yok” yorumu doğru değildir.

Bununla birlikte, Auth verisinin bulunması restore'un çalıştığını ispatlamaz. Yönetilen Auth/Storage şema sürümleri, extension'lar, migration geçmişi, bucket/policy'ler, dosyalar, provider ayarları, server secrets, imzalama erişimleri ve dış servis konfigürasyonları birlikte doğrulanmalı. Restore provası yapılmadı. Aynı makinedeki tek kopya felaket kurtarma için yeterli değildir. Ayrı operasyon panelinin güncel çalışma ağacı da ana uygulama yedeğiyle otomatik korunmuş sayılmaz.

P00 bu eksikleri kapatmadan riskli uygulama fazına geçilmez. Hassas SQL ve ham müşteri dosyaları Git'e, plan eklerine, test fixture'larına veya normal CI artifact'larına konmaz.

## 3. Değişmeyecek kimlikler ve marka sınırı

### 3.1. Kimlik koruma manifest'i

| Alan | Korunacak değer / davranış | Otomatik kanıt |
|---|---|---|
| iOS production bundle | com.riskdetected.app | Build settings + imzalı IPA/entitlements karşılaştırması |
| Android production applicationId | com.riskdetectedan.app | Birleştirilmiş manifest + AAB/APK incelemesi |
| Android namespace | com.riskdetectedan.app | Kaynak/build assert; ilk dönüşümde paket refactor'ı yok |
| Mağaza kayıtları | Mevcut App Store Connect / Play Console kayıtları | Read-only manifest diff; yeni app-create operasyonu bulunmamalı |
| Apple numeric app kaydı | RDConfig URL'sinde 6769498181; canlı kayıt P00'da doğrulanır | Aynı store record'a upload ilişkilendirmesi |
| İmzalama | Aynı Apple team/App ID ve keychain access group'ları; Android mevcut app signing zinciri | Sertifika fingerprint/entitlement manifest'i; gizli anahtar içermez |
| Abonelik | Mevcut product ID, entitlement plus/pro, subscription group/base plan ve RC proje eşlemeleri | Katalog snapshot diff + restore purchase testi |
| Kullanıcı | Supabase Auth UUID = profile owner; RC AppUserID mevcut normalize UUID sözleşmesi | Önce/sonra UUID, ownership ve receipt-owner karşılaştırması |
| Auth dönüşü | io.supabase.riskdetected://login-callback ve mevcut OAuth allowlist | Sıcak/soğuk başlangıç, eski e-posta linkleri, Apple/Google dönüşleri |
| Push | Mevcut APNs topic/Firebase uygulaması/FCM eşlemeleri | Güncelleme sonrası token refresh + gerçek cihaz alım testi |
| Yerel veri | Keychain service/account anahtarları; Android şifreli saklama/cache isimleri | Kaldırmadan update; oturum, pending işler, tercihler ve dosya referansları korunur |

Marka için görünür ad, ikon, splash, onboarding, yardım, şablon üstbilgisi ve mağaza metinleri değişir. Teknik sabitler için global “RiskDetected → İSG Adası” replace yapılmaz. Eski rapor snapshot'ları yeniden markalanmaz. Yeni belge yeni şablon sürümü kullanır. Eski URL'ler, QR'lar, yasal belge kabul sürümleri ve callback'ler çalışmaya devam eder; domain değişimi ayrıca yönlendirme ve sahiplik planı ister.

Apple mevcut kayıt adını yeni sürümle değiştirmeye izin verirken yüklenmiş bundle kimliğini sabit kabul ediyor. Android'de yayımlanmış applicationId de uygulama kimliğidir. Bu nedenle kullanıcı isteğiyle uyumlu yol aynı kayda güncellemedir. [Apple uygulama bilgileri](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [Android release kimliği](https://developer.android.com/studio/publish/preparing).

## 4. Kesin sınırlar ve çözülmesi gereken çelişkiler

### 4.1. Ürün değişmezleri

- Tek uygulama kullanıcısı uzman. Firma yetkilisi, eğitici, çalışan ve taşeron kişi kayıtları rapor kişisidir; yeni Auth kullanıcısı, portal, onay rolü veya bildirim alıcısı değildir.
- Çalışan muayenesi, teşhisi, aşısı, sağlık uygunluğu, sağlık raporu var/yok alanı, sağlık tarihi/takvimi kapsam dışı. JSON, ek alan, import veya telemetry içinde dolaylı depolanması da kapsam dışı.
- Eğitimde sağlık konu grubu ve ilk yardım eğitim/belgesi olabilir; bu kişisel sağlık gözetimi değildir.
- Çalışma izni modülü form hazırlama/arşivdir; fiziksel çalışmaya izin veren, kapı açan veya çoklu onay yöneten sistem değildir.
- ISG-KATIP alanı manuel sözleşme/evrak takibidir; resmi sisteme kullanıcı adına giriş/scrape/otomatik bildirim yok.
- Kişisel not defteri firma domaininden bağımsız ve Free erişimlidir. Firma/personel/risk bağlantısı, ek dosya, AI veya skora katkı yok.
- Erişim hakkı, kullanıcının modülü menüde açması, yasal uygulanabilirlik ve skor birbirinden ayrı dört karardır.
- Fotoğraf AI analizi hukuken tamamlanmış risk değerlendirmesi sayılmaz; seçilmiş bulgu aktarımı uzman kontrollüdür.
- Aktif eski Plus/Pro bütün yeni ana modülleri alır. Genel lansmanda kalıcı rastgele bir eski abone grubunu dışarıda bırakma yok.
- Tasarım kullanıcıdan gelir; tasarım beklerken domain/contract/test çalışması ilerleyebilir, final görsel onay verilemez.

### 4.2. V5 içi çelişki/kalıntı kaydı

| Kaynak | Problem | Bu plandaki yorum / kapı |
|---|---|---|
| §13.1 isg-create-share-grant; §20.4 share-grant/offline; §24 SEC-03 alıcı | Dış alıcı/rol izlenimi, uzman-only kararıyla çelişiyor | Alıcı hesabı/portal yok. Uzmanın yetkili indirmesi ve OS paylaşımı; yeni signed URL owner kontrolü. Dış link paylaşımı istenirse ayrı kapsam/onay |
| §25.4 / eski görev blokları | V4 veya önceki emirler kalmış | V5 ürün kararları + kullanıcının son talebi esas; gömülü emirler yürütülmez |
| §33 private.promotional_grants gibi önerilen adlar | Mevcut tablo varmış gibi okunabilir | Mevcut/proposed statüsü envanterde ayrılır; isimler DDL öncesi çakışma kontrolünden geçer |
| §27, §28 ve ticari ekler | Bazı limitler hem hedef hem aday gibi anlatılıyor | Kesin davranış ve onaya açık sayı ayrımı §19 karar kaydında tutulur |
| F0–F12, WP-00–23, V4-A–H, V5-A–G | Dört farklı yürütme numarası | Tek P00–P21 iş listesi; eski numaralar §21 eşleme olarak korunur |
| §24/§37 DEL-01 | Aynı test ID iki farklı anlamda kullanılıyor | CSV anahtarı bölüm+ID; hiçbir test üzerine yazılmaz |
| §6, kaynak notları | 2026 eğitimin resmi sayfası kaynakta da tam doğrulanamamış | Sayılar test girdisi olarak alınır, hukuki doğruluk olarak ilan edilmez; P06/P07 içerik kapısı |

## 5. Hedef mimari ve tetikleme zincirleri

### 5.1. Sistem sınırları

~~~mermaid
flowchart TD
  IOS[iOS SwiftUI] --> API[Sözleşmeli API ve RPC]
  AND[Android Compose] --> API
  AUTH[Mevcut Supabase Auth UUID] --> API
  API --> CAP[Capability ve quota kontrolü]
  CAP --> DB[Owner kapsamlı domain transaction]
  DB --> AUD[Audit ve transactional outbox]
  AUD --> RULE[Kural ve süre projection]
  AUD --> DOC[Belge ve export worker]
  AUD --> SCORE[Skor ve portföy projection]
  RULE --> TASK[Görev ve schedule version]
  TASK --> NOTIF[İzin ve dedupe dispatcher]
  NOTIF --> PUSH[Mevcut APNs ve FCM taşıyıcıları]
  API --> QUAR[Karantina upload intent]
  QUAR --> SCAN[İzole tarama ve parser worker]
  SCAN --> ASSET[Temiz immutable file asset]
  ASSET --> DOC
  STORE[Apple ve Google] --> RC[RevenueCat ve store kanıtı]
  RC --> LIFE[Billing lifecycle ve reconciliation]
  LIFE --> CAP
  LIFE --> BENEFIT[Gift ve discount defterleri]
  BENEFIT --> CAP
  ADMIN[Mevcut operasyon paneli] --> ADMAPI[MFA ve scope korumalı admin API]
  ADMAPI --> RULE
  ADMAPI --> BENEFIT
  API -. redacted olay .-> OBS[Birinci taraf teknik izleme]
~~~

Yeni dosya tarayıcı/render/import worker'ı Edge request süresine ve AI worker kapasitesine bağımlı tutulmaz. Teknoloji seçimi P04 spike'ında belirlenir: mevcut Edge orchestration korunur; dosya işlemleri ağ çıkışı kapalı, kaynak sınırlı ayrı işlem/container üzerinde çalışır. Antivirüs, format algılama, dönüştürücü ve renderer sürümleri image digest ile kilitlenir. Belge içeriği otomatik AI sağlayıcısına gönderilmez.

### 5.2. Ortak mutation sözleşmesi

Yeni write istekleri için önerilen alanlar: operation_id, client_mutation_id, expected_version, schema_version, company_id (yalnız şirket domain'inde), domain payload. user_id istemciden güvenilir kabul edilmez; JWT'den çıkarılır. Kişisel not DTO'sunda company_id ve entity bağlantıları hiç bulunmaz, bilinmeyen alan reddedilir.

~~~text
JWT doğrula → owner + capability → şema / kapsam / tarih doğrulaması
→ idempotency kaydını kilitle veya önceki sonucu döndür
→ expected_version kontrolü
→ domain + audit + outbox + gerekli quota reservation tek transaction
→ commit edilmiş sonuç / operation_id
→ bağımsız consumer'lar → projection ve kullanıcıya durum güncellemesi
~~~

Önerilen hata sınıfları: AUTH_REQUIRED, ACCESS_DENIED, CAPACITY_EXCEEDED, VALIDATION_ERROR, VERSION_CONFLICT, SCAN_PENDING, UNSUPPORTED_FORMAT, RULE_NEEDS_REVIEW, RETRYABLE_FAILURE, OPERATION_PENDING. Gerçek HTTP/JSON eşlemesi contracts/isg/v1 içinde dondurulur. Eski API hata biçimleri topluca değiştirilmez. 409 çatışmada güncel sürüm ve güvenli çözüm bilgisi verilir; başka müşterinin varlığı açıklanmaz.

Aynı mutation key farklı payload ile gelirse önceki sonucu sessizce başka işleme uygulamak yerine conflict. Pagination kararlı cursor; tarihler gün için DATE, olay anı için TIMESTAMPTZ; parasal tutarlar float değil mağaza currency/minor-unit sözleşmesi. Dosya boyutları byte, süreler instruction_minutes ve break_minutes olarak açık birimle tutulur.

### 5.3. Olay sahipliği ve hatalar

| Kaynak eylem | Atomik kayıt | Sonraki tüketiciler | Bağımsız kalan |
|---|---|---|---|
| Firma/işyeri sınıfı değişir | Context history + event | Applicability, eğitim ihtiyacı, risk süre incelemesi, task, skor | Eski belge snapshot'ı |
| Çalışan görevi değişir | Assignment history + event | Yeni ihtiyaç önerisi, plan/task incelemesi | Eski sertifikadaki görev/unvan |
| Eğitim tamamlanır | Completion + snapshot + event | Requirement, belge export, takip dönemi, skor | AI analiz kotası |
| Risk tam yenilenir | Yeni version + tarih + event | İlgili requirement/schedule, G4 review, skor | Önceki PDF ve diğer kapsamların geçmişi |
| Risk yeniden taranır | Yeni file variant + audit | Belge sunumu | Genel yasal yenileme tarihi |
| Uygunsuzluk kapanır | Verification/closure event | Kendi görevleri, timeline, skor politikası | Legacy findings.is_resolved kendiliğinden değişmez |
| Not düzenlenir | Owner note version + sync event | Sadece kişisel cihaz senkronu | Firma takvimi, campaign qualification, skor |
| Store olayı gelir | Dedupe + lifecycle evidence | Billing projection, capability, kampanya suppression/settlement | AI sonucu ve geçmiş doküman |
| Teknik telemetry çöker | Bounded queue/drop bilgisi | Sonradan flush | Domain transaction başarılı kalır |

Teslimat en az bir kezdir; exactly-once taşıma varsayılmaz. Consumer işlem kimliği (event_id, consumer_name) benzersizdir. Claim lease, retry/backoff, dead-letter, replay ve daily reconciliation gerekir. Commit sonrası worker çöküşü kullanıcı kaydını geri silmez. Projection bekleniyorsa UI “hesaplanıyor”; başarısızsa “yeniden denenecek/inceleme” gösterir, eski skoru yeni sonuç gibi sunmaz.

## 6. Veri modeli, geçiş dalgaları ve güvenlik

Bu bölüm DDL değildir. Tablo adları öneridir; mevcut DB/catalog ile çakışma ve tip kontrolünden sonra contracts ve migration dosyalarında kesinleşir. Mevcut tüm sütunlar A0'da kalır; burada yeni domain'lerin minimum zorunlu alanları ve bağlantıları tanımlanır.

### 6.1. Yeni tablolarda ortak sözleşme

Şirket domain'i: id UUID, company_id UUID, gerekiyorsa workplace_id UUID, version BIGINT, created_at/updated_at TIMESTAMPTZ, archived_at nullable, created_by UUID. Owner tek otorite companies.user_id üzerinden doğrulanır. Denormalize user_id kullanılacaksa değişmezlik/FK/trigger ile tutarlılık sağlanır; ikinci bir yetki kaynağı oluşturulmaz.

Cross-company parent ID atamasına karşı sadece RLS yetmez: (company_id, id) unique + composite FK; workplace bağlı çocuklarda (company_id, workplace_id, parent_id) kapsamı doğrulanır. Soft archive/historical referanslar için cascade delete varsayılan değildir. Finalize edilmiş kayıtlar değişmez, düzeltme yeni sürümdür. Kritik audit ve outbox yazımı başarısızsa domain mutation commit olmaz.

Private tablolar: app client GRANT yok, yalnız dar server RPC. SECURITY DEFINER fonksiyonları sabit güvenli search_path, explicit yetki, owner doğrulaması ve negatif rol testleri taşır. View/projection'lar RLS'yi dolanmaz. Service-role istemciye veya signed URL dışında dosya metadata'sına sızmaz.

### 6.2. Şema dalgaları

| Dalga / paket | Önerilen varlıklar ve önemli sütunlar | Bütünlük / lifecycle |
|---|---|---|
| D01 / P01 | mutation_receipts(key, actor, payload_hash, response, status); domain_outbox(event_id, aggregate_id, aggregate_version, type, schema_version, payload); consumer_receipts(event_id, consumer); domain_audit(actor, operation, entity, version, reason) | Unique mutation ve consumer; payload allowlist; lease/retry/dead-letter bilgisi; saklama süresi |
| D02 / P02 | Private auth_recovery_aliases(user_id, normalized_alias, verified_at, changed_at); auth method metadata gerekiyorsa mevcut identities'den türetilir | Parola/OTP uygulama tablosunda yok; unique alias, rate limit; eski UUID'yi değiştirme |
| D03 / P03 | plan_catalog/version; legacy_entitlement_floors(user_id, capability, value/unlimited, source, cutoff); quota_reservations(operation, quota_kind, period, amount, funding_source, state); settlement entries | Hesap+period kilidi; güncel kullanım otoritesi legacy kalır; infinity açık tip, NULL belirsizlik demek değil |
| D04 / P04 | upload_intents(owner, purpose, expected_size/hash, state, expiry); file_assets(bucket, immutable_path, detected_type, hash, bytes, scan_version, scan_status, preview_status); file_derivatives(source_hash, kind, renderer_version) | Karantina okunamaz; aynı path overwrite yok; promotion final hash tekrar doğrular; orijinal/türev ayrı |
| D05 / P05 | workplaces(company_id, code, name, timezone, jurisdiction); workplace_context_versions(effective_from/to, hazard_class, industry_code, evidence); departments; job_roles; employees(employee_code, display_name, employer_org_id, status); employee_assignments(employee, workplace, department, role, starts_on, ends_on, is_primary) | Firma içi unique code; isimden merge yok; tarih aralığı ve primary çakışma engeli; sağlık/TCKN varsayılan yok |
| D06 / P06 | legal_sources(url, checksum, retrieved_at, effective_at, verified_by); rule_versions(source, expression, jurisdiction, status); module_usage_preferences; applicability_decisions(state, reason, context_version, rule_version); requirement_instances(period, status); tasks; schedules(version, due_on, timezone, state) | DSL sınırlı; bilinmeyen needs_review; unique gereksinim+dönem+aksiyon; eski schedule invalidation |
| D07 / P07 | training_catalogs/versions; topic_groups/topics; company_curriculum_versions; training_plans; sessions; enrolments; attendance_intervals; assessment_attempts; completions; external_credentials | Catalog/version sabit; G4 snapshot; yoklama interval union; attempt/completion transaction; dış belge eğitimden ayrı |
| D08 / P08 | risk_assessments; risk_assessment_versions(kind, assessment_on, revision_on, scope, previous_version, source_snapshot, file_asset_id); risk_source_links(analysis_id, finding_id, source_version, copied_fields); revision_impacts | Tam/kısmi/metadata/tarama ayrımı; gerçek esas tarih; kaynak bulgu kullanıcı seçimi; optimistic lock |
| D09 / P09 | nonconformities(source_ref, opened_on, due_on, assignee_contact, state, severity); actions; verification_records; checklist_templates/versions; checklist_runs/items | Uzman kapatır; legacy text alanını tarih sanma; template yayınlandıktan sonra immutable |
| D10 / P10 | emergency_plan_versions; drill_records; equipment/inspection_records; service_contract_records; annual_work_plans/items; annual_training_plans; board_meetings/decisions; appointments; ppe_handovers/returns; notebook_records; permit_forms; contractor_organizations/engagements/person_links; site_visits/observations | Her biri kendi olay/tarih/evrak state'ine sahip; onay portalı/sağlık kapsamı yok; aynı çalışan ana kaydına link |
| D11 / P11 | documents(type, source_domain/id, current_version); document_versions(snapshot, snapshot_hash, template_version, document_no); export_jobs(format, state, asset_id, error_code); template_versions; import_batches/mappings/rows/commit_checkpoints | Mevcut reports'tan ayrı; numara allocation concurrency-safe; import preview hash/version; sağlık kolonunu JSON'a taşıma yok |
| D12 / P12 | isg_notification_jobs/episodes; consent provenance; rule/template_versions adaptörü; delivery_attempts(provider, state, failure); producer_ownership_registry | Mevcut preferences/device token ile uyum; send-time izin; eski CHECK'lere bilinmeyen kind yazma yok |
| D13 / P13 | personal_notes(user_id, title, body, version, tombstone); note_items; tags/note_tags; personal_reminders; reminder_occurrences; device_delivery_claims(installation_id, owner_strategy) | company_id/workplace_id/employee_id/entity_type/entity_id hiçbir seviyede yok; Free; body telemetry'ye girmez |
| D14 / P14 | billing_lifecycle_evidence/projection; benefit_definitions/instances; discount_quote/intents; store_offer_mappings; benefit_settlements(environment, store, transaction/order, billing_period); reconciliation_jobs | BillingTier/gift/effectiveCapability ayrımı; tek ödemeye family bağımsız unique settlement; pending/review state |
| D15 / P15 | referral_codes/claims; qualification_events; campaign_definitions/versions; winback_episodes; suppression/eligibility records; budget_reservations | Canonical account; yalnız server proof; one-time/period kuralı; consent kampanya ödül koşulu değil |
| D16 / P16–17 | Technical event envelope + allowlisted metadata; admin simulations/publishes/audit; score_policy_versions; score_snapshots/contributions; portfolio projections | Not/dosya metni yok; scope/MFA; score snapshot policy ile yeniden üretilebilir |

### 6.3. Backfill ve eski istemciyle birlikte çalışma

1. Yeni tablolar nullable/eklemeli açılır; eski tablo/kolon/enum/endpoint silinmez. Gerekli index'ler lock bütçesiyle oluşturulur; büyük constraint doğrulaması ayrı adım olabilir.
2. Mevcut firmaya tek default workplace oluşturulur. Unique legacy_company marker ile retry güvenlidir. Bilinmeyen jurisdiction/hazard_class uydurulmaz; needs_review.
3. companies.department serbest metni eski istemci için korunur. Tarihli personel ilişkisine sessiz dönüştürülmez. Kullanıcı eşleme/onayı ile yeni departman kurulabilir.
4. İlk backfill bittiğinde eski binary'nin oluşturduğu yeni şirketler catch-up/lazy initializer tarafından aynı kuralla kapsanır. Backfill “bir kere script çalıştı” ile tamamlanmaz.
5. Mevcut analizlerden otomatik risk assessment, onboarding cevaplarından personel eğitimi, finding metninden resmi son tarih üretilmez.
6. Eski paid kullanıcıların floor kaydı ölçülür. Kaynağı sözleşme/plan/istisna/kullanım diye ayrılır. Örneğin eski Plus hakkı 5 ise kullanıcının 1 firması olması floor'u 1 yapmaz.
7. Dry-run sayım/hata listesi → küçük batch → checkpoint → yeniden çalıştırma → catch-up → toplam/referans/ownership karşılaştırması. Kısmi başarısızlık görünür.
8. Okuma önce shadow; farklar açıklanır. Eski write otoritesi sadece açık cutover planıyla değiştirilir. Genel lansmana kadar destructive contract fazı yok.

### 6.4. Saklama ve silme

Her tablo/dosya sınıfı için owner, kişisel veri kategorisi, amaç, retention, silme sırası ve istisna gerekçesi data inventory'de tutulur. Hukuki süre uydurulmaz; onaylı politika gereklidir. Hesap silme mevcut request-account-deletion zincirine yeni verileri ekler: alias, notes, reminder occurrence, file quarantine, türev/orijinal, campaign, referral, attribution, projections ve tasks dahil.

Silme job'u idempotent olur; FK yüzünden sonsuz retry veya yeniden event üretimi olmaz. İlgili gelecek notification/schedule iptal edilir. Tutulması gereken mali/audit kayıtları minimum ve erişimi sınırlı hale getirilir; uygulama profilini yeniden yaratamaz. İndirilmiş dış kopyanın uzaktan silinemeyeceği ve kısa ömürlü URL'nin TTL sınırı dürüstçe belirtilir.

## 7. Domain bazında ayrıntılı çalışma ve test sözleşmesi

### 7.1. Firma, işyeri ve personel

Firma sahipliği güvenlik sınırıdır; bir firmada birden fazla işyeri ve işyerine ait farklı tehlike sınıfı/tarihçe olabilir. İşveren/taşeron ilişkisi kişi kaydından ayrıdır. Departman/görev değişimi yeni assignment aralığı açar. İşten ayrılma arşivleme yapar; eski eğitim/imza/teslim/rapor ilişkileri bozulmaz.

Testler: iki uzman, aynı uzmanın iki firması, bir firmada iki işyeri, aynı isimli iki çalışan, aynı kodun aynı/farklı firma sınırı, çakışan primary görev, geçmiş/future tarih, işveren değişimi, arşiv/yeniden etkinleştirme, eşzamanlı son kapasite slot'u, eski binary'den firma oluşturma, downgrade'de salt okunur firma seçimi.

### 7.2. Eğitim

~~~text
Sürümlü katalog + işyeri bağlamı + çalışan görevi
  → eğitim ihtiyacı / uzman incelemesi
  → plan → oturum(lar) → katılımcı → yoklama segmentleri
  → değerlendirme denemeleri → completion doğrulaması
  → değişmez tamamlanma snapshot'ı
  → belge export + geçerlilik/takip dönemi + skor contribution
~~~

Plan, gerçekleşmiş oturum ve completion ayrı kayıttır. Bir plan oluşturmak eğitimi tamamlamaz. Süre, yoklama aralıklarının birleşiminden hesaplanır; aynı dakikanın iki derste kredilendirilmesi engellenir. Ders süresi/mola ayrı alan; G4 toplamın içindedir. G1/G2/G3 resmi alt konu kodları ve G4 işyerine özgü içerik versiyonlanır. UI kısa başlığı resmi belge etiketini değiştirmez.

V5'ten alınacak, resmi içerik kapısı henüz geçmemiş fixture değerleri: ilk temel eğitim düşük/orta/yüksek sınıf için 8/12/16 ders; tekrar 8; G4 alt sınırı 2/3/4; tekrar periyodu 3/2/1 takvim yılı; 45 dakika ders + 15 dakika mola; başarı 60, en fazla 3 deneme; işe başlama için ayrı 2 saat ve temel eğitim için 3 ay iddiaları. Bu değerler burada mevzuat teyidi olarak sunulmuyor. Test oracle'ı, resmi sürüm onaylandığında o sürümle dondurulacak.

Özel eğitim ayrı catalog namespace'idir; adını “Temel İSG” yapmak eşdeğerlik yaratmaz. MYK hazırlık eğitimi MYK belgesi vermez. Dış sertifikalar issuer, tarih, geçerlilik, temiz dosya ve kaynakla ayrı kayıt olur. Görev/risk değişince G4 yeni taslak/review üretir; geçmiş imzalı belge mutasyona uğramaz.

Zorunlu test eksenleri: 3 sınıf × ilk/tekrar/işe başlama/özel/dış belge × yöntem × tam/eksik/çakışan katılım × eşik altı/eşik/eşik üstü başarı × deneme sayısı × geçmiş/yeni mevzuat × şirket/işyeri kapsamı. Desteklenen kombinasyonlar tamamlanır; desteklenmeyen her kombinasyon açık validation bekler. 59/60/61; 2/3/4 deneme; sınır dakika ±1; yıl sonu/29 Şubat; sınıf değişiminin effective date'i ayrı boundary'lerdir.

### 7.3. Risk değerlendirmesi

| İşlem türü | Yeni kayıt | Tarih/takip etkisi | Yasak davranış |
|---|---|---|---|
| Daha iyi tarama | File variant, kaynak hash, audit | Esas değerlendirme tarihi değişmez | Yeni yükleme gününü yenileme saymak |
| Metadata düzeltmesi | Düzeltme sürümü + gerekçe | İlgili yanlış bilgi düzelir; otomatik genel süre reset yok | Geçmiş belgeyi üzerine yazmak |
| Kısmi revizyon | Scope'lu version + impact list | Etkilenen risk/task/G4 review güncellenir | Bütün işyerinin vadesini sıfırlamak |
| Tam yenileme | Yeni esas version + uzman doğrulaması | Gerçek assessment_on ve doğrulanmış kural üzerinden yeni dönem | Dosya uploaded_at'i hukuki tarih saymak |

Fotoğraf analizi → sonuç ekranı → uzman seçimi → alan önizlemesi → source analysis/finding/version snapshot → ayrı risk kaydı. Kaynak analiz değişirse otomatik eski risk dokümanı değişmez; kaynak drift işareti/review önerilebilir. Aynı risk versiyonunu iki cihaz finalize ederse tek kazanan, diğerine conflict. Eski schedule kuyruğu varsa version kontrolü gönderimi durdurur. Tarih gelecekte/çok eski/bilinmiyor durumları ayrı validation/review kurallarıdır.

### 7.4. Uygunsuzluk, aksiyon ve checklist

Durum makinesi: draft → open → assigned → in_progress → pending_verification → closed; gerekçeli reopened ve cancelled dalları. Geçiş matrisi sunucuda tanımlanır; her allowed edge, her forbidden edge ve her edge'de yetki/sürüm/retry test edilir. Kontrolü uzman yapar; assignee_contact yeni uygulama kullanıcısı değildir. Kapanış kanıtı, tarih, doğrulayan ve audit tutulur.

Checklist template sürümü → saha run'ı → madde sonucu/kanıt → seçili uygunsuzluk oluşturma. Template güncellenmesi eski run'ı değiştirmez. Bir bulgu/aksiyon için tekrar tıklama mükerrer kayıt üretmez. Legacy finding çözüm işareti yeni lifecycle'ı otomatik kapatmaz.

### 7.5. Diğer bütün ana modüller

Her satır kendi CRUD/validation/archive/list/filter/detail/offline retry/owner/export testlerini de alır. “Ortak CRUD var” denilerek aşağıdaki domain kuralları atlanmaz.

| Modül | Veri ve temel akış | Tetiklenen bağımlılıklar | Modüle özel kabul |
|---|---|---|---|
| Acil durum planı | Plan sürümü, kapsam, tarih, ekip/kişi snapshot'ı, dosya | Rule/task, tatbikat bağlantısı, PDF/XLSX | Plan yenilenmesi eski belgeyi değiştirmez; bilinmeyen mevzuat review |
| Tatbikat | Plan referansı, gerçekleşme tarihi, katılım, gözlem, iyileştirme | Task tamamlama/aksiyon, belge | Planlamak gerçekleştirmek değildir; katılımcı scope'u |
| Ekipman/periyodik kontrol | Envanter, tür, seri/etiket, kontrol kaydı, sonuç, dış kanıt | Tür bazlı rule/due, aksiyon | Bütün ekipmana tek sabit yıl uygulanmaz; özel şart/istisna görünür |
| ISG-KATIP sözleşme takibi | Taraflar/uzman, kapsam, başlangıç-bitiş, belge | Hatırlatma, arşiv | Resmi entegrasyon/onay iddiası yok; boş bitiş ayrı durum |
| Yıllık çalışma planı | Yıl, faaliyet, sorumlu rapor kişisi, planlanan/gerçekleşen tarih | Task, rapor | Takvim yılı değişimi; carry-over gerekçeli; plan tamamlanma sayılmaz |
| Yıllık eğitim planı | İhtiyaç/katalog, hedef grup, plan oturumu | Eğitim planı, ihtiyaç/task | Gerçek completion ile aynı kayıt değil; mükerrer plan kontrolü |
| Kurul/toplantı/karar | Uygulanabilirlik, gündem, katılım, tutanak, karar/aksiyon | Task, belge, gerekiyorsa skor | Gönüllü kullanım ana yasal skoru etkilemez; toplantı için rol/portal yok |
| Görevlendirme | Temsilci/destek elemanı vb. tür, kişi, kapsam, süre, belge | İhtiyaç/due, rapor | Aynı kişinin tür/kapsam çakışmaları ve görevin bitişi |
| KKD teslim/iade | Malzeme, miktar/birim, kişi, teslim/iade tarihi ve kanıt | Belge, gerekirse follow-up | Negatif miktar/teslimden önce iade reddi; belge imzası otomatik varsayılmaz |
| Onaylı defter arşivi | Defter/entry referansı, tarih, temiz imzalı kopya | Evrak merkezi | Mevcut AI defter taslağından ayrı; AI metin resmi kayıt sayılmaz |
| Çalışma izni formu | Şablon, saha/iş, taraf kişi snapshot'ı; draft/rendered/archived; signed-copy göstergesi | Evrak, taşeron/personel referansı | “İş başladı/izin onaylandı” yetki makinesi yok |
| Taşeron/alt yüklenici | Organizasyon, engagement, iş kapsamı, tarih, gerçek işveren/personel linki, evrak | Eğitim/form/evrak ilişkisi | Çalışan duplicate üretilmez; alt yükleniciye Auth hesabı açılmaz |
| Saha ziyareti/gözlem | Yer/tarih, uzman notu, güvenli kanıt, seçili aksiyon | Follow-up, rapor | Kişisel not defteriyle birleşmez; sağlık/klinik alan açılmaz |
| Evrak/rapor merkezi | Arama/filtre, source domain, sürüm, PDF/XLSX, clean original | Export/import/storage | Legacy rapor ile yeni belge doğru kaynak türü; sahte analysis yok |
| Portföy/istatistik | Firma bazlı projection, süreç/dönem/kapsam | Skor ve task read model | Çok çalışanlı firma ağırlığı istenmeden bütün portföyü ele geçirmez |
| Ürün rehberliği | Contextual yardım, açıklama, kullanıcı tercihi | Presentation coordinator, allowlist telemetry | Hukuki uygunluk garantisi yok; eski opt-out reset yok |

## 8. Belge, dosya ve import omurgası

### 8.1. Dosya kabul matrisi

13 uzantı: pdf, jpg, jpeg, png, heic, heif, webp, avif, doc, docx, xls, xlsx, csv. Her uzantı her amaçta kabul edilmez. purpose alanı sunucuda doğrulanır; firma belgesi, kanıt, structured import ve logo ayrı politikalardır. Logo sadece desteklenen raster; kişisel notta attachment endpoint'i yok. Uygulama OS picker'ı gizlese bile API kapsam dışı formatı reddeder.

~~~text
Upload intent + kapasite rezervasyonu
  → private quarantine nesnesi
  → magic/type/hash/size doğrulama
  → AV + güvenli parser + kaynak limitleri
  → clean / rejected / scan_pending / scan_failed
  → yalnız clean için immutable promotion
  → metadata finalize + boyut settlement
  → izinli original URL / ayrı preview / gerekiyorsa import
~~~

Tarama servisi veya ağ hatası “clean” demek değildir. Preview hatası ile güvenlik taraması hatası ayrıdır: temiz orijinal korunabilir, önizleme üretilemeyebilir. İmzalı PDF orijinalinin byte/hash'i değişmez. Önizleme “orijinal” diye etiketlenmez. Tarama sonrası overwrite anti-TOCTOU ile engellenir. Tüm türev/temporary işler silme ve kota hesabında tanımlıdır.

P04 güvenlik spike'ı DOC/XLS için gerçek pozitif fixture ister; sadece uzantıyı kabul etmek yeterli değil. Macro/DDE/OLE/XXE, zip/path traversal, sıkıştırma bombası, aşırı piksel, bozuk font, embedded external resource, parola korumalı dosya ve MIME uyuşmazlığı ayrı sonuç üretir. Harici bağlantı çalıştırılmaz; formül hesaplanmaz. Cached hücre değeri varsa bunun önbellek olduğu belirtilir.

Aday kaynak limitleri V5'te 50 MiB belge, 10 MiB import, 10.000 satır/200 sütun olarak geçiyor; performans ve maliyet kanıtıyla P04/P11'de onaylanacak. Byte limitleri için 0, limit−1, limit, limit+1; decode sonrası bellek ve çıktı boyutu da test edilir.

### 8.2. Belge üretimi

Belgeye şirket adı/adres/logo, çalışan adı/görevi, tarih, kural ve template sürümü finalize anında snapshot olarak alınır. Kaynak nesneler sonradan değişse bile eski belge değişmez. Document number allocation firma/kapsam/yıl politikasına göre transaction-safe olmalı; 20 eşzamanlı export benzersiz numara üretir, retry aynı mantıksal belgeyi çoğaltmaz.

Her yapısal domain PDF ve XLSX parity alır. Aynı snapshot iki formatın ortak kaynağıdır. Tarama/imzalı PDF'den yapısal Excel uydurulmaz; Excel yalnız kaynak metadata/index döker. Boş veri, 1/1.000/10.000 satır, Türkçe karakter, çok uzun ad, tablo başlığı tekrarı, sayfa sonu, font fallback, dark-mode'dan bağımsız baskı, logo oranı, formül injection testleri gerekir. PDF görsel snapshot yanında metin/sayfa/snapshot hash; XLSX hücre/tip/formül bulunmaması ve yeniden açılabilirlik doğrulanır.

### 8.3. İçeri aktarma

~~~text
Dosya clean → tür seçimi → sütun eşleme → satır doğrulama
  → önizleme + açık hata/duplicate listesi + hedef kayıt sürümleri
  → uzman commit onayı → idempotent batch transaction/checkpoint
  → sonuç özeti + hatalı satırlar + event/reconciliation
~~~

Kimlik, isim benzerliğinden türetilmez. Excel 1900/1904 tarih sistemleri, TR ondalık virgül, saat dilimi, baştaki sıfırlar, CSV delimiter/encoding, boş/invalid tarih, yinelenen satır ve cross-company ID test edilir. Sağlık sütunları reddedilir; ham JSON içine saklanmaz. Veri anlamı belirsizse preview review ister.

Idempotency kapsamı firma+dosya hash+mapping version+mutation ID; kullanıcı aynı dosyayı farklı bilinçli amaçla işlerse açık yeni işlem gerekir. Preview sonrası kayıt değişirse commit conflict. Partial commit ancak kullanıcıya açık politika ile; varsayılan gizli yarım başarı yok. Compensation sadece bu batch'in oluşturduğu ve sonradan değişmemiş satırlara uygulanır; kullanıcı düzenlemesini geri silmez.

## 9. Kimlik, abonelik, kota ve kampanya akışları

### 9.1. Auth ve presentation coordinator

Yeni e-posta+parola kaydı → Supabase doğrulama kodu → doğrulama → mevcut finishSignIn/bootstrap → aynı profile/UUID/RC yapılandırması. Eski OTP ve Apple/Google korunur. OAuth kullanıcısına parola ekleme isteğe bağlı, atlanabilir ve aynı user üzerinde update'dir; provider parolası istenmez. Aynı ad/benzer e-posta yüzünden hesap/abonelik merge edilmez.

Parola kuralı V5: en az 8 karakter, ASCII büyük/küçük harf ve rakam; ek Unicode kabulü, karakter/byte üst sınırı ve SDK sunucu davranışı ortak fixture ile netleştirilir. Parola trim/kısaltma/log yok. Autofill/password-manager/paste çalışır. Alias 3–30 ASCII aday politikası, gizli e-posta çözümü, generic hata, rate limit ve recovery freshness gerektirir. Hesap bulunup bulunmadığını response/timing ile ifşa etmeme testi yapılır.

Global sunucu Auth politikası eski binary'yi de etkileyebilir; mobile feature flag tek başına izolasyon değildir. Staging'de eski OTP login, yeni signup OTP tipi, recovery deep link, expired/used link, resend cooldown, offline submit, interrupted verification, Apple relay teslimi ve link cold-start test edilir.

Modal önceliği: zorunlu hukuki işlem → kullanıcının başlattığı akış → bağlamsal bildirim → isteğe bağlı parola önerisi. Parola önerisi ile paywall/OS izinleri üst üste açılmaz. Dismiss/cooldown hesap/cihaz semantiğiyle belirlenir; güncellemede tekrar tekrar gösterilmez.

### 9.2. Hak otoritesi

~~~text
Doğrulanmış store lifecycle → BillingTier (gerçek ücretli durum)
Geçerli süreli sponsor gift → GiftCapability
Legacy sözleşme floor'u → CapacityFloor
Bu üç kaynak + quota policy → effective capabilities / izinli işlem
UI görünürlüğü bu sonucun tüketicisidir; hak kaynağı değildir.
~~~

Hedef ana modül erişimi Plus/Pro için ortak; fark kapasite/AI kotasında. Aday şirket sayıları Plus 3, Pro 30; depolama 5/50 GiB. Başlangıç personel/eğitim hard-limit olmaması V5 hedefidir; kötüye kullanım/kaynak koruması ayrı teknik sınırla açık anlatılır. Son ticari sayılar §19'da onaylanır.

Mevcut AI sayacı davranışı önce korunur: Free 1, Plus 10 standart/2 detay, Pro 40 standart/10 detay; mevcut dönem ve rapor tüketim kuralları A0/gerçek helper fixture'larıyla dondurulur. V5'te 150/750 rapor ve Free standart PDF sınırsız politikası da aynı envantere alınır. Gün/ay/lifetime gibi periyot anlamı UI yazısından tahmin edilmez; SQL otoritesiyle doğrulanır.

Legacy floor = onaylı eski sözleşme hakkı, yeni hak ve korunacak geçerli kullanımın en yükseği; sınırsız ayrı durum. Lansman cutoff'u belgenin tarihi değil, onaylı rollout anıdır. Geç güncelleyen mevcut abone de eligible kalır. Unknown/subscription-sync-pending kullanıcısını Free sayıp kampanya hediye üretme yok.

Expiry/downgrade'de eski kayıtları okuma/indirme/korunmuş export ve takip davranışı politika ile sürer; fazla şirket silinmez. Kullanıcı aktif düzenleme kapsamını seçer; fazla şirket salt okunur olabilir. Mevcut sonucu açmak ile yeni maliyetli rapor render etmek ayrılır; hangi yeni işlem ücretli/kotalı, API capability tablosunda açık olmalıdır.

### 9.3. Kota ve maliyet

Legacy sayaçlar başlangıç otoritesi kalır. Yeni ledger shadow karşılaştırma yapar, aynı işi iki sayaca ücretlendirmez. Yeni document/storage için atomik reserve → commit/settle veya kesin failure release. Provider cevap verip ağ koparsa hemen iade+yeniden üretim yok; operation reconciliation. Kullanılabilir sonuç bulunmayan teknik hata politikasının maliyet kaydı ile kullanıcı kotası ayrıdır.

Gift Plus7, server saatiyle aktif edilen 7×24 saatlik sponsor erişimidir; store auto-renew trial değildir ve mevcut kotayı resetlemez. Funding source sponsor olarak tutulur. İndirim kuponu ise capability/tier/quota vermez. Kontrol kapsamı: company helper/RLS, analyze, result hub, report export/register, premium notebook/training adapter'ları ve tüm paid guard envanteri. Backend reddederken UI açık kalma paritesi engellenir.

### 9.4. Store teklif adaptörü ve lifecycle

İlk teknik hedef: var olan aylık ürün üzerinde tek aylık %20 teklif; yeni abonelik ürün kimliği, normal fiyat değişimi veya otomatik plan yükseltme/düşürme yok. Eski fiyat kohortu korunur. Store'dan alınan gerçek fiyat/phase/currency gösterilir; UI'da fiyat×0,8 yapıp gerçek checkout farklı olamaz. Eski fiyat 100, liste 150, indirim 120 ise kullanıcı için avantaj yoktur; teklif gösterilmez veya ayrı onaylı çözüm gerekir.

iOS: aynı monthly product için promotional offer + doğru imza/nonce/application user bağlamı. RC wrapper'ın kullandığı sürümde destek ve yetkisiz istemcinin teklif imzası alma ihtimali spike ile doğrulanır. Sadece UI eligibility veya RC offering görünürlüğü güvenlik sınırı değildir; hak/quote server kontrolü gerekir. Apple imzalama anahtarı mobil uygulamaya konmaz. [Apple promotional offer](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions), [Apple imza kurulumu](https://developer.apple.com/documentation/storekit/setting-up-promotional-offers?language=objc).

Android: explicit SubscriptionOption/offer token yolu, doğru eski purchase token ve uygun replacement mode. Aynı auto-renewing subscription içi geçişlerde WITHOUT_PRORATION hedefi gerçek wrapper ile denenir; genel DEFERRED varsayımı kullanılmaz. Tam expired kullanıcı yeni normal offer purchase dalındadır. Developer-determined teklifin eski binary normal purchase akışınca otomatik seçilmemesi için rc-ignore-offer ve eski binary katalog testi gerekir. Bu etiket server yetkilendirmesinin yerine geçmez. [Google replacement kuralları](https://developer.android.com/google/play/billing/subscriptions), [RevenueCat offer seçimi](https://www.revenuecat.com/docs/subscription-guidance/subscription-offers).

Store sonucu ile DB aynı transaction değildir. Benefit akışı: earned → available/deferred → reserved → awaiting_store → scheduled (kanıt varsa) → consumed (indirimli ödeme kanıtı); kesin iptal available'a, belirsizlik review'a; refund adjusted'a. Timeout yeni iki checkout üretmemeli. Receipt'le paid erişim açılması, kampanya settlement servisinin geçici hatasına bağlanmaz.

Payment uniqueness anahtarı environment+store+transaction/order+discounted billing period; family anahtara eklenip aynı ödemeye referral ve winback avantajı iki kez bağlanamaz. Webhook duplicate/out-of-order, sync-before-webhook, linked token, restore/transfer conflict ve refund/revoke ayrı fixture'dır.

### 9.5. Davet ve geri dönüş

| Senaryo | Karar |
|---|---|
| Free davetçi + yeni uygun davetli | Her iki uygun taraf Plus7; aktivasyon açık eylemle, server kanıtlı |
| Aktif ücretli aylık Plus/Pro davetçi | Kendi mevcut monthly tier'ında bir dönem %20; davetli Plus7 |
| Yıllık davetçi | Yıllık indirime/otomatik aylığa dönüştürme yok; aday bankalama kararı §19 |
| Qualification | Doğrulanmış yeni hesap + farklı iki gün + Free ile yapılabilen başarılı gerçek işlem, V5 aday pencere/politikasıyla; yalnız heartbeat/not/view/başarısız analiz yeterli değil |
| Fraud | Canonical user, self/cycle/repeat/parallel guard; yalnız IP veya Apple relay kullanımı kötüye kullanım kanıtı değil |
| Winback | Gerçekten bitmiş, geçmişte pozitif ödeme yapmış aylık Plus/Pro; family lifetime-once |
| Winback dışı | Sadece auto-renew kapalı fakat aktif; gift/trial-only; annual; grace/hold/pause/recovery; refund/revoke; diğer mağazada aktif |
| Winback aday zamanlama | 72 saat bekleme, 14 gün kabul, en fazla iki dış temas; ilk push ve 7 gün sonraki email adayları, ayrıca kanal rızası gerekir |
| Suppression | Gönderim/checkout anında tekrar lifecycle; resubscribe veya gift ertelemesi; yeni episode ile TTL/once reset yok |
| Kampanya pause | Yeni üretim/sunum durur; kazanılmış geçerli hak ve kabul edilmiş store işlemi yok sayılmaz; settlement devam eder |

Apple native win-back mekanizmasının “son abonelikten beri” alt sınırı 1 ay; bu yüzden V5'teki 72 saatlik aday temasla aynı mekanizma kabul edilemez. Erken geri dönüş için promotional offer yolu P14 mağaza kanıtına bağlıdır. [Apple win-back eligibility](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/).

Normal satın alma, restore ve mevcut introductory trial her iki kampanya kapalıyken aynen çalışır. Kampanya motoru çökerse mevcut paid erişim kapanmaz. İletişim izni vermeyen kullanıcı ödülden mahrum bırakılmaz.

## 10. Bildirim, kişisel not ve teknik izleme

### 10.1. Tek bildirim omurgası, farklı amaçlar

İş yükümlülüğü, kişisel reminder, operasyonel bildirim ve pazarlama ayrı sınıflardır. Aynı APNs/FCM taşıyıcılarını kullanmaları aynı rıza veya aynı zamanlama kuralına sahip oldukları anlamına gelmez.

~~~text
Domain olayı / kişisel occurrence / kampanya eligibility
 → o amaç için tek yetkili producer
 → kural sürümü + episode + schedule_version
 → send-time owner / hesap / cihaz / kategori / kanal / consent kontrolü
 → quiet hours + frekans + dedupe + desteklenen route
 → APNs/FCM/e-posta adaptörü
 → attempt sonucu + retry/suppression kaydı
~~~

Onboarding'de sade, kapsamı anlaşılır tek seçim; OS permission pazarlama rızası yerine geçmez. E-posta rızası ayrı kayıt. Mevcut opt-out değerleri migrasyonda korunur. Öneri tekrarları V5'te 14 gün cooldown ve 90 günde en çok 2 aday sınırı taşır; final politika onaylanır. iOS OS reddinden sonra Ayarlar yönü; Android sürüme bağlı POST_NOTIFICATIONS ve sistem ayarları; izin istenmiş/atlandı/OS reddedildi/kategori kapalı ayrı durum.

İş bildirimleri için aday quiet-hours 21:00–08:00, operasyonel günlük 2 ve pazarlama haftalık 1 sınırları konfigürasyondur; kişisel açık alarm niyeti aynı kampanya sınırına körlemesine takılmaz. Saat dilimi kullanıcı/işyeri bağlamına göre açık tutulur. Provider accepted kullanıcıya teslim edildi veya okundu demek değildir; metrikler ayrı.

Legacy producer ownership registry: her amaç/episode için eski veya yeni producer tek sahibi olur. Shadow yeni motor gerçekten göndermez. Cutover watermark/episode/schedule eşlemesiyle yapılır; önceki pending işler iptal/suppressed edilir, geri dönüşte mükerrer üretim olmaz. Eski build yeni deep link'i bilmiyorsa güvenli mevcut ekran veya skip; başka firmaya route ile geçiş yok.

### 10.2. Kişisel not defteri ve hatırlatıcı

Notlar P13 olarak şirket modüllerinden bağımsız erken geliştirilebilir. Kullanıcı hesabı ve temel senkron sözleşmesi dışında eğitim/risk/firma/kampanya motoruna bağımlı değildir. Ortak teknik scheduler kütüphanesi kullanılabilir; domain tabloları veya entity bağlantısı paylaşılmaz.

Offline edit → yerel sürümlü taslak → sync mutation → expected_version → conflict varsa iki içeriği koruyan çözüm. Son yazan kazanır ile sessiz metin kaybı yok. Silme tombstone'u tüm cihazlara yayılır; eski offline cihaz notu tekrar yaratamaz. Kullanıcı notu silince varsayılan gelecek reminder'lar iptal; tamamlanmış occurrence geçmişi retention politikasına uyar.

Reminder occurrence kimliği serinin kimliğinden ayrıdır. Bir taneyi ertele/tamamla ile tüm seri kapanmaz. Tek teslim sahibi açık seçilir: belirli installation'da local ya da server push. Offline çok cihazda mutlak exactly-once OS teslimi vaat edilmez; ulaşılabilir garanti, bilinen sınır ve recovery ekranı tanımlanır. DST, reboot, uygulama güncellemesi, timezone değişimi, Focus, pil optimizasyonu ve Android exact alarm erişimi yokluğu test edilir; ilk sürümde gereksiz exact-alarm yetkisine dayanılmaz.

### 10.3. Teknik uygulama sağlığı ve gizlilik

Teknik olay zarfı: request_id, operation_id, trace_id, support_id, environment, app_build, platform, stage, outcome, reason, retry_count, güvenli latency. E-posta, parola, OTP, access/refresh token, store imzası, signed URL, not gövdesi, çalışan belgesi ve fotoğraf içeriği loglanmaz. Typed metadata allowlist ve redaction testleri client/server/admin/export için birlikte uygulanır.

Özellikle “analiz yaptım panelde hiçbir şey görünmedi” türü teşhis için submit öncesi olaylar gerekir: ekran açılışı → fotoğraf seçimi → encode → upload intent → upload → submit → job queued → provider → result → UI render. Analyses satırı oluşmadan biten hata ayrı sayılır. Render edilmemiş sonucu successful user outcome sanma yok. Panelde support ID ile zincir izlenir, ham içerik erişimi varsayılan değildir.

İlk kez kurulumdan satın almaya kadar network denetimi yapılır: IDFA/Meta SDK/RevenueCat attribution/server CAPI/eski queued advertising olayları birlikte. ATT istemiyoruz diye client popup'ı kaldırmak yeterli değildir. Birinci taraf zorunlu operasyon/audit, isteğe bağlı ürün analitiği ve reklam tracking'i ayrı sınıflardır. Bilinmeyen edinim unknown; aggregate postback kullanıcıya join edilmez; fingerprint üretimi yok. Play Referrer, user-entered code/UTM veya Apple AdServices ancak ayrı doğrulanmış kapsamla; Firebase Dynamic Links'e yeni bağımlılık yok.

Admin paneli mevcut ayrı repo içinde genişletilir: lifecycle, quote/benefit/settlement, queue/error, scan/import, migration/backfill, consent/delivery, score explainability. Teknik ihtiyaç, panel AGENTS.md sınırları ve kullanıcı değişiklikleri korunarak ayrı görevde uygulanır. Aynı turda ana uygulama migration'ı ile panel deployment'ı birbirine gizli bağlanmaz. MFA/scope server kontrolü ve kritik publish audit'i başarısızsa publish durması test edilir.

## 11. Kural, takvim ve skor

### 11.1. Mevzuat kataloğu yayın süreci

Kaynak dosya/sayfa → checksum ve erişim tarihi → maddeler/istisnalar → yürürlük ve jurisdiction → gözden geçirme → versioned fixtures → draft/simulation → insan içerik onayı → published rule. Yalnız URL eklemek doğrulama değildir. Kanıt eksikse needs_review; TR dışına otomatik Türkiye kuralı uygulanmaz.

2026 eğitim sayfası bu tur doğrudan açılmaya çalışıldı, erişim zaman aşımı oldu. Bakanlık SSS sayfası erişilebilir olsa da kaynakta geçen tüm yeni eğitim ayrıntılarının doğrulandığı anlamına gelmez. Bu nedenle §7.2 sayılarını prod kuralı yapmadan önce resmi metin ve tarihli uzman incelemesi gerekir. [Resmî Gazete doğrulama hedefi](https://www.resmigazete.gov.tr/eskiler/2026/04/20260402-2.htm), [Bakanlık SSS](https://www.csgb.gov.tr/tr/sikca-sorulan-sorular/is-sagligi-ve-guvenligi-genel-mudurlugu/).

Takvim yılı/ayı, 365/30 güne çevrilmez. due_on ve timezone açık; 29 Şubat, ayın son günü, geriye dönük effective date, sınıf değişimi, kapatılan işyeri, ayrılan çalışan, iptal edilmiş yükümlülük test edilir. Daily reconcile kaçan olayları bulur; aynı task'ı çoğaltmaz.

### 11.2. Skor politikası

Skor resmi uygunluk sertifikası değildir. Aday süreç ağırlıkları 25/25/15/15/10/10 ancak işveren/uzman kararı ve fixture incelemesiyle yayımlanır. Her süreç kendi contribution cap'ine sahiptir; 1.000 çalışan bir modülün ağırlığını sınırsız büyütmez.

required + eksik → paydada kalır, eksik katkı. not_required + doğrulanmış gerekçe → ana skor dışında. needs_review → provisional/hesaplanamayan kapsam görünür, “zorunlu değil”e düşmez. Gönüllü kayıt ana yasal pay/paydayı etkilemez. Hiç veri yokken 100 gösterilmez. Kritik uyarı yüksek toplam skorla kaybolmaz. Policy version/source context/tarih score snapshot'ında saklanır; geçmiş grafik yeni ağırlıkla sessiz yeniden yazılmaz.

Test oracle'ı üretim hesap fonksiyonunu çağırıp aynı sonucu beklemekten ibaret olamaz: elle doğrulanmış küçük altın fixture ve bağımsız referans hesap gerekir. Kural değişiminde önce simulation diff, sonra shadow projection ve insan onayı.

## 12. Otomatik test stratejisi: “tüm varyasyonlar” ne demek?

Hedef, tanımlı tüm fonksiyonların bütün anlamlı iş durumlarını ve hata geçişlerini test etmektir. Sonsuz serbest metin, bütün cihazlar ve bütün dış mağaza davranışları için “%100 her olasılık otomatik denenir” iddiası doğru olmaz. Bunun yerine sonlu durum alanı açık tanımlanacak, kritik kesişimler tam taranacak, büyük girdi alanları property-based/fuzz ile, düşük riskli çaprazlar pairwise ile kapsanacak. İnsan/mağaza gerektiren kontroller otomatik geçti diye işaretlenmeyecek.

### 12.1. Üç kapsam kaydı

1. Kaynak gereksinim kaydı: 203 V5 kabul satırı, orijinal senaryo ve beklenen sonuçlarıyla CSV'de. §24.1: 24, §24.2: 27, §37.3: 48, §40.2: 48, §44.2: 56. Hepsi şu an NOT_IMPLEMENTED / NOT_RUN; mevcut testlerin ilgili bölümü örtmesi ancak eşleme ve çalıştırma kanıtıyla işaretlenir.
2. Fonksiyon sözleşme kaydı: her route, RPC, trigger, RLS policy, Edge handler, consumer, native reducer/service, UI action ve admin mutation için ID → kaynak dosya/symbol → girişler → çıktılar/yan etkiler → test ID → kanıt. P01'de otomatik envanterleyici yazılır; yeni fonksiyon test eşlemesi olmadan release gate geçmez. Saf görsel/private glue istisnası gerekçeli ve incelemeli olur, saklı kapsam kaybı olmaz.
3. Ek geçiş testleri: aşağıdaki X01–X60 matrisi. Kaynak belgedeki tekil kabulü eski/yeni binary, hesap, kesinti ve concurrency ile çaprazlar.

CSV bir test runner değildir. planned_layers önerilen kanıt katmanını gösterir; uygulamada test_file/test_name/fixture/command/run_id alanları ayrı çalıştırma manifest'inde doldurulur. §24 SEC-03 dış alıcı rolü yaratmadan, iptal edilmiş uzman yetkisi ve URL TTL senaryosu olarak yorumlanmıştır.

### 12.2. Her fonksiyona uygulanacak ortak test zarfı

| Katman | Her fonksiyon/endpoint için minimum varyasyon |
|---|---|
| Girdi | Geçerli minimum/maksimum; eksik/null/empty; tip/enum yanlış; bilinmeyen alan; uzun/Unicode; tarih ve byte sınırı; aynı key farklı payload |
| Kimlik | Anonymous; owner; farklı owner; aynı owner farklı company/workplace; expired JWT; logout sonrası retry; service/admin scope sınırı |
| Hak | Free; Plus; Pro; gift; legacy floor; expired/downgraded; unknown sync; tam kapasite; reservation bekliyor |
| State | Her izinli geçiş; her yasak geçiş; aynı geçişin tekrarı; archived/finalized; stale version; parent silinmiş/arşivli |
| Yarış | 2 cihaz; 20 eşzamanlı kritik write; response kaybı; duplicate event; farklı sıra; lease bitimi; işlem ortasında worker restart |
| Hata | DB rollback; storage timeout; provider 429/5xx; renderer/scan fail; telemetry down; retry exhaustion; conflict recovery |
| Yan etki | Domain satırı + audit + outbox + quota + task + document + notification; beklenen sayıda ve beklenen scope'ta; beklenmeyen yan etki sıfır |
| UI | Loading/empty/partial/error/retry/permission denied/read-only/offline/conflict; back/dismiss/cold start; iki platform aynı anlam |
| Gizlilik | Log, analytics, crash, admin ve export'ta yasak payload yok; signed URL/owner sınırı |

Salt mutlu yol CRUD testleri fonksiyon kapsamını tamamlamaz. DB testleri gerçek policy/trigger/RPC'yi authenticated/anon rollerle çağırır; service-role kullanıp RLS geçti demek yasaktır. Static source-string testleri yardımcı regresyondur, davranış kanıtının yerine geçmez.

### 12.3. Varyasyon alanları ve tarama yöntemi

| Alan | Değer kümeleri | Yöntem |
|---|---|---|
| Platform/sürüm | iOS minimum desteklenen+son kararlı; Android API26/32/33/hedef37; küçük/büyük ekran; gerçek cihaz | Her supported OS sınırında smoke; feature suite temsilci cihaz; fiziksel store/push/auth ayrıca |
| Binary/backend/katalog | Eski/yeni iOS, eski/yeni Android × eski/yeni backend × eski/yeni store katalog | Her platform için 2×2×2=8, toplam 16 mantıksal kombinasyon; yeni binary/eski backend güvenli fallback bekler |
| Hesap | OTP, parola, Apple relay/non-relay, Google; yeni/eski; verified/unverified; tek/çok cihaz | Auth kritik akışlarında bütün uygun provider dalları; geçersiz kombinasyon açık reddedilir |
| Erişim | Free, paid Plus/Pro monthly/yearly, trial, gift, expired, grace/hold/pause/refunded, unknown | Hak/lifecycle doğruluk tablosunda tam; her store olayı için geçiş testi |
| Eğitim | 3 hazard × amaç × yöntem × katılım × başarı × version | Finite kural matrisi tam; sayı/tarih property testleri; her kritik hücre iki istemci fixture parity |
| Dosya | 13 uzantı × purpose × clean/corrupt/spoofed × size boundary × worker failure | Her izinli uzantıya pozitif; her yasak purpose reddi; saldırı aileleri ve resource boundary tam |
| Risk | 4 revision kind × scope × tarih class × schedule queue state × stale/current version | Kritik tarih etkileri tam, concurrency/fault injection ayrıca |
| Bildirim | OS izin × hesap/kategori/kanal rızası × timezone × build × producer × schedule version | Send/no-send truth table tam; cihaz görünürlüğü ve batch pairwise |
| Not | Online/offline × 1/2 cihaz × edit/delete/complete/snooze × local/push owner | State machine ve çatışmalar tam; reboot/OS permission boundary cihaz testi |
| Kampanya | Family × store × plan × lifecycle × gift/discount state × eligibility × payment evidence | Parasal/erişim veren bütün kombinasyonlar tam karar tablosu; store mutlak uygunluğu ayrı sandbox kanıtı |
| Dil/görünüm | TR/EN, açık/koyu, büyük yazı, ekran boyutu, klavye, screen reader | Kritik ekran her dil/tema; düşük riskli çaprazlar pairwise; kullanıcı asset golden'ı |
| Zaman | UTC/İstanbul/DST bölgesi; ay/yıl sonu; leap day; ±1 dakika/saniye | Deterministic fake clock; takvim algoritması property; hiçbir test gerçek günü beklemez |

Pairwise güvenlik, hak, parasal settlement veya yasal hesap karar tablosunu azaltmak için kullanılmaz. Geçersiz kombinasyonlar silently skip edilmez; “neden uygulanmaz” kaydı olur. Generated testlerin seed'i ve küçültülmüş failing örneği artifact olarak saklanır.

### 12.4. Değişmezlik/property testleri

- Bir kullanıcının mutation'ı başka kullanıcının/firmanın verisini değiştiremez veya varlığını ifşa edemez.
- Retry ve event sırası nihai domain sonucu/kota/ödül toplamını çoğaltmaz.
- Hesap paid erişimi, kampanya settlement hatası yüzünden düşmez.
- Kullanıcının mevcut hak floor'u sırf uygulama güncellendi diye azalmaz.
- Gift aktivasyonu günlük/lifetime eski kullanım sayaçlarını sıfırlamaz.
- Tek ödeme en fazla tek campaign benefit settlement'ına sahip olur.
- Finalize belge hash/snapshot, kaynak firma/personel/template değişiminden etkilenmez.
- Risk rescan ve kısmi revision global yenileme tarihini resetlemez.
- Çakışan eğitim dakikaları iki kez kredi olmaz; G4 süre toplamına iki kez eklenmez.
- Gönüllü modül işlemleri ana yasal skor pay/paydasını değiştirmez.
- Not işlemleri şirket tablosu/task/skor/qualification event'i üretmez.
- Scan clean olmayan nesne için okunabilir signed URL veya import commit çıkmaz.
- Eski schedule_version yeni tarihli kayıt için mesaj gönderemez.
- Kullanıcı rıza kapattıktan sonra send-time kontrolünü geçen yeni pazarlama mesajı çıkmaz.
- Silme tombstone'undan eski offline mutation ile veri yeniden doğmaz.

Her property için kontrollü mutation testi önerilir: koruma geçici olarak test fixture/model'inde bozulunca suite başarısız olmalı. Kritik authorization/settlement/rule testleri yalnız satır coverage ile ölçülmez; yanlış davranışı yakaladıkları kanıtlanır.

### 12.5. Ek geçiş matrisi — X01–X60

Durum: aşağıdaki testlerin tamamı planlıdır; bu tur çalıştırılmadı. Kaynak 203 kabul satırını tamamlar; onlardan farklı bağımsız 60 geçiş senaryosu tanımlar.

| ID | Senaryo / varyasyon | Beklenen sonuç | Paket / kanıt |
|---|---|---|---|
| X01 | Eski iOS yüklü, OTP session + şirket + rapor + tercih; kaldırmadan yeni sürüm | Aynı bundle/UUID/oturum/rapor/opt-out | P18–20; XCUITest+fiziksel update |
| X02 | Aynı yerinde update Android; imza ve versionCode kontrolü | Aynı package, veriler/keystore saklama erişimi, daha yüksek versionCode | P18–20; instrumentation+Play internal |
| X03 | 16 binary/backend/katalog uyum kombinasyonu | Eski yollar çalışır; desteklenmeyen yeni yol güvenli kapalı | P19; contract+cihaz |
| X04 | Eski Plus 5 hakkı, kullanım 1/3/5; hedef 3 | Floor en az 5; sessiz azaltma yok | P03; DB+native |
| X05 | Eski Pro25→hedef30, unlimited/override kullanıcı | Artış uygulanır; sınırsız/istisna kaynaklı korunur | P03; DB |
| X06 | Lansmanda offline olan eski abone aylar sonra update | Cutoff eligibility korunur; tekrar purchase gerekmez | P03/P20; fake clock+native |
| X07 | Default workplace backfill ortada kesilir, eski binary yeni company yazar | Retry/catch-up sonunda her firmada tek default; orphan yok | P05/P19; migration |
| X08 | 20 paralel son şirket/storage slot'u isteği | Limit aşılmaz; haklı tek/izinli sayıda kazanan | P03; concurrency |
| X09 | Aynı key farklı payload, aynı payload farklı network retry | Farklı payload conflict; retry tek sonuç | P01; RPC/Edge |
| X10 | Domain commit anında audit/outbox insert hatası | Yarım domain mutation yok | P01; DB fault injection |
| X11 | Worker commit öncesi/sonrası ölür, lease tekrar alınır | Tek projection/task/settlement | P01/P06; fault injection |
| X12 | İki firma/iki işyerinin geçerli ID'lerini karıştır | RLS+FK+API her yolu reddeder | P05; pgTAP+API |
| X13 | Çalışan kodu leading-zero, aynı isim, görev geçiş tarihi çakışması | Kod korunur, isim merge yok, illegal overlap reddi | P05/P11; import/domain |
| X14 | Eğitim sınır dakikaları ve 59/60/61 puan, 2/3/4 deneme | Onaylı rule oracle'ına tam uyum | P07; property+native fixture |
| X15 | Eski katalog belgesi, yeni kural ve hazard değişimi | Eski snapshot aynı; yeni ihtiyaç review | P06/P07; domain |
| X16 | Aynı G4 dakikası iki session'da / birden fazla katılım segmenti | Bir dakika tek kredi; yöntem ve minimumlar korunur | P07; property |
| X17 | 4 risk revision türü, eski pending schedule, iki cihaz finalize | Doğru tarih etkisi, tek version, eski mesaj yok | P08; DB+E2E |
| X18 | Seçilmiş AI finding sonra düzenlenir/silinir | Risk source snapshot sabit, kaynak durumu görünür | P08; domain+native |
| X19 | Uygunsuzluk bütün allowed/forbidden state geçişleri | Yetki/gerekçe/verification olmadan kapanmaz | P09; model-based |
| X20 | Optional kurul aç/kapat/kayıt ekle; zorunluyu menüde gizle | Gönüllü skor nötr, required yükümlülük sürer | P06/P17; property |
| X21 | 13 uzantı için temiz örnek + yanlış purpose; gerçek DOC/XLS | Pozitif formatlar açılır, yasak amaç reddi | P04; parser+cihaz |
| X22 | MIME spoof, macro/XXE/zipbomb/path traversal/pixel bomb | Sınırlı izolasyon; ağ/exec yok; clean olmaz | P04; sandbox security |
| X23 | Scan timeout/AV down/preview-only failure/hash swap | Güvenlik hatası fail-closed, preview hatası doğru ayrı state | P04; fault injection |
| X24 | 20 eşzamanlı document number + aynı retry | Unique numara ve tek mantıksal belge | P11; DB |
| X25 | Belge üretildikten sonra logo/adres/personel/template değişir | Eski iki format hash/snapshot aynı | P11; golden+hash |
| X26 | CSV/XLSX tarih1900/1904, TR decimal, sağlık kolonları | Açık preview, sağlık verisi hiçbir yeni alana yazılmaz | P11; parser+DB |
| X27 | Import preview'dan sonra hedef edit; batch kesinti; compensation | Conflict; idempotent resume; sonradan edit silinmez | P11; DB fault injection |
| X28 | OTP/Apple relay/Google hesabına parola ekle; duplicate email | Aynı UUID, güvenli conflict; auto merge yok | P02; Auth staging+native |
| X29 | Alias enumeration, OTP expiry/resend, cold-start recovery | Generic/limitli güvenli akış; hesap/token sızıntısı yok | P02; security+native |
| X30 | Parola Unicode/byte sınırları/autofill/paste + global Auth policy eski client | Sessiz trim/truncate yok; OTP bozulmaz | P02; parity+old binary |
| X31 | Legal/paywall/notification/password prompt aynı anda eligible | Tek doğru öncelikli presentation; dismiss kalıcı semantik | P02/P12/P18; UI |
| X32 | Gift activation iki cihaz, expiry anı, quota dolu | Tek Plus7, server 7×24h, quota reset yok | P03/P14; DB+clock |
| X33 | Discount kaydı var, store ödeme yok | Paid tier veya AI quota açılmaz | P14; negative access |
| X34 | Duplicate/out-of-order webhook, restore/sync yarışı, linked token | Son kanıtlı lifecycle; tekrar grant/downgrade yok | P14; replay |
| X35 | Başka hesabın receipt'i, iki mağazada aynı hesap, sandbox/prod karışması | Owner guard; environment ayrımı; yanlış paid unlock yok | P14; store+DB |
| X36 | Apple mevcut monthly: quote→imza→offer→indirimli dönem→normal renewal | Aynı product, bir dönem indirim, doğru sonraki fiyat | P14; gerçek sandbox evidence |
| X37 | Google aynı monthly/base plan; mevcut same-product guard | Dedicated offer checkout açılır; doğru replacement, normal renewal | P14; license test+wrapper |
| X38 | Eski binary + yeni developer-determined offers | Normal introductory trial/purchase istemeden kampanya seçmez | P14/P19; old binary store QA |
| X39 | Legacy fiyat100/liste150/offer120 + başka currency/pricepoint | Yanlış avantaj iddiası yok; pahalı geçiş engeli | P14; price fixtures+store |
| X40 | Checkout timeout, imza hâlâ geçerli, ikinci cihaz aynı hak | Belirsiz intent review; iki ekonomik kullanım yok | P14; concurrency+store replay |
| X41 | Referral ve winback aynı payment'a settlement; refund daha sonra | Tek ekonomik settlement; refund gerekçeli adjusted | P14/P15; DB |
| X42 | Free/paid-monthly/annual davetçi, yeni/eski davetli, self/cycle/retry | Doğru dal; unsupported reward/auto downgrade yok | P15; decision table |
| X43 | İki gün gerçek Free işlemi vs heartbeat/view/note/failed analysis | Yalnız server proof qualify; pazarlama rızası koşul değil | P15; event integration |
| X44 | Cancelled-active/expired/grace/hold/pause/refund/annual/trial-only/other-store-active | Winback sadece uygun gerçek expired-paid monthly | P15; full lifecycle table |
| X45 | 72h/14day sınır ±1s; resubscribe gönderim sırasında; gift active | TTL reset yok; suppression/erteleme doğru | P15; fake clock+race |
| X46 | Campaign budget/pause, önceden earned veya store accepted benefit | Yeni producer durur; geçerli hak/settlement korunur | P15/P16; operations |
| X47 | OS authorized fakat marketing consent yok; son anda opt-out | Pazarlama çıkışı yok; operasyonel amaç ayrı değerlendirilir | P12; consent truth table |
| X48 | 30 firma overdue, eski/yeni producer, provider retry | Tek episode/özet; fırtına yok; accepted≠delivered | P12; load+provider mock |
| X49 | Eski schedule_version, foreign-company deep link, old build route | Stale gönderilmez; owner check; güvenli fallback | P12; API+native |
| X50 | Notta company/entity ID direkt/JSON/cache/event enjeksiyonu | Reddedilir; hiçbir domain linki/qualification oluşmaz | P13; schema+API+static |
| X51 | İki offline cihaz edit/edit ve edit/delete; logout/login başka hesap | Metin korunur, tombstone kazanır, cache owner izolasyonu | P13; sync E2E |
| X52 | Reminder local/push/2 cihaz, DST/reboot/Focus/exact alarm yok | Belgelenmiş tek sahip ve dürüst delivery durumu | P13; clock+cihaz |
| X53 | ATT'siz clean install→Auth→analysis→purchase; eski advertising queue | Client/server tracking çıkışı yok; unknown attribution | P16; network inspection |
| X54 | Encode/upload/submit öncesi hata, telemetry down, bounded queue dolu | Support zinciri doğru; domain telemetry'ye bağımlı değil | P16; fault injection |
| X55 | Admin yanlış scope/MFA yok; audit publish hatası; export PII | Backend reddi, publish fail-closed, maskeli/izinli veri | P16; API+Playwright |
| X56 | Tüm yeni domain verileriyle account deletion + worker retry | Planlı silme/retention; gelecekte push yok; FK sonsuz retry yok | P19; integration |
| X57 | İzole DB+Auth+Storage restore; hash/FK/profile/receipt mapping | Tutarlı erişim; outbounds kapalı; RPO/RTO ölçülür | P00/P19; restore drill |
| X58 | Yeni feature kill switch/flag endpoint down/DB eski ama yeni binary | Yeni write kapalı/read-only; eski Auth/AI/rapor/billing çalışır | P19; chaos |
| X59 | Kullanıcı tasarımı TR/EN light/dark büyük yazı screen reader tüm state'ler | Onaylı asset/token karşılığı; erişilebilir işlem | P18; golden+accessibility |
| X60 | Final manifest: yeni fonksiyon veya kaynak kabul satırının test eşlemesi eksik | Release gate FAIL; NOT_RUN/blocked test başarı sayılmaz | P01/P20; coverage gate |

## 13. Test otomasyonu nasıl yürütülecek?

### 13.1. Ortamlar ve güvenli fixture'lar

| Ortam | Kullanım | Sınır |
|---|---|---|
| Saf unit/contract | Swift/Kotlin/TS domain modelleri, DTO, fake clock, golden fixtures | Ağ yok; secret yok; deterministik |
| Yerel Supabase | Migration/RLS/RPC/trigger/outbox, seed ve concurrency | Ayrı local proje; production URL denylist; reset sadece bu doğrulanmış hedefte |
| İzole staging | Auth e-posta, Storage scan/render, Edge integration, admin, E2E | Ayrı credentials/buckets/queues; outbound mesaj allowlist ve sink; gerçek müşteri seed'i yok |
| Store sandbox/lisans | İmza, subscriptionOption, renewal/refund/restore ve eski binary katalog | Test hesapları ve environment ayrımı; katalog değişikliği insan onayı; normal kullanıcıya mesaj yok |
| Production read-only/shadow | Uyum/capacity/migration dry-run, ölçüm | Mutasyon/mesaj/paid API/yük testi yok; aktivasyon ayrıca onaylı |

Test kullanıcıları en az: iki ayrı uzman; her birinde iki şirket, her şirkette iki işyeri; 3 hazard ve bilinmeyen/TR dışı; Free/Plus/Pro/gift/legacy/expired; aynı isimli çalışanlar; relay hesap; büyük dataset. Büyük hacim başlangıçta 30 firma ve sınır import batch'leri; gerçek hedef personel sayısı ve SLO P00 ölçümünden sonra sabitlenir. Sentetik adlar ve belgeler kullanılır; gerçek yedekten CI verisi üretilmez. Restore drill gerekiyorsa restricted ortam, iş amaçlı erişim ve egress kapalı olmalı; sonrasında kontrollü temizlik ve kanıt.

### 13.2. Mevcut doğrulanmış komutlar ile kurulacak komutlar ayrımı

Bu tur yalnız aşağıdaki küçük mevcut statik sözleşme testi çalıştırıldı:

~~~bash
node --test scripts/client_flow_contract_test.mjs
~~~

Sonuç: 5/5 geçti. Bu, client flow enum/sınırlı kuyruk/billing guard kaynak sözleşmesi kontrolüdür; yeni V5 özellikleri veya canlı analiz akışı geçti anlamına gelmez. iOS/Android build, tam suite, mağaza ve restore bu tur çalıştırılmadı.

Mevcut Android CI'dan alınan çalışma örnekleri; uygulama fazında önce environment guard ve fixture hazırlığı ile kullanılır:

~~~bash
# android çalışma dizininde; görevler mevcut CI'da kullanılıyor
./gradlew :app:verifyEnvironmentIsolation
./gradlew lint testDebugUnitTest verifyRoborazziDebug -Proborazzi.dumpUiTree=true :app:assembleDebug :app:assembleQa
~~~

Mevcut CI, Deno static testlerini --allow-read ile; local PostgreSQL testlerini supabase test db --local ile yürütüyor. Her testin izin ihtiyacı incelenir; yeni integration suite'e gereksiz --allow-all verilmez. Makefile'daki her target güvenli offline test değildir; live/canary/setup/deletion/release komutları otomatik “test all” içine alınmaz. Global süreç öldüren eski UI runner doğrudan kullanılmaz.

Kurulacak otomasyon için önerilen yollar; bugün var veya çalışır oldukları iddia edilmiyor:

| Önerilen çıktı | İşlev |
|---|---|
| contracts/isg/v1/ | Şemalar, error codes, state machine, shared golden fixtures |
| scripts/isg/verify_environment.mjs | Proje/URL/store environment/recipient allowlist doğrulama; yanlış hedefte hard fail |
| scripts/isg/build_test_manifest.mjs | Kaynak gereksinim ve route/RPC/function envanterini test kayıtlarıyla eşleme |
| scripts/isg/run_suite.mjs | Unit/DB/Edge/native/admin/store-recorded lane seçimi, preflight, seed, kanıt toplama |
| scripts/isg/verify_release_evidence.mjs | NOT_RUN/eksik evidence/yanlış commit/eksik platform varsa gate fail |
| supabase/tests/isg_*.sql | pgTAP owner/RLS/FK/transaction/backfill/ledger testleri |
| supabase/functions/_shared/isg-*/ ve *_test.ts | Domain/reducer/provider adapter testleri; mevcut dizin standardına uyarlanır |
| iOS test target içi ISG test grupları | XCTest saf domain, XCUITest ekran/state/deep-link/update; gerçek target adları P00'da teyit |
| Android ilgili module src/test ve src/androidTest | Domain/unit, Room/cache gerekiyorsa migration, Compose UI, instrumented update |
| Operasyon paneli tests/unit ve tests/e2e | Vitest/API scope, Playwright campaign/telemetry/import iş akışları; ayrı repo değişikliği |
| artifacts/isg/<run_id>/ | Sanitized manifest, JUnit/TRX eşdeğeri, xcresult, screenshots, network özet, DB assertions |

P01 runner sözleşmesi: tek suite çağrısı önce environment manifest'ini doğrular; seed/run ID oluşturur; testleri katmanlara ayırır; başarısız test için log/support ID/seed/screenshot toplar; nonzero exit verir; yalnız o run'ın fixture'larını temizler. Kullanıcının simülatörünü veya aktif build'ini global killall ile kapatmaz. İptal/timeout sonrası cleanup başarısı ayrıca raporlanır.

### 13.3. Otomasyon hatları

| Hat | Tetikleme | Zorunlu kapsam | Çıktı / kapı |
|---|---|---|---|
| PR hızlı | Her değişiklik | Format/typecheck, contract drift, unit, secret/PII, ilgili domain DB; kimlik manifest diff | Hata varsa merge engeli |
| PR domain | Migration/API/feature değişikliği | pgTAP, Edge integration, iki native domain/parity test, admin contract etkisi | Her değişen fonksiyonun test eşlemesi |
| Nightly | Uygulama döneminde onaylı CI takvimi | Tam suite, property/fuzz seed seti, concurrency/fault, dosya corpus, native UI+snapshot | Flaky ayrı iş kaydı; sessiz retry ile yeşil yok |
| Migration candidate | Her şema/backfill dalgası | Boş DB ve başlangıç snapshot'ından upgrade, tekrar çalıştırma, lock/reconcile/old-client | Veri kaybı/orphan/duplicate sıfır |
| Release candidate | Sürüm adayı | Tam 203 kaynak + X01–X60 eşlemeleri, update/E2E, performance/security, tasarım | Eksik kritik/human gate release engeli |
| Store lane | Offer/SDK/katalog değişimi | Apple/Google test hesabı, ilk indirimli dönem ve sonraki normal renewal, restore/refund | Gerçek store kanıtı; mock başarı yetmez |
| Release sonrası | Ayrıca kurulacak izleme planı | Read-only telemetry, shadow drift, queue yaşları, fiyat/hak/izin anomaly | Aksiyon gerektiren sapma; otomatik üretim değişikliği yok |

Bu plan CI veya zamanlanmış izleme kurmadı. Nightly ve release sonrası izleme, uygulama aşamasında ayrıca yapılandırılacak. Her pipeline commit SHA + migration set + config/rule/template version + fixture seed'e bağlı sonuç üretir. Aynı sonucu başka commit'in kanıtı olarak kullanma yok.

### 13.4. Otomatik yapılabilecekler ve insan/gerçek platform sınırı

Codex tarafından otomatik yürütülebilecekler: kod ve contract envanteri, test üretimi, local DB migration/RLS, unit/property/fuzz, mock provider, emulator/simulator UI, belge parser/golden, import, concurrency, sanitized kanıt raporu ve ortam hazırsa staging E2E. Testi yazmak ile çalıştırmak ayrı kayıtlar olur.

İnsan veya dış sistem gerektiren kapılar: resmi mevzuat/içerik onayı, nihai ticari parametreler, tasarım onayı, Apple/Google mağaza teklif konfigürasyonu ve yayın, fiziksel cihazdaki bazı sistem izin/satın alma adımları, gerçek imza/hesap erişimi ve felaket kurtarma saklama kararı. Bu kontrollerin fixture doğrulaması otomatik yapılır; mağazanın gerçek davranışı veya insan kararı mock ile ikame edilmez.

Otomasyon erişimi olmayan test BLOCKED_ENV/HUMAN_GATE olur, PASS olmaz. Paid gerçek hesaplarda deneme satın alması, toplu e-posta/push, gerçek veri silme, production load/fraud denemesi yapılmaz. Store QA kontrollü test hesaplarıyla ve mutasyon yetkisiyle ilerler.

### 13.5. Test raporu ve ölçülebilir bitiş kriterleri

Her run için: test ID, kaynak gereksinim(ler), implementation symbol, platform/OS/build, backend SHA/migrations, store/catalog environment, fixture/seed, started_at/duration, PASS/FAIL/BLOCKED_ENV/NOT_RUN, expected/actual, sanitized evidence, hata severity, owner ve retry açıklaması.

Release'e kabul:

- 203 kaynak gereksinimin ve 60 ek geçiş senaryosunun test eşlemesi %100; uygulanamaz görülen madde için kullanıcı onaylı kapsam kararı, sessiz silme yok.
- Desteklenen kritik state geçişlerinin ve reddedilmesi gereken geçişlerin karar tablosu %100.
- Kimlik/ownership/paid hak/ödül/kota/idempotency/scan güvenliği/regulatory oracle için başarısız veya çalıştırılmamış test yok.
- Her ana modül iki platformda en az bir tam başarılı ve bir başarısız/retry E2E; ek kritik varyasyonlar karar tablosuna göre.
- Store teklifinin indirimli ve izleyen normal dönem kanıtı iki mağazada; normal purchase/intro trial/restore regresyonu yok.
- Restore ve eski binary yerinde update kanıtı mevcut; production mağaza/katalog/şema farkları açıklanmış.
- Bilinen düşük riskli sorunlar açık risk kabulü taşır. Flaky kritik test çözülmeden “bir kez geçti” yayın gerekçesi olmaz.

Kod satır coverage hedefi yeni saf domain kodu için ölçülecek; yüksek yüzde tek başına release kapısı değildir. Performans için ölçülmemiş rakam uydurulmaz: P00 baseline p50/p95 API/başlangıç, import throughput, worker memory, DB lock, queue lag; P19 yük testinde kabul edilen bütçe ve regresyon sınırı manifest'e işlenir. P20'ye geldiğinde “sonra bakarız” kalan SLO olmaz.

## 14. Uçtan uca kullanıcı yolculukları

Her yolculuk iki platformda, gerçek backend staging + deterministik provider fixture ile; store/push olan son adım ilgili gerçek platform lane'inde çalışır.

| Yolculuk | Baştan sona doğrulama |
|---|---|
| E01 Eski uzman update | Mevcut login/session → yeni marka → aynı şirket/analiz/rapor → Plus/Pro yeni modüller → restore → eski opt-out korunması |
| E02 Yeni e-posta hesabı | Email+parola → kod/resend/verify → bootstrap → onboarding izin kararı → Free işlem → aynı UUID ile ikinci cihaz |
| E03 OAuth/relay | Apple veya Google → optional parola dismiss/create → tekrar provider/parola login → recovery → şirketler/RC kimliği değişmez |
| E04 Eğitim tam döngü | Firma/işyeri/çalışan → ihtiyaç → plan/oturum/yoklama/sınav → completion → PDF/XLSX → süre/task/skor → görev değişimi sonrası review |
| E05 Risk tam döngü | Mevcut fotoğraf analizi → seçilmiş aktarım → risk version → rescan/kısmi/tam → eski doküman erişimi → stale bildirim iptali |
| E06 Saha uygunsuzluğu | Checklist/gözlem → uygunsuzluk → aksiyon → kanıt upload/scan → doğrulama → kapatma/reopen → rapor/takip |
| E07 Firma dosyası/import | 13 format purpose politikası → karantina → clean → preview/mapping → commit → hata/duplicate çözümü → evrak arama/export |
| E08 Diğer modüller | Acil durum/tatbikat, ekipman, sözleşme, yıllık plan, kurul, görevlendirme, KKD, defter, izin, taşeron, saha için ayrı kayıt→takip→evrak hikâyesi |
| E09 Kişisel defter | Free kullanıcı → offline not → ikinci cihaz conflict → reminder/snooze → izin reddi → not silme → başka hesaba geçiş |
| E10 Davet | Free ve paid monthly dalları → link/code → yeni hesap → gerçek qualification → manual gift veya monthly offer → settlement |
| E11 Winback | Ücretli dönem biter → eligibility wait → consentli teklif → resubscribe/suppression veya offer → discount dönem → normal renewal |
| E12 Downgrade | Pro→Plus→Free/expiry → fazla firmalar read-only → geçmiş dokümanlar/schedules → yeniden paid → mevcut veri yeniden kullanılabilir |
| E13 Silme | Yeni/eski tüm domain verisi olan hesap → request deletion → schedule iptal → depolama/alias/not/retention → retry ve foreign owner koruması |
| E14 Operasyon | İstemci pre-submit hata → support ID → panel scope'lu teşhis → dry-run/pause → kritik audit → tekrar deneme ve kullanıcı sonucu |

E08 tek bir örnek testle kapatılmaz: tablodaki her modül ayrı parametrik senaryo ve kendi domain-specific assertion'larıyla yürütülür.

## 15. Tek yürütme planı: P00–P21

Sıra bağımlılığa göredir; numaranın büyük olması bütün işi sona bırakmak demek değildir. P16 izleme temeli P01 ile, P14 store spike'ı P03'ün ilk sözleşmesiyle, P13 bağımsız notlar Auth temeliyle erken başlayabilir. Bu plan çoklu agent başlatma yetkisi vermez; işlerin ayrılabilirliğini gösterir.

### 15.1. Bağımlılık grafiği

~~~mermaid
flowchart LR
  P00[P00 Baseline ve restore] --> P01[P01 Contract ve güvenli altyapı]
  P01 --> P02[P02 Auth]
  P01 --> P03[P03 Hak ve quota]
  P01 --> P04[P04 Dosya ve belge çekirdeği]
  P01 --> P16A[P16a İzleme temeli]
  P03 --> P05[P05 Firma ve çalışan]
  P05 --> P06[P06 Kural ve takvim]
  P06 --> P07[P07 Eğitim]
  P06 --> P08[P08 Risk]
  P06 --> P09[P09 Uygunsuzluk]
  P06 --> P10[P10 Diğer modüller]
  P04 --> P07
  P04 --> P08
  P04 --> P10
  P07 --> P11[P11 Import ve tüm evraklar]
  P08 --> P11
  P09 --> P11
  P10 --> P11
  P06 --> P12[P12 Bildirim]
  P02 --> P13[P13 Bağımsız notlar]
  P03 --> P14[P14 Lifecycle ve mağaza provası]
  P14 --> P15[P15 Davet ve winback]
  P16A --> P15
  P12 --> P15
  P07 --> P17[P17 Skor ve portföy]
  P08 --> P17
  P09 --> P17
  P10 --> P17
  P15 --> P16B[P16b Admin operasyon]
  P11 --> P18[P18 Tasarım ve native kabuk]
  P13 --> P18
  P17 --> P18
  P18 --> P19[P19 Bütünleşik güvenlik ve prova]
  P16B --> P19
  P19 --> P20[P20 Mağaza güncellemesi]
  P20 --> P21[P21 Gözlem ve sonra temizlik kararı]
~~~

Grafik ana kritik yolu sadeleştirir; paket tablosundaki ek önkoşullar bağlayıcıdır. Kampanya, temel İSG domain yayınının veri bütünlüğünü bloke eden tek sistem haline getirilmez: ticari kapsam gereği lansmanda hazır olması istenirse ayrı release kapısıdır; hazır değilse kapsamı sessiz daraltmadan kullanıcı kararı gerekir.

### 15.2. İş paketleri: çıktı, test, çıkış ve geri dönüş

| Paket | Önkoşul | Somut işler/çıktılar | Test ve çıkış kapısı | Geri dönüş / risk |
|---|---|---|---|---|
| P00 Başlangıç envanteri | Bu plan | Ana uygulama/panel/ilgili web bağlantı manifest'i; canlı read-only store+Auth/cron/flags envanteri; kimlik/SDK/helper listesi; panel checkpoint; backup kapsamı ve restore drill; SLO baseline | X01/X02 hazırlığı, X57; restore raporu + açık farklar; secret içermeyen BASELINE_DIFF | Kaynak baseline değişmez; restore başarısızsa riskli faz durur |
| P01 Contract ve test omurgası | P00 | contracts/isg/v1; error/state machine; mutation/outbox/audit/lease; environment verifier; function-test manifest; iOS CI ve test runner; **13 Eylül: gerçek şemada tüketici dağıtım defteri** | X09–X12/X60; unit+pgTAP+Edge/native DTO parity; test izolasyonu | Yeni flag kapalı; eski API etkilenmez; altyapı henüz domain açmaz |
| P02 Auth | P01 | iOS mevcut parola girişini reuse; signup-code, Android parola yolları, same-user password, alias/recovery, presentation coordinator | AUTH-* ve X28–X31; provider/parola/OTP aynı UUID; eski binary global Auth ayarı testi | Yeni auth giriş yolları kapatılır; OTP/OAuth çalışır; kullanıcı parolaları silinmez |
| P03 Plan/legacy/quota | P01 | Catalog/floor dry-run; SQL helper ve paid check envanteri; shadow quota, atomic new reservations; read-only downgrade UX sözleşmesi; **13 Eylül: shadow rezervasyon defteri ve ölçülmüş hak tabanı uygulandı** | BILL/QUOTA, X04–X08/X32; hak kaybı/çift tüketim sıfır | Yeni tüketici shadow'a döner; eski otorite korunur; kazanılmış floor silinmez |
| P04 Güvenli dosya/belge çekirdeği | P01/P03 | Purpose matrix, quarantine/scan/immutable assets; sandbox worker spike; upload intent; document snapshot/export abstraction; **13 Eylül: kabul matrisi, intent/karantina, anti-TOCTOU promotion ve türev ayrımı uygulandı; sandbox/belge/import dilimleri açık** | FILE-* X21–X25; DOC/XLS dahil pozitif; scan fail-closed; maliyet sınırı | Yeni upload/import kapalı; clean mevcut dosya okunur; legacy photos/reports etkilenmez |
| P05 Firma/personel | P01/P03 | D05 migration; default workplace backfill/catch-up; assignment history; API; iki native liste/form/detail | **13 Eylül: P05 geliştirme ve yerel kabul tamamlandı.** REV01, DAT04/05, X07/12; REV21/23/X13 P05 parçaları doğrulandı. Native E2E ve tarihli/hiyerarşik ekran kanıtı mevcut; bileşik downstream/mağaza kabulü ayrı ve açık. [Kapanış](P05_CLOSURE_2026-09-13.md) | Yeni write read-only; companies legacy okuma/yazma sözleşmesi devam |
| P06 Kural/süre/task | P05/P01 | Legal source registry, bounded DSL, applicability, task/schedule, daily reconcile; rule publishing gate; **13 Eylül: çekirdek uygulandı, mevzuat içeriği ve tüketiciler açık** | REV03–06/20, SCO, DAT03, X20/49; tarih oracle ve unknown review | Yeni rule producer pause; eski kayıtların gerekçesi/takvimi görünür; eski bildirim sahibi korunur |
| P07 Eğitim | P04/P05/P06 | Catalog/G4, plan/session/enrolment/attendance/assessment/completion/external certificate; iki mobil akış; **13 Eylül: sunucu çekirdeği uygulandı, içerik onayı ve belge/native açık** | REV02/07–16/21, X14–16,E04; resmi kaynak içerik onayı + iki format fixture | Yeni finalize kapalı; mevcut completion ve belge immutable/readable |
| P08 Risk sürümleme | P04/P05/P06 | 4 revision türü; explicit AI finding transfer; impact/review; yeni tarihli schedule; **13 Eylül: sürümleme ve tarih disiplini uygulandı, içerik/belge/skor açık** | REV17–20, DAT02, X17/18,E05; tarih kayması yok | Yeni revision write durur; legacy AI analiz ve eski risk dosyaları okunur |
| P09 Uygunsuzluk/checklist | P04/P05/P06 | State/action/verification; template/run; finding adapter; native saha akışı; **13 Eylül: durum makinesi ve checklist çekirdeği uygulandı, saha akışı/bildirim/skor açık** | X19,E06; bütün allowed/forbidden geçişler; source link/idempotency | Yeni lifecycle write pause; legacy finding işareti bağımsız |
| P10 Diğer İSG modülleri | P04/P05/P06; P07/P09 entegrasyonları gerektiğinde | §7.5'teki her modül ayrı dilim: model/API/mobile/task/document sözleşmesi; **13–14 Eylül: on iki §7.5 başlığı uygulandı; evrak merkezi/taşeron/portföy/rehberlik diğer fazlarda** | REV03/04/22/23,E08; her satır CRUD+domain+belge+permission | Modül bazlı flag/read-only; başka modülü veya temel ürünü kapatma yok |
| P11 Import/evrak merkezi | P04 + ilgili domain hazır | Güvenli parser preview/commit/resume; tüm domain template'leri PDF/XLSX; ortak arama/filtre; legacy report adapter; **14 Eylül: numara/snapshot/export defteri ve import zinciri uygulandı; render/parser açık** | IMP/DOC, X24–27,E07; snapshot parity; compensation güvenliği | Yeni import/render durur, mevcut temiz original/export okunur |
| P12 Bildirim | P01/P06/P16a; Auth coordinator | Consent provenance; onboarding/profil; producer registry; yeni jobs + eski taşıyıcı; simulate/shadow/canary; **Omurga + devir sonrası güvenlik düzeltmesi: tekil token, gerçek zaman/vade, güncel rızayla retry, kapasite rezervasyonu ve belirsiz sonuçta resend yasağı yerel doğrulandı; sağlayıcı/native/cutover açık** | NOTIF/REM ilgili, X47–49; 38 yeni sunucu kabulü; fiziksel teslim ve tüm X49 henüz kanıtlanmadı | Producer ownership geri verilir; uçuşta/belirsiz iş varken devir reddedilir; pending job/version kontrolü; toplu resend yok |
| P13 Not/reminder | P01/P02; ortak teknik delivery adapter | Owner-only note/item/tag; offline conflict/tombstone; occurrence ve installation owner; Free UX; **14 Eylül: sunucu tarafı uygulandı; istemci senkron ve cihaz kabulleri açık** | NOTE/REM, X50–52,E09; şirket bağlantısı sıfır | Sync/reminder üretimi ayrı pause; kullanıcı metni/yerel taslak silinmez |
| P14 Lifecycle/store | P00 katalog + P01/P03/P16a | Canonical lifecycle, gift/discount separation, quote/intent/settlement, RC adapters; erken iki store spike | X32–41, V5 store testleri; discount+normal renewal kanıtı, eski katalog paritesi | Offer üretimi kapalı; normal purchase/restore ve settlement açık |
| P15 Referral/winback | P14 + server qualification kaynağı + P12/P16a | V5 kampanya karar tabloları, Plus7/monthly20, anti-abuse/budget, suppression, channel policy | REF/V5, X42–46,E10/11; human ticari kararlar ve store gate | Family/kanal ayrı pause; earned/store kabul edilmiş haklar korunur |
| P16 İzleme/admin | P01'de temel; her domain ile genişleme | Trace/redaction/network privacy; pre-submit funnel; mevcut panelde scope'lu sayfalar; simulate/review/publish/audit | PRIV/OBS,V5 admin, X53–55,E14; service key/PII/tracking sızıntısı yok | Analytics nonblocking; admin write pause; audit/settlement devam |
| P17 Skor/portföy | P06 + skor alanına giren domain'ler | Versioned policy, contribution explainability, provisional, read-model, firma/portföy UI | SCO/REV04–06,X20; bağımsız oracle; ağırlık insan onayı | Yeni projection shadow; eski skor geçmişi yeniden yazılmaz |
| P18 Marka/native kabuk | Kullanıcı tasarım teslimi; feature state sözleşmeleri; P02/12/13/17 | Navigation/feature screens, assets/tokens, TR/EN/accessibility, eski URL ve teknik ID koruma; iOS/Android parity | UX,X01/02/31/59; asset manifest ve update snapshot'ları | Teknik ID sabit; eski kabuk/fallback yalnız uyumlu flag; app downgrade varsayımı yok |
| P19 Bütünleşik prova | İlgili bütün paketler | Tam acceptance, security/fault/load, account deletion, restore+backfill rehearsal, old/new compatibility | 203+60 manifest; X03/56–58; açık kritik hata yok; RPO/RTO/SLO kararı | Yeni write/producer pause + roll-forward; prod DB restore rutin rollback değil |
| P20 Yayın | P19 + insan tasarım/hukuk/store/ticari onayı | Same-record update; additive prod hazırlık; internal/pilot/canary/genel rollout; legacy all-core entitlement catch-up | İmzalı release manifest, mağaza smoke, hak/price/consent metrikleri | Dağıtım durdurma/hotfix, backend flag; yayımlanmış binary uzaktan geri alınmış sayılmaz |
| P21 Stabilizasyon | P20 | Drift/reconcile/queue/maliyet gözlemi, destek geri bildirimleri, kanıtlı fixes; daha sonra contract cleanup teklifi | Eski istemci kullanımı/support window; veri mutabakatı; karar kaydı | Eski tablo/endpoint silmek ayrıca onaylı sonraki proje; otomatik temizlik yok |

### 15.3. İlk uygulanacak küçük dilimler

Uygulama yetkisi verildiğinde ilk sıra:

1. P00: gerçek store/SDK/helper manifest'i, ayrı panel checkpoint kapsamı ve restore kanıtı. Kimlik/secret içermeyen inventory dosyalarını üret.
2. P01: ortam guard + contract/test manifest + minimal mutation/outbox örneği; gerçek owner testleri ve iki native fixture decoder.
3. P03 ilk dilim: mevcut şirket limitini ve paid helper truth table'ını testle dondur; floor shadow dry-run. Henüz üretimde limit değiştirme.
4. P14 spike: aynı-plan store teklif uygulanabilirliği; normal purchase guard korunarak izole branch/test adapter. Katalogda yazma öncesi ayrı onay.
5. P04 spike: 13 format/purpose + gerçek DOC/XLS olumlu örnek + izolasyon/scan. Seçilmiş worker teknolojisinin maliyet/performans kararı.
6. P05 ilk dikey dilim: tek firma → default workplace → departman/görev/çalışan → iki platform CRUD → owner/assignment/backfill testleri.

Sonra modüller bağımlılık sırasıyla ilerler. Tek büyük commit yerine review edilebilir dilimler; uygulama branch'leri oluşturulacaksa codex/ öneki. Bu tur branch oluşturulmadı. Her PR, veri etkisi, eski client etkisi, test kanıtı, flag, migration lock ve geri dönüş notu taşır.

Takvim tahmini, P00/P04/P14 keşfi ve tasarım teslimi olmadan güvenilir değildir. İş paketleri bağımlılık ve kabul kapısıyla tahminlenir; store review veya mevzuat onayına süre garantisi verilmez. Her paket tamamlanınca kalan iş yeniden tahminlenebilir.

## 16. Güvenlik ve dış bağımlılık kapıları

### 16.1. Supabase özel kontrol listesi

Supabase beceri rehberi doğrultusunda yalnız genel “RLS var” kontrolüyle yetinilmeyecek. Plan şu testleri ayrıca zorunlu kılar:

| Risk | Uygulama / test |
|---|---|
| Tablo var ama API erişimi yok | Her yeni exposed tablo için minimum explicit GRANT + RLS + policy; staging default grants'e güvenme; REST üzerinden pozitif/negatif kontrol |
| authenticated rolünü owner sanma | USING ve WITH CHECK ile scope; anonymous Auth session varsa ayrıca gerçek kullanıcı şartı; user_metadata yetki kaynağı değil |
| UPDATE sessiz 0 satır | SELECT policy ve UPDATE kapsamını birlikte test et; optimistic result doğrula |
| Owner değiştirerek satır kaçırma | company/user/workplace reassignment negatif testi; yeni ve eski owner koşulları |
| View üzerinden RLS bypass | Uygun PG sürümünde security_invoker veya erişimi kapalı private view; doğrudan view/API sorgusu |
| SECURITY DEFINER yanlış güven | Tercihen invoker; gerçekten privileged olan private fonksiyonda explicit caller/owner kontrolü; PUBLIC EXECUTE ve role grant audit |
| Silinen/logout hesap token'ı hâlâ geçerli | Hassas mutation/signed URL mint işleminde hesap/session geçerliliği; eski JWT ile negatif test; yalnız Auth delete'in anında revocation olduğu varsayılmaz |
| JWT eski app_metadata | Hak değişimi DB/server otoritesi; refresh gecikmesi/freshness testleri |
| Storage upsert ile immutable ihlali | Yeni quarantine/promotion overwrite kapalı; legacy upsert gerekiyorsa gerekli INSERT/SELECT/UPDATE policy kapsamı ayrı ve geriye uyumlu |
| Realtime scope sızıntısı | Kullanılacaksa private kanal/owner kontrolü; REST güvenli diye realtime güvenli sanma; not/cross-company subscription testleri |
| Anahtar/sır sızıntısı | Public publishable key ile service role ayrımı; client bundle/log/artifact secret scan; imza/DB parola/OTP yok |
| Schema drift | Local ve managed ortam capability/extension/grants farkını manifest'e al; migration advisor + gerçek API test |

Supabase API erişiminde GRANT ile RLS'nin farklı katmanlar olduğu güncel resmi belgede açık. Yeni tabloların otomatik açılacağı varsayımı güvenli değil. [Supabase API güvenliği](https://supabase.com/docs/guides/api/securing-your-api). Oturum iptali ile eldeki JWT süresinin ilişkisi nedeniyle hassas işlemlerde session doğrulama gereksinimi ayrı değerlendirilir. [Supabase sessions](https://supabase.com/docs/guides/auth/sessions).

### 16.2. 12 Eylül 2026 tarihli platform değişiklik kontrolü

Bu tur changelog okundu. Aşağıdakiler projede kesin arıza var demek değildir; P00 keşif ve P01/P16/restore testine eklenmiş dış değişim riskleridir:

- Yeni public tablolar için explicit API grant davranışı: Supabase duyurusunda yeni proje varsayılanı ve 30 Ekim 2026 mevcut proje geçişi bulunuyor. Yeni migration'lar mevcut defaults ne olursa olsun gerekli minimum grant/RLS/policy'yi birlikte tanımlayacak. [Resmi duyuru](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
- Management API logs.all endpoint geçişi: duyuru 23 Eylül 2026 kaldırılma tarihi veriyor. Eski A0 CLI runbook'ları, panel ve teknik teşhis araçlarının bu endpoint'e bağımlılığı P00/P16'da aranacak; yeni logs/ClickHouse sorgu sözleşmesi gerekiyorsa ayrı adaptör testi. Ana repo ilk dar taramasında doğrudan eşleşme görülmedi; bütün dış araçların temiz olduğu sonucu çıkmaz. [Resmi logs geçişi](https://supabase.com/changelog/48235-migration-of-supabase-management-api-logs-all-analytics-endpoint-to-logs-endpoint).
- Extension version pinning değişimi: restore sırasında SQL'deki VERSION metni gerçek kurulu extension sürümünü garanti sayılmayacak; hedef ortamdan sürüm okunup davranış test edilecek. [Resmi extension duyurusu](https://supabase.com/changelog/extension-version-pinning-ignored).

Uygulama başlamadan ve production migration öncesinde changelog/CLI --help tekrar kontrol edilir. Bu tur CLI güncellenmedi, yeni migration oluşturulmadı. Deneysel DDL yalnız izole local DB'de; kalıcı migration repo prosedürüne uygun CLI üretimi ve tekrar oynatılabilir testle hazırlanır; production üzerinde deneme DDL yok.

### 16.3. Secret, CLI ve imzalama envanteri

P00 manifest'inde yalnız secret adı, sahibi, kullanım amacı, environment ve erişim yolu bulunur; değer bulunmaz. Mevcut scripts/rd_ops_env.mjs Keychain wrapper'ı korunur. CLI komutları kurulu --help ile doğrulanır; eski dokümandaki komut metni körlemesine çalıştırılmaz. Örneğin account/RevenueCat silme araçları hiçbir otomatik smoke zincirine girmez.

Kontrol grupları: Apple signing/provisioning ve APNs; Android upload keystore/app-signing fingerprint; Google OAuth/Firebase/Play service account; Supabase DB/Auth/Edge secrets; RevenueCat client public/server secret/webhook authorization; e-posta taşıyıcısı; mevcut AI sağlayıcı anahtarları; admin Vercel/Cloudflare sırları; gelecekte scan/render worker kimliği. Yeni sistem başka secret üretme ihtiyacı doğurursa amacı/rotasyon/erişimi ayrıca onaylanır. Keychain'in tamamı rastgele arşivlenmez.

## 17. Geri yükleme, migration ve yayın runbook'u

### 17.1. P00 geri yükleme provası

Amaç eski commit'e checkout yapmayı değil, çalışan ürünü geri kurabilmeyi ispatlamaktır. Mevcut checkpoint hash kontrolü ve arşiv varlığı önemli, tek başına yeterli değil.

1. Ana uygulama, operasyon paneli, store manifest'i ve kullanılan dış konfigürasyonların zaman/commit/hash envanteri. Varsa submodule commit ve içerik erişimi; .agents/aso-skills git submodule kaydı unutulmaz.
2. Mevcut 12 Eylül backup checksum ve archive integrity tekrar doğrulaması. Bu tur Auth COPY kapsamı yeniden kontrol edildi; eski hatalı kapsam notu ileride checkpoint runbook'unda düzeltilmeli.
3. Ayrı, erişimi kısıtlı test hedefi; production webhook, cron, SMTP, APNs, FCM ve AI outbound kapalı. Yönetilen Auth/Storage yapıları hedef platform sürümüne göre hazırlanır; dump körlemesine sistem şeması üstüne basılmaz.
4. Roles/schema/data/migration history/extensions/grants/RLS/cron/job ayarları uyumlu sırayla. Migration history'nin SQL dump'ta var olduğu varsayılmaz; ayrı doğrulanır. Auth kimlik/identity ilişkileri ve profile FK'leri kontrol edilir.
5. Storage bucket/policy/object metadata ile 588 yedek dosya envanteri/hash eşlemesi; örnek clean erişim ve foreign owner reddi. Metadata var, binary yok durumları raporlanır.
6. İzole uygulamayla şirket/analiz/rapor okuma; Auth test hesabı doğrulaması; abonelik store çağrısı yapmadan UUID/RC mapping ve read projection kontrolü.
7. Yeni migration/backfill setini bu başlangıca uygula, tekrar çalıştır, old-client smoke ve referans sayımlarını karşılaştır. Canlıdan fark varsa row count'a ek içerik/hash/aggregate invariant kontrolü.
8. RPO ve RTO ölç: backup zamanı ile veri referans zamanı; hedef hazırlanmasından kullanılabilir duruma süre. Kabul edilen hedefler kullanıcıyla kaydedilir, sonuç uydurulmaz.
9. İkinci şifreli/offline veya bağımsız konum kopyası ve anahtar erişim prosedürü. Hedef kullanıcı tarafından seçilir; bilinmeyen buluta hassas veri yüklenmez.
10. Restore kanıt raporu: başarılar/eksikler/harici bağımlılıklar; hassas satırlar değil sayım/hash. Test ortamı kontrollü temizlenir; üretim anahtar rotasyonu yanlışlıkla tetiklenmez.

Supabase resmi restore rehberi, backup türü ve hedef platform farkları için uygulama anında izlenir; Storage nesneleri ve dış ayarların ayrı kapsamı doğrulanır. [Supabase backup/restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).

### 17.2. Migration dalgası öncesi kontrol

- Hedef environment/project ref, commit, migration listesi, schema diff, dirty state ve yeni backup zamanı doğrulandı mı?
- İşlemin lock/timeout/row scan/indeks maliyeti staging'de ölçüldü mü? Büyük batch'ler restart/checkpoint destekli mi?
- Eski binary eski endpoint/enum ile aynı cevabı alıyor mu? Yeni tablo GRANT+RLS politikaları fixture dışında REST ile denenmiş mi?
- Backfill unknown/duplicate/orphan/legacy-write-after-backfill raporu temiz mi?
- Rollback'in hangi flag/producer/read path'i değiştireceği belli mi? Eski backend yeni yazılan veriyi görmezse kullanıcıya ne olacak?
- Notification producer, worker ve store katalog sırası açık mı? Yeni producer shadow iken e-posta/push çıkışı gerçekten sıfır mı?

### 17.3. Rollout sırası

| Adım | İşlem | Geçiş şartı |
|---|---|---|
| R0 | Tasarım/ticari/mevzuat/store ve kapsam kararlarını dondur | §19 kritik OPEN yok; kaynak hash belli |
| R1 | Onaylı additive schema + kapalı flags + compat backend | Eski üretim binary smoke; migration/grants kontrolü |
| R2 | Floor/workplace/backfill dry-run → batch → catch-up | Hak kaybı/orphan/duplicate sıfır |
| R3 | Worker ve projection shadow; notification/kampanya çıkışı kapalı | Eski-yeni projection farkları açıklanmış |
| R4 | iOS TestFlight + Android internal/closed test; mevcut kayıtlara aday build | İmza/kimlik; install-over-update; iki platform E2E |
| R5 | Offer katalog konfigürasyonu gerekiyorsa onaylı kontrollü adım | Eski binary+new catalog testleri ve gerçek fiyat/phase kanıtı |
| R6 | İnsan onaylı mağaza update gönderimi | Privacy/Data Safety/review notları/hesap erişimi ve build manifest'i |
| R7 | Sınırlı teknik pilot, kullanıcı verisi korunarak gözlem | P0/P1 ihlali yok; queue/latency/cost kabul aralığı |
| R8 | Genel özellik açılışı ve bütün eligible legacy Plus/Pro'ya all-core hak | Geç güncelleyenleri kapsayan catch-up; kalıcı keyfi dışlama yok |
| R9 | Kampanya family ve iletişim kanallarını ayrı kontrollü aç | Lifecycle/store/consent/budget gate'leri geçilmiş |
| R10 | Stabilizasyon ve roll-forward düzeltme | Ölçüm raporu; bir sonraki temizlik kararı ayrıca |

Apple/Google inceleme ve dağıtım zamanları aynı olmayabilir. Bir platform önce güncellendiğinde aynı hesaptaki eski diğer platformun schema/capability ve quota davranışı test edilmelidir. Genel abonelik hakkı cihaz sürümüne göre iki farklı ekonomik hak yaratmaz; eski UI'nın henüz ekranı olmamasıyla server hakkının olmaması ayrıdır.

### 17.4. Durdurma / rollback matrisi

| Olay | Anında dar kapsamlı aksiyon | Korunacak |
|---|---|---|
| Cross-tenant okuma/yazma | İlgili yeni endpoint/signed URL mint kapalı; olay müdahalesi ve erişim incelemesi | İlgisiz eski ürün; audit kanıtı; yeni veri silinmez |
| Hak kaybı/yanlış quota | Yeni decision/cutover shadow/read-only; onaylı otoriteye dönüş; düzeltme defteri | Mevcut paid erişim/floor ve gerçekleşmiş sonuçlar |
| Çift reward/yanlış fiyat | Yeni quote/qualification producer pause; insan ekonomik inceleme | Store kabul edilmiş işlem ve settlement consumer |
| Scan sorunu | Yeni upload promotion/import/render bloke; quarantine | Önceden doğrulanmış temiz dosyalar ve legacy erişim |
| Bildirim fırtınası/rıza ihlali | İlgili kategori/kanal producer pause; pending version suppression | Tercihler, once/episode geçmişi; toplu resend yok |
| Hatalı kural/skor | Yeni rule publish/consumer pause; önceki onaylı sürüm veya needs_review | Belge snapshot'ı ve audit; tarihçe yeniden yazılmaz |
| Mobil crash | Mağaza rollout pause + mevcut uyumlu flag fallback + hotfix | Bundle/package; session/cache mümkün olduğunca korunur |
| DB hasarı | Olay komutası, yeni write stop, son veri/delta capture; özel restore kararı | Backup sonrası geçerli verinin kaybolmaması için mutabakat |

Git tag'e dönmek yalnız kaynak kodu geri getirir; DB/store/worker state'i geri getirmez. Production DB'yi 12 Eylül yedeğine basmak olağan rollback yöntemi değildir: yeni kayıtları kaybettirir. Varsayılan geri dönüş yeni write'ları kapatıp veriyi okuyabilmek ve roll-forward düzeltmedir. Restore sadece felaket kurtarma kararı ve güncel delta planıyla.

Sayısal eşik beklemeden durdurulacak sınıflar: cross-tenant, parola/token sızıntısı, tracking ihlali, taranmamış dosya erişimi, eski abonenin hak kaybı, yinelenen tahsilat/ödül/kota, yanlış kampanya fiyatı, rızasız mesaj. Performans alarm eşikleri ayrı ölçülür.

## 18. Tasarım teslimi ve native entegrasyon

Kullanıcıdan gelecek paket: görünür adın TR/EN yazımı, logo/ikon kaynakları, light/dark renk-token listesi, tipografi/lisans, ekranlar ve bileşen state'leri, boş/hata/loading/read-only/offline/conflict durumları, mobil breakpoint/spacing, rapor şablonları ve mağaza asset'leri. Eksik varyasyon tasarım karar kaydına girer; sessizce final tasarım icat edilmez.

Her asset dosyası checksum, kaynak, kullanım yeri ve sürümle manifest'e alınır. iOS/Android ekran eşleme tablosunda aynı feature'ın native navigasyonu, metinleri, accessibility label, test ID, input validation ve behavior parity bulunur. UI piksel eşitliği platform davranışını bozmak için kullanılmaz; aynı iş sonucu ve onaylı görsel sistem korunur.

Yeni ana kabuk: portföy/firma bağlamı ve modül gezinmesi, eski analiz/rapor girişleri, kişisel defterin bağımsız girişi, profil/abonelik/izin ayarları. Belirli tab sayısı veya nihai yerleşim bu plan tarafından kesinleştirilmez. Eski turuncu ve mevcut paywall varlıkları baseline kapsamında korunur; yeni marka sırasında silinmez. Gelecekte A/B kararı verilirse görünüm variant'ı billing/gift/eligibility iş kurallarından bağımsız olmalıdır; bu tur A/B açılmadı.

Testler: küçük iPhone ve Android ekranında klavye/düğme erişimi; büyük yazı; VoiceOver/TalkBack; uzun Türkçe şirket/çalışan adı; EN metin uzaması; renk körlüğü/kontrast; reduced motion; network pending; paywall/OS permission modal çakışması; çıkış ve geri tuşu; rotation destek politikasına göre. Screenshot golden'ları kullanıcı tasarım onayıyla güncellenir; yanlış UI'yı geçirmek için topluca baseline regenerate yapılmaz.

## 19. Açık kararlar: hangisi geliştirmeyi, hangisi yayını bekletir?

Bu tur soru-cevap beklenmeden güvenli altyapı planı hazırlanmıştır. Aşağıdaki konular uygulamada ilgili kapıya gelmeden kesinleşmelidir; öneri, kullanıcının onayı yerine geçmez.

| Karar | V5 / bu planın güvenli başlangıcı | Kim/kanıt | Engellediği adım |
|---|---|---|---|
| K01 Görünür ad ve marka | İSG Adası hedef adı; TR/EN mağaza yazımı/ikon/tasarım kullanıcıdan | Kullanıcı tasarım manifest'i | P18 final/P20 |
| K02 Şirket/storage sayıları | Plus3/Pro30 ve 5/50GiB aday; eski Plus5 floor korunur | Kullanıcı ticari kararı + canlı mevcut plan manifest'i | P03 yeni policy publish |
| K03 Personel/eğitim hard-limit | İlk hedef hard-limit yok; teknik abuse sınırı ayrı | Ticari onay + maliyet testi | P03/P07 genel aktivasyon |
| K04 Quota dönem/rapor ayrıntısı | Mevcut helper tek otorite; free standard PDF ve ücretli report sınırı korunur | P00 gerçek SQL/API fixture | P03 settlement cutover |
| K05 Legacy cutoff/istisna | Lansman anı; geç update korunur; sınırsız floor açık | Kullanıcı + dry-run exception raporu | P20 genel hak geçişi |
| K06 Yıllık davetçi | Aylığa otomatik çevrilmez; aday hakkı uygun aylık döneme bankalama | Kullanıcı; süre/expiry/plan değişimi kararı | P15 annual dalı |
| K07 Qualification ve tekrar | İki gün anlamlı server kullanım; 30 gün aday pencere; once-per-role/program aday | Kullanıcı + abuse/maliyet simulation | P15 ödül üretimi |
| K08 Gift aktivasyon/çakışma | Açık aktivasyon, 7×24h, reset yok; aynı anda gift/paid/diğer gift politika tablosu | Kullanıcı + lifecycle testi | P14/P15 gift açılışı |
| K09 Winback takvimi | 72h/14day/iki temas aday; once-family | Kullanıcı, gerçek store uygulanabilirliği | P15 campaign publish |
| K10 Teklif fiyatları | %20 hedef; actual store price/phase; legacy kullanıcı pahalıya geçmez | Store pricepoint/katalog kanıtı | P14 store gate/P20 |
| K11 E-posta altyapısı ve rıza | Mevcut auth mail ile marketing aynı kabul edilmez | Provider/consent/deliverability ve kullanıcı kararı | P12/P15 email açılışı |
| K12 Bildirim frekansı | V5 cooldown/quiet-hour/cap önerileri sürümlü config | Kullanıcı + simulation | P12 publish |
| K13 Dosya limit/worker | 13 format zorunlu hedef; teknik worker ve byte/bellek limitleri spike | P04 corpus, maliyet, güvenlik raporu | P04 real upload |
| K14 Resmi eğitim/kural oracle | 2026 metin ve istisnalar teyit edilmeden published değil | Resmi kaynak + içerik uzmanı | P06/P07 automatic compliance |
| K15 Skor ağırlıkları | Aday 25/25/15/15/10/10; gönüllü nötr, unknown provisional | Kullanıcı/alan uzmanı + fixtures | P17 publish |
| K16 Saklama/silme | Veri türü bazında gerekçeli retention; minimum audit | Veri sorumlusu/hukuki inceleme | P19/P20 |
| K17 Yedek ikinci konum/RPO/RTO | Aynı disk dışı şifreli kopya; hedef henüz seçili değil | Kullanıcı + restore ölçümü | P00 riskli faz/P20 |
| K18 Desteklenen OS/build penceresi | Mevcut min iOS16/Android26 korunarak başla | P00 store/SDK/device envanteri | P18/P20 |
| K19 Dış paylaşım | Uzmanın OS paylaşımı dışında alıcı portalı/hesabı yok | Kullanıcı yeni kapsam isterse ayrı karar | Share-grant genişlemesi |
| K20 Kampanyalar lansmana yetişmezse | Sessiz kapsam daraltma yok; modül güvenli yayınına ayrı ürün kararı | Kullanıcı | P20 lansman kapsamı |
| K21 Not local/push sahipliği | Installation bazlı tek strateji; exact teslim garantisi yok | P13 cihaz spike + UX kararı | P13 reminder rollout |
| K22 Admin ve web koordinasyonu | Mevcut panel genişletilir; sibling repo değişiklikleri ayrıca scope'lanır | Repo sahibi, ayrı checkpoint/contract | P16 admin release/P18 linkler |

## 20. Risk kaydı ve önceliklendirme

| Risk | Öncelik | Erken önlem | Yayın kanıtı |
|---|---|---|---|
| Eski Plus haklarının 5→3 azalması | P0 | Legacy floor helper truth table | X04/X06 ve tüm eligible kullanıcı dry-run |
| Rename sırasında bundle/package/Keychain değişimi | P0 | Identity manifest ve denylist diff | X01/X02; install-over-update |
| Başka firmanın personel/dosya bağlanması | P0 | Composite FK + RLS + API owner | X12 ve SEC-* gerçek authenticated |
| Store teklifinin yanlış/fazla ücretlendirmesi | P0 | P14 erken proof; normal purchase guard ayrı | X36–X41 iki store evidence |
| Gift/discount karışıp yetkisiz paid erişim | P0 | Server source ayrımı; bütün helper listesi | X32/X33/X35 |
| Resmi kuralın hatalı otomatik uygunluk vermesi | P0 | Kaynak+human gate; needs_review | REV/EDU oracle ve P06/P07 onayı |
| Dosya parser'ında zararlı içerik/TOCTOU | P0 | Quarantine/networkless worker/immutable hash | X21–X23 |
| Rızasız/çift bildirim veya eski job | P0 | Ownership registry/send-time consent/version | X47–X49 |
| Yeni migration legacy Auth/AI/report'ı bozması | P0 | Additive contract+16 compatibility kombinasyonu | X03/X58 |
| Restore'un yalnız kağıt üstünde olması | P0 | DB+Auth+Storage drill ve ayrı panel checkpoint | X57 |
| Outbox/ledger yarışında çift tüketim | P0 | Transaction/idempotency/reconcile | X08–X11/X40/X41 |
| ATT'siz görünürken reklam tracking sürmesi | P0 | Client+server+old queue network audit | X53 |
| Kişisel notun şirket verisine dönüşmesi/silinmesi | P1 | Strict DTO ve bağımsız cache/schema; conflict | X50–X52 |
| Global Auth config eski kullanıcıyı kilitlemesi | P0 | Isolated auth staging+old binary | X28–X31 |
| Pre-submit hatanın panelde görünmemesi | P1 | Teknik trace'i analyses satırından bağımsız başlat | X54/E14 |
| Ayrı admin deposu değişikliklerinin kaybolması | P1 | Dirty worktree koruma; checkpoint scope'u | P00 manifest ve panel regression |
| Tasarım beklenirken final UI varsayımı | P1 | State contract önce, asset onayı sonra | X59 |
| Platform breaking change / SDK wrapper farkı | P1 | Changelog+actual installed API spike | §16.2, P00/P14 |
| Büyük import/render DB ve AI'yı yavaşlatması | P1 | Ayrı worker, limit/backpressure, query index | P19 load/memory/queue budget |
| Kampanya ölçümünde vadesiz renewal'ı başarısız saymak | P1 | Mature cohort/denominator/state bazlı rapor | V5-53, P16 lifecycle analytics |

P0/P1 buradaki plan önceliğidir; mevcut kodda doğrulanmış güvenlik açığı iddiası değildir. Somut arıza bulunduğunda ayrı bulgu/kanıt/etki kaydı açılır; teşhis ile uygulama yetkisi ayrılır.

## 21. V5'in tamamının bu plana izlenebilirliği

### 21.1. 44 bölüm eşlemesi

| V5 bölümü | Bu plandaki iş sahibi | Kanıt / test grubu |
|---|---|---|
| 1 Ürün kapsamı | P00/P01 | §4 değişmezleri, REV/SEC |
| 2 Korunacak mevcut sistem | P00/P03/P19 | B01–B17, X01–X06/X58 |
| 3 Ürün/gezinme | P18 | E01/E08/E09, UX/X59 |
| 4 Modül/uygulanabilirlik/skor | P06/P17 | REV03–06,SCO,X20 |
| 5 Firma/işyeri/personel | P05 | D05,REV01/21/23,X07/12/13 |
| 6 Eğitim | P06/P07 | REV02/07–16,X14–16,E04 |
| 7 Risk sürümü/tarih | P08 | REV17–20,DAT02,X17/18 |
| 8 İzin formları | P10/P11 | REV22,E08 |
| 9 Taşeron | P05/P10 | REV23,E08 |
| 10 Diğer modüller | P10/P11 | §7.5 her satır ayrı E08 |
| 11 Teknik mimari | P01/P04/P06 | §5, DAT/X09–11 |
| 12 Veri/güvenlik | P01/P05/P19 | D01–D16,SEC,X12/56 |
| 13 API/RPC/olay | P01 | Contract registry, DAT,X09–11/X60 |
| 14 Kural/süre | P06 | Rule oracle, X15/20/49 |
| 15 Evrak/PDF/XLSX | P04/P11 | DOC,X24/25,E07 |
| 16 Import | P11 | IMP,REV24,X26/27 |
| 17 Bildirim | P12 | NOTIF,REV20,X47–49 |
| 18 Skor/istatistik | P17 | SCO,REV04–06,X20 |
| 19 Gizlilik/yaşam döngüsü | P01/P16/P19 | SEC/PRIV/DEL,X53/55/56 |
| 20 Native/offline | P02/P13/P18 | NOTE/REM,X01/02/28/51/52/59 |
| 21 Rebrand/abonelik | P03/P18/P20 | BILL/UX,X01–06 |
| 22 Geçiş | P00/P19/P20 | OPS,X03/07/57/58 |
| 23 Faz/iş paketleri | P00–P21 | §15; eski numara eşlemesi aşağıda |
| 24 Kabul/yayın | P19/P20 | CSV 24.1+24.2 toplam51 |
| 25 Risk/ilk işler | P00/P14/P19 | §§4.2/15.3/19/20 |
| 26 Auth/parola | P02 | AUTH,X28–31,E02/E03 |
| 27 Abone geçişi | P03 | BILL,X04–06,E12 |
| 28 Kota/maliyet | P03/P14 | QUOTA,X08/32/33 |
| 29 Analitik/edinim | P16 | PRIV,X53 |
| 30 Hata/admin | P16 | OBS,X54/55,E14 |
| 31 Dosya format/güvenlik | P04/P11 | FILE,X21–27 |
| 32 İzin/bildirim stüdyosu | P12/P16 | NOTIF,X31/47–49/55 |
| 33 Davet | P14/P15 | REF,V5,X42/43 |
| 34 Kişisel not/reminder | P13 | NOTE/REM,X50–52,E09 |
| 35 Kullanıcı tasarımı | P18 | UX,X59 |
| 36 Güncel model/servis | P01/P03/P13–16 | §6, function manifest |
| 37 Birleşik sıra/kabul | P00–P21 | CSV37.3 toplam48; §15 |
| 38 Kaynak/sınırlar | P00/P06/P14 | Kaynak hash; §§11/16; resmi store dokümanları |
| 39 A0 entegrasyon haritası | P00/P01/P03/P18 | B01–B17,identity manifest,compatibility |
| 40 V4 kabul mirası | P19/P20 | CSV40.2 V4-01..48 tamamı |
| 41 Winback | P14/P15 | V5,X44/45,E11 |
| 42 Store teklif/hak defteri | P14 | V5,X32–41,E10/E11 |
| 43 Kampanya ölçüm/admin | P15/P16 | V5,X46/53/55; mature cohort |
| 44 V5 paket/kabul/emir | P14–P20 | CSV44.2 V5-01..56; uygulama değil plan kapsamı |

### 21.2. Eski iş paketi adlarından tek numaraya geçiş

| V5/WP referansı | Bu plan |
|---|---|
| WP-00 / V4-A / V5-A | P00 |
| WP-01–02 | P01 + §4 karar kaydı |
| WP-03 | P05 |
| WP-04 | P01/P03 |
| WP-05–06 | P06/P07 |
| WP-07 | P08 |
| WP-08 | P04/P11 |
| WP-09 | P11 |
| WP-10 | P12 |
| WP-11 | P17 |
| WP-12 | P19 + §6.4 |
| WP-13 | P18 |
| WP-14 | P00/P19/P20/P21 |
| WP-15 / V4-B | P02 |
| WP-16 / V4-F | P03/P14 |
| WP-17 | P03 |
| WP-18 | P16a/P16b |
| WP-19 / V4-D | P04 |
| WP-20 / V4-C | P12 |
| WP-21 / V4-G / V5-D | P15 |
| WP-22 / V4-E | P13 |
| WP-23 | P18 |
| V4-H / V5-G | P19/P20 |
| V5-B–C | P14 |
| V5-E | P15 |
| V5-F | P16b |

F0–F12 önceki üst seviye fazları P00–P21 içinde ayrıntılandırıldı; yeni iş takibinde iki bağımsız “tamamlandı” listesi tutulmaz. Test ID'leri ise geçmiş izlenebilirlik için korunur.

### 21.3. Bu planın teslim sınırı

Hazır olanlar: kaynak V5'in değişmez kopyası; kod/yedek/panel kapsam farkları; 22 iş paketi ve bağımlılıkları; veri/olay/API/migration/rollback yaklaşımı; 203 kaynak kabul senaryosunun kayıpsız kaydı; 60 ek geçiş senaryosu; tüm fonksiyonlar için test zarfı ve otomasyon/yayın kapıları.

Henüz yapılmayanlar: yeni özellik kodu, yeni DB migration'ı, yeni otomatik test runner/suite'leri, restore provası, gerçek mağaza indirimi, yeni tasarım, panel değişikliği, store/deploy/production değişikliği. Bu turdaki 5 mevcut statik testin başarısı bu işleri tamamlanmış göstermez.

Uygulama onayı sonrası ilk iş P00'dır. Tasarım bekleyen işler dışında contract, güvenlik, hak koruma, test omurgası ve teknik spike'lar ölçülebilir çıktılarla ilerleyebilir. İlgili kapının yetkisi/kararı eksikse orada durulur; geriye dönülemez veya kullanıcı hakkını azaltan varsayım yapılmaz.

### 21.4. Bu tur yapılan belge doğrulaması

Otomatik belge kontrolleri başarılı: kaynak kopyanın SHA-256 eşitliği; 203 CSV satırının benzersiz bölüm+ID anahtarı ve orijinal satır numarası; 60 ek X testi; 22 P iş paketi; 44/44 kaynak bölüm eşlemesi; 10 yerel dosya bağlantısının varlığı; Markdown başlık boşlukları ve kod bloğu kapanışları. Kaynak test statülerinin tamamı NOT_IMPLEMENTED/NOT_RUN olarak doğrulandı. Bu kontroller test senaryolarının uygulamada başarıyla çalıştığını veya Mermaid görsellerinin piksel olarak render edildiğini iddia etmez.

Mevcut node client-flow sözleşme testi 5/5 başarılı; tracked uygulama kodunda değişiklik yok. Oluşturulanlar yalnız bu plan, V5 kabul kaydı ve değişmez kaynak kopyasıdır. Önceden bulunan artifact'lar ve operasyon panelinin kirli çalışma ağacı korunmuştur.
