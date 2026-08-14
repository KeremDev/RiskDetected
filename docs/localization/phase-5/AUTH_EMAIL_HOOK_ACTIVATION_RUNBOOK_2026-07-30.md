# RiskDetected Faz 5 — Auth Send Email Hook Activation Runbook

Tarih: 2026-07-30  
Production project: `ppcrzemgiztzcgddbins`  
Durum: **completed / production verified**

## Hazır olan teknik parça

- Edge Function: `auth-send-email-hook`
- JWT doğrulama: kapalı; bunun yerine Supabase Standard Webhooks imzası
  zorunlu.
- Exact locale'ler:
  `tr-TR`, `en-001`, `en-GB`, `en-US`, `en-AU`, `en-CA`.
- Desteklenen aksiyonlar:
  signup, magic link/OTP, recovery, email change, reauthentication, invite ve
  güncel Supabase güvenlik bildirim aksiyonları.
- Secure Email Change iki alıcı ve iki OTP ile ele alınır.
- Eksik/uyuşmayan locale başka dile fallback yapmaz.
- `SEND_EMAIL_HOOK_SECRET` veya token/e-posta içeriği loglanmaz.

## Production aktivasyon sırası

1. `auth-send-email-hook` Edge Function'ını `--no-verify-jwt` ile deploy et.
   - Tamamlandı: production version `7`, `2026-07-31T07:15:06.815Z`.
   - Production bundle SHA-256:
     `3cffc99745e2b247a0b4bbf96b2b9762d3bfde37e9ae5d10179d922af0afbdf2`
2. Supabase Dashboard → Authentication → Hooks → Send Email bölümünde HTTP
   hook'u seç ve function URL'sini tanımla.
3. Dashboard'un ürettiği Standard Webhooks secret'ını production function
   secret'ı olarak `SEND_EMAIL_HOOK_SECRET` adıyla kaydet. Değeri repo,
   terminal transcript'i veya dokümana yazma.
4. `RESEND_API_KEY`, sender ve reply-to secret'larının mevcut olduğunu
   doğrula.
5. Hook'u etkinleştir.
6. Her iki dilde signup/OTP ve recovery smoke testi; ayrıca Secure Email
   Change çift e-posta testi yap.
7. Eksik locale fixture'ının `AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING` ile
   fail closed olduğunu doğrula.

## Production sonucu

2026-07-31 doğrulamasında:

- `auth-send-email-hook` production version `7` olarak `ACTIVE`;
  `verify_jwt=false`.
- HTTPS Send Email Hook production'da `ENABLED`.
- `SEND_EMAIL_HOOK_SECRET`, `RESEND_API_KEY` ve `RESEND_FROM_EMAIL` secret
  adları production'da mevcut. Secret değerleri veya digest'leri kanıta
  alınmadı.
- Türkçe ve İngilizce signup ile recovery smoke testleri geçti.
- Secure Email Change iki teslimatlı smoke testi geçti.
- Geçersiz Standard Webhooks imzası `401 invalid_webhook_signature` ile
  fail closed oldu.
- Testler Resend provider test alıcısıyla yapıldı; production kullanıcı
  kaydı oluşturulmadı.

Machine-readable production kanıtı:
`docs/localization/phase-5/AUTH_EMAIL_HOOK_PRODUCTION_VERIFICATION_2026-07-31.json`

Kaynak:
https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook
