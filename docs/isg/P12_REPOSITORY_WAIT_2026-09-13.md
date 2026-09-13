# P12 — SQL repository bağlantısı ve kalıcı sağlayıcı beklemesi

13 Eylül 2026 · Başlangıç `18f253f3` · **Bu bağlantı dilimi yerel olarak tamamlandı. P12 bütünü ve canlı aktivasyon tamamlanmadı.**

Önceki işçi/adaptör kütüphanesinin `claim/complete` portları artık sabit, parametre bağlı PostgreSQL çağrıları yapan gerçek bir repository adaptörüyle eşleşiyor. İşçi → repository → PostgreSQL → taklit sağlayıcı → PostgreSQL sonucu zinciri izole kabulde çalıştırıldı. Canlı connection pool, credential, cihaz kayıt kaynağı veya scheduler bağlanmadı.

## Tamamlananlar

- `createNotificationRepository`: sabit `SELECT private_isg.dispatch_notification(...)` ve `complete_notification_delivery_with_retry(...)` çağrıları; değerler ayrı parametre dizisidir. SQL metnine kullanıcı/veri değeri eklenmez. Driver SQL hatasında exception üretmeli ve tek JSON scalar döndürmelidir; RPC `{data,error}` zarfı başarı sayılmaz.
- Snapshot owner/build/kategori/OS alanları, job/token/kanal ve timestamp doğrulaması; claim/receipt yanıtında `schema_version`, aynı job ve token, attempt UUID, replay/durum, teslim/okundu=false ve aynı bekleme değeri kontrol edilir. Bozuk yanıt recorded sayılmaz.
- SQL/driver hataları ham connection string veya provider mesajı taşımayan sabit iç hata koduna çevrilir. Repository otomatik query veya gönderim retry yapmaz.
- `delivery_attempts.retry_after_seconds` sütunu eklendi; 1–86400 saniye, yalnız bilinen geçici retlerde kullanılabilir. Yeni özel fonksiyon eski tokenlı tamamlayıcıyla **aynı transaction/sahip/iş kilidini** kullanır.
- Sonraki deneme zamanı mevcut üstel backoff ile sağlayıcı beklemesinin büyük olanıdır. Yeni tamamlayıcıda `RATE_LIMITED` için en az 60 saniye uygulanır; 10 deneme sınırı ve diğer durumlar korunur.
- Aynı token/same-result replay beklemeyi yeniden başlatmaz; farklı bekleme değeri `IDEMPOTENCY_CONFLICT` olur, satırlar değişmez. Response içinde aynı job/token ve uygulanan sağlayıcı bekleme girdisi geri verilir.
- APNs/FCM 429 yanıtı artık geçerli `Retry-After` ile `rejected/RATE_LIMITED` üretir. Saniye ve standart GMT tarih biçimi desteklenir; yoksa/çok kısa ise 60 saniye taban kullanılır. 24 saatten uzun veya temsil edilemeyen değer sessizce kısaltılmaz: belirsiz/incelemelik durumda tutulur. 5xx veya ağ sonucu belirsizliğinde otomatik resend hâlâ yoktur.

~~~text
429 + Retry-After: 120
  → işçi receipt: rejected / RATE_LIMITED / 120
  → parametre bağlı SQL tamamlayıcı
  → attempt + job.next_attempt_at atomik kayıt
  → 119. saniye: claim yok, sağlayıcı çağrısı yok
  → 120. saniye: yeni claim/token → tek yeni istek

SQL commit oldu, cevabı kayboldu
  → worker: receipt_pending_reconcile
  → yeni işçi çağrısı: sent iş tekrar claim edilmez
  → aynı receipt replay: aynı attempt, sağlayıcı çağrısı yok
~~~

## Paket sonu kanıt

