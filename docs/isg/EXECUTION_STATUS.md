# İSG Adası geçişi — yürütme kaydı

Başlangıç: 12 Eylül 2026. Kullanıcı planın uygulanmasına devam edilmesini istedi. Bu dosya ilerledikçe güncellenir; master planın tarihli teslim açıklamaları tarihsel kayıttır.

## Güncel durum

- P00 devam ediyor: kaynak/kimlik/yedek kontrolleri, veritabanı restore'u ve kullanıcının seçtiği Masaüstü'ne şifreli ikinci kopya tamamlandı; tam servis/mobil restore ve mağaza envanterinin kalan kısmı açık. Masaüstü aynı disk; off-device koruma değil.
- P01'in production'a dokunmayan güvenlik/test dilimi başladı. Domain migration veya gerçek kullanıcıya özellik açılışı yok.
- P03'ün ilk shadow dilimi hazır: eski şirket SQL truth table ve hak koruma hesabı. Yeni fiyat/limit/floor yayınlanmadı; uygulamaya bağlanmadı.
- P14 ilk regresyon düzeltmesi uygulandı: Android explicit offering bulunamadığında current'a fallback yapmıyor; iOS davranışıyla eşleşiyor. Yerel kod değişikliği, mağaza yayını değil.
- Production'da yalnız read-only envanter ve Auth/Storage şema yedeği alındı. DB/store/paid policy/notification değişikliği yapılmadı.
- Mevcut app bundle/paket, callback ve entitlement'ları değişmedi. UI ve kullanıcı tasarımı değiştirilmedi.
- Geliştirme dalı `codex/isg-transition-foundation`. Eski `riskdetected-change-point-20260912` etiketi `dbcc979d` üzerinde korunuyor. V5 plan/registry `0fd78e17`, P00 backup/restore araçları ve kanıtları `0d8b9bce`, P01 ilk test/contract dilimi `2fd6b9ef`, P03 shadow `8252f408` commit'lerinde. Henüz push veya deploy yapılmadı.

## Tamamlanan kanıtlar

