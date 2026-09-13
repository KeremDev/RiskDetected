# P12 — tek istekli işçi ve APNs/FCM adaptörleri

13 Eylül 2026 · Başlangıç commit'i `7929c550`.

**Bu işçi/adaptör kütüphanesi dilimi tamamlandı ve yerel doğrulandı. P12 bütünü kapanmadı.** Kod henüz canlı kuyruğa, gerçek cihaz tokenlarına veya bir HTTP/cron girişine bağlanmadı. Canlı gönderim yoktur. Önceki [SQL gönderim güvenliği](P12_DISPATCH_SAFETY_2026-09-13.md) korunur.

## Yapılanlar

- `runNotificationJob`: off/shadow/live ayrımı, güvenilir repository üzerinden snapshot okuma, credential hazırlığından sonra token/sahip/kategori/build değişikliğini yeniden kontrol, ikinci kill-switch kontrolü ve ardından tekil claim.
- Claim'in job/kanal/token/route/süre doğrulaması: eksik veya bozuk izin, başka işe ait hak, e-posta claim'i ve yetersiz süre ağ isteği başlatamaz. `allowed` tam olarak boolean true olmalıdır.
- Sağlayıcı çağrısı en çok 15 saniye ve tek istek; claim'de ayrıca 1 saniye pay aranır. Timeout, bağlantı hatası ve bozuk sonuç belirsiz receipt üretir; otomatik resend yoktur.
- Sonuç kaydı başarısızsa **aynı receipt** `receipt_pending_reconcile` ile çağırana döner; `prepare/send` tekrar çağrılmaz. Bu, henüz kalıcı bir receipt outbox'ı değildir; süreç kaybında SQL lease/mutabakat davranışı gereklidir.
- APNs ve FCM için ayrı endpoint/payload/header oluşturan `preparePush` eklendi. APNs sandbox/production host'u ve topic açıkça seçilir; FCM proje adı doğrulanır. Dış URL kabul edilmez, redirect takip edilmez, bearer/token header enjeksiyonu reddedilir.
- Eski `deliverToAPNs`/`deliverToFcm` iç retry döngüleri **yeni yoldan çağrılmaz**; legacy dosyalar değişmedi. Hazırlanmış adaptör ikinci `send` çağrısını reddeder.
- Veri yükünde yalnız `schema_version`, `job_id`, uygulama içi `route` ve seçilmiş başlık/gövde bulunur. Başlık/gövde için onaylı şablon ve kişisel veri kontrolü gelecekteki üreticiye aittir; uzunluk kontrolü DLP değildir.
- Sağlayıcı HTTP 200 kabul sayılır, **teslim/okundu sayılmaz**. Response body okunamaması kabulü tekrar gönderilebilir hataya çeviremez.
- 429, `PROVIDER_RETRY_POLICY_REQUIRED` ile bekletilir: mevcut SQL 30 saniyelik backoff'u sağlayıcının Retry-After kuralını temsil etmediği için otomatik retry açılmaz. 5xx/bağlantı kaybı belirsizdir. 401/403 yapılandırma incelemesi ister. Yalnız APNs 410 token geçersizliği olarak sınıflanır; çıplak FCM 404/APNs 400 ile cihaz kapatılmaz. Bu katman token tablosuna zaten yazmaz.

~~~text
off → hiçbir port çağrılmaz
shadow → etkinlik + snapshot kontrolü → gönderimsiz sonuç
live → snapshot → credential hazırla → snapshot ve kill switch'i yeniden oku
     → SQL claim portu → hak/süre doğrula → tek APNs/FCM isteği
     → aynı tokenla complete portu
         ├─ başarı → recorded
         └─ hata   → receipt_pending_reconcile; tekrar gönderme
~~~

## Bağlantı sözleşmesi ve önemli sınırlar

Repository portları `load`, `claim`, `complete`; gerçek SQL/REST adaptörü bu dilimde yoktur. `claim`, önceki SQL `dispatch_notification` sözleşmesini temsil eder. `complete`, SQL/HTTP hata cevaplarını exception'a çevirmelidir; error nesnesini başarı diye döndürmemelidir. Store bağlanırken sonuç doğrulaması, en az yetkili worker kimliği ve receipt'in kalıcı saklanması ayrıca uygulanacaktır.

