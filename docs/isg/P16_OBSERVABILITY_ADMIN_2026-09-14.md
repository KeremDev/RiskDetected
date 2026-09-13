# P16 — teknik izleme zarfı, teşhis zinciri ve scope'lu admin operasyonu

14 Eylül 2026 · dal `codex/isg-transition-foundation` · migration `20260914130000_isg_observability_admin.sql`

P16'nın **sunucu tarafı** ilk paketi. Canlıya hiçbir şey uygulanmadı: `private_isg.rollout('observability')` kapalı doğdu, istemciye GRANT verilmedi ve **ayrı repodaki operasyon paneli bu turda hiç değiştirilmedi**. Buradaki şey, panelin ve istemci telemetrisinin uyması gereken sunucu sözleşmesidir.

## Ne eklendi?

13 tablo (`private_isg` toplamı **144**, hepsinde RLS açık) ve 13 fonksiyon:

| Tablo | Sorumluluk |
|---|---|
| funnel_stages | `screen_open` → `ui_render`, on aşama sıra numarasıyla, veri olarak |
| telemetry_event_kinds | Aşama başına typed metadata anahtar allowlist'i |
| support_chains | Support ID; istemcide, analiz satırından önce açılır |
| technical_events | Zarfın kendisi: request/operation/trace, stage, outcome, reason, retry, güvenli latency |
| funnel_progress | Aşama başına tek ilerleme satırı |
| telemetry_queue_reports | Sınırlı istemci kuyruğu; düşen olay raporlanır, yükseltilmez |
| attribution_records | İzin yoksa atıf `unknown`; tanımlayıcı ve üçüncü taraf SDK imkânsız |
| admin_scopes / admin_sessions | Scope kataloğu ve sunucu tarafı assurance level |
| admin_audit_entries | Publish'ten **önce** yazılan, ham yük taşımayan denetim kaydı |
| admin_actions | simulate → publish; audit'siz publish'in satır şekli yok |
| admin_exports | Maskeli, allowlist'li projeksiyon |
| admin_operation_state | Tek satırlık admin yazma duraklatması; audit ve settlement devam eder |

Fonksiyonlar: `observability_gate`, `telemetry_redaction_violation`, `start_support_chain`, `record_technical_event`, `close_support_chain`, `record_queue_report`, `record_attribution`, `open_admin_session`, `admin_authorize`, `simulate_admin_action`, `publish_admin_action`, `request_admin_export`, `set_admin_write_pause`.

## Kapatılan kabul senaryoları

| ID | Karşılığı |
|---|---|
| X53 | İzin olmadan atıf `unknown`; tanımlayıcı saklanamaz, üçüncü taraf SDK çağrısı iddia edilemez |
| X54 | Encode/upload/submit öncesi hata tam zincir üretir; telemetri taşıyıcısı kapalı ve kuyruk dolu olsa bile domain işlemi etkilenmez |
| X55 | MFA'sız ve scope'suz admin reddi; simülasyonsuz ya da audit'siz publish imkânsız; export maskeli ve allowlist'li |
| E14 | Süreç: istemci pre-submit hatası → support ID → scope'lu teşhis → dry-run → duraklatma → kritik audit |

## Test kanıtı

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **966 PASS** (965 tekil; 34'ü yeni P16 kontrolü), `disposable_container_cleanup: PASS` |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **32 PASS**, 25 migration, 144 tablo hepsinde RLS, legacy satır ve helper gövdeleri değişmedi |
| `run_suite.mjs foundation` | **397 PASS** (önce 386), 0 fail |

Duraklatma testi gerçek bir çapraz faz kontrolüdür: admin yazmaları duraklatılmışken P14'ün `record_billing_evidence` çağrısı ve yeni bir audit kaydı hâlâ başarıyla yazılır.

## Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| `the_envelope_has_no_column_for_a_secret_or_a_body` iki sorgudan biri anlamsızdı | Regex'in içine kaçak bir `;` girmişti; o sorgu zaten hiçbir şeyle eşleşemezdi | Tek, doğru regex'e indirildi |
| `a_simulation_reports_without_changing_a_domain_row` kendini kendisiyle karşılaştırıyordu | Aynı sorgu iki kez çağrılıp eşitliği kontrol ediliyordu | Simülasyon öncesi sayım değişkene alındı, sonrasıyla karşılaştırılıyor |
| `a_publish_without_a_simulation_is_refused` yayın kapısını değil kaydın yokluğunu ölçüyordu | Rastgele bir `action_id` gönderiliyordu; `SIMULATION_REQUIRED` zaten CHECK ile yapısal olarak erişilemez | Kontrol, başka bir session'ın aynı aksiyonu yayımlayamamasını ölçüyor; simülasyon zorunluluğu guard testinde CHECK olarak doğrulanıyor |
| Advisor aşaması kırmızı | 13 yeni tablo `denyTables`'da, 12 indeks `reviewedFKIndexes`'te yoktu | İki liste güncellendi. Bu dilimde **indekssiz foreign key çıkmadı**; hiçbir bulgu susturulmadı |

Üretim davranışını etkileyen defect çıkmadı; üçü de test kurgusunun kendi hatalarıydı.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
~~~

## Açık kalanlar

1. **İstemci üreticisi yok.** iOS/Android telemetri kuyruğu, taşıyıcı, support ID üretimi ve ATT izin ekranı yazılmadı. Şu an olayları yalnız test yazıyor.
2. **Panel değişmedi.** Ayrı repodaki operasyon paneli (`RiskDetected-OperasyonMerkezi`) kendi AGENTS.md sınırları ve kullanıcı değişiklikleri korunarak ayrı bir görevde genişletilecek. Bu turda ana uygulama migration'ı ile panel deployment'ı birbirine bağlanmadı (K22).
3. **Playwright/API kabulleri açık.** X55'in panel tarafı (yanlış scope, MFA yok, export PII) uçtan uca denenmedi.
4. **Saklama ve silme kararı yok.** Teknik olayların retention süresi ve hesap silmede davranışı K16 kapsamında; bu dilim hiçbir şey silmiyor.
5. **Log/ClickHouse adaptörü.** Supabase Management API `logs.all` geçişi (23 Eylül 2026 kaldırma tarihi) için dış araç taraması ve gerekiyorsa adaptör testi açık.
6. **Domain üreticileri bağlanmadı.** P05–P15 mutation'ları henüz teknik olay yazmıyor; bu bağ P19 provasından önce kurulmalı.
