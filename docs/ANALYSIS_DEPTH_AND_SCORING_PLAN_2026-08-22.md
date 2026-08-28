# Mevcut çağrı bütçesiyle analiz derinliği ve risk skoru kalitesi — revize plan

**Tarih:** 2026-08-23
**Revizyon:** Kod/veri doğrulaması sonrası v3 — hızlandırılmış shadow rollout
**Durum:** öneri, uygulanmadı
**Kısıt:** yeni model çağrısı yok, fotoğraf başına fan-out yok, zorunlu mobil build yok
**İlgili:** `FANOUT_PER_PHOTO_ANALYSIS_PLAN_2026-08-22.md`, `ANALYSIS_QUALITY_ADDENDUM_2026-08-21.md`, `ANALYSIS_QUALITY_RECOVERY_PLAN_2026-08-21.md`

---

## 1. Amaç ve karar özeti

Bu planın amacı modelden daha uzun metin almak değil; aynı çağrı içinde şu dört kaliteyi yükseltmektir:

1. **Görsel doğruluk:** yalnız fotoğrafta desteklenen tehlikeyi yazmak
2. **Uzman derinliği:** bariz bulguların yanında mekanik/proses ayrıntılarını yakalamak
3. **Risk kalibrasyonu:** Fine-Kinney ve 5×5 girdilerini görünür kanıt ve açık varsayımla gerekçelendirmek
4. **Kontrol kalitesi:** tekrar etmeyen, kontrol hiyerarşisine uygun ve uygulanabilir önlemler üretmek

Ana kararlar:

- `maxOutputTokens` doluluk oranı kalite veya tasarruf KPI'ı değildir. Bu değer bir **üst sınırdır**; çıktı maliyeti kullanılan token üzerinden artar.
- `finish_reason = STOP`, kesilme olmadığını gösterir; tek başına kısa prompt kurallarının kalite kaybının kök nedeni olduğunu kanıtlamaz. Bunu ancak eşlenik A/B ölçümü gösterebilir.
- Başarı hedefi “daha uzun çıktı”, “daha çok önlem” veya “high/critical oranını belli bir yüzdeye indirmek” değildir. Hedef, **İSG uzmanıyla uyum**, **kanıt precision'ı**, **kritik tehlike recall'ı** ve **doğru risk sıralaması**dır.
- Ham model olasılığının `P=3` üzerinde `101/164 = %61.6` yığılması, `3` değerinin yanlış olduğunu kanıtlamaz; modelin bu parametrede yeterince ayrım yapmadığını gösteren güçlü bir **dejenerasyon sinyalidir**.
- Gold set, A1+A2'nin kontrollü shadow deneyini başlatmak için önkoşul değildir. Ancak yeni rubric'in skorlarının doğru olduğunu söylemek ve kullanıcıya yansıyan skoru değiştirmek için yayın otoritesidir.
- Skor dağılımı bir **shadow teşhis/drift sinyali** olabilir; gerçek saha dağılımı bilinmeden kalite hedefi veya production yayın kapısı olamaz.

---

## 2. Ölçüm tabanı ve önce düzeltilmesi gereken yorumlar

Son 30 gündeki kayıtlar ham snapshotta 164, final bulgu tablosunda 163 satır içeriyor. Kod ve veri yolu birlikte incelendiğinde doğrulanmış başlangıç tablosu şöyledir:

| Sinyal | Ham model | Final / uygun kohort | Yorum |
|---|---:|---:|---|
| `fk_probability = 3` | `101/164 = %61.6` | `100/163 = %61.3` | Kusur model davranışında; sunucu P'ye dokunmuyor |
| `fk_severity >= 40` | `%40.9` | `%48.5` | Modelde enflasyon sinyali var; server height-fatality guard final metriği ayrıca yükseltiyor |
| Boş referans | toplu oran anlamlı değil | Plus/TR `%4.5`, Pro/TR `%0` | Eski `%43` kusur iddiası kohort karışımından kaynaklanıyor |

Şiddette ham ve final satır sayısı aynı olmadığı için server etkisi yalnız iki yüzdeliğin çıkarılmasıyla ölçülmemelidir. Her finding için raw→final eşleşmesi ve `reason_code` raporlanmalıdır.

### 2.1 Zorunlu kohort ayrımları

Her metrik en az şu boyutlarda kırılmalı:

- model, provider ve prompt sürümü
- plan (`free` / `plus` / `pro`)
- çıktı dili ve safety profile
- `structured_regulatory_references_enabled`
- tek/çok fotoğraf
- sektör ve analiz modu
- ilk model çıktısı ile sunucu-normalize edilmiş final değer
- kullanıcı tarafından düzenlenmiş/düzenlenmemiş bulgu

Özellikle:

- Free veya referans özelliği kapalı profillerde boş `references_text` kalite kusuru değildir.
- Veritabanındaki final şiddet, modelin ham şiddeti olmayabilir. `calibratedRiskInputs()` görünür yükseklik/düşme deseninde şiddeti en az 40'a çıkarıyor. Ham model değeri ile sunucu sonrası değer ayrı ölçülmelidir.
- `needs_field_verification` model boolean'ından doğrudan gelmiyor. Sunucu sıradan bulgularda bunu esas olarak `confidence ∈ [0.50, 0.70)` aralığından türetiyor. Başlıkta “belirsizlik” yazması ile final boolean arasındaki farkın bir bölümü buradan geliyor.
- 163 bulgu bağımsız 163 örnek değildir; aynı analizin bulguları korelasyonludur. Güven aralıkları analiz seviyesinde bootstrap edilmelidir.

### 2.2 Uzman gold set: yayın otoritesi, shadow önkoşulu değil

