# Dosya kabul matrisi ve karantina yaşam döngüsü — v1 sunucu sözleşmesi

13 Eylül 2026. P04'ün ilk dikey dilimidir. Bucket, storage policy, gerçek tarayıcı, parser ve istemci yüzeyi **bu dilimde yoktur**; mevcut analiz fotoğrafı ve rapor yolları değişmedi.

Migration: [20260913130000_isg_file_core.sql](../../../supabase/migrations/20260913130000_isg_file_core.sql).

## Amaç bazlı kabul

Sunucu otoritedir. Uygulama OS picker'ı bir formatı gizlese bile API kapsam dışı formatı reddeder; tersi de geçerlidir.

| Amaç | Kabul edilen uzantılar | Aday boyut sınırı |
|---|---|---|
| company_document | pdf, doc, docx, xls, xlsx | 50 MiB |
| evidence_photo | jpg, jpeg, png, heic, heif, webp, avif | 50 MiB |
| structured_import | xls, xlsx, csv | 10 MiB |
| company_logo | jpg, jpeg, png, webp | 5 MiB |

Kaynak 13 uzantının tamamı en az bir amaçta geçerlidir; hiçbiri **her** amaçta geçerli değildir. `csv` yalnız import, `heic/heif/avif` logo değil. Sınırlar V5 kaynağından gelen **aday** değerlerdir: satır `limit_source='v5_candidate'` ve `limit_approved=false` taşır, P04/P11 maliyet/performans kapısı kapanmadan onaylı sayılmaz. 0 byte kabul edilmez; `limit` ve `limit−1` kabul, `limit+1` `SIZE_LIMIT`.

## Yaşam döngüsü

~~~text
open_upload_intent  → pending      (karantina yolu bir kez yazılır, tekrar kullanılmaz)
mark_upload_received→ uploaded     (inen byte/hash/tip karar verir, istemcinin beyanı değil)
record_scan_result  → clean | rejected | scan_failed
promote_clean_upload→ promoted     (taranan hash yeniden doğrulanır, immutable asset)
reject/expire       → rejected | expired
~~~

- **Tarayıcı hatası temiz değildir.** `verdict='failed'` ayrı bir `scan_failed` durumudur ve `SCAN_UNAVAILABLE` ile kapanır; `rejected` ile karıştırılmaz.
- **Anti-TOCTOU:** tarama, yüklenen byte'ların hash'ini kaydeder; promotion yalnız aynı hash ve aynı boyutla yapılır. Farklıysa dosya `HASH_MISMATCH` ile reddedilir.
- **Overwrite yok:** `immutable_path` unique'tir. Aynı sahip ve aynı içerik hash'i için ikinci promotion mevcut nesnenin üzerine yazmaz, hata verir.
- **Önizleme hatası orijinali bozmaz:** `file_derivatives` ayrı durumdadır; başarısız preview asset'i `preview_status='failed'` yapar, `scan_status='clean'` ve orijinal okunabilir kalır. Türev "orijinal" diye etiketlenmez.
- **Idempotency:** `(owner, client_mutation_id)`. Aynı anahtar farklı gövdeyle gelirse `IDEMPOTENCY_CONFLICT`; her adım (received/scan/promote) tekrar çağrıldığında yeni yan etki üretmez.

## Depolama kotası gölgede kalır

Intent açılırken, `quota_ledger` açıksa `storage_bytes` için bir **gölge** rezervasyon yazılır; promotion `settle`, red/expire `release` eder. Gölge defter kapasiteyi aştığını söylerse yükleme **engellenmez**: intent `storage_shadow_denied=true` ile açılır ve yanıt `storage_authority='legacy'` der. Ledger kapalıyken dosya çekirdeği aynen çalışır. Otorite hâlâ mevcut legacy kota/limit yollarıdır.

## Henüz olmayanlar

Gerçek AV/parser sandbox'ı, DOC/XLS pozitif güvenlik fixture'ları (macro/DDE/OLE/XXE, zip traversal, sıkıştırma bombası, aşırı piksel, parola korumalı dosya, MIME uyuşmazlığı), signed URL politikası, bucket/storage policy, belge üretimi (§8.2) ve import (§8.3) bu dilimde yoktur. Dosya olayları henüz outbox'a yazılmıyor, bu yüzden dağıtım defterinin üçüncü bir kaynağı yok. İstemciye ve native tarafa hiçbir yüzey açılmadı.
