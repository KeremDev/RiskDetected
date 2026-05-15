# Auth Live Verification - 2026-05-12

Tarih/saat: 2026-05-12 09:48 +03

## Canlı Kontrol Sonucu

Supabase project:

- Project ref: `ppcrzemgiztzcgddbins`
- Project name: `riskdetected`
- Region: Central EU (Frankfurt)
- Auth callback URL: `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`
- iOS redirect URL: `io.supabase.riskdetected://login-callback`

Canlı `/auth/v1/settings` sonucu:

- Email provider: açık
- Signup: açık
- Mailer autoconfirm: kapalı
- Apple provider: açık (`external.apple=true`)
- Google provider: açık (`external.google=true`)
- Phone provider: kapalı

Authorize endpoint smoke test:

- Apple: provider enabled, TestFlight gerçek cihazda native Apple Sign In geçti.
- Google: provider enabled, native Google Sign-In SDK ile mevcut kullanıcı girişi ve yeni kullanıcı kaydı canlı geçti.

iOS app prerequisites:

- `io.supabase.riskdetected` URL scheme `Config/RiskDetectedInfo.plist` içinde kayıtlı.
- `com.apple.developer.applesignin = Default` entitlement mevcut.
- Supabase client redirect URL `RDConfig.Auth.redirectURL` üzerinden ayarlı.
- Telefon/Firebase auth app/backend yüzeyinden kaldırılmış durumda.

## Sonuç

Apple ve Google provider'ları canlı Supabase tarafında açık.
Google native SDK akışı gerçek hesapla başarıyla denendi. Mevcut kullanıcı girişi ve yeni kullanıcı kaydı geçti.
Apple native akışı gerçek Apple hesabıyla TestFlight cihazda başarıyla denendi. Canlı DB'de `auth.identities.provider = apple`, auth user ve otomatik `profiles` satırı doğrulandı.

## Apple Provider İçin Gerekenler

Supabase Dashboard > Authentication > Providers > Apple:

- Apple provider enabled olmalı.
- Apple Services ID / Client ID girilmeli.
- Apple Team ID girilmeli.
- Apple Key ID girilmeli.
- Apple private key girilmeli.

Apple Developer tarafında:

- App Identifier: `com.riskdetected.app`
- Sign in with Apple capability açık olmalı.
- Services ID Return URL:
  - `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`
- Services ID domain/subdomain:
  - `ppcrzemgiztzcgddbins.supabase.co`
- Supabase resmi Apple dokümanı:
  - `https://supabase.com/docs/guides/auth/social-login/auth-apple`

Aktivasyon sonrası beklenen kontrol:

- `/auth/v1/settings` içinde `external.apple=true` görüldü.
- Apple authorize endpoint artık `Unsupported provider` dönmemeli.
- 2026-05-15 TestFlight gerçek cihazda Apple Sign In geçti.
- Supabase Apple provider `Client IDs` alanında Services ID yanında native iOS bundle id `com.riskdetected.app` da tanımlı olmalı.
- Sadece Services ID tanımlı kalırsa native iOS token'ında `aud = com.riskdetected.app` geldiği için Supabase `Unacceptable audience in id_token` hatası verir.

Apple `Secret Key (for OAuth)` alanı tek değer istiyorsa:

- Bu alan Apple'ın hazır verdiği bir parola değildir.
- `Team ID`, `Key ID`, `Client ID` ve `.p8` private key ile imzalanmış bir JWT üretilir.
- Repo içinde yardımcı script eklendi:
  - `scripts/generate_apple_client_secret.mjs`

Örnek kullanım:

```bash
node scripts/generate_apple_client_secret.mjs \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_KEY_ID \
  --client-id com.riskdetected.app.service \
  --p8 /absolute/path/AuthKey_XXXXXXXXXX.p8
```

Bu komut tek satır bir JWT üretir. Çıkan değeri Supabase Dashboard > Apple > `Secret Key (for OAuth)` alanına yapıştır.

## Google Provider İçin Gerekenler

Google Cloud Console:

- iOS OAuth Client oluşturuldu.
- Web OAuth Client oluşturuldu ve Google SDK `serverClientID` için kullanılıyor.
- Authorized redirect URI:
  - `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`
- Supabase resmi Google dokümanı:
  - `https://supabase.com/docs/guides/auth/social-login/auth-google`

Supabase Dashboard > Authentication > Providers > Google:

- Google provider enabled.
- Web OAuth Client ID girildi.
- Web OAuth Client Secret girildi.

Supabase URL Configuration:

- Redirect allow-list içinde şu URL olmalı:
  - `io.supabase.riskdetected://login-callback`

Aktivasyon sonrası beklenen kontrol:

- `/auth/v1/settings` içinde `external.google=true` görüldü.
- Google authorize endpoint artık `Unsupported provider` dönmüyor.
- iOS simülatörde mevcut Google hesabıyla native SDK girişi geçti.
- Fiziksel `Kerem iPhone` cihazında Google yeni kullanıcı kaydı geçti.
- Google OAuth consent screen hâlâ test modunda; release öncesi production/publish adımı tamamlanmalı.

## OAuth Marka Görünürlüğü Notu

Google giriş akışı Supabase web OAuth yerine native Google Sign-In SDK'ya taşındı.
Bu yüzden Google tarafında `ppcrzemgiztzcgddbins.supabase.co` görünen web OAuth ekranı ana akıştan çıktı.

Custom domain ileride yine değerlendirilebilir:

- Supabase custom domain/auth domain yapılandır.
- Örnek: `auth.riskdetected.com`
- Apple Services ID domain/return URL ve Google Authorized redirect URI değerlerini yeni domainle güncelle.
- Supabase URL Configuration redirect allow-list içinde iOS scheme kalmaya devam etmeli:
  - `io.supabase.riskdetected://login-callback`

## Email OTP / SMTP İçin Gereken Canlı Test

Mevcut durum:

- Email provider açık.
- Email OTP uygulama akışı çalışıyor.
- Resend/Supabase SMTP ayarı kullanıcı tarafından yapıldı.
- Email OTP ile giriş ve kayıt canlı test edildi; geçti.
- Supabase resmi custom SMTP dokümanı:
  - `https://supabase.com/docs/guides/auth/auth-smtp`

Doğrulananlar:

1. Email OTP ile yeni kullanıcı kayıt akışı geçti.
2. Email OTP ile mevcut kullanıcı giriş akışı geçti.
3. Resend/Supabase SMTP üzerinden kod teslimi doğrulandı.

Kalan:

1. Release öncesi Email OTP, Google ve Apple için kısa final smoke test yapılabilir.
2. Google Cloud OAuth consent screen production/publish adımı release öncesi tamamlanmalı.