İki ayrı soru birbirine karıştırılmamalıdır:

1. **Model P değerlerini ayırt ediyor mu?** Tek değerin payı, entropi ve rationale çeşitliliğiyle uzman olmadan shadow ortamında ölçülebilir.
2. **Üretilen P/F/S değerleri doğru mu?** Bu soru uzman ground truth'u gerektirir.

Bu nedenle A1+A2 shadow deneyi beklemeden başlayabilir; aynı anda küçük fakat güvenilir bir gold set kurulmalıdır:

- En az **30–50 analiz**, mümkünse **100+ fotoğraf**
- En az 10 zor analiz üç kez tekrar çalıştırılarak varyans ölçümü
- Bulgular varyant adı gizlenerek İSG uzmanına değerlendirilir
- Yüksek/kritik ve ekipman/proses alt kümesi ikinci uzman tarafından da etiketlenir
- Anlaşmazlıklar üçüncü değerlendirme veya ortak adjudication ile çözülür
- Prompt ayarı geliştirme setinde; son karar ayrı holdout setinde yapılır

Gold kayıt başına en az:

- görünür tehlike ve kaynak fotoğraf(lar)
- kanıtlanan zarar mekanizması
- bağımsız düzeltilebilir fiziksel koşul kimliği
- uzman P/F/S girdileri ve kabul edilebilir komşu değerler
- ölümcül/çoklu ölüm mekanizması varlığı
- saha teyidi gerektiren varsayımlar
- uygun kontrol hiyerarşisi
- geçerli mevzuat/standart referansı veya “referans verilmemeli” kararı

---

## 3. Ölçülen kusurların revize yorumu

### 3.1 Olasılık ve frekans kalibrasyonu eksik — ana doğrulanmış kusur

`ai_original_snapshot` içindeki ham bulguların `101/164 = %61.6`'sında `fk_probability = 3` bulunuyor. Finalde oran `100/163 = %61.3`; sunucu olasılığa dokunmuyor. Bu, server kontaminasyonundan bağımsız ve bugün deney yapılmasını hak eden ana kusurdur.

Bu dağılım tek başına `P=3` değerinin yanlış olduğunu göstermez. Gösterdiği şey, modelin olasılık parametresini örnekler arasında ayırt etmekte isteksiz veya yetersiz olduğudur. A1+A2 shadow deneyinde yığılmanın azalması gerekli bir teknik sinyal olabilir; skor doğruluğunun kanıtı değildir.

Önerilecek cetvelde olasılık ve frekans birbirine karıştırılmamalıdır.

Fine-Kinney ayrımı:

- **Olasılık (P):** tek bir maruziyet anında, mevcut görünür bariyerler altında olayın gerçekleşme ihtimali
- **Frekans (F):** kişinin/kişilerin tehlikeli duruma ne sıklıkla maruz kaldığı
- **Şiddet (S):** olay gerçekleşirse makul en ağır sonuç

“Koruma yok ve maruziyet sürekli” ifadesi P içinde kullanılmamalıdır; “maruziyet sürekli” F bilgisidir ve iki çarpanda birden kullanılırsa skor şişer.

Tek fotoğraftan F çoğu zaman güvenilir biçimde çıkarılamaz. Çalışma istasyonu veya geçiş yolu görünmesi günlük kullanımın kanıtı değildir. Frekans dayanağı yoksa rastgele `3 = haftalık` seçmek yerine:

- `frequency_basis = unknown_from_photo` işaretlenmeli
- `needs_field_verification = true` olmalı
- kullanılacak provisional F değeri İSG uzmanının onayladığı, sürümlenmiş politika ile belirlenmeli
- kullanıcıya gösterilen sonuçta bunun tahmin olduğu anlaşılmalı

### 3.2 Şiddet enflasyonu var; ham model ve server etkisi ayrılmalı

Ham model bulgularında `fk_severity >= 40` oranı `%40.9`; final bulgularda `%48.5`. Önceki `%48.5 model şiddeti` yorumu bu nedenle abartılıydı. Yine de `%40.9` araştırılması gereken güçlü bir model sinyalidir. Olası kaynaklar:

- prompttaki tek örneğin `P=6, F=6, S=100` olması
- modelin ölümcül sonucu varsayılan “makul en ağır sonuç” gibi kullanması
- sunucunun yükseklik deseninde şiddeti en az 40'a yükseltmesi
- sektör/fotoğraf örnekleminin gerçekten yüksek risk ağırlıklı olması

Bu yüzden “ölüm sınıfı <%30” veya “high+critical <%35” kalite hedefi yapılmamalı. Doğru kapılar:

- uzmanla şiddet exact/adjacent agreement
- ölümcül olmayan bulgunun 40/100 alması: over-score
- ölümcül bulgunun 15 ve altı alması: kritik under-score
- bulgular arası risk sıralamasının uzman sıralamasıyla uyumu

### 3.3 Kontrol hiyerarşisi içerikte var, çıktı sözleşmesinde yok

Safety profile promptlarında kontrol hiyerarşisi bulunuyor; ancak üretim çıktısı bunu yapısal olarak korumuyor. `normalizeRecommendedMeasures()` bir düzeltici ve bir önleyici olmak üzere tam iki kayıt oluşturuyor ve modelden gelebilecek ek listeyi etkin biçimde kullanmıyor.

Sorun “iki önlem az” değildir. İki iyi ve farklı önlem, beş tekrarlı önlemden değerlidir. Önce şu semantik kalite sağlanmalı:

- düzeltici eylem: mevcut alanı hemen güvenli duruma getiren somut adım
- önleyici kontrol: tekrarı engelleyen kalıcı ve mümkün olan en üst seviye kontrol
- KKD, daha üst kontroller mümkünken tek kalıcı çözüm olamaz
- high/critical bulguda durdurma/izolasyon kriteri açık olmalı
- aynı eylem farklı kelimelerle tekrar edilmemeli

Değişken 2–5 maddelik `recommended_measures_v2` ancak bu semantik iyileştirme ölçüldükten sonra eklenmelidir. Sabit madde sayısı veya ortalama 2.8 üstü kalite hedefi olmamalıdır.

### 3.4 Kalıntı risk alanları var, fakat uçtan uca taşıma yok

`findings` tablosunda residual kolonları hazır. Bununla birlikte yalnız model şemasına alan eklemek yetmez:

- `findingRows` residual girdileri yazmıyor
- `finalize_analysis_result_v2` RPC'sinin explicit `INSERT` kolonları residual alanları taşımıyor
- `register-report` snapshot select'i residual alanları okumuyor
- `generate-excel-report` türleri ve çalışma sayfaları residual skoru göstermiyor
- mobil bulgu modelleri residual alanları göstermiyor

Dolayısıyla yeni tablo kolonu gerekmese de **SQL migration ile RPC değişimi**, Edge Function değişiklikleri ve rapor testleri gerekir. Mobil sonuç ekranında göstermek istenirse ayrıca build gerekir; yalnız sunucu PDF/Excel çıktısı build gerektirmeyebilir.

Kalıntı risk, gerçekleşmiş bir ölçüm değil **önerilen kontroller eksiksiz uygulanırsa beklenen risk** olarak adlandırılmalıdır.

### 3.5 84 serbest kategori gerçek bir taksonomi problemi

12 inspection layer iyi bir üst kategori eksenidir; fakat uzman analitiği ve mevzuat eşlemesi için tek başına fazla geniştir. İki eksen önerilir:

1. `primary_category_key`: 12 kanonik inspection layer'dan biri
2. `hazard_type_key`: daha ayrıntılı, sürümlenmiş tehlike türü (`open_edge_fall`, `exposed_conductor`, `missing_hook_latch`, `unstable_stack` gibi)

İlk rolloutta yalnız `primary_category_key` zorunlu olabilir. Mevcut `category` alanı istemci uyumluluğu için sunucuda bu anahtardan lokalize etikete dönüştürülür. Modelin raw anahtarı doğrudan kullanıcıya gösterilmez.

Bir bulgu birden fazla inspection layer taşıyabilir; `primary_category_key`, bulgunun ana fiziksel tehlikesini temsil eden layer olmalı. Yalnız `inspection_layer_keys[0]` değerine körlemesine güvenilmemeli; server normalization açık bir öncelik kuralı kullanmalıdır.

### 3.6 Referans boşluğu aktif kusur değil; precision ilkesi guardrail olarak kalmalı

Toplu `%43` boş referans metriği tier/profile karışımı nedeniyle geçersizdir. Doğrulanmış kırılım:

| Plan / dil | Bulgu | Boş referans |
|---|---:|---:|
| Plus / TR | 89 | `%4.5` |
| Pro / TR | 8 | `%0` |
| Free / TR | 45 | `%100` — tasarım gereği |
| Plus / EN | 12 | `%100` — profil referansa izin vermiyor |

Referansın beklendiği uygun kohortta coverage `%95.5` seviyesindedir. Dolayısıyla bu çalışma acil kalite kusurları arasından çıkarılır. Buna rağmen “emin değilse genel yönetmeliği yaz” gibi bir kural eklenmemelidir; boş oranını düşürürken alakasız veya yanıltıcı boilerplate'i artırabilir.

Öncelik sırası:

1. Referans doğru ve ilgili olmalı
2. Safety profile ilgili yargı alanında referansa izin vermeli
3. Emin olunmayan madde/standart numarası yazılmamalı
4. Coverage ancak precision korunduktan sonra artırılmalı

Uzun vadede precision/ilgililik sorunu ölçülürse model serbest metni yerine, `hazard_type_key + safety_profile_id` üzerinden uzman-onaylı referans kataloğu değerlendirilebilir. Mevcut veriyle acil rollout maddesi değildir.

### 3.7 Seyrek skor kafesi tek başına kusur değildir

Fine-Kinney girdileri ayrık değerlerden oluştuğu için bazı skor aralıklarının hiç oluşmaması beklenir. Asıl sorun:

- aynı P/F/S kombinasyonunda aşırı yığılma
- çok sayıda eşit skor nedeniyle sıralama ayırt ediciliğinin düşmesi
- uzman sıralamasıyla uyumsuzluk

Ölçümler: kombinasyon entropisi, en sık kombinasyon payı, tie-rate ve uzmanla pairwise ranking agreement.

### 3.8 Belirsizlik kontratı tutarsız

Başlığında “belirsizlik” geçen bir bulgunun yüksek confidence alması ve finalde `needs_field_verification=false` olması mümkündür; çünkü server model boolean'ını değil confidence bandını esas alır.

Revize kural:

- Bulgu başlığı belirli fiziksel tehlikeyi söyler; “durumu/belirsizliği” gibi soyut başlık kullanılmaz.
- Görünür bir tehlike var ama ayrıntı belirsizse confidence en fazla 0.69 ve `needs_field_verification=true`.
- Tehlikenin kendisi görünmüyor, yalnız kontrol kaydı/etiket okunamıyorsa fiziksel bulgu değil `field_verification_item` üretilir.
- Validator, metin/score basis ile confidence arasındaki çelişkiyi telemetriye yazar ve güvenli biçimde normalize eder.

### 3.9 Sorumlu ve termin model tarafından uydurulmamalı

