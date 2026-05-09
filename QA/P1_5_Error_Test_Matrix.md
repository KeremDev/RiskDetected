# P1.5 Error Handling, Messages and Supportability Test Matrix

Bu matris RiskDetected hata yönetimi geçişi için manuel QA kaydıdır. Amaç, teknik hataları kullanıcıya ham backend metni olarak göstermeden; anlaşılır Türkçe mesaj, doğru aksiyon ve izlenebilir `support_id` ile yönetmektir.

## Test Kuralları

- Testleri mümkünse demo/free/pro test hesaplarıyla yap.
- Production RLS/policy ayarlarını kırarak test etme; zorunluysa değişikliği hemen geri al ve not düş.
- Kullanıcıya görünen alert içinde ham HTTP body, enum, RLS veya stack trace görünmemeli.
- Her ana hata akışında kullanıcıya gösterilen `support_id` app loglarında, Edge Function response/loglarında veya ilgili DB kaydında izlenebilmelidir.
- Retry gereken akışlarda aynı kullanıcı aksiyonu duplicate analysis/report oluşturmamalıdır.

## Beklenen Mesaj Yapısı

Her kullanıcı mesajı şu yapıda olmalı:

1. **Ne oldu:** Kısa ürün dili.
2. **Ne yapmalı:** Tek net aksiyon.
3. **Destek kodu:** `RD-XXXXXXXX` formatında kısa kod.

Örnek:

```text
AI servisi şu anda yoğun.
Aynı analiz otomatik tekrar deneniyor. Devam etmezse biraz sonra tekrar dene.
Destek kodu: RD-1A2B3C4D
```

## Hata Kategorileri

| Kategori | Kaynak | Retry | Kullanıcı aksiyonu | Not |
| --- | --- | --- | --- | --- |
| `quotaExceeded` | Edge Function / plan limiti | Hayır | Pro sayfasına yönlendir | Free toplam günlük limit: 2 |
| `authRequired` | Supabase Auth/session | Hayır | Tekrar giriş yap | Expired token ve nil session kapsanmalı |
| `networkUnavailable` | iOS / Supabase / Storage | Evet | Bağlantıyı kontrol et, tekrar dene | Offline sim testiyle doğrula |
| `storageDenied` | Storage RLS / bucket policy | Hayır | Destek koduyla bildir | Raw RLS metni gösterilmemeli |
| `aiRateLimited` | Gemini 429 | Evet, 1 kez | Bekle / otomatik retry | Duplicate analysis yok |
| `aiUnavailable` | Gemini 500/502/503/504 | Evet, 1 kez | Otomatik retry, sonra tekrar dene | Status card görünmeli |
| `aiInvalidResponse` | JSON parse/schema | Hayır veya fallback | Tekrar dene | Edge log raw response tutmalı |
| `pdfRenderFailed` | Local PDF render | Hayır | Tekrar oluştur | Lokal dosya oluşmadıysa açık söyle |
| `reportArchiveFailed` | PDF Storage/upload/reports insert | Hayır | PDF oluşturulduysa paylaş, arşiv kaydı olmadığını bildir | Storage ve DB ayrımı önemli |
| `validationFailed` | Foto/metin/input | Hayır | Eksik alanı tamamla | Kullanıcıyı doğru kontrol noktasına götür |
| `unknown` | Beklenmeyen | Duruma bağlı | Destek koduyla bildir | Ham teknik detay gizli kalmalı |

## Manuel Test Matrisi

