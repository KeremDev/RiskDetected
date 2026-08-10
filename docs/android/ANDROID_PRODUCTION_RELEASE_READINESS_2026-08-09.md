# Android 1.5.0 production release kapanış kaydı

Branch: `codex/android-release-readiness`

Referans: `app-store-live-1.3.1-build-81-baseline-2026-08-06`

Package/version: `com.riskdetectedan.app`, `1.5.0`, versionCode `1` (Play Console'da
kullanılmadığı owner tarafından doğrulanacak).

## Bu dalda tamamlanan anahtarsız işler

- Debug/QA staging, release production olacak şekilde fail-closed Gradle ayrımı.
- Upload signing yalnız `ANDROID_UPLOAD_*` environment/CI secret'larından okunuyor.
- Production Supabase/OAuth/RevenueCat/Firebase public yapılandırması source fallback'ı kullanmıyor;
  release CI ortamından eksik olduğunda build fail-closed duruyor. Bilinen production public
  kimlikleri yalnız debug/QA sızıntısını engelleyen karşılaştırma sentinel'ları olarak tutuluyor.
- Manuel `android-release-candidate` CI: iOS freeze, Deno, pgTAP, unit/golden, lint, R8,
  signed AAB, bundletool, 16 KB, signature, secret ve iOS asset kontrolleri.
- QA varyantı da R8/minify/resource shrink ile release-benzeri derleniyor; placeholder Firebase
  varken mapping upload kapalı, gerçek QA Firebase kimliği geldiğinde açık.
- Crashlytics Analytics olmadan eklendi; debug collection kapalı ve PII-siz sınır kullanıyor.
- Install Referrer bir kez okunuyor, AD_ID istemiyor ve yalnız allowlist attribution alanlarını
  RevenueCat'e iletiyor.
- In-App Review: en az 7 gün kullanım ve üçüncü benzersiz başarılı rapordan sonra uygunluk
  kazanıyor; arşiv ve analiz sonucu üretim yollarının ikisi de sayılıyor.
- In-App Updates: backend hard/soft kararını immediate/flexible Play akışına çeviriyor.
- Uygulama kökü production `client` runtime gate'ini bootstrap sırasında fail-closed uyguluyor:
  policy yüklenene kadar ana akış açılmıyor, eksik/kapalı gate bloke ekranına düşüyor ve hard
  update kararı önceliğini koruyor. Böylece backend gate modelinin yalnız veri katmanında kalıp
  istemci tarafından atlanması engellendi.
- Adaptive launcher, round ve Android 13 monochrome kaynakları eklendi; onboarding'in iOS
  asset path bağı kaldırıldı. Mevcut adaptive foreground aynı ön-yuvarlatılmış bitmap'i kullandığı
  için gerçek cihaz ikon görsel kabulü yeni full-bleed marka master'ı gelene kadar açık kapıdır.
- Android legal bundle, pending review record, migration ve release-policy checksum'ları build
  sırasında birlikte doğrulanıyor; gerçek owner/hukuk onayı yalnız release varyantının ayrı
  fail-closed kapısında zorunlu.
- Web hesap silme queue migration'ı, request-only API, 24 saatlik `due_at`, idempotent worker,
  stale-claim recovery, sınırlı retry, PII'siz Resend alarmı ve audit PII temizliği tamamlandı.
- Profiles RLS politikaları davranışı koruyan tek SELECT/UPDATE/INSERT setine konsolide edildi.
- Beş SECURITY DEFINER RPC'nin auth/sahiplik/search_path/anon revoke testleri local pgTAP'te
  doğrulandı.
- Local Supabase reset sonrası 21 pgTAP dosyasında 475 test geçti; Edge Function paketinde 316
  Deno testi geçti; schema lint warning üretmedi.
- AAB içindeki symbol table taşıyan native kütüphaneler Play'in beklediği `lib/<abi>/*.so`
  yapısında ayrı, hash'lenen `native-debug-symbols.zip` artefaktına çıkarılıyor. Uygulamanın kendi
  NDK kodu eklenirse AGP `SYMBOL_TABLE` üretimi de açık.
- Onboarding Roborazzi baseline'ları sekiz ekran için görsel inceleme sonrası JDK 17 tabanına
  yenilendi ve change threshold `0` ile geçti.
- Analiz bekleme/polling, Free sonuçtaki sarı Plus ve yeşil Pro CTA'ları, Pro bulgu detayı ve
  PDF oluşturma overlay'i için dört ek Roborazzi baseline'ı görsel olarak incelendi ve threshold
  `0` ile doğrulandı. Backend risk band wire değerleri (`critical/high/medium/low/unknown`)
  fixture'larda da aynen kullanılıyor.
- `App/` kaynaklarında hem baseline→HEAD hem working-tree diff'i sıfır.
- Son tam yerel Android kapısı:
  `lint testDebugUnitTest verifyRoborazziDebug assembleDebug assembleQa bundleQa` toplam 639
  görevle geçti. Son mekanik API temizliğinden sonra `app:lintDebug app:bundleQa` ayrıca 496
  görevle tekrar geçti; QA APK source-secret/PII-log/AD_ID taramasından geçti.
- Minified QA AAB, pinned bundletool hash/validate, gerçek JAR imzası, 16 KB zip alignment,
  tüm ELF `LOAD` segmentleri, iOS asset sızıntısı ve paket-içi server-secret taramasından geçti.
  Bu kanıt release scriptinin çalıştığını doğrular; owner imzalı release AAB kanıtının yerine
  geçmez.

## Açık yerel parite kanıtları

Anahtar gerektirmeyen altyapı kapıları tamamlanmış olsa da aşağıdaki UI kabul yüzeyleri henüz
Roborazzi baseline'ına alınmadı; bunlar tamamlanmadan “golden matrisi tamamen yeşil” kabulü
verilemez:

- auth idle/e-posta/OTP/hata durumları
- dört ana tabın dolu ve boş durumları
- fotoğraf tepsisi, sıra ve işaretleme
- rapor arşivi/ayarları ve Excel üretim durumu
- tam Plus/Pro paywall varyantları
- profil, şirket ve hesap silme akışı

Bu ekranların gerçek veri bağımlı son durumları ayrıca staging E2E kanıtı gerektirir. Mevcut
12 golden yalnız onboarding ile kritik analiz/bulgu/PDF yüzeylerini korur; tüm ürün için görsel
parite kanıtı olarak sunulamaz.

## Owner signing töreni

2026-08-10 tarihinde RSA-4096 `riskdetected-upload` upload key repo dışında owner kasasında
üretildi. Parolalar macOS Keychain'de, keystore ise owner kontrollü Application Support
dizininde tutuluyor. Keystore, parolalar ve private key repo/issue/chat'e eklenmedi. Public
hash/fingerprint ve CI secret adları
`ANDROID_UPLOAD_SIGNING_RECORD_2026-08-10.json` kaydında yer alıyor.

Törende aşağıdaki kanıtlar kaydedilir:

- Keystore SHA-256 dosya hash'i; dosyanın kendisi repo/issue/chat'e yüklenmez.
- Upload certificate SHA-1/SHA-256.
- Play App Signing etkinleştirildikten sonra app-signing SHA-1/SHA-256.
- Firebase Android app ve Google OAuth kayıtlarında hem gerekli package hem fingerprint eşleşmesi.
- CI production environment secret'ları:
  `ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_STORE_PASSWORD`,
  `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`, `ANDROID_UPLOAD_CERT_SHA256`.
- CI, keystore alias'ının gerçek SHA-256 sertifika parmak izini owner kaydıyla eşleştirmeden
  release derlemesine başlamaz.

## Açık dış kapılar