`responsible` ve `deadline` finding kolonlarının boş olması tek başına AI kalite kusuru değildir. Firma düzeyinde `default_responsible/default_due_days` var. Excel'de Fine-Kinney skor→eylem→termin için bir **legend tablosu** bulunuyor (`1801 ≤ R` → “Hemen / 1 hafta” gibi); fakat bu değer finding satırına hesaplanıp yazılmıyor.

Öneri:

- sorumlu: yalnız kullanıcı/firma varsayılanından
- termin: mevcut yayımlanmış legend politikasından deterministik biçimde türetilen “öneri”; finding alanına yazılması yeni politika tasarımı değil küçük bir ürün/veri adımıdır
- model kişi/rol veya hukuki sorumlu atamasın

---

## 4. Revize uygulama planı

### Faz 0 — Ölçüm otoritesi ve sürümleme

**Maliyet:** sıfır model çağrısı.
**Amaç:** yanlış metriği optimize etmemek.

Faz 0'ın tamamı sıfırdan yapılmayacak. Bugün:

- `ai_original_snapshot` ham model P/F/S değerlerini saklıyor
- `findings` final server değerlerini saklıyor
- mevcut kayıtlarla raw `%61.6` / final `%61.3` olasılık yığılması ölçülebiliyor

Eksik olan, bunu tekrarlanabilir ve sürüm karşılaştırmalı hâle getirmektir. Eklenecek/standartlaştırılacak audit alanları:

- `risk_scoring_policy_version`
- `scoring_experiment_id` ve `scoring_variant`
- `category_taxonomy_version`
- `control_policy_version`
- `reference_policy_version`
- snapshot raw P/F/S → finding final P/F/S eşleştirmesi
- her server değişikliği için reason code
- `frequency_basis`
- `schema_fallback_used`, çıktı/düşünme tokenı ve finish reason

Mevcut 164 raw / 163 final kayıt yeniden raporlanır; Free/referans-kapalı ve kullanıcı-düzenlenmiş satırlar uygun metriklerden çıkarılır. Aynı analiz içindeki korelasyon korunur.

**Kabul:** her skorun model raw değeri ile final server değeri eşleştirilebiliyor; prompt/policy varyantı belli; metrikler analiz bazında tekrar üretilebiliyor.

---

### Faz A — Risk skorlama v2

#### A1. P/F/S cetvellerini ayır

Taslak aşağıdadır. Kontrollü shadow ayrım deneyi uzmanı beklemeden başlayabilir; cetvelin üretim skoru için doğru otorite sayılması İSG uzmanı onayı gerektirir:

```
Fine-Kinney OLASILIK (P) — tek bir maruziyet anında olayın gerçekleşme ihtimali:
- 10 = Olayı önleyecek etkili bariyer yok; olay olağan koşulda beklenir.
- 6  = Bariyer yok, bozuk veya kolayca aşılabilir; olay oldukça mümkündür.
- 3  = Kısmi bariyer var; tek hata/ihlal ile olay mümkündür.
- 1  = Etkili bariyer var; olay için birden fazla olumsuz koşul gerekir.
- 0.5 = Birden fazla bağımsız ve görünür bariyer vardır.
- 0.2 = Olay ancak istisnai bir zincirle teorik olarak mümkündür.

Fine-Kinney FREKANS (F) — tehlikeli duruma maruziyet sıklığı:
- 10 = Sürekli / vardiyanın büyük bölümü
- 6  = Günlük
- 3  = Haftalık
- 2  = Aylık
- 1  = Yılda birkaç kez
- 0.5 = Çok seyrek

Fotoğraf maruziyet sıklığını göstermiyorsa F için kesinlik iddia etme.
frequency_basis="unknown_from_photo" kullan, needs_field_verification=true yap
ve yalnız sürümlenmiş provisional frekans politikasını uygula.
```

#### A2. Maksimum çapa örneğini kaldır

`P=6, F=6, S=100` tek örnek olarak kalmamalı. Tercih sırası:

1. Tam sayısal örneği kaldırıp yalnız rubric kullanmak
2. Gerekirse düşük/orta/yüksek/kritik sınırlarını gösteren kısa ve kontrastif örnekler
3. Her örnekte “neden bu değer, neden bir üst değer değil?” açıklaması

Maksimum çapanın kaldırılması uzmanı beklemeden shadow ortamında denenebilir. Production promptuna girecek kontrastif örnekler regression fixture'lardan seçilmeli ve İSG uzmanı tarafından puanlanmalıdır.

#### A2-shadow. Hızlı ayrım deneyi

Bu plandaki **shadow**, aynı production analizi için ikinci model çağrısı yapmak anlamına gelmez. Şu iki yoldan biri kullanılır:

1. geçmiş sabit fotoğrafları kontrollü evaluation job'ında yeni promptla bir kez replay etmek, veya
2. yalnız iç test/allowlist analizlerini tek çağrıyla yeni varyanta yönlendirip skoru kullanıcı ve kalıcı finding otoritesi yapmadan saklamak

Baseline: ham `P=3` payı `101/164 = %61.6`.

Shadow iterasyon sinyalleri:

- en sık P değerinin payı ve P kombinasyon entropisi
- P'nin tehlike mekanizması/görünür bariyer katmanlarında ayrışması
- geçersiz P/F değeri ve schema fallback oranı
- aynı fixture'da tekrarlar arası stabilite
- evidence precision için mevcut otomatik guard regresyonu
- çağrı başına token, süre ve hata oranı

**Shadow ilerleme kriteri:** tek değerdeki yığılma birden fazla fixture/stratada düşer, geçersiz değer veya teknik regresyon oluşmaz. Bu sonuç yalnız “model artık daha çok ayrım yapıyor” demektir; “yeni skorlar doğru” veya “productiona yayınlanabilir” demek değildir.

