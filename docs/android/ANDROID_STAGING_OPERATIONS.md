# Android staging işletim sözleşmesi

Bu belge Android `debug`/`qa` ortamının production'dan ayrılmasını ve dış servis kabul kapılarını tanımlar. iOS canlı uygulamasının yapılandırması bu akışın parçası değildir.

## Yerel public istemci ayarları

Değerler yalnızca `android/local.properties` içinde tutulur; dosya Git'e eklenmez.

```properties
RD_STAGING_SUPABASE_URL=https://qlymhrrlhklcudveknih.supabase.co
RD_STAGING_SUPABASE_PUBLISHABLE_KEY=<sb_publishable_... veya anon client key>
RD_STAGING_GOOGLE_WEB_CLIENT_ID=<staging web oauth client id>
RD_STAGING_REVENUECAT_PUBLIC_KEY=<RevenueCat test public sdk key>
RD_STAGING_FIREBASE_PROJECT_ID=<staging firebase project id>

RD_PRODUCTION_SUPABASE_URL=<production url>
RD_PRODUCTION_SUPABASE_PUBLISHABLE_KEY=<production publishable key>
RD_PRODUCTION_GOOGLE_WEB_CLIENT_ID=<production web oauth client id>
RD_PRODUCTION_REVENUECAT_PUBLIC_KEY=<RevenueCat production public sdk key>
RD_PRODUCTION_FIREBASE_PROJECT_ID=<production firebase project id>
```

İstemciye `service_role`, `sb_secret_…`, Apple private key, Firebase service-account JSON veya AI sağlayıcı anahtarı konmaz. `./gradlew verifyEnvironmentIsolation` staging ve production public değerleri aynıysa ya da istemci anahtarı sunucu yetkisi taşıyorsa build'i durdurur. `release` derlemesi ayrıca `verifyReleaseEnvironment` üzerinden eksik production URL/public yapılandırmada fail-closed durur.

`app/src/debug/google-services.json` ve `app/src/qa/google-services.json` yalnız staging Firebase
projesinden gelir. 2026-08-10 itibarıyla iki varyantın ayrı Firebase app kaydı ve debug/upload
sertifika fingerprint'leri tanımlıdır. Debug'da otomatik bildirim toplama kapalı kalır; token
yalnız kullanıcı bildirim akışını etkinleştirdiğinde istenir.

## Supabase staging sunucu secret kontrolü

Edge Function secret'ları yalnız `riskdetected-android-staging` projesine yüklenir:

- Analiz: `GEMINI_API_KEY_FREE`, ücretli havuz anahtarları ve tanımlı fallback anahtarları.
- Bildirim: `FCM_SERVICE_ACCOUNT_JSON`.
- E-posta: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, auth hook secret'ı.
- Hesap silme web akışı: `ACCOUNT_DELETION_ALLOWED_ORIGINS`,
  `ACCOUNT_DELETION_QUEUE_SECRET`, opsiyonel `ACCOUNT_DELETION_ALERT_EMAIL`; Vault'ta `project_url` ve
  `account_deletion_queue_secret`.
- RevenueCat: webhook authorization secret'ı ve kullanılan sunucu entegrasyonu değerleri.
- Platform/OAuth: Google provider staging redirect URI'siyle tanımlanır. Apple OAuth Android v1
  release kapsamı dışındadır; Android giriş ekranında CTA gösterilmez ve iOS provider davranışı
  değiştirilmez.

Secret eksikken ilgili runtime gate açılmaz ve o E2E senaryosu başarılı kabul edilmez. 2026-08-10
E2E oturumu için staging'deki altı gate de yalnız version code `1` allowlist'ine açılmıştır:
`client`, `auth`, `pdf_reports`, `analysis_submit`, `payments`, `notifications`. Production
gate'leri değiştirilmemiştir; staging kapıları test bitiminde yeniden kapatılabilir.

Aynı read-only kontrolde production endpoint'i henüz additive `android_runtime_gates` alanını
döndürmedi. Android istemci eksik gate sözleşmesini fail-closed değerlendirir; dolayısıyla canlı
Android işlevi açılamaz. Canonical Edge Function paketi staging E2E ve iOS fixture kabulünden sonra
production'a tüm gate satırları kapalıyken dağıtılmalıdır; bu kayıt deploy onayı değildir.

`ACCOUNT_DELETION_ALLOWED_ORIGINS` production ve staging web origin'lerini virgülle ayırır.
Fonksiyonun güvenli varsayılanı yalnız `https://riskdetected.com` değeridir; localhost ancak
yerel function serve sürecine açıkça verilen environment ayarıyla kullanılabilir. Resend hatası
silme kuyruğunu durdurmaz. Saatlik worker yalnız Vault secret'ları mevcutsa migration tarafından
schedule edilir. Worker hataları ham kullanıcı/e-posta/request verisi olmadan yalnız destek kodu,
güvenli hata sınıfı ve HTTP durumu ile Resend alarmı üretir.

2026-08-09 read-only kontrolünde staging ve production ortamlarında `RESEND_API_KEY` ile
`RESEND_FROM_EMAIL` secret adları bulundu. Bu kontrol secret değerini, gönderen domain
doğrulamasını veya gerçek e-posta teslimini kanıtlamaz; teslim E2E kapısı ayrıca geçilmelidir.

## OAuth callback sözleşmesi

- Debug: `com.riskdetectedan.app.debug://login-callback`
- QA: `com.riskdetectedan.app.qa://login-callback`
- Release: `com.riskdetectedan.app://login-callback`

