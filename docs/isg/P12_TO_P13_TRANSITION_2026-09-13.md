# P12 → P13 geliştirme geçişi

13 Eylül 2026. Kullanıcı sonraki faza geçmek için gerekenlerin yapılmasını istedi.

## Karar

**Aktif geliştirme P13 kişisel not defterine geçti. P12 tamamlandı veya yayına hazır olarak işaretlenmedi.** Ana geçiş planının §10.2 ve faz tablosuna göre P13 not senkronu P01/P02'ye bağlıdır; P12'nin canlı push aktivasyonuna bağlı değildir. P12'nin kalan işleri not defteri API/offline geliştirmesini durdurmaz. P13 server-push hatırlatıcıları ise bu eksikler çözülmeden açılmaz.

## P12'den taşınan açık işler

- Cihaz okuma kaynağının worker claim/prepare akışına son bağlantısı ve çok cihaz teslim stratejisi.
- Çalışma ortamı, kısıtlı worker rolü/bağlantısı ve gerçek sağlayıcı credential bağlaması. Kalıcı dosya journal adaptörü Edge geçici diski için uygun değildir.
- Domain producer/schedule güncelliği, e-posta, sağlayıcı genel kota koordinasyonu, native yeni payload/deep-link erişim doğrulaması.
- Gerçek sağlayıcı/cihaz kabulü, onaylı amaç/kanal politikaları, canary ve canlı cutover.

Bu satırlar yalnız insan onayı bekleyen maddeler değildir; uygulama ve entegrasyon işi de içerir. Canlı bildirim rollout'u kapalı kalır. P12'nin eksiklerini P13 bitmiş gibi göstermek için başka bir faza taşımıyoruz.

## P13'te başlatılan iş

Mevcut özel not çekirdeğine aktif oturumlu, owner-only ve Free okuma/yazma API'si eklendi. Mutation receipt'i, ilk yazma yarışı, aynı isteğin tekrarı, güncel sürümlü conflict çözümü ve tombstone koruması bu API'de bulunur. Liste ve conflict okumaları sayfalıdır. [API sözleşmesi](../../contracts/isg/v1/notebook-sync-api.md).

Devam sırası: native güvenli taslak/kuyruk ve RPC repository → iki cihaz conflict/tombstone senkronu → not ekranları/etiket/checklist → yerel hatırlatıcı sahipliği ve cihaz kabulleri. Hatırlatıcı server-push yolu P12 bağımlılığı nedeniyle kapalı kalacaktır.

P13 bütünü, native akışlar ve cihaz kabulleri tamamlanmadan kapanmış sayılmayacak. Canlı migration, mağaza yayını ve uygulama kimlik değişikliği yapılmadı.

## Bu geçişte tamamlanan API paketi ve doğrulama

- Sentetik Auth/PostgREST/DB: **816 PASS, 815 tekil kontrol kimliği**; notebook API'ye ait **30 yeni PASS**. Dört bağımsız PostgreSQL bağlantısında aynı mutation yalnız bir kez kaydedildi. Eski `local_smtp_code_received` kimliği iki kontrolde kullanıldığı için toplam/tekil sayıları ayrıdır.
- Tam legacy yedek kopyasında upgrade: **32/32 PASS**, **20 migration**, 109 özel RLS tablo, doğrudan istemci tablo yetkisi yok; mevcut satır ve helper fingerprint'leri korunuyor.
- Foundation: **355/355 PASS**. Yeni migration/API bu paket sonu koşusunda düzeltme gerektirmeden geçti.
- Advisor: İSG kapsamındaki bulgularda ERROR/WARN yok. İki geçici veritabanı ortamının temizliği PASS. Canlı ortama işlem yapılmadı.

Raporlar: `output/isg/runs/synthetic-auth-zngU8B/REPORT.json` ve `backups/isg-auth-service-restore-20260912-rJpgSX/REPORT.json`. Testler native SDK/offline cihaz kabulü veya P13 faz kapanışı değildir. Bu tur native kaynak değişmedi; native derlemeler tekrar çalıştırılmadı.