#### A3. Kısa skor dayanağı

İlk sürümde şema patlamasını sınırlamak için iki kısa alan:

```
score_rationale: "P: koruyucu yok; F: fotoğraftan bilinmiyor; S: 4 m düşme tek ölüm doğurabilir"
frequency_basis: "unknown_from_photo"
```

`score_rationale` kullanıcıya hemen gösterilmese bile `ai_original_snapshot` ve evaluation kayıtlarında saklanır. Kalıcı kullanıcı alanı veya rapor sütunu yapılacaksa ayrı DB/report kontratı gerekir.

#### A4. Kanıt-temelli server guard

Kategoriye göre kör downscore yapılmaz. Bunun yerine:

- `S=100`: aynı olayda birden fazla kişinin ölümünü destekleyen görünür maruziyet + escalation mekanizması gerekir
- `S=40`: tek ölüm/kalıcı iş göremezliğe giden somut zarar mekanizması gerekir
- frekans dayanağı yoksa verification zorunlu
- model P/F/S ile rationale çelişiyorsa reason code yazılır
- height fatality mevcut hard-coded yükseltmesi raw/final telemetri ile ayrıca ölçülür

Guard ilk etapta **shadow** çalışır. Uzman gold karşılaştırması olmadan otomatik downscore açılmaz.

#### A5. Fine-Kinney / 5×5 tutarlılığı

İki yöntem birbirinden bağımsız rastgele sayılar üretmemeli. İSG uzmanının onayladığı bir crosswalk sürümlenir:

- FK şiddet → 5×5 şiddet
- FK olasılık/frekans bağlamı → 5×5 likelihood
- uyumsuz çiftler normalize edilir ve telemetriye yazılır

**Faz A production kabulü:** hedef dağılım yüzdesi değil; uzman exact/adjacent agreement iyileşir, kritik under-score artmaz, over-score azalır. A1+A2 shadow iterasyonu bu nihai kapıdan önce yürüyebilir ama onu geçersiz kılamaz.

---

### Faz B — Kanonik taksonomi ve görsel grounding

#### B1. Geriye uyumlu kategori anahtarı

- Model `primary_category_key` üretir; enum 12 inspection layer ile sınırlıdır.
- Mevcut `category` kullanıcı alanı server tarafından aktif dile göre lokalize edilir.
- Geçersiz anahtar sonucu terminal hataya çevrilmez; normalize edilir, `category_normalized=true` yazılır.
- Eski serbest kategori metni için alias tablosu hazırlanır; geçmiş kullanıcı metni körlemesine yeniden yazılmaz.

#### B2. Ayrıntılı tehlike türü

Kategori rolloutundan sonra, uzman-onaylı küçük bir `hazard_type_key` taksonomisi pilotlanır. Amaç:

- skor kalibrasyonunu mekanizmaya bağlamak
- mevzuat eşlemesini güvenilir yapmak
- “kanca mandalı”, “açık iletken”, “dengesiz istif” gibi uzman bulgularını ölçmek
- benzer ama bağımsız tehlikeleri dedup sırasında ayırmak

İlk sürümde geniş enum yerine en sık 20–30 tür + `other` kullanılabilir. Şema karmaşıklığı nedeniyle `coverage_schema_fallback_used` izlenir.

#### B3. Kanıt izi ve opsiyonel bbox shadow

Her bulguda:

- kaynak fotoğraf indeksi
- somut `observed_evidence`
- mümkünse normalize edilmiş kanıt bölgesi

zorunlu tutulur. `bounding_box` istemcide gösterilmese bile shadow olarak toplanabilir; bu mobil build gerektirmez ve offline QA/dedup için değerlidir. Ancak doğruluğu kanıtlanmadan kullanıcıya gösterilmez.

---

### Faz C — Aynı çağrıda uzman derinliği

#### C1. Uzunluk yerine bilgi yoğunluğu

Karakter tavanları kontrollü biçimde gevşetilir; fakat `description=500` gibi hedefler kalite amacı değildir.

Alan sözleşmesi:

- `observed_evidence`: ne ve nerede görülüyor
- `description`: tehlike mekanizması ve makul sonuç; evidence'i tekrar etmez
- `root_cause`: fotoğraftan kesin neden uydurmaz; “muhtemel katkı” dili
- `corrective_action`: hemen güvenli duruma alma/durdurma/izolasyon
- `preventive_control`: kalıcı üst-seviye kontrol ve tekrar önleme

Başlangıç tavanları pilotla belirlenir; hedef uzunluk değil, tekrar oranının düşmesi ve uzman completeness skorunun artmasıdır.

#### C2. İki alanı önce gerçekten kaliteli yap

Şema büyütmeden:

- corrective action mümkün olan en üst kontrol seviyesinden başlar
- preventive control kalıcı mühendislik/sistem kontrolünü tarif eder
- high/critical bulguda iş durdurma veya güvenli izolasyon kriteri bulunur
- KKD tek kalıcı kontrol olamaz
- iki alan semantik olarak tekrar ederse validator işaretler

#### C3. Değişken önlem listesi ancak ikinci adımda

İki alan yeterli kaliteyi vermiyorsa `recommended_measures_v2` flag'i eklenir:

- 1–4 ayrı ve tekrar etmeyen kontrol; sayı banda göre zorlanmaz
- `kind`: corrective/preventive
- `hierarchy`: elimination/substitution/engineering/administrative/ppe
- `text`: somut eylem
- en fazla birincil 4 madde; padding yasak

