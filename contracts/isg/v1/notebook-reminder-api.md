# P13 kişisel hatırlatıcı API v1

Tarih: 13 Eylül 2026. Bu sözleşmenin ilk teslim stratejisi yalnız `server_push`'tır. Yerel alarm veya sessiz fallback yoktur. API owner-only ve Free'dir; firma, işyeri, çalışan, abonelik veya başka İSG entity kapsamı kabul etmez.

## Açık istemci RPC'leri

`isg_notebook_reminders_v1(p_after uuid)` aktif oturum sahibinin hatırlatıcılarını UUID keyset ile en fazla 20'şer döndürür. Yanıt `schema_version=1`, `delivery_mode=server_push`, `reminders`, `has_more` ve `next_after` alanlarını içerir. Her kayıtta seri sürümü, tekrar kuralı, yerel saat/timezone, seçili kurulum ve varsa sıradaki açık occurrence bulunur.

`isg_notebook_reminder_mutate_v1(...)` dört işlem kabul eder:

- `create`: yeni mutation UUID, başlık, `once|daily|weekly|monthly`, gelecekteki yerel tarih/saat, IANA timezone ve istemcinin kalıcı kurulum UUID'si gerekir. `expected=0` olur.
- `complete`: hatırlatıcı, occurrence ve güncel seri sürümü gerekir.
- `snooze`: `complete` alanlarına ek olarak occurrence'ın asıl zamanından ileri bir UTC anı gerekir.
- `cancel`: hatırlatıcı ve güncel seri sürümü gerekir; yalnız gelecekteki açık occurrence'lar kapanır.

Opsiyonel parametreler eksik bırakılmaz; kullanılmadığında açıkça JSON `null` gönderilir. Aynı mutation ve aynı içerik receipt'i replay eder. Aynı mutation/farklı içerik `IDEMPOTENCY_CONFLICT` olur. Receipt kullanıcı başlığı veya not gövdesi taşımaz.

## Teslimat sahipliği ve P12 bağı

Oluşturma ancak seçili kurulum için kullanıcının güncel, etkin token'ı, son 24 saatte aktif oturumla yazılmış OS izin kaydı ve açık ana bildirim + `app_reminders` tercihi varsa kabul edilir; aksi hâlde `DEVICE_UNAVAILABLE` döner. Geçmiş tarih sunucu tarafından `VALIDATION_ERROR` ile reddedilir. Sunucu teslim claim'ini `server_push` olarak tek kurulum üzerine yazar ve ilk sekiz occurrence'ı projekte eder.

Özel producer `enqueue_personal_reminder_notifications` yalnız ufuk içindeki occurrence'lardan P12 episode/job üretir; sağlayıcı çağırmaz. İşçi claim anında ve sağlayıcı isteğinden hemen önce aşağıdakileri tekrar doğrular:

- seri ve occurrence hâlâ aktif mi,
- occurrence ve episode seri sürümü güncel mi,
- ertelenmiş/asıl zaman job zamanı ile aynı mı,
- cihaz hâlâ reminder'ın seçili kurulumu mu,
- token güncel, OS izni açık, oturum geçerli, minimum build ve `app_reminders` tercihi uygun mu.

Koşul değişmişse job bastırılır; başka cihaza veya eski zamana gönderim yapılmaz. Provider kabulü cihaz teslimi veya kullanıcı okuması sayılmaz. Tam bir teslim ve exactly-once garantisi verilmez.

## Native davranış

iOS ve Android aynı create/complete/snooze/cancel sözleşmesini kullanır. Kurulum UUID'si kullanıcı kimliğinden türetilmeyen rastgele bir değerdir ve cihazda kalıcı tutulur. iOS APNs, Android FCM token kaydı aynı UUID'yi `push_device_tokens.installation_id` alanına yazar.

Ekranlar `NotebookUIRelease.enabled=false` altında kalır. Sunucu `personal_notes` ve `notifications` rollout'ları da varsayılan kapalıdır. İstemci bayrağı yetkilendirme değildir; sunucu her çağrıda aktif session ve rollout'u doğrular.

## Hata ve gizlilik sınırı

Beklenen kapalı hata kodları: `AUTH_REQUIRED`, `FEATURE_UNAVAILABLE`, `ACCESS_DENIED`, `VERSION_CONFLICT`, `IDEMPOTENCY_CONFLICT`, `VALIDATION_ERROR`, `DEVICE_UNAVAILABLE`. Ham token, not gövdesi ve kullanıcı başlığı teknik hata/receipt telemetrisine yazılmaz. Notification snapshot yalnız provider isteği için sınırlı başlık ve sabit gövde üretir.

Bu sözleşme production scheduler, pool/worker rolü, APNs/FCM credential'ı, canlı rollout, fiziksel cihaz teslimi veya mağaza yayını yapmaz ve bunların tamamlandığını iddia etmez.
