# P15 — davet, geri kazanım, anti-abuse ve bütçe çekirdeği

14 Eylül 2026 · dal `codex/isg-transition-foundation` · migration `20260914110000_isg_campaign_core.sql`

P15'in **sunucu tarafı** ilk paketi. Canlıya hiçbir şey uygulanmadı: `private_isg.rollout('campaigns')` kapalı doğdu, istemciye GRANT verilmedi, tek bir pazarlama mesajı gönderilmedi ve hiçbir mağaza teklifi oluşturulmadı. Ödüller doğrudan yazılmaz; hepsi P14'ün `grant_benefit` defterinden geçer ve o defter `access_authority='legacy'` kilidindedir.

## Ne eklendi?

11 tablo (`private_isg` toplamı **131**, hepsinde RLS açık) ve 14 fonksiyon:

| Tablo | Sorumluluk |
|---|---|
| campaign_definitions | `referral` / `winback` aileleri; aile bazında ayrı duraklatma |
| campaign_versions | Sürümlü kural + insan onaylı yayın kapısı; tüm sayılar onaysız fixture |
| referral_codes | Kanonik hesap başına tek kod |
| referral_claims | claimed → qualified → rewarded / rejected; ret kodu her zaman yazılır |
| qualification_events | Yalnız yedi tamamlanmış sunucu mutation'ı, `proof_source='server_mutation'` |
| campaign_budgets / budget_reservations | Dönem başına kapasite; reserve → commit/release |
| winback_episodes | Aile başına ömür boyu tek episode; 72 saat bekleme, 14 gün pencere |
| winback_contacts | En fazla iki temas, teslim iddiası taşımaz |
| suppression_records | Her ret, karar aşamasıyla birlikte; `CHECK(NOT ttl_reset)` |
| eligibility_checks | Her uygunluk kararının lifecycle anlık görüntüsüyle kaydı |

Fonksiyonlar: `campaign_gate`, `publish_campaign_version`, `pause_campaign_version`, `issue_referral_code`, `claim_referral`, `record_qualification_event`, `evaluate_referral_qualification`, `reserve_campaign_budget`, `settle_campaign_budget`, `award_referral_reward`, `winback_eligibility`, `open_winback_episode`, `record_winback_contact`, `resolve_winback_episode`.

`campaign_versions.inviter_reward_code` / `invitee_reward_code` / `winback_reward_code` gerçek FK ile P14'ün `benefit_definitions(code)` satırlarına bağlıdır: bir kampanya, var olmayan bir ödülü işaret edemez.

## Kapatılan kabul senaryoları

| ID | Karşılığı |
|---|---|
| X42 | Free/paid-monthly/annual davetçi dalları; self/cycle/repeat guard'ları; annual → `UNSUPPORTED_BRANCH`, otomatik plan çevirimi yok |
| X43 | İki farklı günde gerçek Free işlemi qualify eder; heartbeat/ekran/not/başarısız analiz satır şekli bile yok; pazarlama rızası koşul değil |
| X44 | cancelled-active, expired, grace, hold, pause, refund/revoke, annual, trial-only, diğer mağazada aktif — her biri kendi ret koduyla |
| X45 | 72 saat/14 gün sınırları; gönderim sırasında resubscribe → suppression, `accept_until` değişmez; aktif hediye ayrı ret |
| X46 | Duraklatma yeni üretimi durdurur; kazanılmış benefit ve settlement korunur; bütçe dolunca `BUDGET_EXHAUSTED` |

