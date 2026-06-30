# RiskDetected Analiz Promptları, Limitler ve Çoklu Foto İyileştirme Planı

Hazırlanma tarihi: 2026-06-30

Bu doküman, RiskDetected analiz sisteminde bugün hangi prompt parçalarının hangi senaryoda AI'a gönderildiğini, Free/Plus/Pro farklarını, canvas ve sektör seçimlerinin prompta nasıl eklendiğini, mevcut bulgu limitlerini ve tek foto modelinden çoklu foto modeline geçiş için yapılması gereken prompt/limit iyileştirmelerini açıklar.

Kaynak dosyalar:

- Backend analiz fonksiyonu: `supabase/functions/analyze/index.ts`
- Aktif sektör promptları: `supabase/functions/analyze/sector-context.ts`
- iOS canvas katalogu: `App/Models/AnalysisCanvas.swift`
- iOS sektör katalogu: `App/Models/AnalysisSector.swift`
- iOS analyze çağrısı: `App/Services/AnalysisService.swift`
- Çoklu foto capability migration: `supabase/migrations/20260622195418_multi_photo_editable_findings.sql`
- Coverage v2 migration: `supabase/migrations/20260625191650_multi_photo_coverage_v2.sql`

## 1. Ana Tespit

Sistem ilk tasarımda tek foto analizi için kurulmuştu. Çoklu foto analizine geçildikten sonra prompt, limit ve backend kontrol katmanında bazı alanlar tek foto varsayımıyla kalmış durumda.

Bugünkü düşük bulgu sayısının temel nedenleri:

- Tek foto analizde minimum bulgu hedefi promptta uygulanmıyor. Mevcut prompt sadece "fotoğraf başına en fazla 12" diyor.
- Çoklu foto coverage v2 hedefleri prod ayarında düşük: fotoğraf başına `min=5`, `max=8`, toplam `40`.
- Response schema JSON alanlarını zorunlu kılıyor ama minimum bulgu sayısını garanti etmiyor.
- Repair pass yalnız coverage açık çoklu foto analizlerde çalışıyor; tek foto analizde 6 bulgu gelirse backend bunu kabul ediyor.
- Plus/Pro plan toplam bulgu tavanı `60`; 5 fotoğraf için foto başı `13` istenirse toplam tavan `65` olmalı.

Hedef davranış:

- Tek foto: minimum `12`, ideal aralık `12-14`.
- Çoklu foto: fotoğraf başına minimum `9`, maksimum `13`.
- Çoklu foto toplam tavanı: `photoCount * 13`; 5 foto için `65`.
- Düşük kalite veya kanıt yoksa bulgu uydurulmayacak; `coverage_gap_reason` ile gerekçe yazılacak.

## 2. iOS'tan Backend'e Giden İstek

iOS analiz başlatırken önce `analyses` tablosunda pending kayıt oluşturur, sonra `analyze` Edge Function'a body gönderir.

Mevcut örnek body:

```json
{
  "analysis_id": "uuid",
  "canvas": "general",
  "canvases": ["general", "ppe", "working_at_height"],
  "analysis_mode": "standard",
  "text_input": null,
  "request_id": "client-trace-id",
  "support_id": "RD-XXXXXXXX",
  "company_id": null,
  "analysis_sector": "construction",
  "analysis_sector_source": "user_selected",
  "analysis_sector_prompt_version": "active-sector-v1",
  "photo_paths": [],
  "photo_base64_parts": [
    {
      "mime_type": "image/jpeg",
      "data": "base64...",
      "width": 1280,
      "height": 960,
      "client_photo_id": "local-id"
    }
  ],
  "client_app_version": "1.2.0",
  "client_app_build": "72",
  "client_platform": "ios",
  "api_contract_version": 2,
  "client_capabilities": {
    "multi_photo_analysis": true,
    "multi_photo_coverage_v2": true,
    "editable_findings": true
  }
}
```

Önemli noktalar:

- `canvas`: Legacy tek canvas alanı. iOS seçilen canvas id'lerini alfabetik sıralıyor ve ilkini buraya yazıyor.
- `canvases`: Asıl çoklu canvas listesi. Backend prompt odağını buradan kuruyor.
- `analysis_mode`: iOS tarafında seçilen canvaslardan biri paid ise `detailed`, aksi halde `standard`.
- `analysis_sector`: Kullanıcı analiz kapsamı sektörünü seçtiyse gönderilir.
- `photo_base64_parts`: Inline fotoğraflar. Backend bunları Storage'a kalıcı yazar ve AI'a base64 image part olarak gönderir.
- `photo_paths`: Daha önce Storage'a yüklenmiş fotoğraflar için kullanılır.

## 3. Prompt Montaj Sırası

Backend promptu tek bir metin olarak yazmaz; birkaç parçayı sırayla birleştirir.

### 3.1 Gemini İçin Sıra

Gemini çağrısında yapı şu şekildedir:

```json
{
  "system_instruction": {
    "parts": [
      { "text": "CORE_ANALYSIS_PROMPT" }
    ]
  },
  "contents": [
    {
      "role": "user",
      "parts": [
        { "text": "analysisContext" },
        { "text": "<foto index=\"1\" label=\"FOTO_1\">...</foto>" },
        { "inlineData": { "mimeType": "image/jpeg", "data": "base64..." } },
        { "text": "<foto index=\"2\" label=\"FOTO_2\">...</foto>" },
        { "inlineData": { "mimeType": "image/jpeg", "data": "base64..." } },
        { "text": "<kullanici_metin_girdisi>...</kullanici_metin_girdisi>" }
      ]
    }
  ],
  "generationConfig": {
    "responseMimeType": "application/json",
    "responseSchema": "responseSchema(tier, coveragePolicy)",
    "temperature": 0.2,
    "maxOutputTokens": 12000
  }
}
```

Coverage açıkken `maxOutputTokens` `16000` olur. Coverage kapalıyken `12000`.

