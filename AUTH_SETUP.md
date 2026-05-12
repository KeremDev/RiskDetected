# RiskDetected Auth Setup

Bu doküman iOS auth akışının üretime alınması için gereken ayarları tutar.

## Mevcut Uygulama Akışı

- E-posta/şifre: demo hesaplar için aktif.
- E-posta kod doğrulama: kullanıcıya açık ana şifresiz giriş akışı Supabase Email OTP üzerinden çalışır.
- Apple Sign In: iOS `AuthenticationServices` ile gerçek Apple identity token alır ve Supabase `signInWithIdToken(provider: .apple)` akışına verir.
- Google Sign In: Supabase OAuth/PKCE web akışına bağlandı.
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

Mevcut uygulama GoogleSignIn SDK yerine Supabase OAuth web flow kullanır. Bu, iOS tarafında ekstra Google SDK ve client plist gerektirmeden çalışır; ancak Supabase provider ve redirect URL doğru ayarlanmalıdır.

Google Cloud Console tarafında Web OAuth Client kullanılmalı:

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
- Kullanıcıya açık giriş akışları: Email OTP, Apple Sign In ve Google OAuth.
- İleride telefon girişi yeniden istenirse yeni bir tasarım kararı ve ayrı güvenlik incelemesi gerekir.

## Sonraki Auth İşleri

- Apple/Google provider aktivasyonu bekliyor:
  - Canlı Supabase `/auth/v1/settings` kontrolünde `external.apple=false` ve `external.google=false` göründü.
  - Canlı authorize endpoint testi Apple/Google için `Unsupported provider: provider is not enabled` döndü.
  - Kullanıcı Apple Developer ve Google Cloud OAuth key/secret bilgilerini aldıktan sonra Supabase Dashboard > Authentication > Providers altında Apple ve Google aktif edilecek.
  - Aktivasyon sonrası tekrar `/auth/v1/settings` kontrolü yapılacak; `apple=true` ve `google=true` görülmeli.
  - Ardından gerçek Apple hesabı ve Google hesabı ile iOS giriş testi yapılacak.
- Özel SMTP kurulumu:
  - Supabase Dashboard > Authentication > SMTP Settings altında SMTP sağlayıcısı bağlanacak.
  - Tercih edilen seçenek: Resend veya Postmark ile doğrulanmış domain üzerinden gönderim.
  - Amaç: Supabase built-in mail servisinin düşük test limitlerine takılmamak ve gerçek kullanıcıya daha güvenilir kod teslimatı sağlamak.
- Supabase dashboard provider ayarlarını tamamla.
- Email OTP canlı kontrolü:
  - `POST /auth/v1/otp` geçerli Gmail formatlı test adresiyle `200` döndü; Email provider aktif.
  - Admin `generate_link` + `/auth/v1/verify` token hash testi access token döndürdü; Supabase session üretimi çalışıyor.
  - Çok sık test isteği sonrası Supabase `over_email_send_rate_limit` döndürdü; uygulama bunu kullanıcıya "Kod gönderme sınırı" olarak gösterecek şekilde normalize ediyor.
  - Kalan manuel adım: Supabase Dashboard'da `Confirm signup` ve `Magic Link` şablonlarını repo'daki OTP şablonlarıyla değiştir; gerçek erişilebilir e-posta kutusunda 6 haneli kodun (`{{ .Token }}`) göründüğünü doğrula.
- Gerçek Apple hesabıyla cihaz/simülatör doğrulaması yap.
- Google OAuth redirect dönüşünü doğrula.
- RevenueCat sonrası `profiles.tier` sadece doğrulanmış webhook/profil güncellemesiyle değişmeli.
