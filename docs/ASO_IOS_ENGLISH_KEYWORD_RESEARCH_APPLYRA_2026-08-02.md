# RiskDetected iOS İngilizce Lokalizasyon Keyword Araştırması

Tarih: 2 Ağustos 2026  
Veri kaynağı: Applyra MCP / Apple App Store (iTunes)  
Kapsam: `en-US`, `en-GB`, `en-AU`, `en-CA`  
Hariç tutulan lokalizasyon: `tr-TR`  
App Store Connect durumu: **Hiçbir değişiklik yapılmadı**

## Yönetici özeti

Mevcut İngilizce keyword alanlarındaki `photo`, `field`, `PDF`, `Excel`, `controls` ve bazı pazarlardaki `checklist` kelimeleri kaldırılmalıdır. Bu kelimelerin bir bölümü yüksek trafik gösterse de App Store arama sonuçları RiskDetected ile örtüşmüyor; diğerleri ise uygulamanın gerçek bir özelliğini veya kullanıcı niyetini doğru temsil etmiyor.

Araştırmada:

- 8 ülke/niş analizi,
- 16 yerel App Store autocomplete sorgusu,
- 65 exact-keyword incelemesi,
- her aday için trafik, zorluk, KEI ve ilk sıralardaki uygulama kontrolü

yapıldı.

En güçlü yerel fırsatlar:

- ABD: `JSA` T96/D26, `JHA` T92/D31
- Birleşik Krallık: `JSA` T72/D29, `job safety analysis` T25/D8, `risk matrix` T25/D10
- Avustralya: `risk matrix` T41/D11, `JSA` T60/D25
- Kanada: `JSA` T96/D27, `hazard assessment` T50/D5

Buradaki `T`, Applyra trafik skorunu; `D`, zorluk skorunu gösterir. Bunlar 0–100 arası göreli skorlardır, aylık kesin arama sayısı değildir.

## Eleme ve puanlama sistemi

### Zorunlu filtreler

Bir keyword aşağıdaki şartlardan birini karşılamıyorsa elendi:

1. Ürün veya arama sonucu ilgisi 80/100 altında.
2. Zorluk 45'in üzerinde. Yalnızca trafik en az 60 ve arama sonuçları çok temizse deneysel istisna düşünüldü.
3. Trafik tabanı olan T8 seviyesindeki bir kelime; zorluk 20'nin altında, niyeti çok net ve desteklenen bir özelliğe bağlı değilse elendi.
4. İlk beş App Store sonucunda baskın niyet RiskDetected ile örtüşmüyorsa elendi.
5. Uygulamanın sağlamadığı bir özellik veya garanti ima ediyorsa elendi:
   - SWMS/method statement oluşturma
   - mevzuat veya OSHA compliance garantisi
   - eğitim/sertifikasyon
   - incident/near-miss tracking
   - toolbox talk
   - ekipman bakım yönetimi
   - checklist builder
6. Başlık veya alt başlıkta bulunan bir kelime keyword alanında tekrar ediyorsa 100 karakteri boşa harcamamak için çıkarıldı.

### Opportunity puanı

Manuel ürün + SERP ilgisi de hesaba katıldı:

```text
Opportunity = Traffic × 0.40
            + (100 - Difficulty) × 0.30
            + Relevance × 0.30
```

`Relevance`, ürün kapsamı ve Applyra'nın gösterdiği ilk App Store sonuçlarının temizliği birlikte değerlendirilerek 0–100 arasında verildi.

## Nihai önerilen keyword alanları

Bu satırlar mevcut başlık ve alt başlıklar korunarak hazırlanmıştır. Boşluksuz virgül kullanılmıştır ve tamamı Apple'ın 100 karakter sınırının altındadır.

### en-US — United States

Mevcut metadata:

- Name: `RiskDetected: Safety Audit`
- Subtitle: `Job Hazard Analysis & Reports`

Önerilen keyword alanı — 90 karakter:

```text
JSA,JHA,inspection,observation,risk,matrix,workplace,site,assessment,generator,Fine-Kinney
```

Bu alanın metadata ile oluşturduğu ana hedefler:

- `JSA`
- `JHA`
- `job safety analysis`
- `job hazard assessment`
- `safety inspection`
- `safety observation report`
- `risk matrix`
- `workplace safety audit`
- `site safety audit`
- `safety report generator`
- `Fine-Kinney`

### en-GB — United Kingdom

Mevcut metadata:

- Name: `RiskDetected: Risk Assessment`
- Subtitle: `Hazard Checks & Risk Reports`

Önerilen keyword alanı — 91 karakter:

```text
safety,inspection,health,site,workplace,audit,matrix,job,analysis,JSA,observation,generator
```

Bu alanın metadata ile oluşturduğu ana hedefler:

- `JSA`
- `job safety analysis`
- `safety observation report`
- `risk matrix`
- `site risk assessment`
- `safety inspection`
- `health and safety`
- `workplace safety audit`
- `safety report generator`

### en-AU — Australia

Mevcut metadata:

- Name: `RiskDetected: Safety Audit`
- Subtitle: `WHS Inspections & Risk Reports`

Önerilen keyword alanı — 94 karakter:

```text
JSA,job,analysis,observation,matrix,hazard,assessment,workplace,site,generator,Fine-Kinney,JHA
```

Bu alanın metadata ile oluşturduğu ana hedefler:

- `JSA`
- `JHA`
- `job safety analysis`
- `safety observation report`
- `risk matrix`
- `hazard assessment`
- `workplace safety audit`
- `site safety inspection`
- `risk report generator`
- `Fine-Kinney`

Not: `SWMS` verisi çok güçlü olmasına rağmen RiskDetected özel bir SWMS oluşturucusu olmadığı için bilinçli olarak kullanılmadı.

### en-CA — Canada

Mevcut metadata:

- Name: `RiskDetected: Safety Audit`
- Subtitle: `OHS Inspections & Risk Reports`

Önerilen keyword alanı — 90 karakter:

```text
JSA,job,analysis,hazard,assessment,observation,matrix,workplace,site,generator,Fine-Kinney
```

Bu alanın metadata ile oluşturduğu ana hedefler:

- `JSA`
- `job safety analysis`
- `hazard assessment`
- `safety observation report`
- `risk matrix`
- `workplace safety audit`
- `site safety inspection`
- `risk report generator`
- `Fine-Kinney`

`OHS` T82/D38 ile güçlüdür ancak zaten alt başlıkta bulunduğundan keyword alanında tekrar edilmedi.

## Ülke bazında doğrulanmış adaylar

### en-US

| Keyword | T | D | Relevance | Opportunity | Karar |
|---|---:|---:|---:|---:|---|
| JSA | 96 | 26 | 82 | 85.2 | Kullan; yüksek trafik, akronim karışıklığı metadata ile dengeleniyor |
| JHA | 92 | 31 | 82 | 82.1 | Kullan; mesleki olarak çok ilgili, arama sonucu kısmen karışık |
| job safety analysis | 25 | 13 | 96 | 64.9 | Güçlü hedef |
| safety observation report | 22 | 12 | 95 | 63.7 | Güçlü hedef |
| risk matrix | 25 | 16 | 92 | 62.8 | Güçlü ve uygulama özelliğiyle doğrudan ilgili |
| safety inspection | 33 | 32 | 96 | 62.4 | Ana kategori hedefi |
| job hazard assessment | 8 | 8 | 97 | 59.9 | Düşük hacimli fakat çok temiz uzun kuyruk |
| Fine-Kinney | 8 | 12 | 92 | 57.2 | Özellik-spesifik destekleyici terim |

### en-GB

| Keyword | T | D | Relevance | Opportunity | Karar |
|---|---:|---:|---:|---:|---|
| JSA | 72 | 29 | 80 | 74.1 | Kullan; hacimli fakat akronim sonucu karışık |
| job safety analysis | 25 | 8 | 95 | 66.1 | Çok güçlü yerel fırsat |
| safety observation report | 25 | 10 | 96 | 65.8 | Çok güçlü yerel fırsat |
| risk matrix | 25 | 10 | 92 | 64.6 | Çok güçlü ve özellik-spesifik |
| site risk assessment | 25 | 14 | 94 | 64.0 | UK iş sahası niyetiyle güçlü |
| safety inspection | 36 | 32 | 96 | 63.6 | Yüksek ilişki, kabul edilebilir zorluk |
| health and safety | 29 | 25 | 85 | 59.6 | UK terminolojisi için uygun |
| workplace safety audit | 8 | 9 | 95 | 59.0 | Temiz uzun kuyruk |
| safety report generator | 8 | 8 | 90 | 57.8 | Desteklenen rapor özelliğiyle ilgili |

### en-AU

| Keyword | T | D | Relevance | Opportunity | Karar |
|---|---:|---:|---:|---:|---|
| JSA | 60 | 25 | 90 | 73.5 | Güçlü Avustralya hedefi |
| risk matrix | 41 | 11 | 93 | 71.0 | Araştırmanın en iyi AU fırsatı |
| job safety analysis | 25 | 10 | 95 | 65.5 | Çok güçlü |
| safety observation report | 25 | 11 | 96 | 65.5 | Çok güçlü |
| safety inspection | 34 | 25 | 96 | 64.9 | Ana kategori hedefi |
| hazard assessment | 8 | 8 | 96 | 59.6 | Temiz uzun kuyruk |
| job hazard analysis | 8 | 9 | 95 | 59.0 | Temiz uzun kuyruk |
| Fine-Kinney | 8 | 10 | 95 | 58.7 | Özellik-spesifik destekleyici terim |

