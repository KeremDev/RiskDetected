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

`app/src/debug/google-services.json` ve `app/src/qa/google-services.json` yalnız staging Firebase projesinden gelmelidir. Gerçek staging dosyası sağlanana kadar FCM auto-init kapalı kalır.

## Supabase staging sunucu secret kontrolü

Edge Function secret'ları yalnız `riskdetected-android-staging` projesine yüklenir:

- Analiz: `GEMINI_API_KEY_FREE`, ücretli havuz anahtarları ve tanımlı fallback anahtarları.
- Bildirim: `FCM_SERVICE_ACCOUNT_JSON`.
- E-posta: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, auth hook secret'ı.
- RevenueCat: webhook authorization secret'ı ve kullanılan sunucu entegrasyonu değerleri.
- Platform/OAuth: Google ve Apple provider yapılandırması Supabase Auth panelinde staging redirect URI'leriyle tanımlanır.

Secret eksikken ilgili runtime gate açılmaz ve o E2E senaryosu başarılı kabul edilmez. 2026-08-09 staging durumunda `client`, `auth` ve `pdf_reports` yalnız version code `1` için açıktır; AI/RevenueCat/Firebase istemci kurulumu tamamlanana kadar `analysis_submit`, `payments` ve `notifications` kapalıdır.

## OAuth callback sözleşmesi

- Debug: `com.riskdetectedan.app.debug://login-callback`
- QA: `com.riskdetectedan.app.qa://login-callback`
- Release: `com.riskdetectedan.app://login-callback`

Android Apple girişi Custom Tab + PKCE kullanır. Callback `MainActivity` üzerinden Supabase deep-link handler'a aktarılır. Apple'ın ad alanını yalnız ilk yetkilendirmede döndürebileceği kabul edilir; profil adı zorunlu kimlik alanı değildir.

Apple OAuth client secret en geç altı ayda bir yenilenir. İşletim kaydında üretim tarihi, son geçerlilik tarihi, staging doğrulaması, sorumlu ve bir sonraki yenileme tarihi tutulur. İlk kayıt için hedef yenileme tarihi `2027-02-01` olarak planlanmıştır; yenileme tamamlanmadan `auth` production canary kapısı açılmaz.

## Kalite ve yayın kapıları

Yerel/CI asgari komutları:

```bash
./gradlew verifyEnvironmentIsolation testDebugUnitTest verifyRoborazziDebug lint assembleDebug assembleQa
rg --files supabase/functions | rg '(test\.ts$|static_test\.ts$)' | sort | xargs deno test --allow-read
supabase db start
supabase test db --local
supabase stop --no-backup
```

`--local` zorunludur; test komutunda `--linked` kullanılmaz. CI aynı Edge Function ve pgTAP kapılarını izole local Postgres üzerinde çalıştırır. Analiz oluşturma tekrarlarını engelleyen `analyses.client_submission_id` sözleşmesi; aynı kullanıcı/aynı submission ID için tek kayıt, farklı kullanıcılar için bağımsız kayıt ve legacy `NULL` uyumluluğunu pgTAP ile doğrular.

Staging kabul sırası: auth → profil/okuma → PDF → tek fotoğraf analiz → çoklu fotoğraf → payments → notifications. Production rollout additive backend dağıtımıyla ve tüm Android kapıları kapalıyken başlar; iOS flag'leri hiçbir Android rollout işleminde değiştirilmez.
