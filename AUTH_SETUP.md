# RiskDetected Auth Setup

Bu doküman iOS auth akışının üretime alınması için gereken ayarları tutar.

## Mevcut Uygulama Akışı

- E-posta/şifre: demo hesaplar için aktif.
- E-posta kod doğrulama: kullanıcıya açık ana şifresiz giriş akışı Supabase Email OTP üzerinden çalışır.
- Apple Sign In: iOS `AuthenticationServices` ile gerçek Apple identity token alır ve Supabase `signInWithIdToken(provider: .apple)` akışına verir.
- Google Sign In: Native Google Sign-In SDK ile çalışır; Google `idToken` Supabase `signInWithIdToken(provider: .google)` akışına verilir.
- Apple/Google/e-posta başarılı oturum sonrası `profiles` satırı yoksa uygulama otomatik `free` profil oluşturur.
- Telefon/Firebase Auth: MVP kapsamından çıkarıldı. iOS Firebase SDK, Firebase URL scheme ve `firebase-phone-bridge` Edge Function kaldırıldı.

## Supabase Dashboard Gerekenleri

Authentication > Providers:

- Email provider aktif olmalı.
- Email OTP için mail şablonları kullanıcıya 6 haneli kodu göstermeli. Supabase şablonunda doğrulama kodu token değişkeni kullanılmalı (`{{ .Token }}`).
- Supabase yeni kullanıcı için `Confirm signup`, mevcut kullanıcı için `Magic Link` şablonunu kullanabilir. Bu yüzden iki şablon da link yerine kod göstermeli:
  - Authentication > Emails > Confirm signup
    - Subject: `RiskDetected doğrulama kodun`
    - Body: `supabase/templates/email-otp-confirmation.html`
  - Authentication > Emails > Magic Link
    - Subject: `RiskDetected giriş kodun`
    - Body: `supabase/templates/email-otp-magic-link.html`
- Production mail teslimatı ve rate-limit kontrolü için özel SMTP bağlanmalı. Önerilen sağlayıcılar: Resend, Postmark, SendGrid veya Mailgun.
- Apple provider aktif olmalı.
  - Apple Services ID / Team ID / Key ID / private key Supabase tarafında tanımlanmalı.
- Google provider aktif olmalı.
  - Google OAuth client id/secret Supabase tarafında tanımlanmalı.
  - Google Cloud OAuth redirect URI:
    - `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`

Authentication > URL Configuration:

- Redirect URL olarak şunu ekle:
  - `io.supabase.riskdetected://login-callback`
- iOS bundle Info.plist içinde `io.supabase.riskdetected` URL scheme kayıtlıdır (`Config/RiskDetectedInfo.plist`).

## Apple Developer Gerekenleri

- App Identifier: `com.riskdetected.app`
- Sign in with Apple capability açık olmalı.
- Supabase Apple provider için Apple Developer tarafında Services ID oluşturulmalı.
- Services ID Return URL:
  - `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`
- Services ID domain/subdomain:
  - `ppcrzemgiztzcgddbins.supabase.co`
- Xcode target entitlements:
  - `com.apple.developer.applesignin = Default`

## Google OAuth Notu

Mevcut uygulama native Google Sign-In SDK kullanır. Supabase web OAuth akışı ana Google giriş yolu değildir.

Google Cloud Console tarafında iki client kullanılır:

- iOS OAuth Client:
  - Bundle ID: `com.riskdetected.app`
  - `Config/RiskDetectedInfo.plist` içindeki `GIDClientID`
  - Reversed client ID URL scheme olarak aynı plist içinde kayıtlı.
- Web OAuth Client:
  - Supabase provider ayarında Client ID/Secret olarak kullanılır.
  - Google SDK tarafında `GIDServerClientID` olarak kullanılır.
- Authorized redirect URI:
  - `https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/callback`
- Supabase Authentication > Providers > Google alanına bu Web client'ın Client ID ve Client Secret değerleri girilmeli.
- iOS uygulama dönüş URL'i Supabase URL Configuration içinde allow-list'te olmalı:
  - `io.supabase.riskdetected://login-callback`

## Firebase / Telefon Auth Kararı

2026-05-12 kararı: telefon doğrulama ve Firebase bağımlılıkları MVP kapsamından tamamen çıkarıldı.

- iOS Firebase SDK paketleri (`FirebaseCore`, `FirebaseAuth`) Xcode projesinden kaldırıldı.
- `FirebaseBootstrap`, `FirebasePhoneAuthService` ve `GoogleService-Info` dosyaları kaldırıldı.
- Firebase callback URL scheme Info.plist'ten kaldırıldı.
- Canlı Supabase `firebase-phone-bridge` Edge Function silindi.
- Kullanıcıya açık giriş akışları: Email OTP, Apple Sign In ve native Google Sign-In.
- İleride telefon girişi yeniden istenirse yeni bir tasarım kararı ve ayrı güvenlik incelemesi gerekir.

## Sonraki Auth İşleri

- Apple/Google provider durumu:
  - 2026-05-12 canlı Supabase `/auth/v1/settings` kontrolünde `external.apple=true` ve `external.google=true` göründü.
  - Google native SDK ile mevcut kullanıcı girişi ve yeni kullanıcı kaydı geçti.
  - Google Cloud OAuth consent screen hâlâ test modunda; release öncesi production/publish adımı yapılacak.
  - Apple kodlandı ve Apple/Supabase ayarları yapıldı.
  - 2026-05-15 TestFlight gerçek cihazda Apple Sign In canlı testi geçti.
  - Apple provider `Client IDs` alanında Services ID yanında native iOS bundle id `com.riskdetected.app` da tanımlı olmalı; aksi durumda Supabase `Unacceptable audience in id_token` hatası verir.
  - Detaylı canlı kontrol notu: `AUTH_LIVE_VERIFICATION_2026-05-12.md`.
- Özel SMTP kurulumu:
  - Supabase Dashboard > Authentication > SMTP Settings altında SMTP sağlayıcısı bağlanacak.
  - Tercih edilen seçenek: Resend veya Postmark ile doğrulanmış domain üzerinden gönderim.
  - Amaç: Supabase built-in mail servisinin düşük test limitlerine takılmamak ve gerçek kullanıcıya daha güvenilir kod teslimatı sağlamak.
- Supabase dashboard provider ayarlarını tamamla.
- Email OTP canlı kontrolü:
  - `POST /auth/v1/otp` geçerli Gmail formatlı test adresiyle `200` döndü; Email provider aktif.
  - Admin `generate_link` + `/auth/v1/verify` token hash testi access token döndürdü; Supabase session üretimi çalışıyor.
  - Çok sık test isteği sonrası Supabase `over_email_send_rate_limit` döndürdü; uygulama bunu kullanıcıya "Kod gönderme sınırı" olarak gösterecek şekilde normalize ediyor.
  - Resend/Supabase SMTP ile Email OTP giriş ve kayıt canlı test edildi; geçti.
- Release öncesi Apple/Google/Email OTP için kısa final smoke test yapılabilir.
- Google Cloud OAuth consent screen production/publish durumunu release öncesi tamamla.
- RevenueCat sonrası `profiles.tier` sadece doğrulanmış webhook/profil güncellemesiyle değişmeli.
