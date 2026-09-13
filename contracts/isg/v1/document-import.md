# Belge üretimi ve içeri aktarma — v1 sunucu sözleşmesi

14 Eylül 2026. P11'in ilk dilimi: **numaralandırma, değişmez snapshot, export işi defteri** ve **önizleme/commit/telafi** zinciri. Render eden ve dosyayı ayrıştıran ikili programlar bu dilimde **yoktur**; burası onların uyacağı kural yüzeyidir.

Migration: [20260914030000_isg_document_import_core.sql](../../../supabase/migrations/20260914030000_isg_document_import_core.sql).

## Belge

| Kural | Davranış |
|---|---|
| Şablon | Yayımlanmamış şablonla belge açılmaz; şablon domaini belgenin domaini ile aynı olmak zorunda (`TEMPLATE_NOT_PUBLISHED`) |
| Numara | `(firma, kapsam, yıl)` başına kilitli tek satır; 20 eşzamanlı tahsis 20 farklı numara üretir, `document_no` global unique |
| Snapshot | Finalize anında firma adı, kişi/görev, tarihler ve şablon sürümü donar; kaynak sonradan değişse bile snapshot ve SHA-256 aynı kalır |
| Tekrar | Aynı `mutation_id` ile finalize aynı sürümü döndürür; ikinci mantıksal belge oluşmaz |
| Format pariteliği | PDF ve XLSX **aynı snapshot hash'ini** taşır; `(belge, sürüm, format)` başına tek iş |
| Taranmış kaynak | Taranmış bir orijinalin XLSX'i `content_kind='metadata_index'` olur; yapısal tablo **uydurulmaz** |
| Render hatası | Export işinin `failed` olması belgeyi ve sürümü etkilemez; `ready` bir iş üzerine yazılamaz |

## İçeri aktarma

Sıra: `open_import_batch → stage_import_row (n kez) → preview_import_batch → commit_import_batch → (gerekirse) compensate_import_batch`.

- **Idempotency kapsamı** `(firma, mutation_id)`; parmak izi `(firma, hedef tür, dosya SHA-256, mapping sürümü)` üzerinden alınır. Aynı dosyayı farklı mapping sürümüyle işlemek `IDEMPOTENCY_CONFLICT` verir — bilinçli yeni işlem gerekir.
- **Sağlık sütunu kapıda reddedilir** (`HEALTH_COLUMN_REFUSED`): hem başlık listesinde hem satır anahtarlarında; ham JSON'a da saklanmaz.
- **Kimlik isimden türetilmez:** kodu olmayan satır `review` + `IDENTITY_NOT_DERIVABLE` olur; ne eşleşir ne de ikinci kişi yaratır. Var olan kod `duplicate`tır.
- **Hücre kuralları:** `=`, `+`, `-`, `@` ile başlayan değer formül değil veridir, ön eki alınır ve `sanitised` işaretlenir. TR ondalık virgülü okunur; `1.234` gibi belirsiz değer tahmin edilmez, `review` + `AMBIGUOUS_DECIMAL` olur. Kod alanı baştaki sıfırları korur (metindir). Excel 1900 ve 1904 seri tarih sistemleri desteklenir; 1900'ün olmayan 29 Şubat'ı (`serial 60`) `EXCEL_1900_LEAP_BUG` ile reddedilir. Boş hücre geçersiz hücre değildir.
- **Önizleme sözleşmesi:** preview hash'i her satırın durumunu ve **gördüğü hedef sürümleri** kapsar. Commit bu hash'i ister (`PREVIEW_REQUIRED`, `PREVIEW_STALE`); hedef kayıt önizlemeden sonra değiştiyse commit çakışır.
- **Gizli yarım başarı yok:** hatalı satır varken commit ancak `allow_partial=true` ile yapılır (`PARTIAL_COMMIT_NOT_ALLOWED`), yazılan her satır için checkpoint tutulur ve özet `partial` bayrağı döner.
- **Telafi dar kapsamlıdır:** yalnız bu batch'in yarattığı ve **o gün bıraktığı hâlde duran** kayıtlar silinir; sonradan düzenlenmiş kayıt `kept_because_changed` olarak raporlanır.

## Henüz olmayanlar

PDF/XLSX render eden worker, güvenli dosya ayrıştırıcısı (P04 sandbox kararına bağlı), Türkçe karakter/uzun ad/sayfa sonu/font fallback/logo oranı gibi **görsel** kabuller, satır ölçekli performans (1.000/10.000 satır), ortak arama/filtre yüzeyi, legacy rapor adaptörü ve istemci/native yüzey. `documents` ve `imports` rollout satırları kapalıdır; istemciye GRANT verilmemiştir.