### 3.2 Groq Fallback İçin Sıra

Groq OpenAI-compatible chat endpoint kullanır. Gemini'deki `responseSchema` doğrudan kullanılamadığı için aynı JSON yapısı metin talimatı olarak user content'in başına eklenir.

```json
{
  "messages": [
    {
      "role": "system",
      "content": "CORE_ANALYSIS_PROMPT"
    },
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "groqResponseSchemaInstruction + analysisContext + textInputBlock"
        },
        {
          "type": "text",
          "text": "<foto index=\"1\" label=\"FOTO_1\">...</foto>"
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,..."
          }
        }
      ]
    }
  ],
  "response_format": { "type": "json_object" },
  "temperature": 0.2
}
```

## 4. Ortak System Prompt

Tüm analizlerde aynı `CORE_ANALYSIS_PROMPT` kullanılır.

System prompt'un ana görevleri:

- AI'a Türkiye'de saha deneyimi olan kıdemli A sınıfı İSG uzmanı rolü verir.
- Görsel veya metin girdisinden sahadaki tüm İSG tehlikelerini sistematik tespit etmesini ister.
- Her görseli 12 katmanda taratır.
- Ölümcül potansiyelli bulguları üstte sıralatır.
- Fine-Kinney ve 5x5 ham risk girdilerini kalibre eder.
- Confidence eşiği koyar; `confidence < 0.30` bulguyu döndürme der.
- Görselde olmayan riski uydurmamasını ister.
- Her bulguda tam 2 önlem ister: düzeltici önlem ve önleyici kontrol.
- JSON dışında açıklama döndürmemesini ister.
- Türkçe değerler ve İngilizce JSON key'leri ister.

System prompt'un 12 katmanlı taraması:

1. Zemin, saha düzeni ve düzen-tertip.
2. Çalışanlar ve KKD.
3. Yüksekte çalışma.
4. Elektrik ve enerji.
5. Makine, ekipman ve iş ekipmanı.
6. Kaldırma, taşıma ve istifleme.
7. Kimyasal ve tehlikeli madde.
8. Yangın ve patlama.
9. Fiziksel ortam etkenleri.
10. Ergonomi ve elle taşıma.
11. Kazı, kapalı alan ve özel işler.
12. Çevre, acil durum, işaretleme ve yetkinlik.

System prompt örnek iskeleti:

```text
Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın.

GÖREV:
Sana verilen görsel veya metin girdisinden sahada fiziksel olarak bulunan
bir denetçinin yakalayacağı tüm İSG tehlikelerini sistematik olarak tespit et.

TARAMA PROSEDÜRÜ:
Her görseli sırayla 12 katmanda tara.
Risk yoksa o katmanı atla ama taramayı atlama.

ÖNCELİKLENDİRME:
Önce ölümcül potansiyel: düşme, elektrik, ezilme, kimyasal, düşen cisim.
Sonra yüksek frekanslı bulgular: zemin, ergonomi, KKD, eğitim, belge.

KALİTE FİLTRESİ:
Görselde olmayan riski uydurma.
Genel ifade yerine somut önlem yaz.
Confidence < 0.30 ise bulguyu döndürme.

ÇIKTI:
Yalnız JSON döndür.
Tüm değerler Türkçe, JSON key'leri İngilizce.
```

## 5. Analysis Context Promptu

`analysisContext`, user content'in ilk metin parçasıdır.

Şablon:

```text
<analiz_baglami prompt_version="isg-photo-text-report-language-v2026-06-06-twelve-layer-two-measures" personalization_version="onboarding-v1">
<odak>{canvas promptları}</odak>

<abonelik_seviyesi tier="{free|plus|pro}">
ÇIKTI KAPSAMI:
- {bulgu sayısı ve JSON kapsam kuralı}
- {Free/Plus/Pro alan kuralları}
</abonelik_seviyesi>

<aktif_analiz_sektoru version="active-sector-v1">
{aktif sektör promptu}
</aktif_analiz_sektoru>

<kullanici_profili applied="{true|false}">
{onboarding profil kuralları}
</kullanici_profili>

FİRMA BAĞLAMI: {varsa firma adı ve tehlike sınıfı}

KRİTİK ÇELİŞKİ KURALLARI:
- Abonelik kapsamı çıktı alanlarını belirler.
- Profil veya firma az tehlikeli dese bile görselde kritik risk varsa onu raporla.
- Emin olmadığın mevzuat maddesini, RG tarihini, ölçüm değerini veya standart numarasını uydurma.
</analiz_baglami>
```

Bu blok beş alt karar içerir:

- Seçilen canvaslar hangi odak promptlarının ekleneceğini belirler.
- Plan/quality tier Free, Plus veya Pro çıktı kapsamını belirler.
- Aktif sektör, sektör promptunu belirler.
- Onboarding cevapları ton ve öncelik sinyali olarak eklenir.
- Firma seçildiyse firma adı ve tehlike sınıfı risk önceliklendirmeye eklenir.

## 6. Foto Marker Promptu

Her fotoğraf için image part'ten hemen önce bu metin eklenir:

```text
<foto index="1" label="FOTO_1">
Sıradaki görsel FOTO_1. Bu marker yalnızca makine-okunur kaynak eşleştirme içindir.
Kullanıcıya gösterilecek title, observed_evidence, description, root_cause,
corrective_action, preventive_control, references, photo_summaries ve
per_photo_observations metinlerinde FOTO_1 veya başka FOTO_* marker adını yazma.
Bu görselden çıkardığın bulgularda source_photo_indices alanına yalnızca 1 yaz.
Aynı bulgu başka fotoğraflarda da görünüyorsa tüm ilgili FOTO numaralarını
source_photo_indices içinde birleştir. Her fotoğraf için photo_summaries içinde ayrı özet üret.
</foto>
```

Çoklu foto için bu blok her fotoğrafta tekrar eder:

```text
<foto index="1" label="FOTO_1">...</foto>
image_1
<foto index="2" label="FOTO_2">...</foto>
image_2
<foto index="3" label="FOTO_3">...</foto>
image_3
```

Bu marker'lar kullanıcıya gösterilmez. Backend sonradan metin alanlarından `FOTO_*` ifadelerini temizler.

## 7. Metin Analizi Promptu

Metin input varsa user content'in sonuna eklenir:

```text
<kullanici_metin_girdisi>
METİN ANALİZİ TALİMATI:
- Aşağıdaki metni rapora geçirilecek beyan değil; saha bağlamı, denetim yönlendirmesi ve tehlike arama ipucu olarak değerlendir.
- Ana system prompttaki 12 katmanlı taramayı metne uyarla.
- Yalnızca metinde açıkça belirtilen veya güçlü şekilde ima edilen tehlikeleri bulguya dönüştür.
- Fotoğraf kanıtı olmadığı için belirsiz noktaları uydurma.
- Kullanıcı metni kısa veya eksikse az ama güvenilir bulgu döndür; listeyi doldurmak için risk üretme.
- Kullanıcı metnini hiçbir alanda aynen alıntılama.

KULLANICI METNİ:
{text_input}
</kullanici_metin_girdisi>
```

Mevcut sistemde metin analizleri foto coverage akışına girmez; `hazards[]` döndürür.

## 8. Canvas Promptları

iOS canvas katalogu kullanıcıya gösterilen başlık/body alanlarını içerir. Backend ise aynı canvas id'leri için kendi prompt metinlerini kullanır.

Backend canvas prompt tablosu:

| Canvas ID | Minimum plan | Backend prompt etkisi |
|---|---|---|
| `general` | Free | Standart saha taraması; ana tarama prosedürünü uygular. |
| `ppe` | Free | Baret, gözlük, eldiven, iş ayakkabısı, reflektif yelek, solunum, kulak koruma, emniyet kemeri ve doğru kullanım eksiklerine odaklanır. |
| `machine` | Plus | Makine koruyucuları, döner/hareketli parçalar, sıkışma/ezilme/kesilme, acil durdurma, bakım-kilit/etiketleme, periyodik kontrol ve yetkisiz erişim risklerine odaklanır. |
| `warning_signs` | Free | Uyarı, yasak, zorunluluk, acil çıkış, yangın ekipmanı, yönlendirme, zemin/alan işaretleme, görünürlük ve konum eksiklerini analiz eder. |
| `electrical` | Free | Pano, kablo, priz, topraklama, kaçak akım, açık iletken, izolasyon, dağınık kablolama, nem/sıvı teması, yetkisiz erişim risklerini analiz eder. |
| `sector` | Plus | Sektör bağlamını tahmin eder; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü riskleri görünür kanıtla ilişkilendirir. |
| `fire` | Free | Yanıcı/parlayıcı malzeme, sıcak çalışma, söndürücü erişimi, yangın dolabı, acil çıkış, tahliye yolu ve yangın yüküne odaklanır. |
| `ergonomics` | Pro | Kodda başlık "Özel Ekipman" olarak kullanılıyor; fotoğraftaki ekipmanı tanımlar, tehlike/risk/önlem/KKD/kontrol/durdurma kriterleri ister. |
| `environment_measurement` | Plus | Gürültü, toz, gaz/buhar, aydınlatma, sıcaklık, havalandırma, titreşim ve kimyasal maruziyet gibi ölçüm gerektiren başlıkları "ölçümle doğrulanmalı" olarak yazar. |
| `explosion` | Free | Patlayıcı atmosfer, gaz/buhar/toz birikimi, basınçlı kap, statik elektrik, kıvılcım, havalandırma, Ex ekipman ve patlamadan korunma dokümanı ihtiyacını değerlendirir. |
| `environment` | Free | Atık yönetimi, sızıntı/dökülme, kimyasal depolama, drenaj, toprak/su kirliliği, emisyon/toz yayılımı ve çevresel acil durum risklerine odaklanır. |
| `legislation` | Pro | Bulguları Türkiye İSG mevzuatı açısından eşleştirir; emin olmadığı maddeyi uydurmaması istenir. |
| `working_at_height` | Free | Düşme, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, boşluk/kenar koruması, düşen cisim ve erişim güvenliğine odaklanır. |
| `mobile_equipment` | Free | Forklift, transpalet, vinç, kamyon, araç-yaya ayrımı, kör nokta, manevra alanı, yük güvenliği ve çarpma/ezilme risklerini analiz eder. |
| `general_premium` | Pro | Tüm görünür riskleri daha ayrıntılı ve denetim odaklı analiz eder; kritik seviyeden düşüğe sıralar. |
| `construction_machinery` | Free | Ekskavatör, yükleyici, vinç, kazıcı, kaldırıcı ve saha araçlarında devrilme, ezilme, kör nokta, zemin stabilitesi, bakım ve yetkisiz yaklaşma risklerini analiz eder. |

Canvas birleşim örneği:

```text
<odak>
Baret, gözlük/yüz koruma, eldiven, iş ayakkabısı, reflektif yelek...
Düşme tehlikesi, korkuluk, iskele, merdiven, platform...
Pano, kablo, priz, topraklama, kaçak akım...
</odak>
```

Free kullanıcıda backend birden fazla canvas isteğini reddeder. Plus/Pro kullanıcıda birden fazla canvas seçilebilir.

## 9. Aktif Sektör Promptları

Aktif sektör, onboarding sektöründen farklıdır. Onboarding profil sinyalidir; aktif sektör analiz özelinde kullanıcı seçimi olarak gelir.

Desteklenen sektör id'leri:

| ID | Türkçe etiket |
|---|---|
| `general` | Genel İSG |
| `construction` | İnşaat |
| `manufacturing` | İmalat / Fabrika |
| `mining` | Maden |
| `energy` | Enerji |
| `office` | Ofis |
| `logistics_warehouse` | Depo / Lojistik |
| `chemical_laboratory` | Kimya / Laboratuvar |
| `healthcare` | Sağlık / Hastane |
| `food_production` | Gıda Üretimi |
| `agriculture_livestock` | Tarım / Hayvancılık |
| `retail` | Perakende / Mağaza |
| `municipal_field_services` | Belediye / Kamu Saha İşleri |
| `education` | Eğitim Kurumu |
| `hospitality` | Otel / Konaklama |

### 9.1 Sektör Yoksa

Eski istemci veya eksik seçim durumunda genel blok gider:

```text
<aktif_analiz_sektoru version="active-sector-v1">
AKTİF ANALİZ SEKTÖRÜ

Bu istek eski istemciden gelmiş olabilir ve aktif analiz sektörü belirtilmemiştir.
Mevcut genel İSG analiz prosedürünü koru.
Onboarding sektörlerini yalnızca zayıf profil sinyali olarak kullan;
görünmeyen sektör-tipik tehlikeleri uydurma.
</aktif_analiz_sektoru>
```

### 9.2 General Seçilirse

```text
<aktif_analiz_sektoru version="active-sector-v1">
AKTİF ANALİZ SEKTÖRÜ

Kullanıcı bu analizi genel İSG kapsamında başlatmıştır.
Sektöre özel varsayımlar yapma.
Görsel veya metin kanıtına dayalı genel saha güvenliği taraması uygula.
</aktif_analiz_sektoru>
```

### 9.3 Spesifik Sektör Seçilirse

Örnek: `construction`

```text
<aktif_analiz_sektoru version="active-sector-v1">
AKTİF ANALİZ SEKTÖRÜ

Kullanıcı bu analizi "İnşaat" sektörü kapsamında başlatmıştır.

Bu sektör bilgisini analizde aktif bağlam olarak kullan:
- Tehlikeleri sektörün saha gerçekliğine göre önceliklendir.
- Terminolojiyi seçilen sektöre uygun kullan.
- Düzeltici önlem ve önleyici kontrolleri seçilen sektörde uygulanabilir olacak şekilde yaz.
- Mevzuat, iyi uygulama ve saha kontrol önerilerini seçilen sektörle uyumlu kur.
- Aynı görsel farklı sektörlerde farklı risk önceliklerine sahip olabileceğinden, bu analizi özellikle "İnşaat" kapsamına göre değerlendir.

Ancak:
- Görselde veya kullanıcı metninde kanıtı olmayan sektör-tipik tehlikeleri uydurma.
- Seçilen sektör ile görüntüdeki saha unsurları çelişirse görsel kanıtı üstün kabul et.
- Çelişki varsa bunu kısa ve profesyonel şekilde limitations alanında belirt.
- Kullanıcının onboarding'de seçtiği diğer sektörleri bu analiz için ek tehlike üretmek amacıyla kullanma.

SEKTÖR REHBERİ - İNŞAAT
- Yüksekte çalışma, iskele, merdiven, platform ve kenar koruma.
- Düşen cisim, malzeme istifleme, saha trafiği ve geçiş yolları.
- Kazı, geçici elektrik, kaldırma operasyonları ve iş ekipmanı kullanımı.
- KKD uygunluğu: baret, emniyet kemeri, reflektif yelek, iş ayakkabısı, göz/yüz koruma.
</aktif_analiz_sektoru>
```

## 10. Free / Plus / Pro Prompt Davranışı

Backend iki farklı seviye kavramı kullanır:

- `planTier`: Kullanıcının gerçek aboneliği.
- `qualityTier`: AI çıktı kalitesini belirleyen seviye.

Free kullanıcı standard analizde `FREE_STANDARD_ANALYSIS_AI_ROUTE=paid_trial` ise `qualityTier=plus` olabilir. Bu durumda kullanıcı Free olsa bile prompt Plus alanlarını isteyebilir. Bu özel durum dokümantasyonda ayrı tutulmalıdır.

### 10.1 Free

```text
<abonelik_seviyesi tier="free">
ÇIKTI KAPSAMI:
- {hazardCountRule}
- references ve root_cause alanı üretme; ayrı mevzuat/referans alanı Free'de kapalı.
- corrective_action veya preventive_control alanlarında kullanıcıya uygulanabilir değer sağlayan standart veya mevzuat adı geçebilir.
- RG tarihi, uzun mevzuat dökümü, madde listesi veya ayrı referans açıklaması verme.
</abonelik_seviyesi>
```

Free legacy response schema'da `references` ve `root_cause` zorunlu değildir.

### 10.2 Plus

```text
<abonelik_seviyesi tier="plus">
ÇIKTI KAPSAMI:
- {hazardCountRule}
- Her bulguda references alanını kısa tut: kanun/yönetmelik adı + yalnız emin olduğun kısa madde bilgisi.
- RG tarihi verme; standart numarasını sadece kritik ve güvenli olduğun durumda kısa yaz.
- Her bulguda root_cause alanını en fazla 1 kısa cümleyle, saha diliyle yaz.
</abonelik_seviyesi>
```

Plus response schema'da `references` ve `root_cause` zorunludur.

### 10.3 Pro

```text
<abonelik_seviyesi tier="pro">
ÇIKTI KAPSAMI:
- {hazardCountRule}
- Her bulguda references alanını daha tam yaz: yönetmelik/kanun + madde + güvenliysen RG tarihi.
- TS EN/ISO gibi standartları yalnız ilgili ve emin olduğun bulgularda kullan; emin değilsen "doğrulanmalı" yaz.
- Her bulguda root_cause alanını sistematik, teknik ve kısa kök neden perspektifiyle yaz.
</abonelik_seviyesi>
```

Pro response schema'da `references` ve `root_cause` zorunludur; içerik Plus'a göre daha detaylı istenir.

## 11. Mevcut Bulgu Limitleri

