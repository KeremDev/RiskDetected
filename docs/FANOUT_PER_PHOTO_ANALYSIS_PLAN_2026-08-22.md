# Fotoğraf başına ayrı çağrı (fan-out) — değerlendirme ve ölçüm planı

**Tarih:** 2026-08-22
**Durum:** öneri, uygulanmadı
**İlgili:** `ANALYSIS_QUALITY_RECOVERY_PLAN_2026-08-21.md`, `ANALYSIS_QUALITY_ADDENDUM_2026-08-21.md`

---

## 1. Sorun

Çok fotoğraflı analizde model triyaj yapıyor. Ölçüm, son 30 gün, tamamlanan analizler:

| Fotoğraf | Analiz | Fotoğraf başına bulgu |
|---|---|---|
| 1 | 36 | **2.92** |
| 2 | 10 | 1.70 |
| 3 | 6 | **1.39** |

12 katmanlı denetimde de aynı desen:

| Katman statüsü | 1 foto | 2 foto | 3 foto |
|---|---|---|---|
| `actionable` | 28.7% | 14.1% | **11.7%** |
| `not_visible` | 30.6% | 39.1% | **43.9%** |

Aynı tip sahneler. Fotoğraf sayısı arttıkça model katmanların yarısına yakınını "görünmüyor" diye kapatıyor ve aksiyon alınabilir katman sayısı yarıdan aza düşüyor.

Hedef minimumu modelin kendi `actionable` sayısından türediği için ([`index.ts` `effectiveCoverageTargetMinForLayers`](../supabase/functions/analyze/index.ts)) ince bir ilk paso kendi çıtasını düşürüyor ve "kapsama tamam" diyor.

### 1.1 Varyans

Bayt bayt aynı 3 fotoğrafla 7 koşu (`photo_input_audit.decoded_byte_count` ile doğrulandı):

| Saat | depth | foto başına | toplam | FK | bant |
|---|---|---|---|---|---|
| 22:23 | on | 1/2/1 | 4 | 921 | critical |
| 22:48 | on | 0/1/0 | 6 | 145.5 | low |
| 23:35 | off | 1/2/2 | 5 | 757 | high |
| 00:01 | shadow | 1/1/0 | 2 | 366 | high |
| 00:14 | off | 1/2/2 | 5 | 1000 | high |
| 01:51 | off | 1/3/0 | 4 | 313 | medium |
| 02:04 | off | 1/2/1 | 4 | 493 | high |

`off` koşularının bulgularını birleştirdiğimde bu üç fotoğrafta **~10 ayrı tehlike** var. Her koşu 4-5 tanesini buluyor — recall ≈ **%45**.

En kötüsü, değerli olanların isabet oranı en düşük:

| Bulgu | FK | Kaç `off` koşusunda (4 üzerinden) |
|---|---|---|
| Tavan vinci kancalarında güvenlik mandalı eksikliği | 360 | **1** |
| İş makinesi operatörü KKD eksikliği | 270 | **1** |
| İş makinesi güvenlik mesafesi / yaya ayrımı | 240 | **1** |
| Vinç kancalarının korumasız bırakılması | 135 | **1** |
| Tank üstü açık menfez/baca ağızları | 120 | **1** |
| Korkuluk boşluğu | 240 | 3 |
| Kazı / şev stabilitesi | 100 | 3 |
| Malzeme istifleme | 30–90 | 4 |

Bariz olan her seferinde çıkıyor. Uzman bulgusu dörtte bir çıkıyor.

---

## 2. Süre ve maliyet

### 2.1 Ölçülen token maliyeti

`_input_audit` kayıtlarından, `job_mode = "analysis"`:

| Fotoğraf | promptTokenCount |
|---|---|
| 1 | 2942, 3683, 3713, 3732 |
| 2 | 4075, 4076, 4149 |

Çıkarım: **taban prompt ≈ 3.300 token**, **her fotoğraf ≈ +400 token**.

Çıktı tarafı, tek fotoğraf: `candidatesTokenCount` 2189–6188, `thoughtsTokenCount` 2330–5978.

### 2.2 Bugün (3 fotoğraf)

| | girdi | çıktı | düşünme |
|---|---|---|---|
| Paso 1 | ~4.500 | ~2.900 | ~3.000 |
| Repair | ~6.400 | ~2.000 | 739–3.034 |
| **Toplam** | **~10.900** | **~4.900** | **~4.400** |

2 çağrı. Ölçülen `total_analysis_duration_ms`: **51.047 / 60.156 / 65.637 ms**.

### 2.3 Fan-out (3 fotoğraf, repair kaldırılmış)

| | girdi | çıktı | düşünme |
|---|---|---|---|
| 3 × tek foto | ~11.100 | ~9.000 | ~12.000 |

3 çağrı, paralel.

### 2.4 Karşılaştırma

| | Bugün | Fan-out | Oran |
|---|---|---|---|
| Çağrı | 2 | 3 | 1.5× |
| Girdi token | ~10.900 | ~11.100 | **≈ 1.0×** |
| Çıktı + düşünme | ~9.300 | ~21.000 | **2.3×** |
| Duvar saati | 51–66 sn | **~30–40 sn** | **0.6×** |

**Girdi maliyeti neredeyse aynı.** Sebep: repair zaten fotoğrafları ve önceki bulguları tekrar gönderiyor, yani ikinci çağrının girdi maliyetini bugün de ödüyoruz.

**Çıktı 2.3× artıyor.** Çıktı tokenı girdiden belirgin şekilde pahalı olduğu için toplam maliyet kabaca **2×** civarında çıkar. Kesin rakam için kendi tarife kartınızı bu token sayılarına uygulayın — buradaki token sayıları ölçüm, dolar tahmini değil.

**Süre kısalıyor.** Paralel çağrıların duvar saati en yavaş tek fotoğraf çağrısı kadar. Bugün seri çalışan paso 1 + repair'den hızlı.

> ⚠️ Daha önce "fan-out bugünkü maliyete yakın" demiştim. Girdi için doğru, çıktı için değil. Ölçüm sonrası düzeltiyorum: toplam ≈ 2×.

---

## 3. İstediğimiz performansı verir mi?

Dürüst cevap: **kısmen.**

### Vereceği

Fotoğraf başına bulgu oranı tek fotoğraf seviyesine döner: **1.39 → ~2.9**. 3 fotoğraflı analizde 4-5 yerine **~8-9 bulgu** beklenir. Katman triyajı ortadan kalkar çünkü her çağrının tek bir sahnesi olur.

### Vermeyeceği

**Varyansı çözmez.** Tek fotoğraflı koşular da dalgalanıyor — aynı dönemde 2, 4, 7, 11 bulgu. Fan-out ortalamayı yükseltir, dağılımı daraltmaz.

Yani "vinç kancası mandalı" gibi dörtte bir çıkan bulgular fan-out sonrası belki üçte bir çıkar. Kaybolmaya devam eder.

Varyansı asıl çözen şey **aynı fotoğrafı birden çok kez örnekleyip birleştirmek.** Fan-out ile birleştirilirse 3 fotoğraf × 2 örnek = 6 çağrı, ≈ 4× maliyet. Muhtemelen fazla.

### Gerçekçi hedef

| Senaryo | Çağrı | Maliyet | Beklenen bulgu (3 foto) |
|---|---|---|---|
| Bugün | 2 | 1× | 4–5 |
| Fan-out | 3 | ~2× | 8–9 |
| Fan-out + 2 örnek | 6 | ~4× | 11–13 |

Karar bu tablodadır. Ölçüm bu tabloyu doğrulamak içindir.

---

## 4. Sistemimiz buna uygun mu?

Mimari olarak **evet**, ama dört gerçek iş var.

### 4.1 Uygun olan taraflar

**Çağrı fonksiyonu zaten parça alıyor.** [`callAIForAnalysis(context, parts, coveragePolicy, options)`](../supabase/functions/analyze/index.ts) — `parts` dizisini tek elemanlı verip N kez `Promise.all` ile çağırmak yapısal olarak sorunsuz.

