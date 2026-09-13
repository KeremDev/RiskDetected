# P12 ilk dilim — tek bildirim omurgası, dört ayrı amaç

> Devir sonrası düzeltme: ilk dilimin gönderim-anı ve retry iddialarında dört davranış açığı bulundu ve ek migration ile giderildi. Bu belgedeki sayılar/endpoint açıklamaları tarihsel ilk dilime aittir; güncel durum için [P12 gönderim güvenliği](P12_DISPATCH_SAFETY_2026-09-13.md) ve [güncel sözleşme](../../contracts/isg/v1/notification-backbone.md) esas alınmalıdır. Tokensız `record_delivery_attempt` artık kullanılamaz.

14 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; `notifications` rollout satırı kapalı, canlıya uygulanmadı, gerçek sağlayıcı bağlanmadı.**

Migration: [20260914050000_isg_notification_core.sql](../../supabase/migrations/20260914050000_isg_notification_core.sql) · Sözleşme: [bildirim omurgası](../../contracts/isg/v1/notification-backbone.md) · [Kanıt](evidence/P12_NOTIFICATION_CORE_2026-09-14.json).

## Ne eklendi?

- **Dört amaç ayrı sınıf:** iş yükümlülüğü, kişisel hatırlatıcı, operasyonel, pazarlama. Aynı taşıyıcıyı kullanmaları aynı rıza veya zamanlama kuralına sahip oldukları anlamına gelmiyor. Sessiz saat ve sıklık sınırları amaç başına ve `caps_approved=false` ile **aday** olarak duruyor.
- **Rıza kökeni:** `(sahip, amaç, kanal)` başına tek kayıt + kaynak. **OS izni pazarlama rızası değil** (hem CHECK hem hata kodu), e-posta rızası ayrı kayıt, eski opt-out migrasyonda ters çevrilemiyor.
- **Üretici sahipliği:** `(amaç, episode türü)` başına tek sahip; sahibi olmayan üretici episode açamıyor; `shadow` modda yeni motor üretiyor ama göndermiyor; sahip devrinde önceki sahibin bekleyen işleri `PRODUCER_HANDOVER` ile iptal ediliyor.
- **Gönderim anı kapısı:** sahiplik, cihaz sahibi, kategori, kanal rızası, sessiz saat, günlük/haftalık sınır ve build'in bildiği route **gönderim anında** yeniden kontrol ediliyor. Kuyruğa alındıktan sonra rıza geri alınırsa iş bastırılıyor.
- **Açık alarm istisnası:** kullanıcının bilerek kurduğu kişisel alarm sessiz saate ve kampanya sınırına takılmıyor; `explicit_alarm` yalnız `personal_reminder` amacında olabiliyor.
- **Eski build güvenli ekrana düşüyor:** yeni deep link'i bilmeyen build `fallback_route` alıyor, route başka firmaya çevrilmiyor.
- **Teslim iddiası yok:** `delivery_confirmed` ve `read_confirmed` CHECK ile yalnız `false`; sağlayıcının kabul etmesi teslim veya okundu sayılmıyor. Gönderim-anı kontrolü yapılmadan deneme kaydedilemiyor.

## Test kanıtı

`--synthetic-session` → **689/689 PASS** (30'u bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **29/29 PASS**: tam legacy kopyada **on beş** migration replay, 99 tablo, hepsinde RLS. Offline foundation **232 PASS**.

Kapsam: OS izninin pazarlamaya ve e-postaya yazılamaması; push/e-posta rızalarının ayrılığı; eski opt-out'un korunması; kayıtsız episode türünün üretmemesi; sahibi olmayan üreticinin reddi; shadow modun göndermemesi; devrin bekleyen işi iptal etmesi; gönderim-anı kontrolü olmadan denemenin reddi; route çözümü; sağlayıcı kabulünün teslim sayılmaması ve teslim bayrağının zorlanamaması; reddedilen denemenin işi `failed` bırakıp ikinci denemeye izin vermesi; eski build'in güvenli ekrana düşmesi; başka hesabın cihazına gönderilmemesi; kapalı kategori; sessiz saat; açık alarmın sessiz saatte geçmesi; günlük sınırın üçüncü mesajı bastırması ve pencerenin yerel gün olması; pazarlamanın açık rıza olmadan bastırılması; haftalık sınır; kuyruktan sonra geri alınan rıza; kill switch.

## Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| `AUTH_RESTORE_SQL_FAILED`, SQLSTATE **42702** (ambiguous_column), yalnız **izin verilen** dispatch yolunda | plpgsql değişkeni `route` adını taşıyordu ve `notification_jobs` tablosunda da `route` sütunu var; `SET resolved_route=route` belirsizdi. Bastırma yolları bu satıra gelmeden döndüğü için ilk dispatch kontrolleri geçmişti | Değişken `resolved` olarak yeniden adlandırıldı |
| Advisor aşamasında `unindexed_foreign_keys` | `notification_consents` ve `notification_episodes`, `notification_purposes(purpose)`'a FK veriyordu ama o sütunda öncü indeks yoktu | `consent_purpose_idx` ve `episode_purpose_idx` eklendi |

İlk hata, **yalnız bir kod yolunda** ortaya çıkan gölgeleme hatasına iyi bir örnek: 14 kontrol geçtikten sonra patladı. Benzer değişken adlarını (`route`, `state`, `version`, `purpose`, `scope`) baştan farklı adlandırmak gerekiyor.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
node scripts/isg/run_suite.mjs foundation
~~~

Bu dilim sentetik koşuda `notification-core` aşamasında çalışır.

## Açık kalanlar

1. **Gerçek sağlayıcı adaptörleri:** APNs/FCM/e-posta, cihaz token yönetimi, retry/backoff politikası ve sağlayıcı hata matrisi.
2. **Onboarding rıza ekranı** ve izin durumlarının ayrımı (istendi / atlandı / OS reddetti / kategori kapalı), iOS Ayarlar yönlendirmesi, Android POST_NOTIFICATIONS sürüm farkları.
3. **Operasyon akışı:** simulate / shadow / canary, üretici cutover'ının gerçek watermark eşlemesi, öneri cooldown politikası (14 gün / 90 günde 2 aday) ve onaylanmış sessiz saat/sınır değerleri.
4. **Metrikler:** teslim ve okundu ayrı ölçüm; bu dilimde yapısal olarak iddia edilemiyor.
5. P01 dağıtım defteriyle bağ: domain olayından episode üretimi henüz bir tüketici tarafından yapılmıyor.
6. İstemci/native yüzey, canlı migration ve rollout.
