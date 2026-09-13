# P11 ilk dilim — belge üretimi omurgası ve içeri aktarma zinciri

14 Eylül 2026 · Durum: **yerel geliştirme ve izole kabul tamamlandı; `documents` ve `imports` rollout satırları kapalı, canlıya uygulanmadı.**

Migration: [20260914030000_isg_document_import_core.sql](../../supabase/migrations/20260914030000_isg_document_import_core.sql) · Sözleşme: [belge ve import](../../contracts/isg/v1/document-import.md) · [Kanıt](evidence/P11_DOCUMENT_IMPORT_2026-09-14.json).

## Ne eklendi?

**Belge tarafı:** sürümlü şablon yayını, kaynak başına tek belge, `(firma, kapsam, yıl)` kilidiyle numara tahsisi, finalize anında donan snapshot + SHA-256, PDF/XLSX export işi defteri ve render sonucu.

- Snapshot **kaynağı takip etmez**: testte finalize'dan sonra firma unvanı değiştirildi, belgenin `snapshot->>'company_name'` değeri ve hash'i aynı kaldı.
- Aynı `mutation_id` ile finalize ikinci mantıksal belge üretmiyor.
- İki format **aynı snapshot hash'ini** taşıyor; taranmış bir orijinalin XLSX'i `metadata_index` oluyor, yapısal tablo uydurulmuyor.
- Export'un `failed` olması belgeyi etkilemiyor; `ready` bir iş üzerine yazılamıyor.

**Import tarafı:** batch → satır → önizleme → commit → telafi. Hücre kuralları SQL'de: formül ön eki nötrleme, TR ondalık, belirsiz ondalıkta `review`, baştaki sıfırı koruyan kod alanı, Excel 1900/1904 seri tarihleri ve 1900'ün olmayan 29 Şubat'ı.

- **Kimlik isimden türetilmiyor:** kodsuz satır `review` + `IDENTITY_NOT_DERIVABLE`.
- **Sağlık sütunu kapıda reddediliyor** — hem başlık listesinde hem satır anahtarında.
- **Önizleme sözleşmesi:** preview hash'i satır durumlarını ve gördüğü hedef sürümleri kapsıyor; hedef kayıt değişirse commit `PREVIEW_STALE`.
- **Gizli yarım başarı yok:** hatalı satır varken commit ancak `allow_partial=true` ile; her yazılan satır için checkpoint.
- **Telafi dar:** yalnız bu batch'in yarattığı ve sonradan değişmemiş kayıtlar siliniyor; değişmiş olan `kept_because_changed` olarak raporlanıyor.

## Test kanıtı

`--synthetic-session` → **659/659 PASS** (38'i bu dilimin yeni kontrolü), cleanup PASS. `--isolated-copy --p05-upgrade` → **29/29 PASS**: tam legacy kopyada **on dört** migration replay, 93 tablo, hepsinde RLS. Offline foundation **224 PASS**.

Öne çıkan kontroller: 20 eşzamanlı numara tahsisinin 20 farklı numara üretmesi; snapshot'ın kaynaktan bağımsızlığı; format pariteliği; taranmış kaynakta metadata index; formül ön ekinin dört varyantı; `1.234`'ün tahmin edilmeyip incelemeye düşmesi; `007`'nin sıfırlarını koruması; iki Excel tarih sisteminin 1462 günlük ilişkisi; `serial 60`'ın reddi; boş hücrenin hatalı sayılmaması; sağlık sütununun iki ayrı noktada reddi; önizlemesiz commit, bayat hash, taşınmış hedef ve politikasız kısmi commit redleri; commit replay'inin yeni kayıt yazmaması; telafinin yalnız değişmemiş kaydı silmesi.

## Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| `AUTH_RESTORE_SQL_FAILED`, SQLSTATE **42883** (undefined_function) | PostgreSQL'de `date + bigint` operatörü yok; Excel seri numarası `bigint` olarak tanımlanmıştı | Değişken `integer` yapıldı (`2958465` sınırı zaten integer'a sığıyor) |
| Satır staging'de **CHECK_VIOLATION** | `import_rows.error_code` regex'i yalnız `A-Z_` kabul ediyordu; `EXCEL_1900_LEAP_BUG` rakam içeriyor | İki `error_code` regex'i `^[A-Z][A-Z0-9_]{2,n}$` olarak genişletildi |

Her ikisi de ilk koşuda yakalandı; kanıt JSON'unda `defects_found_and_fixed` altında kayıtlı.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
node scripts/isg/run_suite.mjs foundation
~~~

Sentetik koşu bu dilimi `document-and-import` aşamasında çalıştırır; rapor `output/isg/runs/<run>/REPORT.json` altındadır.

## Açık kalanlar

1. **Render worker'ı:** PDF/XLSX üretimi ve görsel kabuller (Türkçe karakter, çok uzun ad, tablo başlığı tekrarı, sayfa sonu, font fallback, logo oranı, baskı) — P04'ün sandbox/teknoloji kararına bağlı.
2. **Güvenli ayrıştırıcı:** gerçek CSV/XLS/XLSX okuma, delimiter/encoding tespiti, 10.000 satır ölçeği ve kaynak limitleri.
3. Ortak arama/filtre yüzeyi ve legacy rapor adaptörü (§7.5 "Evrak/rapor merkezi").
4. Import hedefi şimdilik yalnız `employee`; `equipment` hedefi tablo düzeyinde tanımlı ama commit yolu yazılmadı.
5. Belge/import olayları henüz outbox'a yazılmıyor.
6. İstemci/native yüzey, canlı migration ve rollout.
