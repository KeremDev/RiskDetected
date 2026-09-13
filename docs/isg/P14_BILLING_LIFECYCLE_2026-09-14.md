# P14 — kanonik abonelik lifecycle, hediye/indirim ayrımı ve settlement zinciri

14 Eylül 2026 · dal `codex/isg-transition-foundation` · migration `20260914090000_isg_billing_lifecycle.sql`

Bu dilim P14'ün **sunucu tarafı** ilk paketidir. Canlıya hiçbir şey uygulanmadı: `private_isg.rollout('billing_lifecycle')` kapalı doğdu, istemciye GRANT verilmedi, projeksiyon `access_authority='legacy'` kilidinde. Mağaza kataloğu, fiyatlar, RevenueCat yapılandırması, legacy paid helper'ları ve kazanılmış haklar değişmedi.

## Ne eklendi?

11 tablo (`private_isg` toplamı **120**, hepsinde RLS açık) ve 13 fonksiyon:

| Tablo | Sorumluluk |
|---|---|
| billing_lifecycle_evidence | Mağazanın söylediği her olay; webhook/client_sync/restore/reconciliation tek doğruluk kaynağı |
| billing_lifecycle_projection | Abonelik başına güncel durum; `access_authority='legacy'` |
| benefit_definitions | `gift_access` ve `discount_coupon`; ikisinin şekli CHECK ile birbirinden ayrı |
| benefit_state_edges | 18 izinli geçiş, veri olarak |
| benefit_instances | earned → available/deferred → reserved → awaiting_store → scheduled → consumed; belirsizlik `review`, iade `adjusted`, hediye `active` |
| store_offer_mappings | Gerçek mağaza teklifi; imza materyali saklanamaz, fiyat otoritesi mağaza |
| discount_quotes | Sunucu quote'u; avantaj yoksa `rejected` olarak yazılır |
| checkout_intents | Quote başına tek canlı checkout |
| benefit_settlements | `UNIQUE(environment,store,purchase_ref,billing_period)` — family anahtarda yok |
| settlement_adjustments | refund/revoke/chargeback/correction |
| billing_reconciliation_jobs | Günlük mutabakat sayacı |

Fonksiyonlar: `billing_gate`, `record_billing_evidence`, `project_billing_lifecycle`, `effective_billing_access`, `grant_benefit`, `advance_benefit`, `activate_gift`, `issue_discount_quote`, `open_checkout_intent`, `resolve_checkout_timeout`, `settle_benefit`, `adjust_settlement`, `reconcile_billing`.