| Kapı | Durum | Açılma kanıtı |
| --- | --- | --- |
| Upload key / Play App Signing | PARTIAL | upload key/CI/Firebase fingerprint tamam; ilk AAB sonrası Play App Signing fingerprint'i bekliyor |
| Staging Firebase/FCM | PASS | debug/QA Firebase app'leri, `google-services.json`, server credential ve foreground/background/killed gerçek FCM teslimi tamam; killed bildirimi Profil deep-link'ini açtı |
| Google OAuth | PARTIAL | staging web + debug/QA Android client'ları ve Supabase provider tamam; Credential Manager doğru client ile açılıyor, hesaplı cihaz E2E bekliyor |
| Apple OAuth | N/A | Android v1 kapsamından çıkarıldı; görünür CTA yok, iOS canlı akışı değişmedi |
| RevenueCat Android | PARTIAL | Play app, `default`, `plus`/`pro`, dört ürün, `qa_test_store`, Plus/Pro Test Store satın alma ve staging webhook→DB plan aktivasyonu tamam; ilk Play AAB sonrası gerçek Play transaction/RTDN bekliyor |
| Gemini gerçek analiz | PARTIAL | gerçek yüksekte çalışma fotoğrafında Android bekleme→2 bulgu→sonuç→PDF/XLSX zinciri geçti; 10 fotoğraf corpus ve İSG uzman kabulü bekliyor |
| Resend | PARTIAL | staging + production secret adları doğrulandı ve gerçek staging OTP e-postası teslim edildi; hesap silme talep/tamamlanma teslimi ile domain operasyon kanıtı bekliyor |
| Production canonical backend deploy | BLOCKED | canlı `app-release-policy` henüz `android_runtime_gates` döndürmüyor; staging E2E sonrası gate'ler kapalı additive deploy |
| Web `/hesap-silme` | BLOCKED | ayrı web repo deploy'u ve web kabul testleri |
| Web `/gizlilik` | BLOCKED | yayınlanmış Android metni ve erişilebilirlik kontrolü |
| Android hukuk/owner onayı | BLOCKED | pending kayıt gerçek reviewer ve tarih ile owner tarafından onaylanmalı |
| Play store icon | BLOCKED | ön-yuvarlatmasız 512×512 full-bleed master |
| Adaptive launcher görsel kabulü | BLOCKED | aynı full-bleed master ile Pixel/Samsung maske kanıtı |
| Feature graphic/screenshots | BLOCKED | 1024×500 + sekiz gerçek Android store görseli |
| versionCode 1 | BLOCKED | Play Console'da hiç kullanılmadığının owner kanıtı |
| Play owner cihaz doğrulaması | BLOCKED | yeni kişisel hesapsa owner, Play Console mobil uygulamasıyla gerçek Android cihaz erişimini doğrulamalı |
| Fiziksel cihaz matrisi | BLOCKED | Pixel + Samsung, API 26/33/37 kanıt paketi |
| Closed testing | BLOCKED | 12 tester × kesintisiz 14 gün |
| Pre-launch/Data Safety | BLOCKED | blocker'sız rapor ve owner onaylı beyan |

Production Gemini anahtarı iOS/Android ortak backend havuzunda kullanılabilir; anahtar Android
istemciye veya staging APK'ya konulamaz. Resend secret'ı yalnız Edge Function ortamında kalır.
2026-08-10 kontrolünde Resend secret değerleri/hash'leri okunmadan yalnız adlarının hem staging
`qlymhrrlhklcudveknih` hem production `ppcrzemgiztzcgddbins` projesinde bulunduğu doğrulandı.

## Anahtarlar geldikten sonraki kapı sırası

1. Staging `client/auth`; gerçek OTP tamamlandı; Google hesaplı cihaz, fresh install ve process-death bekliyor.
2. Profil ve salt-okuma.
3. `pdf_reports`; gerçek analizden cihaz PDF'i, 2 gerçek sayfa, arşiv ve paylaşım tamamlandı; silme ve şirket snapshot varyantı bekliyor.
4. Tek fotoğraf standart gerçek analiz tamamlandı; detaylı analiz ve kalan corpus bekliyor.
5. Multi-photo; sıra, işaretleme, idempotency ve recovery.
6. RevenueCat Test Store Plus/Pro satın alma ve webhook aktivasyonu tamamlandı; gerçek Play dört ürün, pending/cancel/refund/owner conflict ve cross-platform bekliyor.
7. FCM foreground/background/killed ve deep-link tamamlandı; reddedilmiş izin senaryosu bekliyor.
8. Minified signed Internal AAB üzerinde tüm akış smoke testi.