**Süre bütçesi yeterli.**

```
ANALYZE_WORKER_TIMEOUT_MS   = 135_000   ← analyze invocation'a verilen süre
MAIN_AI_TIMEOUT_MS          = 120_000   ← çağrı başına
ANALYSIS_JOB_LEASE_SECONDS  = 300       ← kuyruk kirası
```

Paralel çağrılar duvar saatinde en yavaşı kadar sürer. Bugün 3 fotoğraflı çağrı 35–52 sn; tek fotoğraf daha hızlı olacağı için 135 sn içinde rahat.

**Şema sorunu kendiliğinden çözülür.** Gemini'nin `400 INVALID_ARGUMENT "too many states for serving"` hatası `photo_findings`'in tam N elemana sabitlenmesi ile `inspection_layers`'ın tam 12'ye sabitlenmesinin iç içe geçmesinden geliyordu. Fan-out'ta dış dizi tek elemanlı olur, iç içe patlama biter. Bugün kaldırmak zorunda kaldığım iç kısıtlar geri konabilir.

**Kalıcılık tamamen sunucu tarafında.** `finalize_analysis_result_v2` RPC'si `findingRows` + `photoSummaryRows` + analiz sonucunu yazıyor. `total_score_fk` bulgulardan sunucuda hesaplanıyor.

### 4.2 Yapılacak dört iş

**a) Fotoğraflar arası tekilleştirme.** Bugünkü dedup (`areMergeableCoverageFindings`, `coverageFindingKey`, `isCoverageRepairSubfindingAlreadyCovered`) tek yanıt içinde çalışıyor. Fan-out'ta N yanıt arasında çalışması gerek.

Gerçek risk, yukarıdaki tabloda görünüyor: aynı tehlike koşudan koşuya farklı yazılıyor — *"Düzensiz Malzeme İstifleme"* vs *"Raflarda düzensiz ve dengesiz malzeme istifleme"*. Eşikler ayarlanmalı ve ölçülmeli. Ayarsız bırakılırsa kullanıcı aynı tehlikeyi iki kez görür.

**b) `ai_summary`.** Bugün modelin tüm fotoğrafları görüp yazdığı metin. Fan-out'ta her çağrı kendi özetini yazar. İki seçenek:

- Sunucu tarafında foto özetlerinden birleştir — bedava, deterministik, biraz daha az akıcı
- Ek bir metin-only çağrı — akıcı, ~500 token, +1 çağrı

Öneri: sunucu tarafı birleştirme. Metin şablonu `user-facing-copy.ts` üzerinden lokalize edilir, L10N envanterine girer.

**c) Kısmi başarısızlık politikası.** 3 çağrıdan biri patlarsa ne olacak? Bugün tek çağrı patlarsa analiz komple düşüyor. Fan-out'ta seçenek var:

- Tümünü düşür (bugünkü davranış, basit)
- Başarılı olanları yaz, eksik fotoğrafa `coverage_gap_reason` koy (daha iyi, dikkat ister)

Öneri: ikincisi, ama en az bir fotoğraf başarılı olmak şartıyla; hepsi patlarsa analiz başarısız.

**d) Sayaçlar ve bütçeler.** `provider_request_count_total`, `maxProviderRequests`, toplam bulgu bütçesi (39) ve `ProviderAttemptTracker` şu an tek çağrı varsayımıyla çalışıyor. N çağrı için toplanmalı.

### 4.3 Kontrol edilecek

**Eşzamanlı istek limiti.** 3 paralel çağrı tek anahtar aliası (`gemini_paid_primary`) üzerinden gider. Paid tier RPM limitleri bunu kaldırır ama 5 fotoğraflı plan açılırsa (`enable_plus_pro_5_photo_limit` şu an `false`) 5 eşzamanlı olur. Ölçüm sırasında `429` sayılmalı.

---

## 5. Build almadan denenebilir mi?

**Evet.** İstemci tarafında hiçbir değişiklik gerekmiyor — bunu kodu okuyarak doğruladım.

