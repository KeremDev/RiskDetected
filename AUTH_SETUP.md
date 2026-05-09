# RiskDetected Auth Setup

Bu doküman iOS auth akışının üretime alınması için gereken ayarları tutar.

## Mevcut Uygulama Akışı

- E-posta/şifre: demo hesaplar için aktif.
- E-posta kod doğrulama: kullanıcıya açık ana şifresiz giriş akışı Supabase Email OTP üzerinden çalışır.
- Apple Sign In: iOS `AuthenticationServices` ile gerçek Apple identity token alır ve Supabase `signInWithIdToken(provider: .apple)` akışına verir.
- Google Sign In: Supabase OAuth/PKCE web akışına bağlandı.
- Telefon/Firebase Auth: SDK ve bridge altyapısı hazır, ancak kullanıcıya açık akıştan geçici olarak kaldırıldı.

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

Authentication > URL Configuration:

- Redirect URL olarak şunu ekle:
  - `io.supabase.riskdetected://login-callback`
- iOS bundle Info.plist içinde `io.supabase.riskdetected` URL scheme kayıtlıdır (`Config/RiskDetectedInfo.plist`).
- Firebase Phone Auth callback için `app-1-195728384880-ios-64819727b2f43607ab25b5` URL scheme kayıtlıdır.

## Apple Developer Gerekenleri

- App Identifier: `com.riskdetected.app`
- Sign in with Apple capability açık olmalı.
- Xcode target entitlements:
  - `com.apple.developer.applesignin = Default`

## Google OAuth Notu

Mevcut uygulama GoogleSignIn SDK yerine Supabase OAuth web flow kullanır. Bu, iOS tarafında ekstra Google SDK ve client plist gerektirmeden çalışır; ancak Supabase provider ve redirect URL doğru ayarlanmalıdır.

## Firebase Phone Auth Kararı

2026-05-09 kararı: telefon ile giriş/doğrulama MVP akışından geçici olarak çıkarıldı. Firebase billing/Identity Platform gereksinimi çözülene kadar kullanıcıya açık giriş akışı e-posta kod doğrulama üzerinden ilerleyecek.

Supabase'in Firebase Auth entegrasyonu Firebase JWT'yi doğrudan Supabase API çağrılarında kullanabilir. Bunun için Firebase tokenlarında `role: authenticated` custom claim gerekir.

RiskDetected'in mevcut veritabanı şeması `uuid` kullanıcı idleri ve `auth.uid()` tabanlı RLS üzerine kurulu. Firebase UID değerleri UUID olmadığı için Firebase JWT'yi doğrudan Supabase auth tokenı gibi kullanmak mevcut RLS yapısını kırar.

Bu nedenle güvenli üretim kararı:

1. MVP için kullanıcıya açık şifresiz girişte Supabase Email OTP kullanılır.
2. Firebase Phone Auth istenirse ayrı bir bridge tasarlanır:
   - iOS Firebase Auth ile telefonu doğrular.
   - Backend Firebase ID tokenı doğrular.
   - Backend doğrulanmış telefon numarasını mevcut Supabase kullanıcı/profil modeliyle güvenli şekilde eşler.
   - RLS ve kullanıcı id stratejisi değiştirilmeden Firebase UID doğrudan tablo sahibi yapılmaz.

### Kod Durumu

- Firebase iOS SDK paketleri projeye eklendi: `FirebaseCore`, `FirebaseAuth`.
- App açılışında `FirebaseBootstrap.configureIfAvailable()` çalışır.
- `GoogleService-Info.plist` bundle içinde yoksa Firebase sessizce devre dışı kalır; uygulama crash olmaz.
- Güvenlik: gerçek `App/GoogleService-Info.plist` git dışında tutulur. Repo’da sadece `App/GoogleService-Info.plist.example` template’i bulunur.
- `FirebasePhoneAuthService` SMS kod gönderme ve kod doğrulama/token alma işlemlerini hazırlar.
- `RDConfig.Auth.useFirebasePhoneBridge = false`; kullanıcıya açık telefon girişi geçici olarak kapalıdır.
- `firebase-phone-bridge` Edge Function deploy edildi ancak telefon auth kapalı olduğu için endpoint 410 dönecek şekilde devre dışı bırakıldı.
- `firebase_phone_auth_links` tablosu remote Supabase veritabanına uygulandı.
- `FIREBASE_PROJECT_ID=riskdetected` Supabase secret olarak eklendi.
- Canlı endpoint sahte token için beklenen şekilde `invalid_token_format` döner; bu bridge'in config yüklü olduğunu gösterir.
- Firebase Auth initialize denemesi `BILLING_NOT_ENABLED` döndü. Firebase Phone Auth aktif edilene kadar telefon UI'ı gösterilmeyecek.

### Firebase'i Aktif Etmek İçin

1. Firebase Console'da iOS app oluştur:
   - Bundle ID: `com.riskdetected.app`
2. `GoogleService-Info.plist` dosyasını indir.
3. Dosyayı Xcode projesinde `App/GoogleService-Info.plist` konumuna ekle.
4. Firebase Console > Authentication > Sign-in method:
   - Phone provider aktif edilmeli.
   - Test numaraları istenirse burada tanımlanmalı.
5. Supabase secrets içinde `FIREBASE_PROJECT_ID=riskdetected` kayıtlı.
6. `RDConfig.Auth.useFirebasePhoneBridge = true` tekrar aktif edilir ve UI yeniden açılır.

## Sonraki Auth İşleri

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
- Telefon girişi tekrar açılacaksa Firebase Console'da billing/Identity Platform gereksinimi tamamlanmalı, Phone provider aktif edilmeli ve gerçek/test telefonla uçtan uca doğrulanmalı.
- RevenueCat sonrası `profiles.tier` sadece doğrulanmış webhook/profil güncellemesiyle değişmeli.