### 11.1 Kod Sabitleri

`PLAN_LIMITS`:

| Plan | Günlük standart | Günlük detaylı | Metin min | Metin max |
|---|---:|---:|---:|---:|
| Free | 1 | - | - | - |
| Plus | 10 | 2 | 12 | 16 |
| Pro | 40 | 10 | 12 | 16 |

`DEFAULT_PLAN_CAPABILITY_RULES`:

| Plan | Max foto | UI slot | Max bulgu/foto | Max bulgu/analiz | Çoklu foto |
|---|---:|---:|---:|---:|---|
| Free | 1 | 5 | 12 | 12 | Hayır |
| Plus | 5 | 5 | 12 | 60 | Evet |
| Pro | 5 | 5 | 12 | 60 | Evet |

`DEFAULT_MULTI_PHOTO_FLAGS`:

| Alan | Mevcut |
|---|---:|
| `max_photo_count_free` | 1 |
| `max_photo_count_plus` | 5 |
| `max_photo_count_pro` | 5 |
| `max_findings_per_photo` | 12 |
| `target_findings_per_photo_min` | 5 |
| `target_findings_per_photo_max` | 8 |
| `target_findings_total_max` | 40 |

### 11.2 Prod Migration Değerleri

Coverage v2 migration mevcut hedefleri şu şekilde set ediyor:

```sql
target_findings_per_photo_min = 5
target_findings_per_photo_max = 8
target_findings_total_max = 40
coverage_repair_enabled = true
```

Bu ayarlar bugünkü 5 foto analizde 20-25 bandını normal hale getiriyor.

## 12. Mevcut Analiz Varyasyonları

### 12.1 Metin Analizi

Koşul:

- `imageBase64Parts.length === 0`
- `text_input` dolu

Prompt:

```text
system_instruction = CORE_ANALYSIS_PROMPT
user.parts = [
  analysisContext,
  userTextInputBlock
]
```

Bulgu sayısı:

- Plus/Pro quality tier ise `PLAN_LIMITS`: 12-16.
- Free legacy ise fallback prompt: 10-13.

JSON:

```json
{
  "hazards": [
    {
      "title": "Makine koruyucularının sahada doğrulanması",
      "category": "Makine, Ekipman ve İş Ekipmanı",
      "observed_evidence": "Üretim ekipmanı ve operasyon güvenliği için koruyucu yeterliliği sahada doğrulanmalıdır.",
      "description": "Makine koruyucusu eksikliği temas veya sıkışma riskini artırabilir.",
      "corrective_action": "Koruyucu uygunluğunu sahada kontrol et; eksikse ekipmanı devre dışı bırak.",
      "preventive_control": "Periyodik makine güvenliği kontrol listesi ve sorumlu onayı tanımla.",
      "confidence": 0.62,
      "fk_probability": 3,
      "fk_frequency": 3,
      "fk_severity": 15,
      "m5_probability": 3,
      "m5_severity": 4,
      "references": "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
      "root_cause": "Makine güvenlik kontrolünün sahada doğrulanmamış olması"
    }
  ],
  "ai_summary": "Kısa özet",
  "limitations": "Metin girdisi sınırlı olduğu için bazı alanlar sahada doğrulanmalıdır."
}
```

### 12.2 Tek Foto Analizi - Mevcut

Koşul:

- `imageBase64Parts.length === 1`
- `coveragePolicyFor(...)` `null` döner çünkü `photoCount <= 1`

Mevcut prompt:

```text
Bu analizde 1 fotoğraf var. Görseller FOTO_1 marker'larıyla sırayla verilir;
source_photo_indices alanında sadece bu marker numaralarını kullan.
FOTO_* marker adlarını kullanıcıya gösterilecek hiçbir metin alanında yazma.
Her fotoğraf için photo_summaries içinde ayrı özet üret.
Her fotoğraf için 12 katmanlı taramadan çıkan tüm anlamlı bulgu adaylarını yaz;
fotoğraf başına en fazla 12, toplamda en fazla 12 final bulgu üret.
Kanıt varsa listeyi gereksiz kısaltma.
Risk kanıtı zayıfsa bulgu uydurma.
source_photo_indices ve per_photo_observations alanlarını doldur.
```

Sorun:

- "En az 12" yok.
- Response schema `hazards[]` kullanıyor.
- Repair pass yok.
- AI 6 bulgu döndürürse backend kabul ediyor.

Mevcut JSON:

```json
{
  "hazards": [
    {
      "title": "Korumasız açık kenar",
      "category": "Yüksekte Çalışma",
      "observed_evidence": "Çalışma alanı kenarında düşmeyi önleyici korkuluk görünmüyor.",
      "description": "Açık kenar yüksekten düşme riski oluşturur.",
      "corrective_action": "Kenar koruması kurulana kadar bölgeye erişimi durdur.",
      "preventive_control": "Günlük kenar koruma kontrolünü saha başlangıç listesine ekle.",
      "confidence": 0.88,
      "fk_probability": 6,
      "fk_frequency": 3,
      "fk_severity": 40,
      "m5_probability": 4,
      "m5_severity": 5,
      "source_photo_indices": [1],
      "per_photo_observations": [
        { "photo_index": 1, "observation": "Kenar hattında fiziksel korkuluk görünmüyor." }
      ],
      "references": "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği",
      "root_cause": "Kenar koruma kontrolünün uygulanmaması"
    }
  ],
  "photo_summaries": [
    {
      "photo_index": 1,
      "scene_summary": "Şantiye çalışma alanında açık kenar ve saha düzeni riskleri görülüyor.",
      "candidate_findings_count": 6,
      "highest_risk_level": "high",
      "ai_confidence": 0.82
    }
  ],
  "ai_summary": "Fotoğrafta yüksekten düşme ve saha düzeni riskleri öne çıkıyor.",
  "limitations": ""
}
```