`effective_billing_access` planın §9.2 hak otoritesini üç ayrı bölüm olarak raporlar — `billing_tier` (projeksiyon), `gift_capability` (aktif hediye), `capacity_floor` (P03 `effective_floor`, kota rollout'u kapalıysa `unavailable`) — ve `decides_access=false`, `discount_grants_access=false` döner.

## Kapatılan kabul senaryoları

| ID | Karşılığı |
|---|---|
| X32 | Hediye iki cihazdan aktive edilince replay; süre `activated_at+168h`; expiry anında kapanır; kota rezervasyonu üretilmez |
| X33 | İndirim kaydı var, ödeme yok → capability/tier/kota açılmaz (yapısal CHECK + rapor alanı) |
| X34 | Duplicate webhook tek satır; sıra dışı olay projeksiyonu geri yazmaz |
| X35 | Başka hesabın satın alması `PURCHASE_OWNED_ELSEWHERE`; sandbox üretim tier'ı olmaz |
| X36/X37 | Apple imza zorunlu + replacement yok, Google offer token + replacement mode zorunlu (CHECK) |
| X38 | `excluded_from_default_offering` zorunlu true; eski binary normal purchase'ta kampanya teklifini seçemez |
| X39 | 100/150/120 durumu: teklif ucuz değilse quote `rejected/NO_ADVANTAGE` olarak yazılır, hak harcanmaz |
| X40 | Quote başına tek canlı checkout; timeout `review`'a gider, ikinci ekonomik kullanım yok |
| X41 | Tek ödeme tek settlement; ikinci kampanya ailesi `SETTLEMENT_CONFLICT`; iade `adjusted`, dönem serbest kalmaz |

## Test kanıtı

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **894 PASS** (893 tekil ID; 36'sı yeni P14 kontrolü), `disposable_container_cleanup: PASS` |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **32 PASS**, 23 migration, 120 tablo hepsinde RLS, legacy satır ve helper gövdeleri değişmedi |
| `run_suite.mjs foundation` | **375 PASS** (önce 363), 0 fail |

Sentetik mod müşteri verisine dokunmaz; upgrade modu ağsız restore container'ının **kopyasını** kullanır. Bu koşuların hiçbiri gerçek mağaza, gerçek ödeme veya canlı DB kanıtı değildir.

## Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| `a_discount_definition_can_never_carry_a_capability` FAIL | Ham SQL ile CHECK denemesi yapılmıştı; runner psql'i `VERBOSITY=sqlstate` ile çalıştırdığı için kısıt adı hiç görünmüyor, hata yalnız `AUTH_RESTORE_SQL_FAILED` oluyor | "İmkânsız iddia" denemeleri `observe` dispatcher'ına sabit `force_*` dalları olarak taşındı; 23514 → `CHECK_VIOLATION` |
| `the_ledger_can_not_promote_itself_to_the_access_authority` sessizce geçiyordu | `UPDATE ... SET access_authority='billing'` henüz hiç projeksiyon satırı yokken çalışıyor, 0 satır etkiliyor ve CHECK tetiklenmiyordu | Kontrol ilk projeksiyon oluştuktan **sonraya** alındı, ayrıca `bool_and(access_authority='legacy')` doğrulaması eklendi |
| `a_second_device_activating_the_same_gift_changes_nothing` FAIL | Beklenen sürüm 2 yazılmıştı; grant(1) → advance(2) → activate(3) | Beklenti 3 yapıldı |
| `the_daily_reconciliation_counts_what_is_waiting` FAIL | Mutabakat ikinci checkout'un timeout anından **önce** çalıştırılıyordu, `timed_out_checkouts` 0 geliyordu | Mutabakat saati timeout sonrasına alındı |
| Guard testinde kenar sayısı 17 ≠ 18 | Regex `\),?$` son satırdaki `);` ile eşleşmiyordu | `\)[,;]?$` |
| Probe'un ilk hâli `randomUUID()` ile sahte hesap üretiyordu | `public.profiles.id` → `auth.users(id)` FK'si var | İkinci hesap sentetik fixture'dan okundu, üçüncüsü `auth.users` + `profiles` olarak açıkça oluşturuldu |
| Advisor aşaması kırmızı | 11 yeni tablo `denyTables`'da, 12 FK-kapsayan indeks `reviewedFKIndexes`'te yoktu | İki liste güncellendi; eksik gerçek FK indeksi yoktu, hiçbir bulgu susturulmadı |

Üretim davranışını etkileyen bir defect çıkmadı; yukarıdakilerin hepsi bu turda yazılan test/probe kurgusunun hatalarıydı ve düzeltildi.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
~~~

## Açık kalanlar

1. **Gerçek mağaza kanıtı yok.** Apple promotional offer imza/nonce/application-username akışı, Google offer token + `WITHOUT_PRORATION` replacement davranışı ve iki mağazada sandbox satın alma provası yapılmadı. Plan §15.3'teki "P14 spike" hâlâ açık.
2. **Adaptör yok.** RevenueCat/webhook → `record_billing_evidence` köprüsü, retry/dead-letter bağı (P01 defteri) ve worker kimliği yazılmadı. Şu an kanıtı hiçbir üretici yazmıyor.
3. **Ticari sayılar onaysız.** 7×24 saat hediye ve %20 indirim `unapproved_fixture`; plan katalogu, eligibility cutoff'u ve fiyat kohort kararları (§19, K08/K10) insan onayı bekliyor.
4. **Cutover yok.** `access_authority='legacy'` kilidi ayrı bir migration ile açılmalı; P03 gölge kota defteri ile birlikte tek karar olarak ele alınmalı.
5. **Yüzey yok.** Paywall/teklif ekranı, admin simulate/publish ve izleme (P16) bağlanmadı; P15 referral/winback bu deftere yazacak ama kampanya karar tabloları henüz yok.
6. **Eski binary katalog testi** (X38) ve fiyat fixture matrisi (X39) gerçek mağaza kayıtlarıyla tekrarlanmalı.