| Kontrol | Sonuç |
|---|---|
| Eski checkpoint | 31 ana hash + 588 dosya hash; 6 arşiv + Git bundle doğrulandı |
| Auth dump kapsamı | 208 kullanıcı, 210 identity; auth verisi var. Önceki CHECKPOINT.md kapsam notu hatalı; eski hash manifest'ini bozmamak için orijinal dosya değiştirilmedi |
| Admin çalışma ağacı yedeği | backups/isg-panel-checkpoint-20260912-IZgsfU; 526 kaynak dosyası, binary diff, Git bundle; kaynak ağacı değişmedi |
| Auth/Storage DDL eki | backups/isg-managed-schema-20260912-HHgZf9; canlıdan read-only pre/post-data şeması; gizli/kişisel veri ihtimaline karşı 600/700 izin |
| Restore deneme 1 | application-schema aşamasında 42830: Auth PK/unique henüz yüklenmedi. Hata kanıtı korundu; boş test container'ı kaldırılıp yeniden kuruldu |
| Restore deneme 2 | backups/isg-managed-schema-20260912-v3faRK; Auth/Storage anahtarları önce, public bootstrap trigger sonra; 131 tablo satır sayısı eşit |
| İlişkiler | 214 foreign key gerçek veride denetlendi; 0 public tablo RLS'siz |
| Storage eşleme | 588/588, 512.280.146 byte; legal-documents doğrudan, diğer bucket'lar bucket/bucket şeklinde capture layout'u |
| RLS okuma | authenticated owner 4/4 kendi şirketini ve 1 profilini görüyor; foreign şirket/profil/analiz/rapor 0 |
| İzolasyon | isg_restore_20260912_db; network none, yayınlanan port/host mount yok; cron execution off |
| Extension farkı | Kaynak pg_net 0.20.0, restore image 0.20.4; dış ağ çağrısı test edilmedi, tam ortam paritesi iddia edilmiyor |
| Canlı şirket helper'ı | Plus 5, Pro 25; bir stored Plus profile için effective limit 0 gözlendi. profiles.tier tek başına aktif paid hak kaynağı olamaz |
| iOS mağaza kimliği | App 6769498181, bundle com.riskdetected.app, SKU riskdetected-ios doğrulandı |
| iOS ürünler | riskdetected_plus_monthly/yearly ve riskdetected_pro_monthly/yearly APPROVED; mevcut ürünler korunuyor |
| iOS TUR liste fiyatı | Plus aylık 249,99 / yıllık 2.499,99 TRY; Pro aylık 499,99 / yıllık 4.999,99 TRY. Kohort fiyatı ve teklif fiyatı kanıtı değil |
| Play katalog | Aynı dört ürün etkin, monthly/yearly base plan, Türkiye fiyatları iOS liste fiyatlarıyla eşleşiyor; aylık grace7/hold53, yıllık grace14/hold46 gün. Hold paid erişim değildir |
| Play mevcut teklif | Yalnız Plus yıllık trial-7d-v1: 7 gün, uygulamada daha önce hiçbir abonelik edinmemiş kullanıcı, etkin/Türkiye/backward-compatible |
| RC katalog | default offering dört paket × iki gerçek mağaza; plus/pro sekizer ürün (mağaza + QA); legacy Riskdetected Pro yalnız iki Test Store ürünü; Targeting ve Experiments boş |
| RC API erişimi | Mevcut anahtar v2 katalog okumasına 403 verdi; anahtar/yetki değişmeden açık dashboard'dan read-only doğrulama yapıldı |
| Android offering guard | 10 yeni seçim testi; tüm core:data 151/151, 27 sınıf, 0 fail/error/skip; tam debug APK build PASS. Kurulum, app launch veya satın alma yapılmadı |
| Ortak kaynak kontrolü | iOS bundle, Android package/namespace, auth callback, plus/pro entitlement geçerli |
| Test envanteri | 203 kaynak + 60 geçiş = 263 benzersiz kabul; henüz domain testlerine UNMAPPED, başarı iddiası yok |
| Foundation ilk test turu | 38/38 Node test; yanlış ortam ve kimlik mutasyon testleri dahil |
| Foundation güncel tur | 45/45 Node; şifreleme negatifleri, transport fonksiyon-test eşleme kapısı ve hostless iOS test envanteri dahil |
| Ortak context corpus | Deno 44/44 (43 fixture + 1 ilave test), Swift 43/43, Android 43/43 ayrı JUnit senaryosu |
| Sentetik DB transaction | 30/30; 20 paralel retry, 20 version yarışı, 20 worker claim, audit/outbox fault, lease expiry ve gerçek DB bağlantısı öldürme; cleanup PASS |
| P03 legacy DB matrisi | Ek 329/329 varyasyon; suite toplam 31 üst seviye kontrol PASS; orijinal helper gövdeleri restore ile eşleşti |
| P03 kapasite shadow | 17/17 Node grup, 864 sonlu kombinasyon; Plus5 floor, Pro aday30, unlimited, unknown sync ve downgrade ayrımı |
| Masaüstü ikinci kopya | ISG_Adasi_Yedek_2026-09-12_rX4mVI; 3.613.777.956 byte AES-256-GCM, authenticated decrypt/hash PASS; anahtar macOS Keychain; aynı disk |
| iOS ana proje derleme | XcodeBuildMCP build_sim PASS, Debug/no signing; iPhone 17 Pro iOS 26.5 kullanıcı izniyle açıldı. App launch/login yapılmadı |
| Gerçek iOS Simulator test | Yeni hostless ISGContractTests hedefi, 43 PASS / 0 FAIL / 0 SKIP; ana uygulama/SDK/ağ servisi yüklemeden aynı Swift kaynak kodu ve ortak JSON corpus |
| iOS mevcut uyarılar | PaywallDesignKit.swift:631–641 main-actor çağrıları için 11 uyarı; bu dosyada değişiklik yapılmadı |
| SwiftPM | 19 mevcut pin; Package.resolved için dar gitignore istisnası; SDK sürümü yükseltilmedi |
| CI | Yeni isg-foundation.yml: Node/Deno, saf Swift + hostless iOS XCTest, izole PostgreSQL testleri ve kanıt artifact'ları; henüz uzak CI'da koşmadı. Android corpus mevcut Android CI kapsamındadır |

Kanıt dosyaları: [yedek bütünlüğü](evidence/P00_BACKUP_INTEGRITY_2026-09-12.json), [DB restore](evidence/P00_DATABASE_RESTORE_2026-09-12.json), [Storage ve RLS](evidence/P00_RESTORED_DATA_2026-09-12.json).

