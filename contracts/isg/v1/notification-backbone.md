# Bildirim omurgası — v1 sunucu sözleşmesi

14 Eylül 2026. P12'nin ilk dilimi. Gerçek APNs/FCM/e-posta adaptörü **yoktur**; burası onların uyacağı rıza, sahiplik ve gönderim-anı kural yüzeyidir. Mevcut legacy bildirim kuyruğu, tip CHECK'i ve üreticileri okunmaz ve yazılmaz.

Migration: [20260914050000_isg_notification_core.sql](../../../supabase/migrations/20260914050000_isg_notification_core.sql).

## Dört amaç, tek taşıyıcı

`obligation`, `personal_reminder`, `operational`, `marketing`. Aynı APNs/FCM'i kullanmaları aynı rızaya veya aynı zamanlamaya sahip oldukları anlamına gelmez. Sessiz saat, günlük/haftalık sınır ve açık rıza ihtiyacı amaç başına tanımlıdır ve **aday** değerlerdir: `caps_approved=false`.

## Rıza kökeni

Rıza `(sahip, amaç, kanal)` başına tek satırdır ve **nereden geldiğini** taşır: `onboarding`, `settings`, `os_permission`, `legacy_migration`.

- **OS izni pazarlama rızası değildir**: `os_permission` kaynağı `marketing` amacına veya `email` kanalına yazılamaz — hem CHECK hem `OS_PERMISSION_IS_NOT_CONSENT` ile.
- **E-posta rızası ayrı kayıttır**; push rızası onu kapsamaz.
- **Eski opt-out korunur**: `legacy_migration` kaynağı mevcut bir `granted=false` kaydını `true` yapamaz (`LEGACY_OPT_OUT_PRESERVED`).
- Rıza geri alındığında `revoked_at` yazılır.

## Üretici sahipliği ve cutover

`(amaç, episode türü)` başına tek sahip: `legacy` veya `isg_engine`. Sahibi olmayan üretici episode açamaz (`PRODUCER_NOT_OWNER`). `mode='shadow'` iken yeni motor üretir ama **göndermez** (`SHADOW_MODE_NO_SEND`). Sahip değişince önceki sahibin `queued` işleri `PRODUCER_HANDOVER` ile iptal edilir; geri dönüşte episode tekilliği mükerrer üretimi engeller.

## Gönderim anı kapısı

Kuyruğa alma anı yeterli değildir; `dispatch_notification` her şeyi **gönderim anında** yeniden kontrol eder ve tek bir bastırma kodu döndürür:

| Kod | Ne zaman |
|---|---|
| `PRODUCER_HANDOVER` | İş, artık sahibi olmayan üreticiye ait |
| `SHADOW_MODE_NO_SEND` | Yeni motor gölge modda |
| `DEVICE_OWNER_MISMATCH` | Cihaz başka hesaba ait |
| `CATEGORY_DISABLED` | Kategori kapalı |
| `CONSENT_MISSING` / `CONSENT_REVOKED` | Açık rıza yok ya da sonradan geri alındı |
| `QUIET_HOURS` | Yerel saat sessiz aralıkta |
| `FREQUENCY_CAP` | Günlük/haftalık sınır dolmuş |

Sessiz saat ve sıklık sınırı **yerel gün** üzerinden, işin kendi timezone'unda hesaplanır. Kullanıcının bilerek kurduğu **açık alarm** (`explicit_alarm`, yalnız `personal_reminder`) sessiz saate ve kampanya sınırına takılmaz. Eski bir build yeni deep link'i bilmiyorsa güvenli mevcut ekran döner (`route_downgraded`); route başka firmaya çevrilmez.

## Teslim iddiası yok

`record_delivery_attempt` yalnız sağlayıcının `accepted`/`rejected`/`error` yanıtını kaydeder. `delivery_confirmed` ve `read_confirmed` sütunları CHECK ile **yalnız false** olabilir: sağlayıcının kabul etmesi kullanıcıya ulaştı ya da okundu demek değildir. Gönderim-anı kontrolü yapılmadan hiçbir deneme kaydedilemez (`SEND_TIME_CHECK_REQUIRED`).

## Henüz olmayanlar

Gerçek APNs/FCM/e-posta adaptörleri ve cihaz token yönetimi, onboarding rıza ekranı ve iOS/Android izin durum ayrımı, simulate/shadow/canary operasyon akışı, 14 gün cooldown ve 90 günde 2 aday gibi öneri politikaları, teslim/okundu metrikleri, legacy üreticilerden gerçek cutover ve istemci/native yüzey. `notifications` rollout satırı kapalıdır; istemciye GRANT verilmemiştir.