Mevcut istemciler ek maddeleri okuyabiliyor, fakat `hierarchy` etiketini göstermez ve finding edit akışı alanı korumuyor. Build'siz rolloutta hierarchy iç denetim alanı olur; kullanıcıya görünür hiyerarşi ve tam düzenleme için sonraki build gerekir.

#### C4. `ai_expert_depth_v1` yerine kompakt uzman ipuçları

Halted expert-depth şeması geri açılmaz. Bunun yerine mevcut 12 katmanın içine yeni çıktı yükümlülüğü getirmeyen kısa görsel ipuçları eklenir:

- kaldırma: kanca mandalı, halat tel kırığı/kuş kafesi, zincir deformasyonu, uygunsuz pim/bağlantı
- makine: açık dönen mil/kayış/kaplin, koruyucu, kilitleme elemanı, doğaçlama parça
- proses: görünür sızıntı/korozyon/deformasyon, gösterge hasarı, hortum/kelepçe, tahliye yönü, ankraj/çarpma koruması
- elektrik: açık kapak, rekor/IP bütünlüğü, hasarlı ek, su teması, erişim

Bu modül yalnız düşünme rehberidir; `equipment_depth_scan` veya 12 yeni process output kaydı istemez. Kanca mandalı, proses ekipmanı ve makine koruyucu regression fixture'larıyla ölçülür.

**Faz C kabulü:** uzman-hazard recall'ı artar; evidence precision ve schema başarı oranı gerilemez; output token artışı yalnız fayda başına ölçülür.

---

### Faz D — Önerilen kalıntı risk

#### D1. Semantik kontrat

Kalıntı risk şu varsayımla üretilir:

> Önerilen kontroller eksiksiz uygulanmış ve doğrulanmış olsaydı beklenen risk.

Kurallar:

- residual bileşenler mevcut bileşenlerden yüksek olamaz
- residual skorun **eşit kalmasına izin verilir**; etkisiz/jenerik kontrol için yapay düşüş zorlanmaz
- şiddet varsayılan olarak değişmez
- şiddet yalnız eliminasyon, ikame veya enerji/sonuç mekanizmasını gerçekten değiştiren mühendislik kontrolünde düşebilir
- idari kontrol ve KKD otomatik olarak büyük olasılık düşüşü yaratmaz
- residual gerekçesi kontrol maddelerine bağlanır
- kalıntı risk gerçekleşmiş ölçüm veya mevzuata uygunluk iddiası değildir

#### D2. Uçtan uca taşıma

- model response schema
- `findingRows`
- `finalize_analysis_result_v2` explicit kolonları için SQL migration
- deterministic fallback ve finding mutation davranışı
- `register-report` snapshot select
- PDF/Excel risk tablosunda “mevcut risk / önerilen kalıntı risk”
- TR/EN başlıkları ve L10N
- GENERATED kolonların insert edilmediğini doğrulayan testler

Kullanıcı bulguyu veya kontrolleri düzenlerse residual değerlerin eski kalması güvenli değildir. Mutation politikası:

- risk girdisi veya önlem değişince residual alanlar temizlenir, ya da
- kullanıcı ayrıca residual girdileri düzenleyebilen yeni kontrata sahipse birlikte güncellenir

Build'siz ilk rollout yalnız yeni AI bulguları ve sunucu raporlarıyla sınırlandırılabilir.

---

### Faz E — Referans kalitesi (aktif rollout dışı guardrail/backlog)

#### E1. Ölçümü temizle

Coverage metriği yalnız referans özelliği açık Plus/Pro ve ilgili safety profile kayıtlarında hesaplanır.

Mevcut uygun kohort coverage'ı `%95.5` olduğu için bu faz acil kusur düzeltmesi değildir. Önce precision/ilgililik örneklemi alınır; sorun kanıtlanmazsa yeni ürün işi açılmaz.

#### E2. Precision-first politika

- spesifik madde/standart yalnız yüksek güvenle
- emin değilse alakasız genel yönetmelik yazılmaz
- boş referans yanlış referanstan daha güvenlidir
- yasaklı yargı alanı/uyumluluk iddiası validator tarafından reddedilir

#### E3. Uzman-onaylı katalog

`hazard_type_key + safety_profile_id + profile_version` anahtarından deterministik aday referanslar üretilir. Model yeni mevzuat numarası icat etmez; yalnız katalogdaki seçenekleri ilgili bulguya bağlar.

**Aktivasyon koşulu:** uzman örnekleminde precision/ilgililik problemi veya uygun kohortta anlamlı coverage regresyonu görülmesi. Aksi hâlde mevcut davranış korunur.

---

### Faz F — Repair'i beklenen değerle daralt

13 repair'de 4 ek bulgu ve son 7 koşuda 0 ek bulgu, optimizasyon sinyalidir; fakat trigger silmek için örneklem küçüktür.

Önce trigger bazında ölç:

- çağrı sayısı
- eklenen ve uzman tarafından doğru bulunan bulgu
- duplicate/unsupported ret
- token ve süre
- kritik tehlike kazanımı

Başlangıç politika önerisi:

- **koru:** `zero_finding_photo`, `record_incomplete`, yüksek değerli temsil edilmemiş actionable layer/process check
- **tek başına zayıf sinyal:** `low_finding_count`, `multi_layer_finding`, `excessive_not_visible`
- **birleşik tetikleyici:** zayıf sinyal + aday boşluğu/evidence guard reddi/yüksek riskli ekipman ipucu

Trigger'lar önce `would_repair` shadow telemetrisiyle daraltılır. Gold sette recall kaybı göstermeden production çağrısı kapatılmaz.

