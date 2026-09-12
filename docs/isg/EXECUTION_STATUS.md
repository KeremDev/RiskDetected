# İSG Adası geçişi — yürütme kaydı

Başlangıç: 12 Eylül 2026. Kullanıcı planın uygulanmasına devam edilmesini istedi. Bu dosya ilerledikçe güncellenir; master planın tarihli teslim açıklamaları tarihsel kayıttır.

## Güncel durum

- P00 devam ediyor: kaynak/kimlik/yedek kontrolleri, veritabanı restore'u ve kullanıcının seçtiği Masaüstü'ne şifreli ikinci kopya tamamlandı; tam servis/mobil restore ve mağaza envanterinin kalan kısmı açık. Masaüstü aynı disk; off-device koruma değil.
- P01'in production'a dokunmayan güvenlik/test dilimi başladı. Domain migration veya gerçek kullanıcıya özellik açılışı yok.
- P01 session freshness adayı gerçek yerel GoTrue JWT/session ile denendi: logout sonrası hâlâ imzalı token reddi, private ACL ve transaction lock ordering. Production RPC/gateway/domain entegrasyonu yok.
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
| Servis migration eki | İlk restore'da Auth/Storage ledger0/0 bulundu; read-only ek dump77/68, 8.690 byte; Masaüstü ana yedek içinde ayrı şifreli ek doğrulandı |
| Auth servis restore | Ayrı disposable gerçek veri kopyasında GoTrue v2.195.0, 474 ACL replay, 17/17 kontrol; sentetik password/login/refresh/logout/admin reddi ve profil trigger PASS; source unchanged, cleanup PASS |
| Auth + Storage servis restore | 42/42 kontrol; 588 dosyanın tamamı API hash/boyut/MIME/cache eşit; dört private bucket için owner/foreign/anon, imza bozma/yanlış path/expiry negatifleri; public5; metadata/source unchanged; dört container cleanup PASS |
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
| iOS teklif türleri | 16 paginated read PASS: yalnız Plus yıllık 175 intro kaydı, tümü 7 gün trial / 30 Eylül 2026 bitiş; dört üründe promotional/win-back/offer-code 0. Territory ilişkileri/hesap uygunluğu ayrı açık |
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
| Foundation Auth restore sonrası | 63/63 Node; ek18 izolasyon/eksik inspection/yanlış komut negatifleri. Gerçek restore verileri CI'a aktarılmadı |
| Foundation Storage restore sonrası | 80/80 Node; ek17 path/symlink öncesi biçim/boyut/header ve signed URL doğrulama testi; gerçek restore verileri CI'a aktarılmadı |
| Foundation session guard sonrası | 98/98 Node; ek18 local-only JWT signature/issuer/audience/expiry ve explicit opt-in/argüman negatifleri |
| Gerçek Auth session freshness | 33 guard kontrolü; Auth temel17 ile50/50; still-signed logout token DENY, expired/ban/deleted/anonymous/foreign claim reddi, row-lock ordering PASS; domain/gateway bağlı değil |
| Son birleşik servis provası | Auth + Storage + session75/75 PASS; 18:30:41–18:31:24 UTC; 588 dosya yeniden doğrulandı, source unchanged, dört container cleanup PASS |
| Sentetik Auth CI dilimi | Müşteri verisiz sıfırdan GoTrue/Auth77, tek hesap, session SQL ve gerçek logout48/48; foundation101/101; ayrı restore regresyonu75/75 yeniden PASS; iki ortam cleanup PASS |
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

