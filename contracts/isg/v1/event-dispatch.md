# Olay dağıtımı — v1 sunucu sözleşmesi

13 Eylül 2026. P05'in **zaten yazdığı** iki üreticiyi (`personnel_outbox`, `directory_outbox`) tüketen ilk gerçek şema dilimidir. Yayınlanmış HTTP/RPC endpoint değildir: istemciye tek bir GRANT bile verilmez ve `event_dispatch` rollout satırı kapalı gelir.

Migration: [20260913110000_isg_event_dispatch.sql](../../../supabase/migrations/20260913110000_isg_event_dispatch.sql).

## Teslim modeli

Taşıma **en az bir kez**dir. Aynı olayın iki kez tüketilmemesini `consumer_receipts(event_id, consumer)` sağlar; tüketici etkisi ile makbuz aynı transaction'da commit olur.

~~~text
üretici outbox (P05 mutation'ının parçası)
  → fanout: kayıtlı + etkin + olay türüne abone her tüketici için bir teslim satırı
  → claim: aggregate sırası + lease + attempt bütçesi
  → complete: makbuz + projection tek transaction  | fail: backoff veya dead-letter
  → replay: yalnız incelenmiş dead-letter          | reconcile: günlük mutabakat
~~~

| Fonksiyon | Rol | Not |
|---|---|---|
| `dispatch_fanout(limit, now)` | Yeni üretici olaylarını abone tüketicilere yazar | Tekrar çalıştırmak yeni satır üretmez |
| `claim_event(consumer, now)` | Lease alır, attempt harcar | Uygun olay yoksa `NULL` |
| `complete_event(consumer, event, token, now)` | Makbuz + `done` | Kaybolan ack tekrarında `false`, ikinci etki yok |
| `fail_event(consumer, event, token, error, now)` | Backoff veya dead-letter | `error` beş sabit koddan biri |
| `replay_dead_event(consumer, event, reason, now)` | Dead → pending | Gerekçe zorunlu; dead-letter geçmişi silinmez |
| `reconcile_dispatch(on, now)` | Günlük sayım raporu | Gün başına tek satır |

## Değişmezler

- **Aggregate sırası:** aynı (tüketici, firma, aggregate) için küçük sürüm `done` olmadan büyüğü claim edilemez. Dead bir olay ardılını **kasten bekletir**; sessiz atlama yoktur.
- **Lease:** süresi dolan lease geri alınır, harcanmış attempt korunur. Süresi geçmiş token ile `complete`/`fail` `LEASE_LOST` verir.
- **Backoff:** `backoff_base_seconds × 2^(attempt−1)`, 3600 saniye tavanı. Jitter worker'ın işidir, defterin değil.
- **Attempt bütçesi:** `max_attempts` dolunca teslim `dead` olur ve dead-letter satırı açılır. Replay `attempts`'i sıfırlar, dead-letter satırına `replayed_at`/`replay_reason` yazar.
- **Tüketici bağımsızlığı:** bir tüketicinin dead olayı diğerini durdurmaz.
- **Producer ownership:** kayıtlı olmayan veya kapatılmış tüketici `ACCESS_DENIED` alır. Abone olunmayan olay türü hiç teslim edilmez.
- **Kill switch:** `event_dispatch` rollout'u kapatmak bütün giriş noktalarını `FEATURE_UNAVAILABLE` yapar; üretici mutation'ları etkilenmez.

## Henüz olmayanlar

Gerçek bir tüketici (eğitim ihtiyacı, skor, bildirim) yazılmadı; worker kimliği/rolü bağlanmadı, bu yüzden fonksiyonlara `anon`/`authenticated`/`service_role` EXECUTE verilmedi. `p_now` **sunucu tarafı** test/worker saatidir, istemciden gelmez. DB dışı sağlayıcı (push, e-posta, mağaza) idempotency'si ve dağıtık atomiklik iddiası yoktur. Mevcut legacy bildirim kuyruğu ve üreticileri değiştirilmedi.