Ek kanıtlar: [Masaüstü şifreli kopya](evidence/P00_DESKTOP_BACKUP_2026-09-12.json), [işlem prototipi](evidence/P01_TRANSACTION_PROTOTYPE_2026-09-12.json), [kapsam ve sınırlamalar](P01_TRANSACTION_PROTOTYPE.md). Bu platform test sayıları kaynak 203 kabul senaryosunun sayılarıyla karıştırılmamalıdır.

[iOS Simulator sonucu](evidence/P01_IOS_NATIVE_CONTRACT_2026-09-12.json) aynı kaynak/fixture hash'lerine bağlı 43 XCTest sonucunu kaydeder. Bu test hedefi ayrı uygulama veya mağaza kaydı değildir; iki mevcut uygulamanın bundle/package ID'leri değişmemiştir.

[P03 shadow kapsamı](P03_CAPACITY_SHADOW.md), [legacy DB matrisi](evidence/P03_LEGACY_CAPACITY_MATRIX_2026-09-12.json), [read-only snapshot karşılaştırması](evidence/P03_CAPACITY_SHADOW_SNAPSHOT_2026-09-12.json).

[Mağaza / RC mevcut katalog](P00_STORE_CATALOG_2026-09-12.md): yönetim sayfalarından read-only gözlemler, trial uygunluğu, grace/hold ayrımı ve offering platform farkı. CI tetik yollarına legacy oracle'ın kullandığı iki tarihsel migration da eklendi; migration değişirse ilgili test job'ları atlanmaz.

[P14 offering guard](P14_OFFERING_GUARD.md) ve [151 Android test / APK kanıtı](evidence/P14_ANDROID_OFFERING_GUARD_2026-09-12.json). Katalog ve CI yol düzeltmesi `f7c93f7a` commit'inde.

## Kullanılabilir yeni komutlar

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/verify_identity.mjs
node scripts/isg/verify_environment.mjs contracts/isg/v1/local-test-environment.example.json
node scripts/isg/build_test_manifest.mjs
node scripts/isg/verify_backup.mjs
node scripts/isg/verify_restored_data.mjs
node scripts/isg/verify_function_map.mjs
node scripts/isg/run_database_contract.mjs contracts/isg/v1/local-test-environment.example.json
node scripts/isg/run_suite.mjs capacity-shadow
node scripts/isg/read_legacy_capacity_snapshot.mjs
~~~

Restore ve capture araçları offline foundation runner'a dahil değildir. Bunlar restricted backup çıktısı üretir ve yalnız açık P00 işlemi için çalıştırılır. Tamamlanmış restore'un üstüne yeniden yazma engeli var. Mevcut diğer Docker/Supabase stack'leri durdurulmadı veya resetlenmedi.

## Açık kapılar

1. Auth API login, Storage signed download ve iki mobil platformla restore E2E henüz yapılmadı.
2. Kullanıcı ikinci kopya konumunu Masaüstü seçti ve kopya doğrulandı. Disk arızası için ayrı fiziksel konum ve anahtarın ayrı güvenli kurtarma kopyası hâlâ yok; bilinmeyen buluta veri gönderilmiyor.
3. Play etkin base plan/tek mevcut teklif/Türkiye fiyatları ve RC üretim offering/entitlement eşlemesi doğrulandı. App Store teklif türleri, iki mağazada eski fiyat kohortları ve RC tüm dış servis ayarları hâlâ açık.
4. iOS/Android aynı-plan gerçek indirim ve izleyen normal renewal deneyi henüz yapılmadı; mağaza yazımı ayrıca onaylı.
5. Tasarım, ticari aday parametreler ve resmi 2026 eğitim oracle'ı onay kapıları korunuyor.
6. P01 transport/native fixture, dar function-test map ve transaction/outbox/lease prototipi hazır. Production mutation migration/gerçek Auth-session-capability, tam function inventory/release gate, gerçek native E2E ve tam iOS app CI henüz tamamlanmadı.

Bu kapılar kapanmadan P00/P01 “tamamlandı” veya yeni domain “yayına hazır” sayılmaz. Güvenli ve bağımsız test/contract geliştirmesi sürdürülebilir.
