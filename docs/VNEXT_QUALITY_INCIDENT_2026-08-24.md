# vNext kalite arızası — teşhis ve yapılacaklar

**Tarih:** 2026-08-24
**Kapsam:** son iki canlı analiz + 24 saatlik sürüm geçmişi
**Durum:** teşhis tamamlandı, hiçbir değişiklik yapılmadı

| | Tek fotoğraf | Üç fotoğraf |
|---|---|---|
| `analysis_id` | `aec255fa-89aa-4b91-8f14-bf516cf3ed62` | `e1223c4a-b26d-440a-b91d-3c8913d53eee` |
| Saat | 22:10 | 21:25 |
| Sektör | construction | manufacturing |
| Prompt | `vnext-photo-expert-v25` | `vnext-photo-expert-v24` |
| Ham fact | 4 | 4 |
| Kanıt kapısını geçen | **1** | **1** |
| Güvence eklenen | +4 | +9 |
| Final bulgu | 5 | 9 |
| FK | 108 | 108 |
| Bant | **Orta** | **Orta** |

Her iki analizde de kullanıcıya giden raporun tek gerçek bulgusu **"dağınık malzeme / takılma riski"**. Geri kalan her şey şablon periyodik kontrol maddesi.

İnşaat fotoğrafında korumasız kenarda çalışan var; rapor "Orta risk" diyor. Bu, bu ürünün üretebileceği en zararlı çıktıdır — sessiz kalmaktan kötüdür, çünkü güvence verir.

---

## 1. Ölçüm: 24 saat, 25 prompt sürümü

Aynı üç fotoğraf üzerinde çalışan 23 analiz:

| Saat | Prompt | Ham fact | Kanıtı geçen | Geçme % | Güvence sonrası | FK | Bant |
|---|---|---:|---:|---:|---:|---:|---|
| 22:26 | v3 | 7 | 7 | 100% | — | 4650 | critical |
| 23:18 | v4 | 13 | 9 | 69% | — | 2031 | critical |
| 23:35 | v5 | 8 | 6 | 75% | — | 960 | high |
| 23:55 | v6 | 3 | 3 | 100% | — | 162 | medium |
| 00:13 | v7 | 6 | 6 | 100% | — | 708 | high |
| 00:24 | v8 | 10 | 10 | 100% | — | 624 | high |
| 00:56 | v9 | 8 | 8 | 100% | — | 987 | high |
| 01:16 | v10 | 7 | 6 | 86% | — | 1400 | critical |
| 01:36 | v11 | 7 | 6 | 86% | — | 936 | critical |
| 02:08 | v13 | 9 | 9 | 100% | 21 | 2148 | critical |
| 02:26 | v14 | 9 | 7 | 78% | 15 | 1131 | high |
| 09:40 | v15 | 11 | 8 | 73% | 16 | 1083 | high |
| 11:45 | v17 | 9 | 5 | 56% | 21 | 315 | medium |
| 12:48 | v18 | 9 | 5 | 56% | 15 | 296 | medium |
| 13:24 | v19 | 6 | 4 | 67% | 12 | 501 | medium |
| 14:56 | v21 | 6 | 3 | 50% | 11 | 900 | critical |
| 15:50 | v21 | 9 | 4 | 44% | 14 | 2214 | critical |
| 16:57 | v23 | 4 | 2 | 50% | 14 | 648 | critical |
| 19:21 | v23 | 2 | 2 | 100% | 12 | 234 | medium |
| 20:35 | v23 | 8 | 6 | 75% | 16 | 870 | high |
| 21:04 | v24 | 13 | 8 | 62% | 16 | 1068 | high |
| **21:25** | **v24** | **4** | **1** | **25%** | **10** | **108** | **medium** |
| **22:10** | **v25** (1 foto) | **4** | **1** | **25%** | **5** | **108** | **medium** |

### Üç ayrı çöküş, aynı tabloda

**a) Kanıt kapısı geçme oranı %100 → %25.** Guard'lar sürüm sürüm sıkıldı. Her sıkma tek bir canlı analizdeki tek bir yanlış pozitife tepki olarak yapıldı.

**b) Ham fact üretimi 2 ile 13 arasında salınıyor.** Aynı fotoğraflar. **6.5 kat.** Bu prompt değişikliklerinden bağımsız bir model varyansı; hiçbir sürüm bunu azaltmadı.

**c) FK toplamı 108 ile 4650 arasında.** **43 kat.** Bant `medium` ile `critical` arasında rastgele geziyor. Aynı fotoğraflar, aynı model.

### Ve en önemlisi: güvence katmanı çöküşü gizledi

```
Kanıtı geçen fact   →  Eklenen güvence
        9           →        12
        8           →         8
        5           →        16
        4           →         8
        3           →         8
        2           →        10
        1           →         9
        1           →         4
```

Ters orantı. **Ne kadar çok gerçek bulgu öldürülürse o kadar çok şablon dolduruluyor.**

Sonuç: dışarıdan bakan biri "final bulgu sayısı" metriğine bakarsa 9–16 arasında sabit görür ve her şey yolunda sanır. Oysa gözlenen fact 8'den 1'e düşmüş. **İzlenen metrik, izlenmesi gereken şeyi maskeledi.**

---

## 2. Kök nedenler

### KN-1 — Yapılandırılmış fact'ler düz metin regex'iyle yargılanıyor

Kanıt kapısı ([engine.ts:1363](../supabase/functions/analyze-vnext/engine.ts)):

```ts
if (hasVisualAbsenceClaim(claim) && !hasPositiveAbsenceGeometry(fact) &&
    !hasDirectVisibleSafetyBarrierGeometry(fact)) {
  return "absence_only_claim";
}
```

`VISUAL_ABSENCE_PATTERNS` içinde `eksik`, `yok`, `missing` var — "korkuluk eksikliği" yazan her fact anında tetikliyor. Kurtarma yolları ise modelin **serbest metnini** arıyor:

```
acikta kalan bosluk | acik kenar | korkuluk kesintisi | bariyer kesintisi
(ara korkuluk|etek tahtasi|…) .{0,64} (eksik|yok) .{0,56} (acikca|gorul|bosluk)
```

Model doğru tehlikeyi doğru şekilde tarif etti ama bu ifade kalıplarından birini o sırayla ve o karakter mesafesinde kullanmadığı için fact öldü.

**Aynı kusur üç yerde:**

| Fonksiyon | Ne yapıyor |
|---|---|
| `hasPositiveAbsenceGeometry` | `affirmative_cues` üzerinde regex |
| `hasDirectVisibleSafetyBarrierGeometry` | `affirmative_cues` üzerinde regex |
| `isCriticalSafetyHardwareAbsenceCandidate.localizableGeometryCue` | `affirmative_cues` üzerinde regex |

Üçüncüsü hedefli yeniden inceleme kurtarma yolu — o da metin eşleştirdiği için hiçbir şey kurtarılmadı, `targeted_reinspection: not_needed` çıktı.

Bu regex'le kazanılamaz: her yeni ifade biçimi yeni pattern gerektirir, hata sessizdir ve **en ağır bulgulara karşı yanlıdır**, çünkü ciddi tehlikeler şablon metinden daha çeşitli dille anlatılır.

Oysa yapılandırılmış alanlar cevabı zaten taşıyor: `entity.equipment_family`, `entity.component`, `observed_condition.condition_code`, `exposed_entity`, `mechanism_code`, `evidence.normalized_region`, `confidence.*`.

### KN-2 — Guard yüksek sonuçlu fact'te fail-closed

Emin değilse siliyor. Güvenlik ürününde bu ters yön. Kaçırılan ölümcül risk, yanlış pozitiften ağır basar.

### KN-3 — Güvence hacmi aktif bulgu sayısına bağlı

Yukarıdaki ters orantı tesadüf değil, mekanizma. Guard ne kadar öldürürse rapor o kadar şablonla doluyor. Bu hem çöküşü gizliyor hem de kullanıcıya gerçek bulgu yerine ödev listesi veriyor.

### KN-4 — 24 saatte 25 prompt sürümü, sabit değerlendirme seti yok

Her sürüm bir önceki canlı analizin tek örneğine göre ayarlandı. Tek örneğe aşırı uyum (overfit). Ham fact üretiminin 2–13 arasında salındığı bir sistemde tek analize bakarak prompt ayarlamak, gürültüyü sinyal sanmaktır.

### KN-5 — Ekipman taksonomisi hatalı eşleştirme yapıyor

Kule vinç "**Köprü vinçler**" olarak render ediliyor. Beton mikseri iki ayrı "proses makinesi" güvence maddesi üretiyor. Etiketsiz kova "kimyasal envanter/SDS" başlatıyor. `yelek` içindeki `elek` proses makinesi eşleşmesi doğuruyor, `guardrail_system` raylı sistem sayılıyor.

---

## 3. Yapılacaklar

Öncelik sırasına göre. **P0 = canlı zarar veriyor.**

### P0-1 · Yön kuralı: yüksek sonuçlu fact sessizce düşmez

`consequence_class ∈ {single_fatality, multiple_fatality_major_environmental}` **ve** maruz kalan kişi varken bir fact hiçliğe reddedilemez. Üç çıkıştan biri olmalı:

1. bulgu olarak hayatta kalır, `needs_field_verification = true`
2. hedefli yeniden inceleme adayı olur
3. `coverage` içine `rejected_high_consequence_fact` olarak yazılır ve **rapora "değerlendirilemedi" notu düşer**

Hiçliğe reddetme yalnız düşük sonuçlu iddialar için geçerli.

> Bu tek kural, sınıfın tekrarını yapısal olarak kapatır. Diğer maddelerin hepsi bu olmadan da yararlı ama korumasız.

### P0-2 · Yapılandırılmış kabul yolu — üç kapıda birden

Metin **kanıt eklemek** için kullanılır, **kanıt şartı** olarak değil. Kabul koşulu yapılandırılmış alanlardan kurulur:

```
observed_condition.condition_code ∈ whitelist
  missing_guardrail, unguarded_open_edge, missing_mid_rail,
  missing_toeboard, missing_machine_guard, unguarded_moving_parts
AND evidence.normalized_region.is_global = false
AND confidence.entity = high AND confidence.condition = high
    AND confidence.localization = high
AND exposed_entity bir kişiyi gösteriyor
AND mechanism_code doğrudan olay yolu tanımlıyor
```

`hasPositiveAbsenceGeometry`, `hasDirectVisibleSafetyBarrierGeometry` ve `isCriticalSafetyHardwareAbsenceCandidate` **üçü birden** bu yolu kullanmalı. Yalnız birini düzeltmek diğer iki kapının aynı bulguyu öldürmesini engellemez.

**Ayırt edilecek:** "occluded / seçilemiyor" (gerçek görünmezlik → reddet) ile "görünür biçimde eksik bariyer" (→ kabul et).

### P0-3 · `model_required` zorunluluğunu kaldır

`isCriticalSafetyHardwareAbsenceCandidate` içindeki `fact.verification.model_required` şartı kalkmalı veya sunucu tarafından belirlenen hedefli gereksinimle değiştirilmeli. Sağlayıcı `false` gönderdi diye kritik bir reddedilmiş fact hedef dışı kalamaz.

### P0-4 · Red oranı alarmı

Bir analizde ayrıştırılan fact'lerin **%50'sinden fazlası** reddedilirse alarm. Her iki arızalı analizde de oran %75'ti. Bu alarm bugün olsaydı sorun aynı gün yakalanırdı.

Ayrıca haftalık izlenecek: `provider_parsed_fact` ve `evidence_valid_fact` toplamları. **Final bulgu sayısı izlenmemeli** — güvence onu maskeliyor.

### P1-5 · Güvence hacmi aktif bulgudan bağımsız olsun

Güvence maddeleri aktif bulgu sayısı **bilinmeden** üretilir. Hacmi ona bağlı olamaz. Reddedilen bulguların yerine sayı doldurulamaz.

Ek olarak:
- Bir gözlenen aktif bulgu aynı ekipmanı kapsıyorsa güvence içeriği o bulgunun önlemlerine **emilir**, ayrı madde açılmaz.
- Tek ekipmandan **en fazla bir** güvence maddesi. Mikserden iki madde çıkmamalı.
- Güvence maddeleri rapor içinde **ayrı bölümde** gösterilir, aktif bulgu listesine karışmaz.

### P1-6 · Ekipman taksonomisi düzeltmeleri

| Sorun | Düzeltme |
|---|---|
| `tower_crane` → "köprü vinç" | `tower_crane` ve `overhead_crane` ayrı kanonik aile; genel `crane` aliası `overhead_crane`'e bağlanmaz |
| `yelek` içinde `elek` | kelime sınırı + negatif eşleşme testi |
| `guardrail_system` → raylı sistem | aynı |
| `dished_end` → komple proses tankı | tank bombesi/parçası tek başına tank sınıfı doğurmaz |
| Etiketsiz kova → kimyasal envanter | `chemical_container` yalnız etiket/işaret görünürse |

Katalog aktivasyonu öncelikle `equipment_family + component` üzerinden yapılmalı; serbest `visible_condition_summary` tek başına ekipman sınıfı oluşturamaz.

### P1-7 · Scaffold parent-child entity ilişkisi

`scaffolding_1 ↔ scaffolding_platform_1 ↔ guardrail_1` gibi ebeveyn-çocuk `entity_ref` bağı kurulmalı; sektör kritik bileşen kapsamasında birlikte değerlendirilmeli.

### P1-8 · Tek fotoğraflı yüksek tehlikeli sektörde kritik kapsam ağı

Tek fotoğraflı construction/high-hazard analizinde de kritik kapsam güvenlik ağı çalışmalı.

**Şart:** ağ yalnız görünür kritik raw fact, actionable zorunlu modül veya somut inspection signal varsa tetiklenir. **Sektör tek başına bulgu veya kritik skor üretmez.**

### P2-9 · Malformed JSON kurtarma

- Yalnız güvenli sözdizimi hatalarında (trailing comma vb.) deterministik repair + strict schema validation.
- Repair mümkün değilse kuyruk yeniden **full primary** çalıştırmamalı.
- Önceki primary attempt checkpoint edilmeli; sonraki çalışma `technical_retry` / 1536 thinking olarak devam etmeli.
- Telemetride iki çağrı da `primary attempt 1` görünmemeli.

### P2-10 · Kullanıcıya giden metin

- `Worker 1` gibi `entity_ref` değerleri **"Çalışan"** olarak normalize edilmeli.
- Tek önlemde `"1."` öneki kaldırılmalı.
- Jenerik güvence mekanizma metni kök neden gibi gösterilmemeli.
- Doğrulanmamış "standartlara aykırı" ifadeleri temizlenmeli.

### P2-11 · Süreç: prompt sürümü kapıya bağlanmalı

24 saatte 25 sürüm, sabit değerlendirme seti olmadan. Bu, gürültüye ayar yapmaktır.

- Bugünkü üç fotoğraf + inşaat fotoğrafı **fixture** olarak repoya girer, beklenen tehlike listesiyle.
- Yeni prompt sürümü, fixture üzerinde **en az 3 tekrar** çalıştırılmadan canlıya çıkmaz.
- Kabul kararı tek koşuya değil, tekrarların medyanına bakar.
- Her sürüm `prompt_version` + fixture raporu + geri alma yolu taşır.