Snapshot, istek gövdesinden ya da kullanıcı metadata'sından yetki olarak alınamaz. Credential hazırlanması ve repository operasyonlarının dış zaman aşımı host/worker bağlamasında uygulanmalıdır; bu katman yalnız sağlayıcı çağrısına deadline koyar. Veritabanı kontrolü ile dış ağ çağrısı atomik değildir; uçuşta iptal veya exactly-once teslim iddiası yoktur. Returned receipt yalnız iç worker içindir; kamuya açık HTTP yanıtı veya log payload'ı değildir.

Adaptörler credential ve `fetchPort` bağımlılıklarını açıkça alır. Global fetch/env/secret erişimi, Deno.serve, otomatik scheduler veya deploy kodu bulunmaz. Dolayısıyla kaynak dosyasının eklenmesi canlı gönderimi açmaz.

## Paket sonu testleri

| Kontrol | Sonuç |
|---|---|
| Node foundation + mevcut regresyon | **298/298 PASS** |
| Bu pakette eklenen davranış testleri | **53 PASS** |
| Aynı 53 test, Deno `--deny-net --deny-env` | **53/53 PASS**; bağımsız 53 yeni senaryo diye toplanmaz |
| İki üretim TypeScript dosyası `deno check` | PASS |
| Function-test-map | 8 kaynak bağlı; iki yeni kaynak `targeted_behavior_tests`; runtime/mağaza hazır iddiası yok |

Kapsam: off/shadow, credential hatası, değişen snapshot, kill switch, hak reddi/bozuk hak, yanlış job/kanal/route, süre, sağlayıcı throw/hang/bozuk cevap, kayıt cevabı kaybı, sekiz paralel çağıran/tek claim kazananı, iki sağlayıcıda 11'er HTTP durum sınıfı, tek kullanım ve yanlış config/URL.

İlk toplu koşu 293 PASS / 4 FAIL idi: üç başarısız test route regex'inin `https://` kabul ettiğini gösterdi; iki yeni kaynağın function-map'e bağlanmaması da mevcut korumayı tetikledi. Route yalnız uygulama içi karakterlerle sınırlandı, kaynaklar SHA-256 ile kendi testlerine bağlandı. Daha sonra boolean izin doğrulamasına bir test eklendi; son sonuç 298 PASS oldu. Deno JS testlerinin ilk varsayılan typecheck denemesi yerel `@types/node` paketi nedeniyle başlamadı; paket yüklemek yerine JS davranış koşusu `--no-check` ile çalıştı, üretim TS dosyaları **ayrıca tip kontrolünden geçti**.

SQL migration, RLS veya DB API değişmedi; bu nedenle bu tur DB restore/upgrade veya native build yeniden çalıştırılmadı. Önceki 754 SQL/sentetik ve 31 upgrade sonucu tarihsel kanıttır, bu turun yeni testi olarak sayılmaz. [Makine kanıtı](evidence/P12_WORKER_TRANSPORT_2026-09-13.json).

## Sıradaki bağlantılar

1. Güvenilir cihaz/token/izin read model'i ve kısıtlı repository/worker rolü; gerçek SQL claim/complete adaptörü, kalıcı receipt outbox'ı ve worker yaşam döngüsü.
2. APNs JWT/FCM OAuth credential kaynağı, gerçek HTTP/2/provider sandbox kanıtı, provider reason envelope ve Retry-After sürelerinin kalıcılaştırılması.
3. E-posta adaptörü ve kanal politikası; P01 domain-event tüketicisi, schedule güncelliği ve operasyonel mutabakat.
4. iOS/Android izin/onboarding ve deep-link erişim yüzeyi; onaylı şablon/politika, simulate/canary ve insan onaylı gerçek cutover.

Bu tur Supabase becerisi doğrultusunda dış işin kalıcılığı ile Edge Function yaşam süresi birbirine eşit sayılmadı; bilinmeyen sonucu background callback'e güvenerek tekrar gönderen yol eklenmedi.

Teknik referanslar: [Supabase background task sınırları](https://supabase.com/docs/guides/functions/background-tasks), [Apple APNs yanıtları](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns), [FCM hata kodları](https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode). Bu kaynaklar sağlayıcı davranışına referanstır; gerçek sağlayıcı testi yerine geçmez.
