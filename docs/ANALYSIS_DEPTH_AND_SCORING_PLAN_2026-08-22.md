# Mevcut çağrı bütçesiyle derinlik ve skor kalitesi

**Tarih:** 2026-08-22
**Durum:** öneri, uygulanmadı
**Kısıt:** yeni model çağrısı yok, fotoğraf başına ayırma yok, yeni build yok
**İlgili:** `FANOUT_PER_PHOTO_ANALYSIS_PLAN_2026-08-22.md` (reddedildi — maliyet), `ANALYSIS_QUALITY_ADDENDUM_2026-08-21.md`

---

## 1. Yöntem

Son 30 günün **163 AI bulgusu** ve `_input_audit` telemetrisi üzerinde ölçüm. Tahmin yok; her sayı sorgulanabilir.

---

## 2. Merkezi bulgu

**Sistem hesap gücüyle değil, talimatla sınırlı.**

| | Değer |
|---|---|
| İzin verilen çıktı (3 foto, Plus) | **24.500 token** |
| Gerçekte üretilen | **~2.900 token** |
| Kullanım | **%12** |

`finish_reason` her koşuda `STOP`. Model yerden dolayı durmuyor — **prompt ona kısa olmasını söylüyor:**

```
- description max 200 karakter; corrective_action max 180 karakter;
  preventive_control max 180 karakter.
- Her bulgu için tam 2 önlem ver
```

Elimizde ödediğimiz ama kullanmadığımız %88'lik bir çıktı bütçesi var. Derinlik oradan gelecek.

---

## 3. Ölçülen dokuz kusur

### 3.1 Olasılığın kalibrasyon kuralı yok

Prompt **şiddet** için tam bir cetvel veriyor (100/40/15/7/3/1, her biri tanımlı). **Olasılık ve frekans için sadece izinli değerleri listeliyor**, tanım yok:

```
- Fine-Kinney ihtimal: 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans:  0.5 / 1 / 2 / 3 / 6 / 10
```

Sonuç tam olarak bu:

| Olasılık | Pay | | Şiddet | Pay |
|---|---|---|---|---|
| 0.5 | 3.1% | | 3 | 2.5% |
| 1 | 11.0% | | 7 | 22.1% |
| **3** | **61.3%** | | 15 | 27.0% |
| 6 | 23.9% | | **40** | **39.9%** |
| 10 | 0.6% | | 100 | 8.6% |

Cetveli olan parametre dağılıyor, olmayan tek değere çöküyor. **Olasılığın %61'i `3`.** Skorun üç çarpanından biri pratikte sabit.

### 3.2 Şiddet şişmiş

**Bulguların %48.5'i ölüm sınıfı şiddet (≥40) taşıyor.** Yani her iki bulgudan biri ölümle sonuçlanabilecek bir tehlike iddiasında.

Bant dağılımı:

| Bant | Pay |
|---|---|
| low | 21.5% |
| medium | 29.4% |
| **high** | **32.5%** |
| **critical** | **16.6%** |

**%49'u high veya critical.** Her şey kritikse hiçbir şey kritik değildir — önceliklendirme değerini kaybediyor.

Kaynağın bir kısmı prompt'taki tek örnek bulgu:

```json
"fk_probability": 6, "fk_frequency": 6, "fk_severity": 100
```

Skor 3600. Modelin gördüğü **tek çapa, ölçeğin en üstünde.**

### 3.3 Önlem sayısı koda gömülü

`recommendedMeasures()` fonksiyonu **her zaman tam 2 eleman döndürüyor** — bir düzeltici, bir önleyici. Modelin `recommended_measures` dizisi yalnız yedek olarak kullanılıyor.

Ölçüm: dört bandın **dördünde de ortalama 2.0 önlem.** Kritik bulgu ile düşük bulgu aynı sayıda önlem alıyor.

**Kontrol hiyerarşisi yok.** İSG'nin temel sıralaması — eliminasyon → ikame → mühendislik kontrolü → idari kontrol → KKD — çıktıda hiç geçmiyor. Prompt'ta sadece bir cümle var ("KKD'yi yalnızca üst sıra kontroller yetersiz kaldığında öner").

### 3.4 Kalıntı risk hiç hesaplanmıyor

Veritabanı bunun için **kurulmuş durumda**:

```sql
residual_fk_probability  nullable
residual_fk_frequency    nullable
residual_fk_severity     nullable
residual_fk_score        GENERATED ALWAYS AS (p * f * s)
residual_m5_score        GENERATED ALWAYS AS (p * s)
```

Doldurulan satır: **0 / 163.**

Kalıntı risk Fine-Kinney'in çekirdek çıktısıdır: *önlem öncesi risk → önlemler → önlem sonrası kalan risk*. Profesyonel bir risk değerlendirme tablosunun olmazsa olmazı. Sütunlar hazır, migration gerekmiyor, sadece girdileri göndermiyoruz.

`register-report` ve `generate-excel-report` içinde de `residual` kelimesi hiç geçmiyor.

### 3.5 Kategori taksonomisi kontrolsüz

**163 bulgu, 84 farklı kategori.** `category` şemada serbest metin (`{ type: "STRING" }`, enum yok).

Sonuç:

| Kategori | n |
|---|---|
| Yüksekte Çalışma | 24 |
| **Work at Height** | **4** |
| Makine ve Ekipman Güvenliği | 7 |
| **Makine Güvenliği** | **4** |
| Elektrik Güvenliği | 5 |
| **Electrical Safety** | **5** |

Aynı tehlike sınıfı hem farklı isimlerle hem **farklı dillerde** kaydediliyor. Türkçe çıktı veren bir üründe `Electrical Safety` kategorisi var.

Bu aynı zamanda L10N kapılarının yakalayamadığı bir sızıntı — `category` model çıktısı, kod literali değil.

Oysa 12 katmanlı denetimin **kanonik anahtarları ve lokalize etiketleri zaten var** (`INSPECTION_LAYER_KEYS`).

### 3.6 Mevzuat referansı bulguların yarısında yok

**70 / 163 (%43)** bulgunun `references_text` alanı boş veya 5 karakterden kısa.

Dolu olanların ortalama uzunluğu bant başına 23–60 karakter — yani bir yönetmelik numarası, madde yok.

### 3.7 Skor kafesi seyrek, bantlar arasında boşluk var

163 bulgu, **36 farklı skor.** Bant sınırlarında delikler:

```
low      3 ─── 63     ⟶ boşluk 63–80
medium  80 ─── 135    ⟶ boşluk 135–240
high   240 ─── 360    ⟶ boşluk 360–480
critical 480 ─── 10000
```

Olasılık `3`'e çakılı olduğu için skorlar dar bir kafese düşüyor. Sıralama ayırt ediciliğini kaybediyor.

### 3.8 Belirsizlik başlıklı bulgular işaretlenmiyor

Başlığında "belirsizlik"/"durumu" geçen 5 bulgunun **3'ünde `needs_field_verification = false`**. Başlığı belirsizlik diyen bulgunun saha teyidi istememesi kendi içinde çelişkili.

### 3.9 Sorumlu ve termin sütunları boş

`responsible` ve `deadline`: **0 / 163.** Türk İSG risk değerlendirme tablosunun standart iki sütunu. `bounding_box` da boş (0/163) ama onu göstermek istemci işi.

---

## 4. Plan

Beş faz. Faz A ve B çıktı maliyetini artırmaz. Faz C artırır ama **repair'den tasarrufla fazlasıyla karşılanır.**

### Faz A — Skor kalibrasyonu

**Maliyet: sıfır.** Prompt değişikliği.

**A1. Olasılık ve frekans cetveli ekle.** Şiddet cetvelinin yaptığını yapacak:

```
Fine-Kinney OLASILIK — tehlike gerçekleşirse zarar doğurma ihtimali:
- 10 = Beklenir, kaçınılmaz. Koruma tamamen yok, maruziyet sürekli.
- 6  = Oldukça mümkün. Koruma yetersiz veya devre dışı bırakılmış.
- 3  = Olası. Koruma var ama eksik/aşılabilir.
- 1  = Düşük, beklenmez. Koruma var, ihlal için özel koşul gerekir.
- 0.5 = Çok düşük. Birden fazla bağımsız bariyer var.
- 0.2 = Zayıf ihtimal. Teorik olarak mümkün.

Fine-Kinney FREKANS — tehlikeli duruma maruziyet sıklığı:
- 10 = Sürekli, vardiya boyunca.
- 6  = Günlük.
- 3  = Haftalık.
- 2  = Aylık.
- 1  = Yılda birkaç kez.
- 0.5 = Çok seyrek.

Frekansı fotoğraftan çıkarabildiğin kadar somut dayan: çalışma istasyonu,
geçiş yolu, sürekli kullanılan ekipman → yüksek. Depolama alanı, nadiren
girilen bölge → düşük. Dayanağı yoksa 3 (haftalık) kullan ve bunu
needs_field_verification ile işaretle.
```

**A2. Çapa örneğini dengeye çek.** Tek maksimum örnek yerine **iki örnek**: biri yüksek (mevcut korkuluk örneği), biri orta (`P=1, F=2, S=15` gibi). Modelin gördüğü referans noktası ölçeğin ortasına iner.

**A3. Şiddet enflasyonuna karşı açık kural:**

```
ŞİDDET 40 ve 100 SEÇİMİ:
- 40 sadece TEK BİR OLAYDA ölüm veya kalıcı iş göremezlik makul ise.
- 100 sadece AYNI OLAYDA birden fazla kişinin ölümü makul ise
  (patlama, toplu göçük, toksik salım). Tek kişilik senaryoda 100 kullanma.
- Düzen-tertip, istifleme, ergonomi, işaretleme bulgularında 40 ve üstü
  ancak somut ölümcül mekanizma gösterilebiliyorsa (devrilerek ezilme,
  yüksekten düşen ağır cisim) kullanılır; gösteremiyorsan 7 veya 15.
```

**A4. Skor gerekçesi alanı.** Şemaya kısa bir `score_rationale` (max 160 karakter) ekle: hangi görsel dayanağın hangi P/F/S değerini verdiğini yazsın. Çıktıya bulgu başına ~40 token ekler; karşılığında modelin parametreyi savunması gerekir, bu da rastgele `3` seçmeyi zorlaştırır.

**Ölçüm:** olasılık dağılımının entropisi. Hedef: hiçbir tek değer **%40'ı geçmesin** (bugün 61.3%). Bant dağılımında high+critical **%35 altına** insin (bugün %49).

---

### Faz B — Kategori taksonomisi

**Maliyet: sıfır.** Şema + sunucu normalizasyonu.

`category` alanını 12 denetim katmanına bağlı **kapalı enum** yap. Anahtarlar ve lokalize etiketler zaten var.

- Şemada `category: { type: "STRING", enum: [...INSPECTION_LAYER_KEYS] }`
- Sunucuda kanonik anahtardan lokalize etikete çevir (`user-facing-copy.ts` üzerinden, L10N envanterine girer)
- Eski serbest metin için eşleme tablosu; eşleşmeyen → bulgunun `inspection_layer_keys` ilk elemanından türet

Kazanç: 84 → 12 kategori, dil sızıntısı biter, rapor ve trend toplaması mümkün olur.

> Not: bu bir çıktı sözleşmesi değişikliği. `display_group` gibi istemcinin okumadığı bir alan değil — istemci `category`'yi gösteriyor. Lokalize etiket sunucudan geldiği için **build gerekmiyor**, ama etiket metinleri L10N envanterine eklenmeli.

---

### Faz C — Derinlik

**Maliyet: çıktı ~2.900 → ~6.500 token.** Aşağıda repair tasarrufuyla netleştiriliyor.

**C1. Karakter tavanlarını kaldır.** `description` 200 → 500, `corrective_action`/`preventive_control` 180 → 300. Ölçülen mevcut `description` zaten 305–362, yani model tavanı çoktan aşıyor; kural sadece baskılıyor.

**C2. Kontrol hiyerarşisine göre önlem.** `recommendedMeasures()` sabit 2 döndürmeyi bırakır. Bant başına:

| Bant | Önlem sayısı |
|---|---|
| low | 2 |
| medium | 2–3 |
| high | 3–4 |
| critical | 4–5 |

Her önleme `hierarchy` alanı: `elimination` / `substitution` / `engineering` / `administrative` / `ppe`. Prompt hiyerarşiyi açıkça ister ve KKD'nin tek başına yeterli sayılmamasını zorunlu kılar.

Kod değişikliği: `recommendedMeasures()` içinde sabit `[corrective, preventive]` dönüşü yerine normalize edilmiş listeyi bant sınırına göre kes, hiyerarşiye göre sırala, en az bir düzeltici + bir önleyici garanti et.

**C3. Kalıntı risk.** Şemaya `residual_fk_probability` / `residual_fk_frequency` / `residual_fk_severity` + `residual_m5_*` ekle. Prompt kuralı:

```
KALINTI RİSK: Önerdiğin önlemler eksiksiz uygulandıktan SONRA kalan riski
puanla. Şiddet genelde değişmez (tehlikenin doğası aynıdır); olasılık ve
frekans düşer. Kalıntı skor mutlaka mevcut skordan küçük olmalı.
Önlem riski tamamen ortadan kaldırıyorsa (eliminasyon) olasılık 0.2 olur.
```

Sunucu tarafında sağlama: `residual_fk_score < fk_score` değilse kalıntıyı düşür ve telemetriye yaz. `residual_fk_score` GENERATED olduğu için sadece üç girdi gönderilir, migration gerekmez.

**C4. Mevzuat referansı.** Prompt referansı zorunlu kılsın ve formatı sabitlesin (yönetmelik adı + madde, ya da TS/EN standart numarası). Emin değilse uydurmak yerine ilgili genel yönetmeliği versin. Hedef: boş referans %43 → **%15 altı**.

---

### Faz D — Sunucu tarafı enflasyon guard'ı

**Maliyet: sıfır.** Deterministik, model çağrısı yok. Mevcut `applyInspectionLayerEvidenceGuard` ile aynı desende.

`fk_severity >= 40` iddiası, bulgunun bağlı olduğu denetim katmanı ölümcül mekanizma taşıyan bir sette değilse (yükseklik, elektrik, makine, kaldırma, kimyasal, yangın-patlama, kazı) **15'e indirilir** ve `severity_downgraded` telemetrisi yazılır.

Bu, düzen-tertip veya ergonomi bulgusunun 40 puan almasını yapısal olarak engeller. Flag arkasında, ölçülebilir, tek yazımla kapatılabilir.

**Şu an ölçülemiyor** — kaç bulgunun bu kurala takılacağını Faz A sonrası ölçüp karar vermek daha doğru. Faz A tek başına enflasyonu düşürürse D gereksiz kalabilir.

---

### Faz E — Repair bütçesini derinliğe aktar

Repair pasosu bugün **13 koşuda 4 bulgu** ekledi; son 7 koşuda **0**. Girdi maliyeti ~6.400 token, çıktı ~2.000, düşünme 739–3.034.

Öneri: repair'i **yalnız sıfır bulgulu fotoğrafta** çalıştır. Orada gerçek bir işi var (`ai_zero_finding_reexamination_v1` ile `checked_no_hazard` yeniden açılıyor) ve henüz prod'da ateşlenmedi. `low_finding_count` ve `multi_layer_finding` tetikleyicileri kaldırılır — bunlar bir şey üretmiyor.

Beklenen etki: repair her analizde değil, **2-3 analizde bir** çalışır.

#### Maliyet muhasebesi (3 fotoğraf)

| | girdi | çıktı + düşünme |
|---|---|---|
| **Bugün** (paso 1 + her seferinde repair) | ~10.900 | ~9.300 |
| **Sonra** (zengin paso 1, repair 1/3 sıklıkta) | ~6.600 | ~11.600 |