### 12.3 Çoklu Foto Analizi - Coverage Açık Mevcut

Koşul:

- `imageBase64Parts.length > 1`
- Client capability `multi_photo_coverage_v2=true`
- Feature flag `multi_photo_coverage_v2=true`
- Plan Plus/Pro

Mevcut prompt:

```text
Bu analizde {photoCount} fotoğraf var.
Görseller FOTO_1...FOTO_{photoCount} marker'larıyla sırayla verilir.
Çıktıyı photo_findings[] formatında fotoğraf bazlı üret.
Her fotoğraf için coverage_status alanını "actionable", "no_actionable_hazard" veya "low_quality" olarak yaz.
Aksiyonlanabilir risk kanıtı olan her fotoğrafta en az 5, en fazla 8 kanıta dayalı ve duplicate olmayan bulgu üret.
Toplam final bulgu üst sınırı 40.
Temiz, ilgisiz, çok bulanık veya risk kanıtı zayıf fotoğrafta bulgu uydurma.
coverage_gap_reason alanında neden düşük kaldığını açıkla.
Aynı tehlikeyi yalnız aynı kök neden ve aynı kontrol tedbiri olduğunda birleştir.
Farklı fotoğraftaki farklı tehlikeleri yalnız sayıyı azaltmak için birleştirme.
```

Mevcut JSON:

```json
{
  "photo_findings": [
    {
      "photo_index": 1,
      "coverage_status": "actionable",
      "scene_summary": "Şantiye içi geçiş alanında açık kenar ve düzensiz malzeme görülüyor.",
      "candidate_findings_count": 6,
      "coverage_gap_reason": "",
      "highest_risk_level": "high",
      "ai_confidence": 0.84,
      "findings": [
        {
          "title": "Açık kenar koruması eksikliği",
          "category": "Yüksekte Çalışma",
          "observed_evidence": "Kenar hattında düşmeyi önleyici fiziksel koruma görünmüyor.",
          "description": "Korumasız kenar yüksekten düşme riski oluşturur.",
          "corrective_action": "Kenar hattına uygun korkuluk kur; kurulana kadar erişimi durdur.",
          "preventive_control": "Kenar koruma kontrolünü günlük saha turuna ekle.",
          "confidence": 0.86,
          "fk_probability": 6,
          "fk_frequency": 3,
          "fk_severity": 40,
          "m5_probability": 4,
          "m5_severity": 5,
          "source_photo_indices": [1],
          "per_photo_observations": [
            { "photo_index": 1, "observation": "Kenar hattında korkuluk görünmüyor." }
          ],
          "references": "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği",
          "root_cause": "Kenar koruma kontrolünün sahada uygulanmaması"
        }
      ]
    }
  ],
  "photo_summaries": [
    {
      "photo_index": 1,
      "scene_summary": "Şantiye içi geçiş alanı.",
      "candidate_findings_count": 6,
      "highest_risk_level": "high",
      "ai_confidence": 0.84,
      "coverage_status": "actionable",
      "coverage_gap_reason": ""
    }
  ],
  "ai_summary": "Çoklu foto analizinde yüksekten düşme ve saha düzeni riskleri öne çıkıyor.",
  "limitations": ""
}
```

Sorun:

- Fotoğraf başı hedef 5-8 olduğu için 5 fotoğrafta 20-25 bulgu normal.
- Kullanıcı beklentisi 5 foto için en az 45 bulgu.
- Toplam tavan 40 olduğu için 5 foto x 13 zaten mümkün değil.

### 12.4 Çoklu Foto Analizi - Coverage Kapalı Mevcut

Koşul:

- Çoklu foto var ama coverage flag/capability kapalı.

Mevcut prompt:

```text
Bu analizde {photoCount} fotoğraf var.
Her fotoğraf için 12 katmanlı taramadan çıkan tüm anlamlı bulgu adaylarını yaz.
Fotoğraf başına en fazla {maxFindingsPerPhoto}, toplamda en fazla {maxFindingsTotal} final bulgu üret.
Kanıt varsa listeyi gereksiz kısaltma.
Risk kanıtı zayıfsa bulgu uydurma.
```

JSON `hazards[]` döner. Fotoğraf başı minimum garanti yoktur.

## 13. Hedef Promptlar

### 13.1 Tek Foto Hedef Promptu

Tek foto da coverage tarzı fotoğraf bazlı şemaya alınmalıdır.

```text
Bu analizde 1 fotoğraf var. Görsel FOTO_1 marker'ıyla verilir.
Çıktıyı photo_findings[] formatında fotoğraf bazlı üret.

Her fotoğraf için:
- coverage_status alanını "actionable", "no_actionable_hazard" veya "low_quality" olarak yaz.
- Aksiyonlanabilir risk kanıtı varsa en az 12, en fazla 14 kanıta dayalı ve duplicate olmayan bulgu üret.
- 12 altı yalnızca coverage_status "low_quality" veya "no_actionable_hazard" ise kabul edilir.
- Hedefin altında kalırsan coverage_gap_reason alanında açık ve profesyonel gerekçe yaz.
- Bulgu uydurma; ancak görünür riskleri gereksiz birleştirip sayıyı düşürme.
- Aynı tehlikeyi yalnız aynı kök neden, aynı kontrol tedbiri ve aynı görsel kanıt olduğunda birleştir.
- Her bulguda source_photo_indices=[1] ve per_photo_observations doldur.
```

Hedef JSON:

```json
{
  "photo_findings": [
    {
      "photo_index": 1,
      "coverage_status": "actionable",
      "scene_summary": "Fotoğraftaki sahnenin kısa özeti.",
      "candidate_findings_count": 14,
      "coverage_gap_reason": "",
      "highest_risk_level": "high",
      "ai_confidence": 0.86,
      "findings": [
        {
          "title": "Kısa tehlike başlığı",
          "category": "Risk kategorisi",
          "observed_evidence": "Nesnel saha kanıtı",
          "description": "Riskin kısa açıklaması",
          "corrective_action": "Mevcut uygunsuzluğu gideren kısa aksiyon",
          "preventive_control": "Tekrarı önleyen sistemsel kontrol",
          "confidence": 0.86,
          "fk_probability": 6,
          "fk_frequency": 3,
          "fk_severity": 40,
          "m5_probability": 4,
          "m5_severity": 5,
          "source_photo_indices": [1],
          "per_photo_observations": [
            { "photo_index": 1, "observation": "Fotoğraftaki kısa gözlem" }
          ],
          "references": "Plus/Pro için referans",
          "root_cause": "Plus/Pro için kök neden"
        }
      ]
    }
  ],
  "photo_summaries": [
    {
      "photo_index": 1,
      "scene_summary": "Fotoğraftaki sahnenin kısa özeti.",
      "candidate_findings_count": 14,
      "highest_risk_level": "high",
      "ai_confidence": 0.86,
      "coverage_status": "actionable",
      "coverage_gap_reason": ""
    }
  ],
  "ai_summary": "Kısa analiz özeti.",
  "limitations": ""
}
```

### 13.2 Çoklu Foto Hedef Promptu

```text
Bu analizde {photoCount} fotoğraf var.
Görseller FOTO_1...FOTO_{photoCount} marker'larıyla sırayla verilir.
Çıktıyı photo_findings[] formatında fotoğraf bazlı üret.

Her fotoğraf için:
- coverage_status alanını "actionable", "no_actionable_hazard" veya "low_quality" olarak yaz.
- Aksiyonlanabilir risk kanıtı olan her fotoğrafta en az 9, en fazla 13 kanıta dayalı ve duplicate olmayan bulgu üret.
- Toplam final bulgu üst sınırı photoCount * 13.
- Temiz, ilgisiz, çok bulanık veya risk kanıtı zayıf fotoğrafta bulgu uydurma.
- Hedef altında kalırsan coverage_gap_reason alanında neden düşük kaldığını açıkla.
- Aynı tehlikeyi yalnız aynı kök neden, aynı kontrol tedbiri ve aynı görsel kanıt olduğunda birleştir.
- Farklı fotoğraftaki farklı tehlikeleri yalnız sayıyı azaltmak için birleştirme.
- Her bulguda source_photo_indices, per_photo_observations ve fotoğraf özeti alanlarını doldur.
```

2 foto için hedef:

- Minimum toplam: 18
- Maksimum toplam: 26

5 foto için hedef:

- Minimum toplam: 45
- Maksimum toplam: 65

### 13.3 Hedef Repair Promptu

Repair pass tek ve çoklu tüm foto analizlerinde ortak çalışmalıdır.

```text
<coverage_repair_pass>
Yalnız şu fotoğraflar için ikinci kısa tarama yap: FOTO_1, FOTO_3.

Amaç:
- Actionable risk kanıtı olan her fotoğrafı hedef aralığa tamamlamak.
- Tek foto hedefi: en az 12, en fazla 14.
- Çoklu foto hedefi: fotoğraf başına en az 9, en fazla 13.

Kurallar:
- Mevcut bulguları tekrar etme.
- Aynı kök neden + aynı kontrol tedbiri + aynı görsel kanıt varsa yeni bulgu sayma.
- Ancak farklı konum, farklı ekipman, farklı çalışan davranışı veya farklı kontrol ihtiyacı varsa ayrı bulgu üret.
- Temiz, ilgisiz veya düşük kaliteli fotoğrafta risk uydurma.
- Hedef altında kalıyorsa coverage_status değerini "no_actionable_hazard" veya "low_quality" yap ve coverage_gap_reason yaz.
- Yanıtı yine photo_findings[] formatında üret; sadece istenen fotoğraf indekslerini döndür.

<mevcut_bulgular>
Foto 1: mevcut 6 bulgu
1. ...
</mevcut_bulgular>
</coverage_repair_pass>
```

## 14. Response Schema Karşılaştırması

### 14.1 `hazards[]` Şeması

Kullanıldığı yerler:

- Metin analizi.
- Tek foto mevcut akış.
- Coverage kapalı eski çoklu foto akışı.

Temel sorun:

- Düz liste olduğu için fotoğraf bazlı minimumu iyi denetleyemiyor.
- `coverage_status` ve `coverage_gap_reason` yok.

### 14.2 `photo_findings[]` Şeması

Kullanıldığı yerler:

- Coverage açık çoklu foto mevcut akış.
- Hedefte tüm foto analizleri.

Avantajları:

- Her fotoğraf için ayrı `coverage_status`.
- Her fotoğraf için ayrı `candidate_findings_count`.
- Hedef altında kalma gerekçesi için `coverage_gap_reason`.
- Repair adaylarını fotoğraf bazında seçmek kolay.
- Çoklu foto analizinde fotoğraf başına minimumları denetlemek mümkün.

## 15. Limit İyileştirme Planı

### 15.1 Hedef Limit Tablosu

| Alan | Mevcut | Hedef |
|---|---:|---:|
| Free max foto | 1 | 1 |
| Free max bulgu/foto | 12 | 12 |
| Plus max foto | 5 | 5 |
| Pro max foto | 5 | 5 |
| Plus/Pro max bulgu/analiz | 60 | 65 |
| Tek foto min | yok | 12 |
| Tek foto max | 12 | 14 |
| Çoklu foto min/foto | 5 | 9 |
| Çoklu foto max/foto | 8 | 13 |
| Çoklu foto total max | 40 | `photoCount * 13`, en fazla 65 |
| Repair kapsamı | Çoklu coverage | Tüm foto analizleri |

### 15.2 Backend Değişiklikleri

- `coveragePolicyFor` tek fotoyu dışlamayacak şekilde yeniden tasarlanmalı.
- `MultiPhotoCoveragePolicy` ismi `PhotoCoveragePolicy` gibi genel bir isme çekilmeli.
- Tek foto için policy:

```ts
{
  enabled: true,
  photoCount: 1,
  targetMin: 12,
  targetMax: 14,
  totalMax: 14,
  repairEnabled: true
}
```

- Çoklu foto için policy:

```ts
{
  enabled: true,
  photoCount,
  targetMin: 9,
  targetMax: 13,
  totalMax: Math.min(maxFindingsPerAnalysis, photoCount * 13),
  repairEnabled: true
}
```

- `DEFAULT_MULTI_PHOTO_FLAGS` hedef değerlere çekilmeli:

```ts
target_findings_per_photo_min: 9
target_findings_per_photo_max: 13
target_findings_total_max: 65
max_findings_per_photo: 13
```

- `DEFAULT_PLAN_CAPABILITY_RULES.plus/pro` güncellenmeli:

```ts
max_findings_per_photo: 13
max_findings_per_analysis: 65
```

- DB migration ile `plan_capability_rules` ve `app_feature_flags` güncellenmeli.

### 15.3 Prompt Version

Mevcut prompt version:

```text
isg-photo-text-report-language-v2026-06-06-twelve-layer-two-measures
```

Hedef yeni versiyon önerisi:

```text
isg-photo-policy-v2026-07-single-multi-targets
```

Bu versiyon değişikliği `raw_ai_response._input_audit.prompt_version` içinde izlenmeli.

### 15.4 Audit Alanları

Yeni audit alanları eklenmeli:

```json
{
  "photo_policy_version": "single-multi-targets-v1",
  "single_photo_target_min": 12,
  "single_photo_target_max": 14,
  "multi_photo_target_min": 9,
  "multi_photo_target_max": 13,
  "target_findings_total_max": 65,
  "post_merge_shortfall_photo_indices": [],
  "coverage_repair_used": true,
  "coverage_repair_photo_indices": [1, 3]
}
```

## 16. Neden Sadece Prompt Yetmez

Prompt hedefi artırmak gerekir ama tek başına yeterli değildir.

Nedenler:

- Gemini response schema array minimum length zorlamıyor.
- Model "en az 12" dense bile bazen 6-8 bulgu döndürebilir.
- Dedup/merge aşaması bulgu sayısını düşürebilir.
- Düşük kaliteli fotoğraf veya gerçekten az riskli sahada hedefe ulaşmak için risk uydurma tehlikesi var.

Bu yüzden hedef davranış dört katmanda uygulanmalıdır:

1. Prompt hedefi net söylemeli.
2. JSON şeması fotoğraf bazlı olmalı.
3. Backend repair pass hedef altını tamamlamalı.
4. Post-merge guard hedef altını tespit edip repair veya shortfall nedeni yazmalı.

## 17. Test Senaryoları

### 17.1 Tek Foto Minimum

Mock AI ilk pass:

```json
{
  "photo_findings": [
    {
      "photo_index": 1,
      "coverage_status": "actionable",
      "candidate_findings_count": 6,
      "findings": [{}, {}, {}, {}, {}, {}]
    }
  ]
}
```

Beklenen:

- Repair tetiklenir.
- Final bulgu sayısı 12-14 aralığına çıkar.
- `coverage_repair_used=true`.

### 17.2 Tek Foto Düşük Kalite

Mock AI:

```json
{
  "photo_findings": [
    {
      "photo_index": 1,
      "coverage_status": "low_quality",
      "candidate_findings_count": 3,
      "coverage_gap_reason": "Görüntü bulanık olduğu için güvenilir ayrı bulgu üretilemedi.",
      "findings": [{}, {}, {}]
    }
  ]
}
```

Beklenen:

- 12 altı kabul edilir.
- `coverage_gap_reason` boş olamaz.
- Bulgular uydurulmaz.

### 17.3 Beş Foto Çoklu Analiz

Beklenen:

- Her actionable foto için 9-13 bulgu.
- Toplam 45-65 arası.
- Düşük kalite foto varsa o foto için gerekçeli istisna.

### 17.4 Dedup Sonrası Shortfall

Senaryo:

- İlk pass her foto için 9 bulgu.
- Merge/dedup sonrası Foto 2 bulgu sayısı 7'ye düşüyor.

Beklenen:

- Foto 2 repair adayına eklenir.
- Repair sonrası hedefe tamamlanır veya gerekçeli shortfall yazılır.

### 17.5 Free / Plus / Pro Schema

Beklenen:

- Free legacy schema `references` ve `root_cause` istemez.
- Plus schema bu iki alanı kısa ister.
- Pro schema daha tam mevzuat ve sistematik root cause ister.

## 18. Uygulama Sırası

1. Prompt/limit dokümanı bu dosyada sabitlenir.
2. Backend policy isimlendirmesi tek/çoklu fotoyu kapsayacak şekilde genelleştirilir.
3. Feature flag ve plan capability migration hazırlanır.
4. Prompt version güncellenir.
5. Tek foto `photo_findings[]` akışına alınır.
6. Repair pass tüm foto analizlerinde ortaklaştırılır.
7. Dedup sonrası post-merge minimum guard eklenir.
8. Worker timeout ve iOS 420 saniye bekleme planı ayrı PR/commit içinde uygulanır.
9. Çoklu foto işaretleme queue/sheet düzeltmesi ayrı iOS değişikliği olarak uygulanır.

## 19. Kısa Sonuç

Bugünkü sistemde modelden az bulgu gelmesi bir model kalitesi sorunu gibi görünse de ana neden policy ve prompt uyumsuzluğudur. Tek foto akışı hâlâ eski `hazards[]` mantığında çalışıyor; çoklu foto akışı ise düşük coverage hedefleriyle sınırlandırılmış. Yeni hedefler için promptlar netleştirilmeli, tek foto da fotoğraf bazlı coverage şemasına alınmalı ve minimum hedef backend repair/guard katmanında zorlanmalıdır.