### en-CA

| Keyword | T | D | Relevance | Opportunity | Karar |
|---|---:|---:|---:|---:|---|
| JSA | 96 | 27 | 84 | 85.5 | En yüksek hacimli Kanada fırsatı |
| OHS | 82 | 38 | 94 | 79.6 | Güçlü; alt başlıkta olduğu için keyword alanına yazma |
| hazard assessment | 50 | 5 | 97 | 77.6 | Araştırmanın en iyi hacim/zorluk dengelerinden biri |
| job safety analysis | 25 | 9 | 95 | 65.8 | Çok güçlü |
| risk matrix | 25 | 7 | 93 | 65.8 | Çok güçlü ve özellik-spesifik |
| safety observation report | 25 | 15 | 96 | 64.3 | Güçlü |
| safety inspection | 36 | 30 | 96 | 64.2 | Ana kategori hedefi |
| Fine-Kinney | 8 | 12 | 92 | 57.2 | Özellik-spesifik destekleyici terim |
| workplace hazard assessment | 8 | 13 | 92 | 56.9 | Temiz uzun kuyruk |

## Kesin elenen mevcut kelimeler

| Keyword | Applyra özeti | Eleme gerekçesi |
|---|---|---|
| photo | T100, D85–100 | Arama sonuçları fotoğraf editörleri ve kamera uygulamaları; ürün discovery niyeti yanlış |
| field | T96, D51–72 | Dating, field service ve GPS niyeti baskın |
| PDF | T100, D54–83 | Genel PDF araçlarıyla rekabet; güvenlik değerlendirmesi niyeti yok |
| Excel | T72–85, D34–50 | Spreadsheet/Office niyeti; RiskDetected discovery'si için alakasız |
| controls | T8, D15–62 | Uzaktan kumanda ve cihaz kontrol uygulamaları baskın |
| checklist | T48–50, D62–70 | Rekabet yüksek; uygulamada bağımsız bir checklist builder yok |
| construction | GB T50/D58 | Oyun ve genel inşaat uygulaması niyeti; çok geniş |

### Tek başına elenen, birleşik sorguda kullanılan tokenlar

Bazı genel tokenlar tek başına hedeflenmedi ancak mevcut title/subtitle ile çok ilgili bir sorgu oluşturdukları için yeni alanda tutuldu:

- `workplace` → `workplace safety audit`
- `site` → `site risk assessment`, `site safety inspection`
- `hazard` → `hazard assessment`
- `assessment` → `job hazard assessment`
- `generator` → `safety/risk report generator`

Bu kelimelerin değeri tekil trafikleri değil, metadata ile oluşturdukları yüksek ilgili birleşik sorgulardır.

## Yüksek skorlu olmasına rağmen elenen fırsatlar

| Pazar | Keyword | T/D | Neden kullanılmadı |
|---|---|---:|---|
| AU | SWMS | 75/12 | Kullanıcı özel SWMS dokümanı bekler; ürün bu özelliği sunmuyor |
| AU | SWMS JSA | 68/10 | Çok iyi skor fakat SWMS vaadi ürün kapsamı dışında |
| AU | WHS | 96/67 | Zorluk çok yüksek, SERP karışık ve zaten alt başlıkta |
| GB | RAMS | 82/27 | Method statement beklentisi yaratır; ayrıca NFL/alışveriş sonucu karışıklığı var |
| GB | HSE | 75/51 | Resmî HSE ve büyük kurumsal uygulamalar baskın; zorluk eşiğini aşıyor |
| US | EHS | 78/47 | Emirates Health Services dahil karışık niyet; zorluk eşiğini aşıyor |
| CA | FLHA | 8/5 | Yerel jargon ilgili fakat trafik taban seviyesinde ve sonuçlar yeterince temiz değil |
| Tümü | safety compliance app | 23–24/13–16 | Skoru iyi olsa da ürün mevzuata uyum garantisi sunmuyor |

## Uygulama önerisi

Bir sonraki App Store sürümünde yalnızca yukarıdaki dört nihai keyword alanını güncellemek en güvenli yaklaşımdır. Başlık ve alt başlıklar aynı kalmalıdır; önerilen alanlar onlarla birlikte çalışacak şekilde tasarlanmıştır.

Değişiklikten sonra:

1. İlk endeksleme kontrolünü 7–10 gün içinde yap.
2. İlk anlamlı sıralama değerlendirmesini 4 hafta sonra yap.
3. JSA/JHA gibi akronimlerde gösterim artıp dönüşüm zayıf kalırsa, ilgili pazardaki akronimi düşük zorluklu uzun kuyrukla değiştir.
4. SWMS, RAMS, compliance ve checklist terimlerini ancak uygulamaya karşılık gelen gerçek özellik eklendiğinde yeniden değerlendir.