Girdi **düşüyor** (repair'in fotoğrafları ve önceki bulguları tekrar göndermesi kalkıyor), çıktı ~%25 artıyor. Toplam maliyet bugünküne **yakın veya biraz altında**, çıktı derinliği iki kattan fazla.

Fan-out'un 2× maliyeti ile karşılaştır: bu yol **~1×** maliyetle derinlik ve skor kalitesi veriyor. Bulgu *sayısını* fan-out kadar artırmaz — o varyans işi, ayrı problem.

---

## 5. Ölçüm kapıları

Her faz sonrası, en az 10 analiz:

| Metrik | Bugün | Hedef |
|---|---|---|
| Olasılıkta en sık değerin payı | 61.3% | **< 40%** |
| high + critical bant payı | 49.1% | **< 35%** |
| Ölüm sınıfı şiddet (≥40) payı | 48.5% | **< 30%** |
| Farklı kategori sayısı | 84 | **12** |
| Türkçe analizde İngilizce kategori | var | **0** |
| Referansı boş bulgu | 43% | **< 15%** |
| Kalıntı riski dolu bulgu | 0% | **> 95%** |
| Bulgu başına ortalama önlem | 2.0 | **> 2.8** |
| Çıktı token kullanımı | %12 | **%25–30** |
| Toplam maliyet | 1× | **≤ 1.1×** |

Bulgu **sayısı** hedefi yok — bu plan sayıyı değil derinliği ve skor ayırt ediciliğini hedefliyor.

---

## 6. Sıra ve risk

| Faz | Etki | Risk | Geri alma |
|---|---|---|---|
| **A** skor kalibrasyonu | Yüksek | Düşük | prompt geri al |
| **B** kategori enum | Orta | Düşük | şemadan enum çıkar |
| **C** derinlik | Yüksek | Orta | prompt + kod geri al |
| **D** enflasyon guard | Orta | Orta | flag |
| **E** repair daraltma | Maliyet | Düşük | tetikleyicileri geri ekle |

**Önerilen sıra: A → ölç → B → C → ölç → E → (gerekirse) D.**

A tek başına en yüksek getirili ve en düşük riskli adım: tek bir prompt bloğu, ölçülebilir hedef, anında geri alınabilir.

### Riskler

- **C2 kontrol hiyerarşisi** çıktıyı uzatır; `max_output_tokens` 24.500 olduğu için yer sorunu yok ama `finish_reason` izlenmeli
- **C3 kalıntı risk** modelden yeni bir muhakeme istiyor; tutarsız çıkarsa sunucu sağlaması yakalar ama bulgu başına 3 alan daha demek — şema büyümesi Gemini'nin "too many states" hatasını geri getirebilir, Faz C sonrası `coverage_schema_fallback_used` izlenmeli
- **B kategori enum** mevcut analizlerin kategorilerini değiştirmez, sadece yenileri; raporlarda karışık taksonomi bir süre yaşar
- **A3 şiddet kuralı** fazla sıkı olursa gerçek ölümcül riskler düşer — bu yüzden hedef %30, sıfır değil

---

## 7. Kapsam dışı

- Fotoğraf başına ayrı çağrı — maliyet gerekçesiyle reddedildi
- Tekrarlı örnekleme / varyans azaltma — ayrı problem, ayrı maliyet
- `bounding_box` doldurma — istemci gösterimi gerektirir, build işi
- `responsible` / `deadline` otomatik doldurma — hukuki sorumluluk taşır; kullanıcı düzenlemesi olarak bırakılmalı, öneri değeri istenirse ayrı karar
- Uzman derinliği (`ai_expert_depth_v1`) — halted, ayrı çağrı olmadan açılamayacağı ölçüldü

---

## 8. Açık kararlar

1. **A ile başlansın mı?** Tek prompt bloğu, sıfır maliyet, ölçülebilir.
2. **A4 `score_rationale` alanı** eklensin mi? Bulgu başına ~40 token, karşılığında parametre disiplini.
3. **C3 kalıntı risk** Excel/PDF raporlarına da eklensin mi? Sunucu tarafı, build gerekmez, ama rapor şablonu değişir.
4. **D enflasyon guard'ı** Faz A sonrası ölçüme bırakılsın mı, yoksa birlikte mi?
5. **`responsible` / `deadline`** için öneri değeri üretilsin mi, yoksa boş kalıp kullanıcı mı doldursun?
