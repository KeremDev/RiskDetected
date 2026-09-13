# Bildirim omurgası — v1 sunucu sözleşmesi

Güncel ek: [SQL repository ve provider wait sözleşmesi](../../../docs/isg/P12_REPOSITORY_WAIT_2026-09-13.md). Yeni `complete_notification_delivery_with_retry(job, token, provider, state, failure, now, retry_after_seconds)` eski tokenlı tamamlayıcıyı aynı transaction'da kullanır, 1–86400 saniyelik sağlayıcı girdisini attempt'e kaydeder ve `next_attempt_at` değerini yalnız ileri taşır. `RATE_LIMITED` en az 60 saniyedir; aynı tokenla değişen bekleme değeri idempotency çakışmasıdır. İşçi repository'si bu yeni fonksiyonu kullanır; önceki fonksiyon eski iç çağrılar için kalır. Yeni fonksiyon client rollerine kapalıdır.

İşçi tarafı devamı: [tek istekli APNs/FCM adaptörü ve orchestration portları](../../../docs/isg/P12_WORKER_TRANSPORT_2026-09-13.md). Adaptör kütüphanesi mevcut; gerçek credential/repository/cihaz bağlantısı ve canlı gönderim henüz yoktur. Bu dosyanın SQL sözleşmesi değişmedi.

14 Eylül 2026 başlıklı ilk dilimin güncellenmiş sözleşmesi. Gerçek APNs/FCM/e-posta bağlantısı **yoktur**; APNs/FCM kütüphane adaptörleri yukarıdaki devam paketinde bulunur. Burası taşıyıcıların uyacağı rıza, sahiplik ve gönderim-anı kural yüzeyidir. Mevcut legacy bildirim kuyruğu, tip CHECK'i ve üreticileri okunmaz ve yazılmaz.

Migration zinciri: [ilk omurga](../../../supabase/migrations/20260914050000_isg_notification_core.sql) → [gönderim güvenliği düzeltmesi](../../../supabase/migrations/20260914070001_isg_notification_dispatch_safety.sql). Aşağıdaki sözleşme zincirin **son** durumunu anlatır; ilk migration tek başına güvenli gönderim kanıtı değildir.

## Dört amaç, tek taşıyıcı

`obligation`, `personal_reminder`, `operational`, `marketing`. Aynı APNs/FCM'i kullanmaları aynı rızaya veya aynı zamanlamaya sahip oldukları anlamına gelmez. Sessiz saat, günlük/haftalık sınır ve açık rıza ihtiyacı amaç başına tanımlıdır ve **aday** değerlerdir: `caps_approved=false`.

## Rıza kökeni

Rıza `(sahip, amaç, kanal)` başına tek satırdır ve **nereden geldiğini** taşır: `onboarding`, `settings`, `os_permission`, `legacy_migration`.

- **OS izni pazarlama rızası değildir**: `os_permission` kaynağı `marketing` amacına veya `email` kanalına yazılamaz — hem CHECK hem `OS_PERMISSION_IS_NOT_CONSENT` ile.
- **E-posta rızası ayrı kayıttır**; push rızası onu kapsamaz.
- **Eski opt-out korunur**: `legacy_migration` kaynağı mevcut bir `granted=false` kaydını `true` yapamaz (`LEGACY_OPT_OUT_PRESERVED`).
- Rıza geri alındığında `revoked_at` yazılır.
- Sahip satırı kilidi ilk rıza kaydında da işlemleri sıralar. Daha eski `captured_at` reddedilir (`STALE_CONSENT`); aynı zaman damgasında opt-out kazanır. Yeni bir opt-in için daha yeni, güvenilir kayıt zamanı gerekir.

## Üretici sahipliği ve cutover

`(amaç, episode türü)` başına tek sahip: `legacy` veya `isg_engine`. Sahibi olmayan üretici episode açamaz (`PRODUCER_NOT_OWNER`). `mode='shadow'` iken yeni motor üretir ama **göndermez** (`SHADOW_MODE_NO_SEND`). Sahip değişince önceki sahibin `queued` ve `failed` işleri `PRODUCER_HANDOVER` ile iptal edilir. `dispatching` veya `uncertain` iş varken sahip değişimi `DISPATCH_IN_FLIGHT` ile reddedilir; sonucu belirsiz iş başka üreticiden yeniden gönderilmez. Firma bağlı episode, composite FK ile gerçekten aynı hesaba ait olmak zorundadır.

İlk üretici kaydının henüz satırı yokken de amaç/tür bazlı transaction advisory kilidi yazıcıları sıralar; var olmayan satırı `FOR UPDATE` ile kilitlemeye güvenilmez.

## Gönderim anı kapısı

Kuyruğa alma anı yeterli değildir; `dispatch_notification(job, device, now)` her **gönderim hakkı ediniminde** yeniden kontrol eder. Yalnız güvenilir sunucu işçisi içindir; HTTP/client RPC değildir. `now`, cihaz sahibi/build/kategori/OS izin bilgisi istemciden doğrulanmadan alınamaz. Ağ çağrısı bağlı değildir; veritabanı kontrolü ile dış sağlayıcı arasında atomik transaction iddia edilmez.

Henüz zamanı gelmeyen veya backoff bekleyen iş `allowed=false, reason=NOT_DUE` ile bekler. Onaylanmamış amaç politikası `POLICY_UNAPPROVED` ile bekler; migration `caps_approved` değerini açmaz. Diğer retler işi `suppressed` yapar:

| Kod | Ne zaman |
|---|---|
| `PRODUCER_HANDOVER` | İş, artık sahibi olmayan üreticiye ait |
| `SHADOW_MODE_NO_SEND` | Yeni motor gölge modda |
| `DEVICE_OWNER_MISMATCH` | Cihaz başka hesaba ait |
| `COMPANY_UNAVAILABLE` | Bağlı firma arşivlenmiş ya da artık bu hesaba ait değil |
| `CATEGORY_DISABLED` | Kategori kapalı |
| `OS_PERMISSION_REQUIRED` | Push için cihazın işletim sistemi izni yok |
| `CONSENT_MISSING` / `CONSENT_REVOKED` | Açık rıza yok ya da sonradan geri alındı |
| `QUIET_HOURS` | Yerel saat sessiz aralıkta |
| `FREQUENCY_CAP` | Günlük/haftalık sınır dolmuş |

Sessiz saat ve sıklık sınırı **gerçek kontrol zamanı** ve işin timezone'u üzerinden hesaplanır; `scheduled_for` saatinden hesaplanmaz. Sessiz aralık başlangıcı dahil, bitişi hariçtir; aynı gün/geceyi aşan aralıklar desteklenir, eşit uçlar boş aralıktır. Günlük sınır yerel gün, haftalık sınır o gün ve önceki altı yerel gündür. `sent` işler kabul zamanından, `dispatching` ve `uncertain` işler yetki zamanından kapasite kullanır; aynı hesapta paralel işler sahibin satır kilidiyle sıralanır.

Kullanıcının bilerek kurduğu **açık alarm** (`explicit_alarm`, yalnız `personal_reminder`) sessiz saate ve kampanya sınırına takılmaz; rıza/OS izni/rollout ve politika onayı kapılarını atlamaz. Eski bir build yeni deep link'i bilmiyorsa mevcut güvenli route döner (`route_downgraded`). Native deep link'in hedef kaydına erişim kontrolü ayrıca gereklidir ve bu sunucu dilimiyle tamamlanmış sayılmaz.

## Tekil gönderim hakkı ve sonuç

~~~text
queued / failed → zaman + güncel izin + politika + kapasite kontrolü
  ├─ henüz hazır değil → aynı durumda bekle
  ├─ bastırma sebebi   → suppressed
  └─ uygun            → dispatching + tek dispatch_token (60 saniye)
                         ├─ accepted                → sent
                         ├─ kesin geçici ret        → failed + backoff → yeniden kontrol
                         ├─ kalıcı ret / 10. deneme  → dead
                         └─ ağ sonucu belirsiz / süre doldu → uncertain (otomatik resend yok)
~~~

`allowed=true` yalnız bir işçiye verilir. `complete_notification_delivery(job, token, provider, state, failure, now)` sonucu UUID hakkına bağlar. Yanlış token `LEASE_LOST`; aynı token ve aynı sonuç aynı receipt'i döndürür; çelişen sonuç `IDEMPOTENCY_CONFLICT` olur. Email işini APNs/FCM, push işini email tamamlayamaz.

`rejected` + `RATE_LIMITED` / `PROVIDER_UNAVAILABLE` / `TEMPORARY_FAILURE`, **kesin gönderilmediği bilinen** geçici rettir. En fazla 10 deneme; bekleme 30 saniyeden başlayıp ikiye katlanarak en çok 3600 saniye olur. Her yeni deneme yeni token ve güncel izin kontrolü ister. Ağ timeout/reset gibi gönderilmiş olabilecek sonuçlar `error` olarak `uncertain` kalır; bu kategoriye otomatik retry uygulanamaz.

Süresi dolmuş hakkın henüz receipt'i yoksa sonradan kesinleşen aynı-token yanıtı kaydedilebilir; ağ isteği yeniden gönderilmez. Önceden `error` receipt'i yazılmışsa onu `accepted` diye değiştirmek çelişkidir; ayrı incelemeli mutabakat aracı henüz yoktur. Bu nedenle tam otomatik toparlanma veya dış sağlayıcıda exactly-once teslim iddia edilmez. Bastırılan işleri daha sonra yeniden planlama da bu dilimde yoktur.

## Teslim iddiası yok

Eski tokensız `record_delivery_attempt` artık `DISPATCH_TOKEN_REQUIRED` verir; eski `resolved_route` gönderim yetkisi değildir. Yalnız tokenlı tamamlayıcı sağlayıcı sonucunu kaydeder. `delivery_confirmed` ve `read_confirmed` sütunları CHECK ile **yalnız false** olabilir: sağlayıcının kabul etmesi kullanıcıya ulaştı ya da okundu demek değildir.

## Henüz olmayanlar

Gerçek APNs/FCM/e-posta adaptörleri ve güvenilir cihaz token/izin yönetimi, kısıtlı işçi rolü, onboarding rıza ekranı ve iOS/Android izin durum ayrımı, simulate/shadow/canary operasyon akışı, belirsiz sonuç mutabakatı, güncelliğini yitirmiş domain schedule sürümü kontrolü, 14 gün cooldown ve 90 günde 2 aday gibi öneri politikaları, teslim/okundu metrikleri, legacy üreticilerden gerçek cutover ve istemci/native yüzey. `notifications` rollout satırı kapalıdır; istemciye GRANT verilmemiştir.