Her staging kapısı test sonrasında tekrar kapatılabilir. Production Android kapıları additive
backend dağıtımı boyunca kapalı kalır.

## Gerçek AI/PDF/XLSX kabulü

2026-08-10 staging kanıt koşusu:

- Gerçek `01-work-at-height.jpg` fotoğrafı Android galeri→işaretleme→İnşaat→Genel akışından
  gönderildi; iOS-parite bekleme ekranı gösterildi ve analiz `completed` oldu.
- İki bulgu üretildi: platform kenarında toplu koruma eksikliği (`FK=900`, critical) ve portatif
  merdivenin sabitlenmemesi (`FK=360`, high). Çıktı `tr`, `tr-TR`, `tr-tr-current-v1` sözleşmesiyle
  kaydedildi.
- Cihaz PDF'i `897286` byte ve gerçek `2` sayfa olarak üretildi; DB'deki `page_count` ve
  `report_page_count` değerleri de `2`.
- Sunucu XLSX'i `79429` byte üretildi, ZIP bütünlük testi geçti ve beş çalışma sayfası içerdi:
  Kapak ve Özet, Risk Analiz Tablosu, Risk Dağılımı, Metot Referansı, Rapor Bilgileri.
- Koşu sırasında Android create payload'ının server-owned `client_platform/client_build`
  sütunlarına doğrudan yazmaya çalıştığı için oluşan 403 düzeltildi. Platform artık analyze
  audit'inden güvenli trigger ile türetiliyor ve kayıt `client_platform=android`, `client_build=1`
  olarak doğrulandı.

- En az 10 sabit saha fotoğrafı; dosya hash'i, sektör, beklenen kritik tehlikeler ve uzman kabulü
  PII içermeyen corpus manifestinde tutulur.
- Android ve iOS aynı backend prompt/capability ile çalıştırılır.
- Kritik tehlike atlama veya platform kaynaklı semantik fark kabul edilmez.
- Bekleme/recovery, sonuç, bulgu detay, PDF ve XLSX her koşuda ekran görüntüsü + UI tree +
  filtrelenmiş logcat ile kanıtlanır.
- PDF/XLSX byte-identical aranmaz; bölüm sırası, bulgular, risk skorları, şirket bilgisi, renk
  semantiği ve gerçek sayfa sayısı eşit olmalıdır.

## Internal, closed ve rollout

- Owner ilk signed AAB'yi Internal Testing'e manuel yükler; CI production promotion yapmaz.
- Yeni kişisel geliştirici hesabında production erişiminden önce owner'ın gerçek Android cihaz
  doğrulaması da Play Console mobil uygulaması üzerinden tamamlanır
  ([Google Play resmi gereksinimi](https://support.google.com/googleplay/android-developer/answer/14316361?hl=tr)).
- Pre-launch blocker içermeden closed test başlatılmaz.
- En az 12 tester 14 gün kesintisiz opt-in kalır; tester kaybında Play Console uygunluk sayacı
  esas alınır.
- Closed test sağlık eşiği: crash-free session en az `%99,5`, Vitals bad-behavior uyarısı yok,
  auth/analiz/rapor ve webhook alarmları yeşil.
- Production sıra: review allowlist → küçük kohort → `%20` → `%50` → `%100`; her kademe en az
  24 saat sağlıklı kalır.

## Rollback

Rollback yalnız Android runtime gate, version allowlist ve Play rollout halt ile yapılır.
Tamamlanmış RevenueCat webhook'ları ve pending hesap silme işleri işlemeye devam eder. iOS
flag'leri, `App/` kaynakları ve canlı kullanıcı verileri değiştirilmez.