---

## 4. Zorunlu regresyon testleri

**Pozitif (bulgu ÜRETMELİ) — bunlar bugün eksik:**

- `HF001` iskele platformunda eksik korkuluk + açık kenarda çalışan → kanıt kapısını **geçmeli**
- `HF002` betonarme döşemede korumasız açık kenar + yakında çalışan → **geçmeli**
- `HF004` beton mikserinde koruyucusuz hareketli parçalar → **geçmeli**
- Ekskavatör kol/kepçe bağlantısı bulgusu → **geçmeli**
- Hidrolik hortum sürtünme/aşınma bulgusu → **geçmeli**
- Kazı şev/gevşek malzeme bulgusu → **geçmeli**
- Final sonuçta **en az iki yüksekten düşme bulgusu** korunmalı

**Negatif (bulgu ÜRETMEMELİ):**

- Aynı koşullar occluded/uncertain ise bulgu değil **hedefli aday** olmalı
- Kule vinç hiçbir yerde köprü/overhead vinç olarak render edilmemeli
- Etiketsiz mavi kova kimyasal güvence üretmemeli
- Gözlenen mikser koruyucu kusuru, iki jenerik mikser güvence maddesini **bastırmalı**

**Değişmezler:**

- Kişi + korumasız kenar içeren inşaat fotoğrafında en yüksek bant **Orta olamaz**
- Kritik skor **sektör nedeniyle değil**, görünür olay yolu ve mekanizma nedeniyle oluşmalı
- Tek fotoğraf construction kritik kapsam testi
- Malformed JSON sonrası ikinci full primary yerine repair veya `technical_retry`

---

## 5. Kapsam dışı

**Thinking artırılmayacak, yeni genel model çağrısı eklenmeyecek.**

Gerekçe telemetride: her iki arızalı analizde de `provider_parsed_fact = 4`. Model mevcut 3072 thinking ile kritik riskleri gördü ve doğru tarif etti. Sorun tamamen post-processing, entity taksonomisi, güvence ve retry katmanında. Thinking artırmak bu hatayı gizler, çözmez.

---

## 6. Çözülmeyen: varyans

Yukarıdaki maddelerin hiçbiri ham fact üretiminin 2–13 arasında salınmasını düzeltmez. Bu ayrı bir problemdir ve ayrı ele alınmalıdır.

Guard'lar düzeltildikten sonra bile aynı fotoğraf setinde koşudan koşuya farklı bulgu kümesi çıkacaktır. Fixture'ın **tekrarlı** çalıştırılması ve medyana bakılması bu yüzden zorunlu — tek koşu hiçbir zaman kabul kararı için yeterli değil.

---

## 7. Önerilen sıra

1. **P0-1** yön kuralı — en küçük değişiklik, sınıfı yapısal olarak kapatır
2. **P0-2 + P0-3** yapılandırılmış kabul yolu, üç kapıda birden
3. **P0-4** red oranı alarmı
4. **P1-5** güvence hacmi bağımsızlığı + ayrı bölüm
5. **P1-6 / P1-7 / P1-8** taksonomi, entity ilişkisi, kritik kapsam ağı
6. **P2-9 / P2-10** retry ve metin
7. **P2-11** fixture ve sürüm kapısı — bundan sonraki her prompt değişikliğinin önkoşulu

P0'lar tamamlanana kadar canlıda inşaat ve imalat analizleri ölümcül riskleri kaçırmaya devam edecek. Düzeltme günlere yayılacaksa ara çözüm olarak `absence_only_claim` guard'ı geçici olarak fact'i öldürmek yerine `needs_field_verification` ile hayatta bırakacak şekilde gevşetilebilir.