### 5.1 İstemci ne okuyor

| İstemci | Kaynak |
|---|---|
| `AnalysisService.swift:2468` | `analysis_photo_summaries` tablosu |
| `AnalysisService.swift:149` | `findings.source_photo_indices` |
| `ResultView.swift:118-124` | bulguları `sourcePhotoIndices`'e göre gruplayıp gösteriyor |

İstemci **kaç model çağrısı yapıldığını bilmiyor ve umursamıyor.** Satırları veritabanından okuyor. Tekilleştirme istemcide değil, sunucuda.

Senin endişen ("benzer sonuçları karşılaştırma kısmı build ister") yerinde bir sezgi ama yanlış katmanda: birleştirme sunucuda, `mergeCoverageRepairRecords` ve `coverageFindingKey` içinde. Build gerekmiyor.

**Tek istemci-görünür sonuç:** dedup ayarsız kalırsa aynı tehlike iki fotoğrafta iki ayrı kart olarak görünür. Bu bir sunucu ayar meselesi, build değil.

### 5.2 Ölçümü nasıl yönetiriz — karşılaştırma işi

Expert depth'te shadow işe yaramadı çünkü **aynı model çağrısını değiştiriyordu.** Burada durum farklı: fan-out kendi çağrılarını yapar, birincil çağrıya hiç dokunmaz. Dolayısıyla gerçek bir A/B mümkün.

**Tasarım:**