| ID | Senaryo | Nasıl Tetiklenir | Beklenen UI | Beklenen İz | Durum |
| --- | --- | --- | --- | --- | --- |
| E01 | Free günlük limit dolu | Free demo ile aynı gün 3. analizi başlat | Foto/metin girişi ve başlatma akışı Pro yönlendirmesi verir; teknik hata göstermez | Paywall quota notunda support id görünür; Edge 429 varsa aynı `quotaExceeded` support id taşınır | Geçti · 2026-05-09 · `RD-8478660C` |
| E02 | Foto seçmeden analiz | Foto modunda foto yokken `Taramayı Başlat` | Galeri/kamera seçim akışı açılır veya limit doluysa upload alanı bloklanır | Lokal validation, backend çağrısı yok | Geçti · 2026-05-09 · kaynak dialog açıldı |
| E03 | Metin çok kısa/boş | Metin modunda boş/kısa metinle başlat | “Eksik bilgi” mesajı gösterilir, ham hata yok | Backend çağrısı yok | Geçti · 2026-05-09 · `RD-73459579` |
| E04 | Oturum yok/expired | App session temizlenmişken analiz başlat | “Tekrar giriş yap” tipi mesaj | Supabase auth error normalize edilir | Mevcut kod desteği hazır · manuel doğrulama bekliyor |
| E05 | Offline ağ | Simulator ağını kes veya Mac bağlantısını kapat | “Bağlantıyı kontrol et” mesajı, UI stuck kalmaz | `networkUnavailable`, support id app logda | Mevcut kod desteği hazır · manuel doğrulama bekliyor |
| E06 | Gemini 429 | Test ortamında API quota/rate limit veya test-only simulate flag | AnalyzingView retry kartı gösterir, 1 kez retry eder, sonra uygun mesaj | `ai_usage_logs.error_code=ai_rate_limited`, aynı `support_id` | Geçti · 2026-05-08 · `RD-58771F8E` |
| E07 | Gemini 503 | Test-only simulate veya gerçek provider unavailable | “AI servisi yoğun” retry kartı, duplicate row yok | `ai_usage_logs.http_status=503`, retry outcome loglanır | Geçti · 2026-05-08 · `RD-29BC4E8D` |
| E08 | Gemini invalid JSON | Test-only invalid JSON response | Kullanıcıya “yanıt işlenemedi” mesajı, stuck yok | Edge logda request/support id ve normalized code | Geçti · 2026-05-08 · `RD-630E27BD` |
| E09 | Analysis Storage upload/RLS | MVP analiz akışı inline görsel gönderir; Storage reddi foto/report veri yollarında simüle edilir | Ham “row-level security” görünmez | `storageDenied` veya `reportArchiveFailed` ayrımı doğru | Geçti · 2026-05-09 · `RD-5F2DA9A1` |
| E10 | Photo Storage download failure | Eski analizde photo path bozuk veya `SIMULATE_DATA_ERROR=photo_download` | Placeholder görünür, ekran açılır | App log support id ile photo load failure | Geçti · 2026-05-09 · `RD-7D048E95` |
| E11 | Standard PDF render failure | Test-only invalid page/image input | PDF oluşturulmadı mesajı | `pdfRenderFailed`, local temp cleanup | Geçti · 2026-05-09 · `RD-78F66A41` |
| E12 | PDF Storage upload failure | Reports bucket/policy test hatası | “PDF oluştu ama arşive kaydedilemedi” ayrımı | `reportArchiveFailed`, aynı support id Storage logda | Geçti · 2026-05-09 · `RD-2C149AAA` |
| E13 | Reports metadata insert failure | Test-only invalid report metadata veya DB constraint | PDF oluştuysa kullanıcıya açık ayrım | `reports` insert error normalized, ham column/enum metni yok | Geçti · 2026-05-09 · `RD-2AB8255A` |
| E14 | Stored report download failure | Reports row var, Storage object yok | “Rapor dosyası bulunamadı/indirilemedi” mesajı | support id app log + reports row id | Geçti · 2026-05-09 · `RD-7CEE5785` |
| E15 | Stored report delete failure | Storage object silme reddi | Delete başarısız, liste bozulmaz | `deleteReport` support id loglanır | Geçti · 2026-05-09 · `RD-AC8ECC68` |
| E16 | Analysis delete failure | Analyses tab delete RLS/network fail veya `SIMULATE_DATA_ERROR=analysis_delete_storage|analysis_delete_metadata` | Silinemedi mesajı, liste yanlış optimistic silinmez | Normalized delete error + support id app logda | Geçti · 2026-05-09 · `RD-46D1F4EF` |
| E17 | Data export failure | Profile > Verilerim export sırasında network/DB fail veya `SIMULATE_DATA_ERROR=data_export` | Export oluşturulamadı, tekrar dene mesajı | AppErrorMessage + support id | Geçti · 2026-05-09 · `RD-DC0F572F` |
| E18 | Account deletion request failure | Profile request insert/network fail veya `SIMULATE_DATA_ERROR=account_deletion_request` | Talep alınamadı, tekrar dene | Support id loglanır | Geçti · 2026-05-09 · `RD-03238C39` |

## Deterministic Test İyileştirmesi

Gerçek Gemini 429/503 veya Storage RLS hatasını beklemek test hızını düşürür. `analyze` Edge Function içinde AI tarafı için test-only simülasyon bayrakları eklendi.

- `RISKDETECTED_ENABLE_TEST_SIMULATION=true`
- `SIMULATE_AI_ERROR_CODE=429|503|invalid_json`
- `SIMULATE_AI_ERROR_ONCE=true`

Desteklenen kodlar: `429`, `500`, `502`, `503`, `504`, `invalid_json`.

Güvenlik/operasyon kuralı:

- `RISKDETECTED_ENABLE_TEST_SIMULATION=true` olmadan simülasyon çalışmaz.
- Bayraklar production ortamında kapalı kalmalı.
- `SIMULATE_AI_ERROR_ONCE` varsayılan olarak `true` kabul edilir; ilk AI denemesi hata üretir, retry/fallback akışı gerçek Gemini çağrısıyla devam eder.
Report/PDF arşiv akışı için iOS DEBUG build içinde ek test bayrakları:

- `RISKDETECTED_ENABLE_REPORT_TEST_SIMULATION=true`
- `SIMULATE_REPORT_ERROR=pdf_render|storage_upload|metadata_insert|download|delete_storage|delete_metadata`

Bu bayraklar sadece DEBUG build içinde okunur. Production/TestFlight release build davranışını etkilemez.

Photo/history/profile veri işlemleri için iOS DEBUG build içinde ek test bayrakları:

- `RISKDETECTED_ENABLE_DATA_TEST_SIMULATION=true`
- `SIMULATE_DATA_ERROR=photo_download|analysis_delete_storage|analysis_delete_metadata|data_export|bulk_report_delete|bulk_analysis_delete|account_deletion_request|quota_exceeded`

Bu bayraklar sadece DEBUG build içinde okunur. Production/TestFlight release build davranışını etkilemez.

## Kapanış Kriterleri

- Tüm P1.5 satırları “Geçti” veya bilinen ürün kararıyla “Ertelendi” olmalı.
- Kullanıcı alertlerinde ham `HTTP 400/500`, `RLS`, `schema cache`, `enum`, `column` ve provider JSON gövdesi görünmemeli.
- Her support gerektiren hatada kullanıcı ekranındaki kod, log/DB tarafında bulunabilmeli.
- Retry edilen AI hatalarında duplicate analysis/report oluşmamalı.
- PDF oluşturma, Storage upload ve reports metadata insert hataları birbirinden ayrı mesajlanmalı.