Callback scheme'leri geriye uyumluluk için kayıtlıdır; Android v1'de Apple giriş CTA'sı yoktur.
Dolayısıyla Apple OAuth secret/rotasyonu Android production canary kapısı değildir. iOS canlı Apple
girişi ve rotasyonu kendi mevcut işletim sürecinde kalır.

## RevenueCat staging sözleşmesi

- Staging public SDK key: RevenueCat Test Store app'i.
- Staging offering: `qa_test_store`.
- Production offering: `default`.
- Entitlement'lar: `plus`, `pro`.
- App User ID: Supabase `auth.uid()`.

Test Store anahtarıyla `default` offering seçilmez; orada Test Store ürünleri bulunmadığından
fiyatlar boş döner. Build type ayrımı bunu fail-safe biçimde engeller. Play service credential
ürün ve base-plan kataloglarını okuyabiliyor. Gerçek transaction doğrulaması ve RTDN topic'in
Play Console'a bağlanması ilk AAB Internal Testing'e yüklendikten sonra tamamlanır.

2026-08-10 gerçek Test Store koşusunda dört paketin fiyatları yüklendi, Plus ve Pro satın alma
akışları tamamlandı ve ayrı staging webhook'u HTTP 200 döndü. RevenueCat App User ID'nin Supabase
`auth.uid()` olması sayesinde staging `profiles`/`user_subscriptions` kaydı Pro entitlement ile
aktifleşti. Production App Store webhook'u değiştirilmedi. Test Store restore çağrısı mevcut
customer info'yu döndürdü; gerçek Google Play restore/pending/cancel/refund davranışları ilk AAB
sonrasındaki Play test şeridinde doğrulanacaktır.

## 2026-08-10 gerçek staging E2E özeti

- E-posta OTP: gerçek Resend teslimi ve Supabase oturumu PASS.
- Google Credential Manager: doğru staging client ile çağrı PASS; emülatörde Google hesabı
  bulunmadığı için hesap seçimi/geri dönüşü açık.
- Firebase: token satırı `platform=android`, `provider=fcm`; foreground, background ve killed
  teslimleri PASS. Killed bildirim tıklaması `account_updates` payload'ını Profil rotasına açtı.
- RevenueCat: `qa_test_store` Plus/Pro satın alma, webhook HTTP 200 ve DB entitlement aktivasyonu
  PASS. Gerçek Play transaction/RTDN ilk AAB'yi bekliyor.
- Analiz/rapor: gerçek saha fotoğrafı, bekleme ekranı, iki bulgu, sonuç, 2 sayfalık cihaz PDF'i ve
  beş çalışma sayfalı sunucu XLSX dosyası PASS. Kullanıcının belirlediği 1/2/3 fotoğraflı kalite
  kapsamının uzman kabulü ayrıca kaydedilir.

Analiz koşusu iki sözleşme hatasını ortaya çıkardı ve kapattı: create isteği server-owned
`analyses.client_platform/client_build` alanlarını doğrudan göndermiyor; `client_platform` artık
`raw_ai_response._input_audit` içinden, sabit `search_path` kullanan ve istemci rollerine execute
edilmeyen trigger ile türetiliyor. Production'a henüz uygulanmadı.

## Kalite ve yayın kapıları

### Yerel Android SDK ve ADB

Bu makinede Android SDK kökü `android/local.properties` içindeki
`/opt/homebrew/share/android-commandlinetools` yoludur. `platform-tools` kurulu olmasına rağmen
`adb` Homebrew `bin` dizinine bağlı olmadığı için Codex shell başlangıçta komutu bulamıyordu.
2026-08-10 tarihinde aşağıdaki PATH bağlantıları oluşturuldu:

- `/opt/homebrew/bin/adb` → SDK `platform-tools/adb`
- `/opt/homebrew/bin/emulator` → SDK `emulator/emulator`

Kontrol komutları:

```bash
adb version
adb devices -l
```

API 36 `OSGBTakip_API36` / `emulator-5554` üzerinde gerçek APK kurulumu; returning-user
sign-out, force-stop/relaunch, fresh install → Atla → Yine de atla, bağımsız Login, e-posta CTA,
IME lift, alan girişi ve panel kapatma akışları PASS. Debug package yerel verisi fresh-install
testi için temizlendi; staging backend hesabı veya verileri silinmedi. Kanıtlar
`docs/android/evidence/auth/` altındadır.

Yerel/CI asgari komutları:

```bash
./gradlew verifyEnvironmentIsolation testDebugUnitTest verifyRoborazziDebug lint assembleDebug assembleQa
rg --files supabase/functions | rg '(test\.ts$|static_test\.ts$)' | sort | xargs deno test --allow-read
supabase db start
supabase test db --local
supabase stop --no-backup
```

`qa` minified/resource-shrunk derlenir. Gerçek staging Firebase project ID yapılandırılmadıkça
Crashlytics collection ve mapping upload kapalıdır; gerçek ID geldiğinde ikisi birlikte açılır.
Release mapping upload her zaman açık ve release-candidate artifact'i olarak saklanır.

`--local` zorunludur; test komutunda `--linked` kullanılmaz. CI aynı Edge Function ve pgTAP kapılarını izole local Postgres üzerinde çalıştırır. Analiz oluşturma tekrarlarını engelleyen `analyses.client_submission_id` sözleşmesi; aynı kullanıcı/aynı submission ID için tek kayıt, farklı kullanıcılar için bağımsız kayıt ve legacy `NULL` uyumluluğunu pgTAP ile doğrular.

Staging kabul sırası: auth → profil/okuma → PDF → tek fotoğraf analiz → çoklu fotoğraf → payments → notifications. Production rollout additive backend dağıtımıyla ve tüm Android kapıları kapalıyken başlar; iOS flag'leri hiçbir Android rollout işleminde değiştirilmez.
