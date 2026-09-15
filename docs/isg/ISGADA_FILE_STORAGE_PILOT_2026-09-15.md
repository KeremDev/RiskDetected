# Dosya depolama (P04) canlıya açıldı — pilot hesap

15 Eylül 2026. Rollout **global açık** (`file_core`, `file_library` — her ikisi de read/write=true), sınırlayan tek şey Nova ekranlarının yalnız `NOVA_PILOT_BUILD` derlemesinde bulunması ve yazma yolunun zaten Plus/Pro abonelik şartı taşıması — modül anahtarı ("modules", "emergency_plan" dahil) da aynı şekilde global açık, bu proje boyunca kurulan alışıldık desen.

## Neden açıldı

Kullanıcı "Acil Durum Planı eklerken dosya da eklemek istiyorum, Evrak Takibi ayrı bir yer olması saçma" dedi. İncelemede çıkan gerçek: `private_isg.file_assets`/`upload_intents`/`file_library_entries` tabloları, `isg-quarantine`/`isg-documents` bucket'ları ve `isg-file-inspect` Edge Function'ı **canlıda hiç yoktu** — repo'da candidate migration olarak duruyordu (`20260913130000_isg_file_core.sql`, `20260915010000_isg_file_library.sql`), asla uygulanmamıştı. Acil Durum Planı'nın kendi `publish_emergency_plan` fonksiyonu bir dosya parametresi (`p_asset`) taşıyordu ama canlıdaki gerçek gövde her zaman `FILE_STORAGE_UNAVAILABLE` fırlatıyordu — dosya sistemi olmadığı için bilerek kapatılmıştı.

## Ne değişti

- `20260915260000_isg_pilot_file_storage_core_and_library.sql` (canlı ledger `20260915122316`): P04'ün iki candidate migration'ı, canlı `rollout_feature_check` kısıtına göre birleştirilerek uygulandı (candidate dosyaların kendi kısıtı canlıdaki `modules`/`document_tracking`/`nonconformity`/`risk` değerlerini düşürürdü). `upload_intents.reservation_id`'nin `quota_reservations`'a FK'ı kaldırıldı — o tablo canlıda yok, `quota_ledger` kapalı kaldığı sürece hiç kullanılmıyor zaten.
- `20260915270000_isg_emergency_plan_asset_attach.sql` (canlı ledger `20260915122620`): `publish_emergency_plan`, `emergency_plan_row`, `mutate_emergency_plans` — üçü de **canlıdaki gerçek gövdeleri okunarak** (candidate dosyadan değil) `CREATE OR REPLACE` ile güncellendi. `mutate_emergency_plans`'ın izin listesine `asset_id` eklendi, dosya artık gerçekten `p_asset`'e geçiyor; ayrıca eklenen dosyanın bu hesabın kendi `file_library_entries` kaydı olduğu (başkasının temiz dosyası değil) ayrıca doğrulanıyor.
- Edge Function `isg-file-inspect` deploy edildi (v1) — kendi format denetleyicisi (`_shared/isg/file-format-inspector.ts`), üçüncü parti değil. `file_scanners` kaydı `detects_malware=false` diyor: virüs taraması iddia edilmiyor, sadece yapı/aktif içerik denetimi (PDF/DOCX/XLSX/DOC/XLS/görsel).

## Doğrulama

- `pg_get_functiondef` ile canlı gövdeler migration yazılmadan önce okundu; ilk taslak yanlış varsayıma dayandığı için hiç uygulanmadan silindi.
- Advisor (security) tekrar okundu: yeni tablolarda "RLS enabled no policy" — kasıtlı, bu repodaki her modülün deseni (kapalı tablo + kontrollü SECURITY DEFINER RPC). Yeni public SECURITY DEFINER yüzeyi yok (`isg_file_library_read_v1`/`mutate_v1`/`isg_file_inspection_v1` hepsi INVOKER sarmalayıcı).
- Disposable Postgres replay **yapılmadı** (Docker bu ortamda kapalı) — canlıya uygulama öncesi risk azaltma canlı şema introspection'ı ile yapıldı (bağımlılık kontrolü, önceki gövde okuma).

## Açık kalanlar

- İstemci tarafı: "Diğer Dosyalar" → "Dosyalarım" adı, Acil Durum Planı formuna dosya ekleme UI'ı, modül-etiketli görünüm — ayrı, bu dilimden sonra.
- Diğer modüllerin (eğitim sertifikası, risk değerlendirmesi vs.) aynı deseni kullanması — bu dilimde yok, istenirse ayrı iş.
- `quota_ledger` kapalı kaldığı sürece depolama miktarı hiçbir yerde sınırlanmıyor (yalnız dosya-başı 50 MB, `file_purposes.max_bytes`).