Maliyet tablosundaki “repair 1/3 sıklıkta” ve “toplam ≤1.1×” değerleri şu an hipotezdir; kabul kriteri değil. Gerçek maliyet, aynı model/prompt/kohortta ölçülen başarılı analiz başına token ve provider faturasıyla doğrulanır.

---

## 5. Ölçüm ve yayın kapıları

Üç ölçüm seviyesi vardır:

1. **Shadow teşhis:** model bir parametreyi ayırt ediyor mu? Dağılım, entropi ve stabilite kullanılır; uzman gerekmez.
2. **Kalite doğrulaması:** ayrıştırılan değerler doğru mu? Uzman gold set gerekir.
3. **Production yayını:** kullanıcıya yansıyan skor güvenli mi? Gold/holdout, kritik under-score ve operasyon kapıları gerekir.

İlk 10 analiz yalnız teknik smoke testtir. A1+A2 shadow iterasyonu için gold set beklenmez. Kullanıcıya yansıyan skor değişikliğinin go/no-go kararı için gold set ve en az 30–50 analiz gerekir.

| Boyut | Ana metrik | Önerilen kapı |
|---|---|---|
| P ayrıştırma — shadow | en sık ham P payı + entropi + strata ayrışması | iterasyon sinyali; baseline `%61.6` yığılmadan belirgin iyi, production kapısı değil |
| Görsel doğruluk | uzman-onaylı evidence precision | ≥%95; baseline'dan >3 puan gerileme yok |
| Kritik kapsama | yüksek/kritik uzman bulgusu recall | baseline'dan gerileme yok; hedef anlamlı artış |
| P/F/S kalibrasyonu | exact veya bir komşu değer agreement | baseline'a karşı istatistiksel iyileşme |
| Kritik under-score | uzman S≥40 iken final S≤15 | 0 |
| Çoklu ölüm over-score | uzman çoklu ölüm mekanizması yokken S=100 | belirgin düşüş; holdoutta sıfıra yakın |
| Risk sıralaması | uzmanla pairwise ranking agreement | baseline'dan anlamlı yüksek |
| Güven kalibrasyonu | confidence reliability / ECE | baseline'dan iyi |
| Belirsizlik | gerekli saha teyidini işaretleme recall | ≥%95 |
| Kontrol kalitesi | uzman uygulanabilirlik + tekrar etmeme | ≥%90 kabul |
| Kontrol hiyerarşisi | high/critical için üst-seviye kontrol veya gerekçe | ≥%90 |
| Residual | mantıksal tutarlılık ve kontrolle bağ | ≥%95 |
| Referans | geçerlilik + ilgililik precision | ≥%98; yalnız uygun kohortta |
| Taksonomi | geçerli primary key | >%99, terminal hata yok |
| Şema | `coverage_schema_fallback_used` artışı | anlamlı artış yok |
| Operasyon | P95 süre ve timeout/429 | baseline sınırları içinde |
| Maliyet | başarılı analiz başına gerçek maliyet | iş hedefiyle belirlenen tavan; başlangıç hedefi ≤1.2× |

Şunlar yayın kapısı değildir:

- tek başına P dağılımı/entropisi; shadow ilerleme sinyalidir
- output token kullanım yüzdesi
- ortalama önlem sayısı
- high/critical bulguların sabit bir yüzdeye düşmesi
- ölüm şiddetinin sabit bir yüzdeye düşmesi
- farklı Fine-Kinney skor sayısının artması

---

## 6. Rollout sırası

1. **Hemen — minimal Faz 0:** mevcut `ai_original_snapshot` raw değerlerini final finding ile eşleştiren baseline sorgusunu sabitle; policy/experiment version ekle
2. **Hemen — A1+A2 shadow:** P/F rubric'ini ayır ve maksimum çapa örneğini kaldır; kontrollü replay veya iç allowlistte ayrıştırma sinyalini ölç
3. **Paralel — uzman gold set:** shadow deneyi bekletmeden 30–50 analizlik seti ve rubric'i kur
4. **Gold set gelince — A3–A5:** skor gerekçesi, server consistency guard ve 5×5 crosswalk
5. **A allowlist:** gold set + gerçek allowlist sonuçlarını ölç; ancak bu noktada kullanıcıya yansıyan skor değişikliğini değerlendir
6. **Faz B:** primary category key; ardından yalnız gerekirse kontrollü hazard taxonomy pilotu
7. **Faz C1–C2 ve C4:** bilgi yoğunluğu, iki kontrolün semantik kalitesi ve kompakt uzman görsel ipuçları
8. **Faz F:** trigger-bazlı repair optimizasyonu
9. **Faz D:** residual risk, yalnız skor ve kontrol kalitesi stabil olduktan sonra
10. Yalnız ihtiyaç kanıtlanırsa **C3 değişken önlem listesi**
11. **Faz E backlog:** ancak referans precision/coverage regresyonu kanıtlanırsa katalog çalışmasını aktive et

Her davranış ayrı flag/policy version taşır. Aynı rolloutta skor rubric'i, residual risk ve repair tetikleyicileri birlikte değiştirilmez; aksi hâlde kalite ve maliyet etkisi ayrıştırılamaz.

---

## 7. Test matrisi

Her faz için:

- TR ve beş EN profile prompt golden
- schema strict/relaxed/json-only fallback testleri
- tek foto, 2 foto, 3 foto ve hedefli repair
- raw → normalized → persisted finding kontratı
- `finalize_analysis_result_v2` taze replay testi
- user edit sonrası residual/taxonomy davranışı
- PDF ve Excel TR/EN görünürlük testi
- L10N inventory + forbidden claim + regulatory reference validation
- kanca mandalı, açık kenar, elektrik, istif, tank/proses ve kabin içi operatör regression fixture'ları
- yanlış pozitif karşı örnekleri: görünmeyen etiket, kabin içi KKD, yalnız insanın yangın ekipmanı önünde durması

