# observability-admin — teknik olay zarfı, teşhis zinciri ve scope'lu admin

P16'nın sunucu tarafı ilk dilimi. `private_isg.rollout('observability')` kapalıdır, istemciye GRANT yoktur. Mevcut operasyon paneli (ayrı repo) bu turda değiştirilmemiştir; burada yalnız panelin uyması gereken sunucu sözleşmesi vardır.

## Ne garanti edilir?

- **Yasak yük taşınamaz.** Zarfta e-posta, parola, OTP, access/refresh token, mağaza imzası, signed URL, not gövdesi, çalışan belgesi veya fotoğraf için **sütun yoktur**. `metadata` her aşamanın kendi anahtar allowlist'i ile sınırlıdır (`METADATA_NOT_ALLOWED`) ve değerler adres, `Bearer`, JWT, imzalı URL ve 200 karakterden uzun metin için taranır (`REDACTION_VIOLATION`). `CHECK(NOT carries_user_content)`.
- **Zincir sunucudan önce başlar.** `start_support_chain` istemci tarafından, herhangi bir analiz satırı oluşmadan açılır; encode/upload/submit öncesi biten hata bile tam teşhis edilebilir. `analysis_row_created` yalnız sunucu işi kuyruğa aldığında true olur.
- **Aşama geri gitmez.** On aşama (`screen_open` → `ui_render`) satır olarak tanımlıdır; daha küçük numaralı aşama `STAGE_OUT_OF_ORDER` verir. Kapanmış zincir yeni olay almaz (`CHAIN_CLOSED`).
- **Görülmeyen sonuç başarı değildir.** `CHECK(outcome<>'rendered' OR last_stage='ui_render')`; sonuç dönmüş ama ekrana çizilmemişse `rendered` yazılamaz. `failed_before_submit` ile analiz satırı bir arada olamaz.
- **Telemetri asla engellemez.** Dolu veya ölü istemci kuyruğu `telemetry_queue_reports` ile raporlanır; `CHECK(NOT blocks_domain)` ve `domain_operation_affected=false`. Migration hiçbir domain tablosunu okumaz/yazmaz.
- **İzin yoksa atıf yoktur.** `CHECK(tracking_authorized OR attribution_source='unknown')`; yetkisiz durumda kaynak tahmin edilmez. `CHECK(NOT identifier_stored)`, `CHECK(NOT third_party_sdk_called)`.
- **Admin kararını sunucu verir.** Canlı ve süresi dolmamış session, gerçek assurance level (`MFA_REQUIRED`), o session'ın gerçekten taşıdığı scope (`SCOPE_DENIED`). Her scope `requires_aal2` zorunludur ve istemcinin iddia ettiği scope'a güvenilmez.
- **Publish fail-closed'dur.** Önce simulate, sonra publish. Audit kaydı publish'ten **önce** yazılır ve aksiyon ona referans verir: `CHECK(state<>'published' OR (simulated_at IS NOT NULL AND published_at IS NOT NULL AND audit_id IS NOT NULL))`. Audit ham yük taşıyamaz (`CHECK(NOT carries_raw_payload)`), yalnız SHA-256 özeti.
- **Export maskeli ve allowlist'lidir.** Tanımlı olmayan bir sütun adı `EXPORT_DENIED`; maskelenmesi gereken sütunlar kayda geçer; `CHECK(NOT raw_pii_included)`.
- **Admin yazma duraklatması denetimi durdurmaz.** `ADMIN_WRITES_PAUSED` yalnız publish'i keser; audit kaydı ve P14 settlement zinciri çalışmaya devam eder (`CHECK(audit_continues)`, `CHECK(settlement_continues)`).

## Ne garanti edilmez?

Gerçek istemci telemetri üreticisi (iOS/Android), gönderim taşıyıcısı, panel sayfaları, Playwright akışları, ATT izin ekranı, log/ClickHouse adaptörü ve saklama/retention politikası bu dilimde yoktur. Operasyon paneli ayrı repo sözleşmesiyle ve ayrı görevle genişletilir.