[Auth servis restore ve migration eki](P00_AUTH_SERVICE_RESTORE.md), [17 kontrol ve kaynak hash'leri](evidence/P00_AUTH_SERVICE_RESTORE_2026-09-12.json). Offering düzeltmesi `7e64ce84`, App Store deneme takvimi `0567e9c9` commit'lerinde.

[Storage servis restore kapsamı](P00_STORAGE_SERVICE_RESTORE.md), [42 kontrol ve kaynak hash'leri](evidence/P00_STORAGE_SERVICE_RESTORE_2026-09-12.json). Önceki Auth/şifreli migration eki `a11c2cdc` commit'inde. Tam dosya byte kontrolü ile birer owner RLS örneğinin kapsamı ayrı tutuldu; orijinal ETag/mtime ve canlı signed URL korunumu iddia edilmiyor.

[P01 gerçek Auth session freshness prototipi](P01_SESSION_FRESHNESS_PROTOTYPE.md), [75 birleşik kontrol / kaynak hash'leri](evidence/P01_AUTH_SESSION_GUARD_2026-09-12.json). Storage dilimi `e519846d` commit'inde. Yeni helper yalnız disposable test şemasında; eski uygulama oturum davranışı ve prod Auth ayarları değişmedi.

[Sentetik Auth CI hazırlığı](evidence/P01_SYNTHETIC_AUTH_CI_2026-09-12.json): yeni `--synthetic-session` müşteri yedeğini okumaz; ayrı48 test ve foundation101 geçti. CI job'u eklendi/YAML parse PASS; uzak çalıştırma NOT_RUN. Önceki gerçek-session dilimi `7c971428` commit'inde.

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
node scripts/isg/run_auth_restore.mjs --isolated-copy
node scripts/isg/run_auth_restore.mjs --isolated-copy --with-storage
node scripts/isg/run_auth_restore.mjs --isolated-copy --with-storage --with-session-guard
node scripts/isg/run_auth_restore.mjs --synthetic-session
~~~

Restore ve capture modları offline foundation runner'a dahil değildir. Bunlar restricted backup çıktısı üretir ve yalnız açık P00 işlemi için çalıştırılır. Ayrı `--synthetic-session` yalnız yeni test verisi üretir; bu dar mod ayrı CI job'una bağlandı. Tamamlanmış restore'un üstüne yeniden yazma engeli var. Mevcut diğer Docker/Supabase stack'leri durdurulmadı veya resetlenmedi.

## Açık kapılar

1. Auth API restore sentetik hesapla; Storage API 588 dosya ve dört private bucket signed download/expiry negatifleriyle doğrulandı. Eski gerçek kullanıcının OTP/OAuth/parola ve token taşınabilirliği, eski signed URL, Storage write politikaları ve iki mobil platformla restore E2E henüz yapılmadı.
2. Kullanıcı ikinci kopya konumunu Masaüstü seçti ve kopya doğrulandı. Disk arızası için ayrı fiziksel konum ve anahtarın ayrı güvenli kurtarma kopyası hâlâ yok; bilinmeyen buluta veri gönderilmiyor.
3. Play etkin base plan/tek mevcut teklif/Türkiye fiyatları, App Store dört teklif türü ve RC üretim offering/entitlement eşlemesi doğrulandı. App Store territory ilişkileri, iki mağazada eski fiyat kohortları ve RC tüm dış servis ayarları hâlâ açık. iOS Plus yıllık deneme bitişi 30 Eylül 2026; değiştirilmedi.
4. iOS/Android aynı-plan gerçek indirim ve izleyen normal renewal deneyi henüz yapılmadı; mağaza yazımı ayrıca onaylı.
5. Tasarım, ticari aday parametreler ve resmi 2026 eğitim oracle'ı onay kapıları korunuyor.
6. P01 transport/native fixture, dar function-test map ve transaction/outbox/lease prototipi hazır. Production mutation migration/gerçek Auth-session-capability, tam function inventory/release gate, gerçek native E2E ve tam iOS app CI henüz tamamlanmadı.

Bu kapılar kapanmadan P00/P01 “tamamlandı” veya yeni domain “yayına hazır” sayılmaz. Güvenli ve bağımsız test/contract geliştirmesi sürdürülebilir.
