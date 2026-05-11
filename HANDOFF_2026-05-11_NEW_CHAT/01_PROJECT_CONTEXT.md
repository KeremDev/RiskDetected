# 01 - Proje Bağlamı

## Ürün

RiskDetected, bireysel İSG/HSE uzmanları için AI destekli saha uygunsuzluk ve risk analizi uygulamasıdır.

Ana akış:

1. Kullanıcı Apple/Google/e-posta OTP ile giriş yapar.
2. Ana sayfada fotoğraf yükler, kamera ile çeker veya metin girer.
3. Fotoğraf için isteğe bağlı işaretleme yapılır.
4. Kullanıcı AI analiz odağı/canvas seçer.
5. Supabase Edge Function `analyze`, Gemini ile analiz yapar.
6. Bulgular Fine-Kinney ve 5x5 L-Tipi Matris ile skorlanır.
7. Sonuç ekranı bulguları, riskleri ve önerileri gösterir.
8. Kullanıcı standart PDF veya Pro risk analizi tablosu PDF/Excel çıktısı oluşturur.

## Mevcut Seviye

Proje MVP aşamasında ama oldukça ileri seviyede:

- iOS SwiftUI shell hazır.
- Auth akışları hazır.
- Supabase DB/Storage/Auth/Edge Functions bağlı.
- Gemini analiz çalışıyor.
- Fotoğraf ve metin analizi var.
- Free/Pro ayrımı UI ve backend tarafında büyük ölçüde var.
- Rapor PDF ve Excel export altyapısı var.
- Dark mode ve büyük UI cilası yapıldı.
- Profil, raporlar, analizler, sonuç ekranı ve ana sayfa önemli ölçüde modernize edildi.

## Teknik Bileşenler

### iOS

- SwiftUI
- Supabase Swift SDK
- Firebase SDK yalnızca ileride telefon auth için bağlı, kullanıcıya açık değil.
- App state: `App/AppState.swift`
- Ana view: `App/RootView.swift`
- Tab shell: `App/Views/Home/MainTabView.swift`

### Supabase

Kullanılan ana bileşenler:

- Auth
- PostgreSQL
- Storage
- Edge Functions
- RLS

Önemli tablolar:

- `profiles`
- `analyses`
- `findings`
- `photos`
- `reports`
- `ai_usage_logs`
- `consents`
- `push_device_tokens`
- `notification_preferences`
- `notification_events`

Önemli buckets:

- `photos`
- `reports`
- `logos`

Önemli Edge Functions:

- `analyze`
- `generate-excel-report`
- `retention-cleanup`
- `send-push-notification`
- `firebase-phone-bridge` mevcut ama telefon auth şu an kapalı/paused.

## Kritik Kurallar

- `fk_score` ve `m5_score` DB-generated; client veya function insert etmemeli.
- Ham teknik hata mesajları kullanıcıya gösterilmemeli.
- Free max bulgu hedefi: 4.
- Pro max bulgu hedefi: 14.
- Free günlük analiz limiti: 2.
- Telefon auth şu an kullanıcıya açık değil.
- Pro gerçek entitlement ileride RevenueCat/Supabase webhook ile doğrulanmalı; local `app.isPro` tek kaynak olmamalı.

## Auth Durumu

- Kullanıcıya açık ana akış: Supabase Email OTP.
- Apple/Google butonları var, provider dashboard prod doğrulama hâlâ yapılmalı.
- Supabase built-in email rate limit var; custom SMTP şart.
- E-posta template tarafında 6 haneli OTP gösterimi hedefleniyor.

## AI ve Gemini Durumu

- `analyze` Edge Function Gemini kullanıyor.
- Çoklu Gemini API key havuzu backend tarafında uygulandı.
- Desteklenen secrets:
  - `GEMINI_API_KEY_PRIMARY`
  - `GEMINI_API_KEY_SECONDARY`
  - `GEMINI_API_KEY_TERTIARY`
  - legacy fallback: `GEMINI_API_KEY`
- Retry/fallback yalnızca retryable provider hatalarında.
- Loglarda gerçek key yok, alias var.

