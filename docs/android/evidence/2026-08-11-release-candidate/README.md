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
- Release geçmişi boş; `versionCode=1` kullanılabilir.
- Internal Testing için boş draft release oluşturuldu.
- Privacy URL, reklam, resmi kurum, finans/sağlık, Business kategorisi, iletişim ve Türkçe listing
  metadata'sı kaydedildi.
- IARC içerik derecelendirmesi kaydedildi: Avrupa `PEGI 3`; dijital ürünler için uygulama içi
  satın alma etiketi gösteriliyor.
- Play yüklemesi, Codex Chrome uzantısında yerel dosya erişimi kapalı olduğu için bekliyor.

## Store varlıkları

- `android/play-store/riskdetected-play-store-icon-512.png`
- `android/play-store/riskdetected-feature-graphic-1024x500.png`
- Telefon mağaza ekran kompozisyonları owner tarafından ayrıca tasarlatılacak; Codex'in geçici
  mockup çıktıları çalışma alanından geri alındı.

## Bilinçli ertelenen/dış kapılar

- Fiziksel cihaz Google/Auth E2E: owner isteğiyle sonraya bırakıldı.
- AAB upload ve Play'den yeniden imzalı build smoke testi
- App-signing fingerprint'lerinin Firebase/OAuth'a eklenmesi
- Gerçek Play Billing/RTDN ve dört ürün E2E
- Dedicated review hesabı parolasıyla Play inceleme erişimi
- Owner onaylı Data Safety formunun gönderimi
- Review erişim bilgileri sonrası 18+ target audience ve restricted-access beyanları
- Fiziksel Pixel/Samsung, İSG uzman kabulü, Pre-launch Report, 12 tester × 14 gün closed test