## Test kanıtı

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **932 PASS** (931 tekil; 38'i yeni P15 kontrolü), `disposable_container_cleanup: PASS` |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **32 PASS**, 24 migration, 131 tablo hepsinde RLS, legacy satır ve helper gövdeleri değişmedi |
| `run_suite.mjs foundation` | **386 PASS** (önce 375), 0 fail |

P15 kontrolleri P14'ün defterini gerçekten kullanır: ödül `grant_benefit` ile üretilir, uygunluk `billing_lifecycle_projection`'dan okunur, rıza P12'nin `notification_consents` tablosundan doğrulanır. Bu yüzden probe koşarken `campaigns` ve `billing_lifecycle` rollout'larını birlikte açar, sonunda ikisini de kapatır.

## Bu dilimde çıkan hatalar ve düzeltmeleri

| Belirti | Kök neden | Düzeltme |
|---|---|---|
| `an_account_that_never_paid_or_can_not_be_read_is_no_candidate` FAIL | Probe davetliyi `SELECT id FROM public.profiles WHERE id<>owner ORDER BY id LIMIT 1` ile seçiyordu; P14 probe'u araya üçüncü bir hesap eklediği için bu sorgu **koşudan koşuya farklı** hesabı döndürüyordu | Probe kendi hesaplarını açtı; "okunamayan lifecycle" hesabı `billing_lifecycle_projection`'dan `lifecycle_state='unknown'` ile açıkça sorgulanıyor |
| Dört **gerçek** indekssiz foreign key (`referral_claims.invitee_owner_id`, `winback_episodes.owner_id`, `suppression_records.campaign_id`, `eligibility_checks.campaign_id`) | Composite indekslerin **baştaki** sütunu başka; bu bir FK'yi kapsamaz | Dört ayrı indeks migration'a eklendi. Bunlar advisor listesine eklenerek susturulmadı |
| `an_unpublished_campaign_qualifies_nobody` hiçbir şey test etmiyordu | Rastgele bir `claim_id` ile çağrılıyordu, `ACCESS_DENIED` yayın kapısını değil kaydın yokluğunu gösteriyordu | Aynı kampanyanın ikinci bir **draft** revizyonu açıldı; gerçek claim onunla denenip `CAMPAIGN_UNAVAILABLE` bekleniyor |
| `the_same_operation_is_never_counted_twice` aslında yeni bir `operation_id` gönderiyordu | Yardımcı fonksiyon her çağrıda `randomUUID()` üretiyordu | Operation ID dışarı alındı, aynı değer ikinci kez gönderiliyor ve `replayed=true` bekleniyor |
| `a_paused_campaign_rewards_nobody_new` `NOT_QUALIFIED` alıyordu | Yeni claim hiç qualify edilmemişti; duraklatma kapısına hiç ulaşılmıyordu | Üçüncü hesap claim → iki gün olay → evaluate → **sonra** pause; artık gerçekten `CAMPAIGN_PAUSED` |
| Uygun olmayan episode'un suppression kaydı kayboluyordu | `open_winback_episode` kaydı yazıp ardından `RAISE` ediyordu; exception subtransaction'ı geri alıyor | Fonksiyon `opened:false` + `reason_code` **döndürüyor**; kayıt kalıyor (P14'teki `NO_ADVANTAGE` ile aynı kalıp) |
| Eksik rıza episode'u kalıcı olarak kapatıyordu | Her ret aynı şekilde ele alınmıştı | `consent_missing` artık episode'u kapatmıyor; rıza sonradan gelirse aynı episode devam eder. Diğer retler kapatır, hiçbiri saati sıfırlamaz |

Üretim davranışını etkileyen bir defect çıkmadı; biri (eksik rızanın episode'u kapatması) gerçek bir tasarım düzeltmesiydi ve migration'a işlendi.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
~~~

## Açık kalanlar

1. **Ticari kararlar yok.** İki gün/30 gün qualification, 72 saat/14 gün/iki temas, Plus7 ve %20 hep aday; K06 (yıllık davetçi bankalama), K07 (qualification ve tekrar), K08 (hediye çakışma politikası), K09 (winback takvimi), K10 (teklif fiyatları) insan onayı bekliyor.
2. **Üretici yok.** Qualification olaylarını P05/P06/P07 mutation'larından besleyen köprü, P01 dağıtım defteri tüketicisi ve kampanya zamanlayıcısı yazılmadı. Şu an olayları yalnız test çağırıyor.
3. **Gönderim yok.** Temas kaydı var, gerçek push/e-posta işçisi yok; P12'nin gerçek sağlayıcı dilimi ve pazarlama şablonları açık.
4. **Mağaza kapısı açık.** İndirim ödülünün gerçekten satın alınabilmesi P14'ün Apple/Google teklif spike'ına bağlı.
5. **Operasyon yüzeyi yok.** Bütçe/pause/fraud incelemesi için admin ekranı, izleme ve uyarılar P16'da.
6. **Native yüzey yok.** Davet linki/kodu ekranı, deep link ve winback teklif ekranı P18'de.