Canlı A/B'de model, provider, prompt hash, safety profile ve fotoğraf byte hash'i sabitlenir. Değişen tek faktör ilgili faz olmalıdır.

---

## 8. Riskler ve azaltma

| Risk | Etki | Azaltma |
|---|---|---|
| Daha uzun çıktı, daha çok tekrar | kalite ve maliyet kaybı | uzunluk değil alan completeness/redundancy metriği |
| Dağılım hedefine göre under-score | kritik tehlike kaybı | yalnız uzman gold agreement ile karar |
| P/F içinde maruziyeti iki kez sayma | skor enflasyonu | P ve F rubric'ini kesin ayır |
| Fotoğraftan frekans uydurma | sahte kesinlik | frequency basis + provisional policy + verification |
| Category enum terminal şema hatası | analiz kaybı | fail-open normalization, schema fallback ölçümü |
| Residual risk yapay olarak düşürülür | yanlış güven | eşitliğe izin ver, kontrol-etkinliği gerekçesi |
| Referans coverage hedefi halüsinasyon yaratır | hukuki/mesleki risk | precision-first, uzman katalog |
| Çok önlem padding üretir | okunabilirlik kaybı | sayı hedefi yok, en fazla 4, semantik dedup |
| Expert cue promptu bulguları yine sona iter | recall regresyonu | yeni çıktı yapısı yok, kompakt talimat, fixture gate |
| Repair erken daraltılır | recall kaybı | trigger bazlı shadow ve gold set |
| Tarihi/yeni skorlar karşılaştırılamaz | analitik drift | policy version ve raw/final saklama |

---

## 9. Kapsam dışı ve build sınırı

- Fotoğraf başına fan-out ve tekrarlı örnekleme bu planın dışında
- `ai_expert_depth_v1` şema yükümlülükleri geri açılmıyor
- Mobil sonuç ekranında residual score, hierarchy etiketi veya score rationale göstermek build gerektirir
- Server PDF/Excel'e residual eklemek mobil build gerektirmeyebilir; report snapshot/RPC/Edge değişikliği yine gerekir
- `responsible` model tarafından üretilmez
- `deadline` kullanıcıya kesin taahhüt gibi verilmez; deterministik “önerilen termin” olabilir
- bbox kullanıcıya gösterilmez; yalnız shadow/evaluation amaçlı denenebilir

---

## 10. Açık kararlar ve önerilen cevaplar

1. **Nereden başlanmalı?** Mevcut snapshotı kullanan minimal Faz 0 ve A1+A2 shadow hemen; uzman gold set paralel. Dağılım, shadow iterasyonuna yön verir ama production yayınını tek başına onaylamaz.
2. **`score_rationale` eklensin mi?** Evet; önce kısa ve iç denetim alanı olarak. Kullanıcıya gösterim ayrı ürün kararı.
3. **Kalıntı risk eklensin mi?** Evet, ama Faz A ve kontrol kalitesi stabilize olduktan sonra; “mutlaka düşük” kuralı olmadan.
4. **Kategori 12 enum olsun mu?** Kullanıcı `category` metni değil, yeni `primary_category_key` 12 enum olsun; server lokalize etsin.
5. **High/critical oranına tavan konulsun mu?** Hayır. Uzman over-score/under-score kapıları kullanılsın.
6. **Önlem sayısı banda göre zorunlu olsun mu?** Hayır. Önce iki mevcut alanın hiyerarşi ve uygulanabilirliği düzelsin; gerekirse en fazla dört maddelik v2 liste.
7. **Referans için şimdi proje açılsın mı?** Hayır. Uygun kohort coverage'ı `%95.5`; mevcut precision-first kuralı korunsun, katalog yalnız ölçülmüş precision/ilgililik problemi çıkarsa aktive edilsin.
8. **Repair hemen sıfır-bulguya indirilsin mi?** Hayır. Önce trigger bazlı yield ve gold recall ölçülsün; zayıf trigger'lar sonra daraltılsın.
9. **Sorumlu/termin AI'dan gelsin mi?** Hayır. Firma varsayılanı ve Excel'de zaten yayımlanmış risk-band legend'ından deterministik önerilen termin kullanılsın; legend bugün finding satırına otomatik yazılmıyor.

---

## 11. Beklenen sonuç

Bu revizyonun hedefi çıktı tokenını iki katına çıkarmak değildir. Başarılı sonuç:

- aynı fotoğrafta daha çok uzman-seviye mekanik/proses ayrıntısı
- daha az skor yığılması ve daha doğru risk sıralaması
- ölüm/çoklu ölüm şiddetinin açık zarar mekanizmasına bağlanması
- frekans varsayımlarının görünür hâle gelmesi
- iki ama güçlü kontrol veya gerekirse kısa, tekrar etmeyen kontrol listesi
- doğru ve lokalize kategori
- uygun kohortta mevcut yüksek referans coverage'ını koruyan, precision-first davranış
- kontrollerle mantıksal olarak bağlı önerilen kalıntı risk
- hangi politika sürümünün hangi skoru ürettiğinin denetlenebilmesi

En yüksek getirili ilk deney: **mevcut raw/final baseline + P/F ayrımı + aşırı çapa örneğinin kaldırıldığı A1+A2 shadow varyantı**. Gold set bu deneyi başlatan kapı değil, doğru skor ve production yayını için otoritedir. En yüksek uzun vadeli kalite getirisi ise **uzman-onaylı hazard taxonomy + kompakt expert visual cues + kontrol semantiği** birleşimidir; referans kataloğu mevcut veriye göre acil değildir.