| Koşu | Sonuç |
|---|---|
| Sentetik Auth/DB + tüm sunucu dilimleri | **768 PASS**, **767 tekil ID**, 0 FAIL |
| Yeni gerçek SQL repository kabulleri | **14 PASS** |
| Tam legacy kopyasında upgrade | **32/32 PASS**, **18 migration**, 107 RLS tablo, istemci tablo GRANT sayısı 0 |
| Node foundation | **331/331 PASS** |
| Deno, ağ ve env erişimi reddedilmiş worker/repository | **84/84 PASS** — aynı Node davranış testleri, ek 84 bağımsız senaryo değildir |
| Üç üretim TypeScript dosyasında `deno check` | PASS |
| Advisor | İSG kapsamındaki 203 bulgunun tamamı INFO; kapsamda ERROR/WARN yok |

İlk paket sonu koşuları geçti; bu dilimde test sonrası kod düzeltmesi gerekmedi. Eski `local_smtp_code_received` kimliği iki mail kontrolünde tekrar ettiği için toplam/tekil sayıları ayrı verildi. Kaynak/harness function-map artık 9 dosyayı kapsar; bu eşleme tam ürün kabulü iddiası değildir.

Sentetik rapor: `output/isg/runs/synthetic-auth-cw7nHT/REPORT.json`.
Upgrade raporu: `backups/isg-auth-service-restore-20260912-tFgEXf/REPORT.json`.
İki modda cleanup PASS; legacy satır ve helper fingerprint'leri aynı. Yeni tablo veya RLS politikası açılmadı; yeni fonksiyon PUBLIC/anon/authenticated/service_role için kapalı. Supabase becerisinin yetki/transaction kontrolleri ve advisor denetimi uygulandı.

Testteki `restart_does_not_resend_committed_job`, **aynı süreçte yeni worker çağrısıdır**; OS süreci öldürme/yeniden başlatma kanıtı değildir. Sekiz çağıran gerçek SQL tekilliğini kullanır; bağımsız DB oturumlarının yarış kabulleri önceki güvenlik paketinde bulunur. Sağlayıcı ve cihaz bilgisi sentetiktir; APNs/FCM sunucusuna hiçbir istek çıkmadı.

[Makine kanıtı](evidence/P12_REPOSITORY_WAIT_2026-09-13.json) · [Repository](../../supabase/functions/_shared/isg/notification-repository.ts) · [SQL kabulü](../../scripts/isg/notification_repository_probe.mjs) · [Migration](../../supabase/migrations/20260914070002_isg_notification_provider_wait.sql)

## Açık kalanlar

1. Güvenilir cihaz/token/izin read model'i ve seçimi: `loadTrusted` hâlâ açık bir iç porttur. İstek gövdesi veya kullanıcı metadata'sı bu portun yetki kaynağı olamaz.
2. Kısıtlı production worker rolü/pool, gerçek APNs JWT/FCM OAuth credential kaynağı, gerçek sağlayıcı/HTTP2 testi ve yeni native payload erişim doğrulaması.
3. SQL tamamlamadan **önce** süreç/DB tamamen kaybolursa receipt'in kalıcı outbox'ı ve operatör mutabakatı. Bu paket yalnız commit sonrası cevap kaybını idempotent replay ile doğrular; genel kayıpsız dağıtık teslim iddia etmez.
4. E-posta adaptörü, P01 domain tüketicisi, schedule güncelliği, global/proje/cihaz sağlayıcı throttle koordinasyonu ve jitter. Bu bekleme tek iş içindir; 429'un bütün proje kotasını çözmüş sayılmaz.
5. Native rıza/onboarding, onaylı içerik/politika, simulate/canary ve insan onaylı canlı cutover.

Migration CLI ile `20260913135434` olarak üretildi; depodaki geleceğe tarihli bağımlılığın arkasına `20260914070002` olarak sıralandı. Önceki migration'lar değiştirilmedi. Canlı migration/rollout, mağaza, abonelik ve iOS/Android kaynakları değişmedi; native testler yeniden koşulmadı.

Teknik referans: [FCM kota ve Retry-After kuralları](https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode), [Supabase fonksiyon yetkileri](https://supabase.com/docs/guides/database/functions). Bunlar ürün onayı veya gerçek sağlayıcı kabulü yerine geçmez.
