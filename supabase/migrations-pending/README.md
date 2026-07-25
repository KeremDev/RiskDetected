# Bekleyen migration'lar

Bu klasördeki SQL dosyaları **henüz uygulanmamalıdır**. Hazır olduğunuzda ilgili dosyayı
`supabase/migrations/` altına taşıyıp `supabase db push` (veya normal deploy akışınızı) çalıştırın.

## `20260630200000_paywall_payment_pending_event.sql`

- **Ne yapar:** `paywall_events.event_name` check constraint'ine `payment_pending` ekler.
- **Önkoşul:** Admin paneldeki paywall `payment_pending` desteği deploy edilmiş olmalı.
- **Sonrası:** iOS'ta `InAppPaywallView.paymentPendingPaywallEventEnabled = true` yapın (şu an `false`).
