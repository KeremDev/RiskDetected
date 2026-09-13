# P17 — sürümlü skor politikası, açıklanabilir katkı ve portföy

14 Eylül 2026 · dal `codex/isg-transition-foundation` · migration `20260914150000_isg_score_portfolio.sql`

P17'nin **sunucu tarafı** ilk paketi. Canlıya hiçbir şey uygulanmadı: `private_isg.rollout('score')` kapalı doğdu, istemciye GRANT verilmedi, hiçbir ağırlık onaylanmadı. Skor bu dilimde ve sonrasında **resmî uygunluk sertifikası değildir**; bunu iddia edecek bir alan yoktur.

## Ne eklendi?

10 tablo (`private_isg` toplamı **154**, hepsinde RLS açık) ve 10 fonksiyon:

| Tablo | Sorumluluk |
|---|---|
| score_policy_versions | Sürümlü politika, insan onaylı yayın kapısı, onaysız ağırlık kaynağı |
| score_processes | Altı süreç; ağırlık ve **katkı tavanı** (tavan ≤ ağırlık) |
| score_subject_states | Firma × süreç: `required` / `not_required` / `needs_review` / `voluntary` |
| score_snapshots | Politika sürümü, kaynak bağlamı ve tarihiyle birlikte donmuş sonuç |
| score_contributions | Süreç başına ağırlık, tavan, ham oran, uygulanan tavan, dışlanma gerekçesi |
| score_critical_findings | Sayının yanında duran kritik uyarı |
| score_oracle_fixtures | Elle doğrulanmış altın fixture'lar |
| score_simulations | Ağırlık değişiminin snapshot yazmadan ölçülmesi |
| portfolio_projections / portfolio_entries | Firma başına eşit ağırlıklı portföy |

Fonksiyonlar: `score_gate`, `publish_score_policy`, `declare_subject_state`, **`score_preview`**, `compute_score_snapshot`, `explain_score`, `raise_score_critical_finding`, `verify_against_oracle`, `simulate_policy_change`, `build_portfolio_projection`.

`score_preview` hiçbir şey yazmayan tek hesap fonksiyonudur; hem snapshot hem simülasyon ondan geçer, böylece simüle edilen sayı ile kaydedilen sayı ayrışamaz.

## Bağımsız oracle

Plan §11.2 açıkça "test oracle'ı üretim hesap fonksiyonunu çağırıp aynı sonucu beklemekten ibaret olamaz" diyor. Bu yüzden beklenen değerler probe'a **elle hesaplanmış sabitler** olarak yazıldı ve tablo `CHECK(hand_computed)` + `CHECK(NOT computed_by_production_function)` taşıyor.

Altın fixture (aday ağırlıklar 25/25/15/15/10/10, sağlık takibinde tavan 5):

| Süreç | Durum | Elle hesap |
|---|---|---|
| risk_assessment | required 4/8 | 0,5 × 25 = **12,5** |
| training | required 8/8 | 1 × 25 = **25** |
| health_surveillance_followup | required 10/10 | 1 × 15 = 15 → tavan **5** |
| nonconformity | doğrulanmış `not_required` | paydadan **çıkar** |
| emergency_readiness | `needs_review` | payda +10, katkı **0** |
| records_and_documents | `voluntary` | **nötr** |

Payda 25+25+15+10 = **75**, pay 12,5+25+5+0 = **42,5**, skor 100×42,5/75 = **56,67** · provisional. Üretim fonksiyonu bu üç sayıyı da birebir verdi.

İki fixture daha: verisi olmayan firma (skor **NULL**, payda 100, provisional — 100 gösterilmez) ve tamamı gönüllü firma (payda **0**, skor **NULL**).

İkinci revizyon yalnız tavanı 5'ten 15'e çıkarır: pay 52,5 → skor **70,00**; simülasyonun bulduğu en büyük fark **13,33** elle hesaplanan değerle aynı.

## Kapatılan kabul senaryoları

| ID | Karşılığı |
|---|---|
| SCO | Sürümlü politika, açıklanabilir katkı, tavan, provisional, verisiz firmada sayı yok, kritik uyarı gizlenemez |
| REV04–REV06 | Uygulanabilirlik durumunun skora etkisi; `not_required` doğrulanmış gerekçe ister; bilinmeyen paydada kalır |
| X20 | Gönüllü modül açıp kapamak ana yasal payı/paydayı değiştirmez; `required` yükümlülük sürer |

## Test kanıtı

| Koşu | Sonuç |
|---|---|
| `run_auth_restore.mjs --synthetic-session` | **997 PASS** (996 tekil; 31'i yeni P17 kontrolü), `disposable_container_cleanup: PASS` |
| `run_auth_restore.mjs --isolated-copy --p05-upgrade` | **32 PASS**, 26 migration, 154 tablo hepsinde RLS, legacy satır ve helper gövdeleri değişmedi |
| `run_suite.mjs foundation` | **408 PASS** (önce 397), 0 fail |

## Bu dilimde çıkan hatalar ve düzeltmeleri

31 kontrolün tamamı **ilk koşuda** geçti; üretim davranışını etkileyen defect çıkmadı. Tek kırmızı aşama Supabase Advisor'dı: 10 yeni tablo `denyTables`, 7 indeks `reviewedFKIndexes` listesinde değildi; iki liste güncellendi. Bu dilimde **indekssiz foreign key çıkmadı** ve hiçbir bulgu susturulmadı.

Tasarımda bilerek alınan iki karar not edilmeli:

- `required_units=0` olan bir süreç oranı 1 sayılır (yapılacak bir şey yoksa eksik de yoktur). Bu, onaylanmış bir ticari kural değil; içerik onayında yeniden değerlendirilmeli.
- Firma tamamen gönüllü kayıtlardan oluşuyorsa payda 0'dır ve skor NULL döner — "0 puan" değil. Sıfır puan göstermek, ölçülecek bir şey olmadığı hâlde başarısızlık iddia etmek olurdu.

## Yeniden çalıştırma

~~~bash
node scripts/isg/run_suite.mjs foundation
node scripts/isg/run_auth_restore.mjs --synthetic-session
node scripts/isg/run_auth_restore.mjs --isolated-copy --p05-upgrade
~~~

## Açık kalanlar

1. **Ağırlıklar onaysız.** 25/25/15/15/10/10 ve tavanlar K15 kapsamında kullanıcı/alan uzmanı onayı bekliyor. Onaylanana kadar `weight_source='unapproved_fixture'` kalmalı.
2. **Üretici yok.** P06 yükümlülükleri, P07 tamamlanmaları, P08 risk sürümleri, P09 uygunsuzlukları ve P10 modülleri `score_subject_states` yazmıyor; durumlar şu an dışarıdan besleniyor. Shadow projection bu bağ kurulunca anlamlı olur.
3. **Kritik uyarı üreticisi yok.** Hangi olayın kritik sayılacağı (süresi geçmiş risk değerlendirmesi, eksik acil durum planı vb.) içerik kararıdır.
4. **Yüzey yok.** Firma skor ekranı, açıklama/katkı listesi, portföy ekranı ve admin explainability sayfası (P16'nın ikinci dilimiyle birlikte) açık.
5. **Sağlık gözetimi süreci yalnız bir takip kalemidir.** Bu dilim hiçbir sağlık verisi tutmaz; `health_surveillance_followup` sadece "takip yapıldı mı" sayacıdır.
6. **Cutover kararı yok.** Eski skor geçmişi yoktur; yeni projection açılırken shadow olarak başlatılmalı ve P19 provasından önce bağımsız oracle tekrar çalıştırılmalı.
