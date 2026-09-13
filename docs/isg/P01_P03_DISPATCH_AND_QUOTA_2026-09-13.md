# P01/P03 — olay tüketici omurgası ve gölge kota defteri

13 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; rollout kapalı, canlıya uygulanmadı.**

P05 kapanışındaki "sonraki iş" sırasının ilk maddesidir: sonraki domain'lerin (P06 kural/task, P07 eğitim, P12 bildirim, P14 lifecycle) ihtiyaç duyduğu **tüketici** ve **rezervasyon** sözleşmeleri. Bu dilim yeni bir ekran, endpoint veya kullanıcıya görünen davranış eklemez.

## Ne eklendi?

| Dilim | Migration | Özet |
|---|---|---|
| P01 / D01 | [20260913110000_isg_event_dispatch.sql](../../supabase/migrations/20260913110000_isg_event_dispatch.sql) | Producer ownership registry, olay başına teslim satırı, consumer receipt, lease/attempt/backoff, dead-letter, incelemeli replay, günlük mutabakat |
| P03 / D03 | [20260913113000_isg_quota_reservations.sql](../../supabase/migrations/20260913113000_isg_quota_reservations.sql) | Gölge rezervasyon defteri, settlement, ölçülmüş eski hak tabanı ve legacy sayaç karşılaştırması |

Sözleşmeler: [olay dağıtımı](../../contracts/isg/v1/event-dispatch.md), [kota rezervasyonu](../../contracts/isg/v1/quota-reservation.md).

P05'in yazdığı `personnel_outbox` ve `directory_outbox` artık gerçekten okunuyor: P05 migration'larının bir "henüz kimse tüketmiyor" notu vardı, bu dilim o boşluğu kapatır. Üretici tablolar, mutation fonksiyonları ve istemci sözleşmeleri **değişmedi**.

## Korunan sınırlar

- Her iki rollout satırı (`event_dispatch`, `quota_ledger`) **kapalı** gelir; migration hiçbir yerde açmaz. Kapalıyken bütün giriş noktaları `FEATURE_UNAVAILABLE` verir.
- Yeni fonksiyonların hiçbirine `anon`/`authenticated`/`service_role` EXECUTE verilmedi; worker kimliği henüz bağlanmadı. P05'in mevcut altı istemci RPC grant'i bit bit aynı kaldı.
- Yeni on tablo RLS açık, istemci GRANT'i sıfır. Advisor'ın bu tablolar için ürettiği kayıtlar INFO düzeyinde "policy'siz kapalı tablo" ve yeni fixture'da henüz taranmamış indekslerdir.
- Kota defteri **otorite değildir**: her satır `authority='shadow'` ve CHECK bu tek değeri kabul eder. `private.company_limit_for_user`, `private.user_plan_tier`, `private.enforce_company_write_rules` gövdeleri ve `public.companies` trigger'ları testte bayt bayt aynı kaldı.
- Limit sayıları migration'a gömülmedi; `p_limit`/`p_unlimited` çağıranın kendi yetki kararından gelir. Sınırsız açık bir bayraktır, büyük bir sayı değil.
- Dead bir olay ardılını **kasten bekletir**. Sessiz atlama yok; devam için gerekçeli replay şart.

## Test kanıtı

`node scripts/isg/run_auth_restore.mjs --synthetic-session` → **362/362 PASS**, 0 fail, container cleanup PASS. Bunun **62'si bu dilimin yeni kontrolü**; kalanı P01/P02/P05'in değişmeden geçen mevcut kontrolleridir. [Makine çıktısı](evidence/P01_P03_DISPATCH_QUOTA_2026-09-13.json).

Yeni kontrollerin kapsamı:

- **Kapı ve izinler:** rollout kapalıyken fanout/claim/reconcile/reserve/floor reddi; sıfır istemci tablo/fonksiyon yetkisi; RLS; sabit `search_path`; mevcut istemci grant listesinin değişmemesi.
- **Fan-out:** yalnız kayıtlı+etkin+abone tüketiciye teslim; kapalı tüketiciye sıfır; abone olunmayan olay türü hariç; tekrar çalıştırmada sıfır yeni satır; gerçek `personnel_outbox` sayısıyla birebir eşleşme.
- **Sıra ve lease:** en küçük aggregate sürümünün önce gelmesi; ardılın `done` olana kadar bekletilmesi; iki tüketicinin birbirinden bağımsız ilerlemesi; yanlış/süresi geçmiş token reddi; süresi dolan lease'in harcanmış attempt korunarak geri alınması.
- **Hata yolu:** backoff'un 5 → 10 saniye büyümesi; pencere dolmadan claim edilememesi; attempt bütçesi bitince dead-letter; dead olayın ardılını bekletmesi; gerekçesiz veya dead olmayan replay'in reddi; replay sonrası attempt sıfırlanırken dead-letter geçmişinin korunması ve boru hattının açılması.
- **Atomiklik:** makbuz yazımına enjekte edilen hata tüm tüketici transaction'ını geri alır; kaybolan ack tekrarı ikinci makbuz/etki üretmez.
- **Mutabakat:** rapor sayılarının defterle birebir uyuşması ve gün başına tek satır kalması.
- **Kota:** verilen limitin üstünde `CAPACITY_EXCEEDED`; aynı mutation'ın replay'i; değişen gövdede `IDEMPOTENCY_CONFLICT`; açık unlimited; settle/release/expire durum geçişleri; settled tüketimin geri açılmaması; dönem ve sahip pencerelerinin ayrılığı; dönem anahtarı biçim ve bilinmeyen timezone reddi; **20 paralel istekten tam birinin son slotu alması**.
- **Hak tabanı ve gölge:** unlimited ile sayısal tabanın birbirini dışlaması; `source='unknown'` kaydının incelemede kalması; kayıtsız tabanın "sıfır" değil "inceleme" dönmesi; tabanın kapasite yaratmaması; uyuşmazlık kaydının legacy sayacı ve helper'ları değiştirmemesi.

`node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade` → **28/28 PASS**. Tam legacy şema kopyasında altı migration sırayla yeniden oynatıldı: legacy satır fingerprint'leri ve eski public/private fonksiyon gövdeleri değişmedi, iki yeni rollout satırı kapalı geldi, yeni defterler boş başladı, kaynak container'a yazılmadı, cleanup PASS. Migration'ların sıfırdan replay edilebilirliği bu koşuyla doğrulandı; elle açılmış bir bayrak veya hazır volume üzerinden değil.

Offline regresyon: `node scripts/isg/run_suite.mjs foundation|capacity-shadow|nova-design|password-auth` ve Deno context/outcome testleri bu dilimden sonra da geçer. Yeni `dispatch_quota_guard.test.mjs` foundation paketine eklendi: rollout'un migration'da açılmadığını, istemci GRANT'i eklenmediğini, her yeni tablonun RLS aldığını ve runner bağının durduğunu offline doğrular.

## Açık kalanlar

1. Gerçek bir tüketici yok: eğitim ihtiyacı, skor projection ve bildirim üreticileri P06/P07/P12/P17'de yazılacak. Bu dilim onların **bağlanacağı** yeri sağlar.
2. Worker çalışma zamanı ve rol bağlaması (Edge/cron kimliği, server saati, jitter, timeout, DLQ yönetim akışı) açıktır; bu yüzden EXECUTE grant'i verilmedi.
3. DB dışı sağlayıcı idempotency'si (push, e-posta, mağaza) ve dağıtık atomiklik iddiası yoktur.
4. P03'ün ticari kapıları duruyor: onaylı plan kataloğu/limitler, eligibility cutoff'u, gift/indirim ayrımı, gerçek floor backfill'i ve mağaza/RevenueCat mutabakatı. Bunlar kapanmadan legacy sayaç otorite kalır.
5. Canlı migration, rollout açılışı, native/HTTP yüzey ve mağaza gönderimi yapılmadı.

**Sonraki iş:** P04 güvenli dosya/belge çekirdeği, ardından P06 kural/task çekirdeği; ikisi de bu tüketici ve rezervasyon sözleşmelerini kullanacak.
