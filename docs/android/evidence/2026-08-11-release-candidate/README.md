# Android 1.5.0 release candidate kanıtı

Tarih: 11 Ağustos 2026

Package: `com.riskdetectedan.app`

Version: `1.5.0` (`versionCode=1`)
Branch: `codex/android-release-readiness`

Bu kayıt secret, keystore, kullanıcı kimliği veya ham saha fotoğrafı içermez. iOS `App/`
kaynakları değiştirilmemiştir.

## İmzalı release artefaktı

- AAB: `android/app/build/outputs/bundle/release/app-release.aab`
- AAB SHA-256: `5706ec4b61b257973d1b271b7c27a229c3db677d9e44a82958b3ac247c256bb2`
- Native symbols: `android/app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip`
- Native symbols SHA-256: `5f518dc53b6fd9e4170c2a08861b8928bcd262c6508fc6227b387964e839666b`
- Upload certificate SHA-1: `88:8A:2F:A6:15:5D:96:29:9B:69:08:05:A9:4B:83:3C:11:42:CE:31`
- Upload certificate SHA-256: `96:AA:19:F1:1E:5A:98:8D:47:AA:83:60:11:E3:2C:CA:66:5D:20:88:AA:51:F6:02:8F:33:19:4C:E4:F7:D1:6D`

Geçen kontroller:

- `lintRelease` ve minified `bundleRelease`
- pinned `bundletool 1.18.3` checksum ve `validate`
- JAR/AAB signature doğrulaması
- 16 KB ZIP alignment ve ELF `LOAD` segmentleri
- R8 mapping ve dört symbol-bearing native library paketi
- server secret, PII-log, `AD_ID`, `.xcassets`, `AppIcon.appiconset` ve `Contents.json` taraması
- release environment isolation ve production public config fail-closed kontrolü

Artefaktlar build çıktısıdır; Git'e eklenmez. Hash'ler aynı artefaktın owner tarafından Play'e
yüklenmesini doğrulamak için kullanılır.

## Otomatik kalite kapıları

- Android unit: geçti
- Roborazzi exact golden (`threshold=0`): geçti
- Debug/release lint: geçti
- Debug ve minified QA assemble/bundle: geçti
- Deno Edge Functions: `316/316`
- pgTAP/RLS/RPC: `485/485`
- `App/` baseline ve working-tree diff: sıfır

## Gerçek staging akışları

Yeni Gemini tüketimi yapılmadı; kullanıcı tarafından sınırlandırılan mevcut kanıtlar kullanıldı:

- 1 fotoğraf standart analiz → sonuç
- 2 fotoğraf analiz → retry/recovery → sonuç
- 3 fotoğraf analiz → sonuç → cihaz PDF'i → server XLSX
- FCM izin reddi, Profil'den etkinleştirme, foreground/background/killed deep-link ve sign-out
  token temizliği

Kanıtlar `docs/android/evidence/2026-08-11-staging-e2e/` altındadır.

## FCM token rotation düzeltmesi

Android istemcisi token upsert conflict kimliğini
`user_id,provider,application_id,installation_id` olarak kullanır. Migration eski aynı-kurulum
FCM kayıtlarını tekilleştirir ve aynı kimlikte unique index kurar. Local pgTAP, staging ve
production şema doğrulaması geçti. Gerçek `onNewToken` teslimi aktif oturumlu cihazla son dış
regresyon olarak kalır.

## Production güvenliği

- Migration `android_push_token_rotation_identity` production'a additive uygulandı.
- `push_device_tokens_android_installation_uidx` production'da doğrulandı.
- `client`, `auth`, `analysis_submit`, `payments`, `notifications`, `pdf_reports` kapılarının
  tamamı `kill_switch=true`, `rollout_mode=off` durumundadır.
- Yeni schema warning/error oluşmadı.
- Beş authenticated `SECURITY DEFINER` RPC bilinçli istemci sözleşmesidir; auth, sahiplik,
  sabit `search_path`, anon revoke ve çapraz kullanıcı negatif pgTAP testleriyle waiver altındadır.
- Supabase leaked-password protection Free planda etkinleştirilemedi; plan yükseltme veya özellik
  erişimi sağlandığında tekrar açılmalıdır.

## Play Console durumu

- Play App Signing ve otomatik koruma etkin.
- `versionCode=1` içeren `1.5.0 (1) — Internal` sürümü 11 Ağustos 2026 21:20'de
  Internal Testing'e yayınlandı.
- Internal test katılım bağlantısı:
  `https://play.google.com/apps/internaltest/4700704956127404530`
- Play app-signing sertifikası SHA-1:
  `58:B2:63:04:BC:28:E5:66:58:48:D7:79:04:50:80:05:4F:9B:56:7E`
- Play app-signing sertifikası SHA-256:
  `E9:34:C9:C2:6D:B9:47:B4:C6:BD:D0:DE:03:B8:1D:55:0B:70:88:99:0B:D0:0C:2A:18:E7:C1:3E:C4:EB:04:6F`
- Upload ve Play app-signing SHA-1/SHA-256 değerleri production Firebase Android
  uygulamasına eklendi; Firebase dört fingerprint'i de döndürüyor.
- Privacy URL, reklam, resmi kurum, finans/sağlık, Business kategorisi, iletişim ve Türkçe listing
  metadata'sı kaydedildi.
- IARC içerik derecelendirmesi kaydedildi: Avrupa `PEGI 3`; dijital ürünler için uygulama içi
  satın alma etiketi gösteriliyor.
- Reklam Kimliği beyanı `Hayır` olarak kaydedildi; release manifesti ve artifact taraması
  `com.google.android.gms.permission.AD_ID` içermiyor.
- Closed Alpha kanalı Türkiye, `RiskDetected Internal` test listesi ve
  `https://riskdetected.com/destek` geri bildirim URL'siyle yapılandırıldı.
- `1.5.0 (1) — Closed Alpha` release'i aynı doğrulanmış AAB ile taslak olarak kaydedildi.

## RevenueCat ve Google Play RTDN

- RevenueCat Android uygulaması: `appf46487b575`, package `com.riskdetectedan.app`.
- Google Play service-account kimlik bilgileri RevenueCat'te `Valid credentials` durumunda.
- `default` offering; Plus/Pro aylık ve yıllık dört paketi içeriyor. `plus` ve `pro`
  entitlement'ları doğrulandı; iOS uyumluluğu için eski `Riskdetected Pro` entitlement'ına
  dokunulmadı.
- Pub/Sub topic:
  `projects/riskdetected-play/topics/Play-Store-Notifications`.
- `google-play-developer-notifications@system.gserviceaccount.com` hesabına yalnız topic
  seviyesinde `Pub/Sub Publisher` rolü verildi.
- Play test bildirimi başarılı oldu; RevenueCat son alımı `2026-08-11 18:46 UTC` olarak
  kaydetti ve `Connected to Google` gösteriyor.
- Play'de dört abonelik ürün kaydı oluşturuldu. Temel plan kaydı ise doğru dönem, yalnız Türkiye
  kullanılabilirliği ve vergi dahil doğrulanmış fiyatla iki farklı üründe tekrarlandığı halde
  Play tarafından yalnız `Değişiklikleriniz kaydedilemedi` yanıtıyla reddedildi. Geliştirici
  ödeme profili mevcut, ancak payout yöntemi eklenmemiş. Banka/payout bilgisi owner tarafından
  tamamlanmadan bu dış finans kapısı Codex tarafından geçilemez.

## Store varlıkları

- `android/play-store/riskdetected-play-store-icon-512.png`
- `android/play-store/riskdetected-feature-graphic-1024x500.png`
- Her iki varlık Play Console'daki varsayılan Türkçe mağaza girişine yüklendi; sayfa yeniden
  yüklenerek `1/1` durumları doğrulandı ve taslak kalıcı olarak kaydedildi.
- Telefon mağaza ekran kompozisyonları owner tarafından ayrıca tasarlatılacak; Codex'in geçici
  mockup çıktıları çalışma alanından geri alındı.

## Bilinçli ertelenen/dış kapılar

- Fiziksel cihaz Google/Auth E2E: owner isteğiyle sonraya bırakıldı.
- Play'den yeniden imzalı build smoke testi fiziksel cihaz oturumuna bırakıldı.
- Google OAuth Android client'ın Play app-signing fingerprint'iyle son provider kontrolü fiziksel
  Credential Manager testiyle birlikte yapılacak.
- Dört Play temel planı, deneme ve gerçek Billing E2E; payout yöntemi/Play tarafındaki genel
  kaydetme hatası giderildikten sonra yapılacak.
- Dedicated Fastmail review mailbox parolası repo'da tutulmuyor. Play oturum açma beyanı,
  parola owner tarafından doğrudan Console'a girilince tamamlanacak; buna bağlı 18+ hedef kitle
  beyanı da o adımın ardından açılıyor.
- Data Safety'de 15 veri türü kaydedildi. `https://riskdetected.com/hesap-silme` doğrudan 200
  döndüğü halde Play doğrulayıcısı 403 görüyor; owner Google desteğine kayıt açtı.
- Fiziksel Pixel/Samsung, İSG uzman kabulü, Pre-launch Report ve 12 tester × 14 gün closed test.
- Owner tarafından hazırlanacak sekiz mağaza ekran görüntüsü.