1. Analiz normal şekilde tamamlanır — kullanıcı bugünkü sonucu görür, hiçbir şey değişmez
2. Tamamlandıktan sonra `fanout_compare` türünde ayrı bir kuyruk işi tetiklenir (coverage quality repair'ın bugün yaptığı gibi, `triggerAnalysisWorker` üzerinden)
3. O iş fotoğraf başına bir çağrı yapar, sonucu **ayrı bir tabloya** yazar: `analysis_fanout_comparisons`
4. Kullanıcının analizi, bulguları, skoru **hiç değişmez**
5. Karşılaştırma SQL ile yapılır

**Neden bu shadow güvenli:**

| | Expert depth shadow | Fan-out karşılaştırma |
|---|---|---|
| Birincil çağrıyı değiştirir mi | **Evet** — şemaya yapı ekliyordu | **Hayır** — ayrı çağrılar |
| Kullanıcı sonucunu etkiler mi | Evet, bulgu kaybettirdi | Hayır, ayrı tabloya yazar |
| Geri alma | Flag | Flag |

**Kapsam kontrolü:** flag `allowlist` modunda, sadece kendi hesabında. Ölçüm maliyeti sadece o hesabın analizlerinde oluşur.

### 5.3 Karşılaştırma tablosu

```sql
create table public.analysis_fanout_comparisons (
  analysis_id      uuid primary key references public.analyses(id) on delete cascade,
  user_id          uuid not null,
  created_at       timestamptz not null default now(),
  photo_count      int not null,
  baseline_finding_count   int not null,
  fanout_finding_count     int not null,
  fanout_findings          jsonb not null,   -- birleştirme öncesi ham
  fanout_merged_findings   jsonb not null,   -- dedup sonrası
  duplicate_collapsed_count int not null,
  baseline_total_fk        numeric,
  fanout_total_fk          numeric,
  baseline_duration_ms     int,
  fanout_duration_ms       int,
  fanout_prompt_tokens     int,
  fanout_output_tokens     int,
  fanout_thought_tokens    int,
  fanout_request_count     int,
  fanout_error             text
);
```

RLS: sadece service role yazar, kullanıcı kendi satırını okuyabilir (ya da hiç okumaz — bu bir ölçüm tablosu).

### 5.4 Karar kriterleri

En az **10 analiz**, karışık fotoğraf sayısı. Bakılacaklar:

| Metrik | Geçme eşiği |
|---|---|
| Tekilleştirme sonrası bulgu sayısı | baseline'ın **≥ 1.6×**'i |
| Yanlışlıkla birleştirilen ayrı tehlike | **0** (elle denetlenir) |
| Kullanıcıya çift görünecek tekrar | **0** |
| Duvar saati | ≤ baseline |
| Çıktı token oranı | ≤ 2.5× |
| Sağlayıcı `429` | **0** |

Bulgu sayısı 1.6×'in altında kalırsa 2× maliyet gerekçelendirilemez; o zaman fan-out'u bırakıp bağımsız ikinci paso (tek çağrı, tüm fotoğraflar, birleştirme) seçeneğine döneriz.

**Kaliteyi elle de denetlemek gerekir.** Bulgu sayısının artması tek başına yeterli değil — yeni bulguların gerçek olup olmadığına bakılmalı. 10 analizin en az 3'ünde fan-out çıktısı elle okunmalı.

---

## 6. Aşamalar

| Faz | İş | Build | Kullanıcı etkisi |
|---|---|---|---|
| **0** | `analysis_fanout_comparisons` tablosu + RLS + flag (`off`) | yok | yok |
| **1** | `fanout_compare` kuyruk işi, N paralel çağrı, ham sonucu yaz | yok | yok |
| **2** | Fotoğraflar arası dedup, eşik ayarı, birleştirilmiş sonucu da yaz | yok | yok |
| **3** | Flag `allowlist` → kendi hesabın, 10+ analiz topla | yok | yok |
| **4** | Karar: kriterler geçerse fan-out'u birincil akışa al | yok | **evet** |
| **5** | `ai_summary` birleştirme, kısmi başarısızlık politikası, sayaçlar | yok | evet |

Faz 0–3 tamamen ölçüm. Faz 4 öncesi hiçbir kullanıcı sonucu değişmez.

**Faz 4 hâlâ build gerektirmiyor** — istemci satırları okuyor, kaç çağrı yapıldığını bilmiyor.

---

## 7. Riskler

| Risk | Etki | Azaltma |
|---|---|---|
| Dedup eşikleri gevşek → kullanıcı aynı tehlikeyi iki kez görür | Yüksek | Faz 2'de eşik ayarı, Faz 3'te elle denetim, karar kriteri 0 tekrar |
| Dedup eşikleri sıkı → gerçek ayrı tehlike birleşir | **Çok yüksek** (bulgu kaybı) | Ayrı ölçüt, elle denetim, `duplicate_collapsed_count` takibi |
| Maliyet 2× | Orta | Ölçümle doğrula, 1.6× bulgu eşiği tutmazsa vazgeç |
| Eşzamanlı 429 | Orta | Ölçümde say, gerekirse eşzamanlılığı 2'ye sınırla |
| `ai_summary` kalitesi düşer | Düşük | Sunucu birleştirmesi, gerekirse metin-only çağrı |
| Ölçüm maliyeti | Düşük | `allowlist`, tek hesap |

En büyük risk **sıkı dedup**: ayrı iki tehlikeyi birleştirmek, bugünkü kaçırma probleminden daha kötü çünkü sessiz. `duplicate_collapsed_count` bunun için var.

---

## 8. Ne yapılmayacak

- İstemci değişikliği — gerekmiyor, ölçüldü
- Birincil analiz çağrısına dokunmak — expert depth regresyonunun kaynağı buydu
- Fan-out ile aynı anda tekrarlı örnekleme — 4× maliyet, önce fan-out ölçülsün
- Repair pasosunu Faz 4'ten önce kaldırmak — bugün 0 ekliyor ama zero-finding yeniden incelemesi henüz prod'da ateşlenmedi

---

## 9. Açık kararlar

1. **Faz 0-3 başlasın mı?** Ölçüm maliyeti sadece allowlist'teki hesapta, kullanıcı etkisi sıfır.
2. **1.6× bulgu eşiği doğru mu?** 2× maliyete karşılık. Daha düşük bir eşik kabul edilebilir mi?
3. **Kısmi başarısızlıkta ne olsun?** Öneri: en az bir fotoğraf başarılıysa yaz, eksik olana `coverage_gap_reason`.
4. **`ai_summary` sunucu birleştirmesi yeterli mi**, yoksa metin-only çağrı mı?
