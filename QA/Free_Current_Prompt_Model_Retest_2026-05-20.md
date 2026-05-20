# Free Current Prompt / Model Retest - 2026-05-20

Kaynak:
- Yeni QA Edge Function: `supabase/functions/gemini-free-qa-run`
- Kaynak analiz: `af3ac756-d4c0-4d2c-b46c-dc7026237490`
- Kaynak fotoğraf: `70cc0ebb-0d32-42f1-ac9b-976b13bd2295/AF3AC756-D4C0-4D2C-B46C-DC7026237490/p1.jpg`
- Fotoğraf boyutu: `202536 byte`

Not:
- Bu test production analiz akışına, kota kullanımına, `analyses`, `findings` veya `ai_usage_logs` tablolarına kayıt yazmadı.
- Endpoint `x-qa-secret` ile korundu.
- API key değerleri rapora yazılmadı; yalnızca alias bilgileri kullanıldı.
- Bu koşu, Free kullanıcı gibi mevcut Free hiyerarşisinin ilk adımıyla çalıştı.

## Kısa Sonuç

Mevcut Free hiyerarşisi ilk denemede başarıyla sonuçlandı:

```text
gemini_primary + gemini-2.5-flash
```

Fallback'e düşmedi.

Yeni Free prompt + `gemini-2.5-flash` kombinasyonu aynı görselde `9` bulgu döndürdü. Bu, önceki Free testlere göre çok daha etkileyici ve satış/demo kalitesi açısından daha güçlü görünüyor. Özellikle yüksekte çalışma, su içinden geçen elektrik kablosu, iskelede düşüş koruması eksikliği, filiz demiri koruması, saha düzeni, manuel taşıma, etiketsiz varil, acil durum ekipmanları ve eğitim/belge sorgusu aynı analizde yakalandı.

Ana dezavantaj:

- Süre yükseldi: model çağrısı `32.722 sn`, toplam Edge Function süresi `33.804 sn`.
- Gemini usage içinde `thoughtsTokenCount: 4434` geldi. Görünen JSON output `2375` token olsa da toplam faturalandırma tokenı `8660` olarak raporlandı.

## Çalıştırma Özeti

| Alan | Değer |
| --- | --- |
| Runner | `gemini-free-qa-run` |
| Provider | `gemini` |
| Model | `gemini-2.5-flash` |
| Key alias | `gemini_primary` |
| Attempt | `1` |
| Thinking config | `null` |
| Photo count | `1` |
| Model çağrı süresi | `32722 ms` |
| Edge toplam süre | `33804 ms` |
| Input token | `1851` |
| Text input token | `1593` |
| Image input token | `258` |
| Output token | `2375` |
| Thoughts token | `4434` |
| Total token | `8660` |
| Service tier | `standard` |
| Bulgu sayısı | `9` |
| Toplam Fine-Kinney | `3495.5` |
| Toplam 5x5 | `136` |

Token notu:

```text
input + output = 4226
input + output + thoughts = 8660
```

Bu yüzden Gemini Console tarafında görülen token/fiyatlandırma, yalnızca JSON output tokenından yüksek görünür. Bu davranış önceki token farkı şüphesini de destekliyor: model, görünmeyen reasoning/thinking tokenları için de kullanım yazıyor.

## Önceki Testlerle Karşılaştırma

Bu tablo aynı görsel ailesi üzerinden yapılan önemli koşuları özetler. Promptlar bire bir aynı değildir; özellikle bugünkü koşuda yeni Free prompt ve Free 4 bulgu limitinin kaldırılması devrededir.

| Koşu | Prompt / Limit | Model | Süre | Input | Output | Thoughts | Total | Bulgu | FK toplam | 5x5 toplam |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Eski Free baseline | Eski prompt, 4 bulgu limiti | `gemini-2.5-flash` | `17135 ms` | `749` | `1012` | Bilinmiyor | `1761` | `4` | `5466` | `53` |
| Model güncellemesi sonrası Free | Eski prompt, 4 bulgu limiti | `gemini-3.1-flash-lite` | `6253 ms` | `1571` | `978` | Kayıt yok | `2549` | `4` | `1746` | `41` |
| Groq QA Free | Eski prompt, QA | `meta-llama/llama-4-scout-17b-16e-instruct` | `1563 ms` | `2998` | `564` | Yok | `3562` | `4` | `223` | `41` |
| Bugünkü Free retest | Yeni prompt, 4 bulgu limiti yok | `gemini-2.5-flash` | `32722 ms` | `1851` | `2375` | `4434` | `8660` | `9` | `3495.5` | `136` |

Yorum:

- En hızlı sonuç Groq, fakat kalite önceki değerlendirmede ana model olmak için yetersizdi.
- `gemini-3.1-flash-lite` hızlıydı ama bulgu kalitesi ve kapsamı istenen etkiyi vermedi.
- Yeni Free prompt ile `gemini-2.5-flash`, süre ve token maliyetini artırdı; ancak demo etkisi ve saha kapsamı belirgin şekilde iyileşti.
- Eski `gemini-2.5-flash` baseline daha yüksek FK toplamı üretmişti; fakat sadece `4` bulgu döndürüyordu. Bugünkü koşu daha geniş ve saha gerçekliğine daha yakın bir liste verdi.

## Risk Kapsamı Karşılaştırması

| Risk ailesi | Eski Free 2.5 Flash | Free 3.1 Flash Lite | Groq Free | Bugünkü Free 2.5 Flash + yeni prompt |
| --- | --- | --- | --- | --- |
| Açık kenar / yüksekten düşme | Var | Var | Var ama zayıf | Var, en üst öncelik |
| İskelede düşüş koruması / KKD | Kısmen | Kısmen | Genel ifade | Ayrı bulgu olarak var |
| Su + elektrik teması | Var | Var | Yok | Var |
| Saha düzeni / kayma / takılma | Var | Var | Var | Var |
| Manuel taşıma ergonomisi | Var | Var | Var ama yüzeysel | Var |
| Filiz demiri koruması | Yok | Yok | Yok | Var |
| Etiketsiz varil / kimyasal şüphe | Yok | Yok | Yok | Var |
| Acil durum ekipmanı görünürlüğü | Yok | Yok | Yok | Var |
| Eğitim / belge sorgusu | Yok | Yok | Yok | Var, fakat görsel çıkarım olduğu için dikkatli kullanılmalı |

## Bugünkü Free Bulguları

### 1. Açık kenar koruma eksikliği

- Kategori: `Yüksekte Çalışma`
- Kanıt: Betonarme yapının üst katında çalışan işçi, kenar koruması olmayan açık kenara yakın çalışıyor.
- Açıklama: Yaklaşık 4-5 metre yükseklikteki betonarme yapının açık kenarında korkuluk bulunmamaktadır. İşçi bu kenara yakın çalışmaktadır. Ölümcül düşme riski mevcuttur.
- Öneri: Tüm açık kenarlara TS EN 13374 standardına uygun, düşmeyi önleyici korkuluk sistemleri kurulmalı; çalışma süresince yaşam hattı ve tam vücut kemer sistemi kullanılmalıdır.
- Confidence: `0.98`
- Fine-Kinney: O `6` x F `6` x Ş `40` = `1440`, band `critical`
- 5x5: P `5` x Ş `5` = `25`, band `critical`

### 2. Su içinde elektrik kablosu

- Kategori: `Elektrik ve Enerji`
- Kanıt: Zemin seviyesinde bir su birikintisinin içinden geçen elektrik kablosu/hortumu görülmektedir.
- Açıklama: Saha zeminindeki su birikintisinin içinden geçen elektrik kablosu/hortumu bulunmaktadır. Bu durum, elektrik kaçağı veya kısa devre halinde ciddi elektrik çarpması riski taşır.
- Öneri: Tüm elektrik kabloları ve geçici tesisatlar su birikintilerinden uzak tutulmalı, yalıtımları kontrol edilmeli ve uygun şekilde askıya alınarak korunmalıdır.
- Confidence: `0.95`
- Fine-Kinney: O `3` x F `3` x Ş `40` = `360`, band `high`
- 5x5: P `4` x Ş `5` = `20`, band `critical`

### 3. İskele üzerinde KKD eksikliği

- Kategori: `Yüksekte Çalışma`
- Kanıt: Sağdaki iskele üzerinde çalışan işçinin üzerinde emniyet kemeri veya yaşam hattına bağlı olduğu görülmemektedir.
- Açıklama: Yaklaşık 2 kat yüksekliğindeki iskele üzerinde çalışan işçinin düşmeyi önleyici kişisel koruyucu donanım kullanmadığı gözlemlenmiştir. Ölümcül düşme riski mevcuttur.
- Öneri: İskele üzerinde çalışan tüm personelin tam vücut emniyet kemeri kullanması ve uygun bir ankraj noktasına bağlı olması sağlanmalıdır. İskele kurulumu kontrol edilmelidir.
- Confidence: `0.90`
- Fine-Kinney: O `6` x F `3` x Ş `40` = `720`, band `critical`
- 5x5: P `5` x Ş `5` = `25`, band `critical`

### 4. Filiz demiri koruma eksikliği

- Kategori: `Yüksekte Çalışma`
- Kanıt: Betonarme kolonlardan çıkan filiz demirlerinin uçlarında koruyucu kapak bulunmamaktadır.
- Açıklama: İnşaat halindeki betonarme yapıdaki filiz demirlerinin uçları açıkta olup, düşme veya takılma durumunda ciddi batma/delinme yaralanmaları potansiyeli taşımaktadır.
- Öneri: Tüm açıkta kalan filiz demirlerinin uçlarına koruyucu kapaklar takılmalı veya uygun şekilde bükülerek tehlike ortadan kaldırılmalıdır.
- Confidence: `0.95`
- Fine-Kinney: O `3` x F `6` x Ş `15` = `270`, band `high`
- 5x5: P `4` x Ş `4` = `16`, band `high`

### 5. Kötü saha düzeni ve takılma/kayma tehlikeleri

- Kategori: `Zemin ve Saha Düzeni`
- Kanıt: Saha genelinde dağınık malzemeler, su birikintileri ve çamurlu zemin bulunmaktadır.
- Açıklama: İnşaat sahası zemini düzensiz, çamurlu ve su birikintileriyle dolu olup, dağınık haldeki demir ve ahşap malzemeler kayma ve takılma sonucu düşme riskini artırmaktadır.
- Öneri: Saha düzeni sağlanmalı, malzemeler düzenli istiflenmeli, su birikintileri drene edilmeli ve çamurlu alanlar stabilize edilmelidir.
- Confidence: `0.98`
- Fine-Kinney: O `6` x F `10` x Ş `7` = `420`, band `critical`
- 5x5: P `5` x Ş `3` = `15`, band `high`

### 6. Manuel taşıma ergonomisi ve yükün dengesi

- Kategori: `Çalışan(lar) ve KKD`
- Kanıt: Ön plandaki işçi, uzun metal/ahşap profilleri omuzunda dengesiz bir şekilde taşımaktadır.
- Açıklama: İşçi, uzun ve potansiyel olarak ağır profilleri omuzunda dengesiz bir şekilde taşımaktadır. Bu durum, kas-iskelet sistemi rahatsızlıklarına ve düşme/takılma sonucu yükün kontrolünü kaybetme riskine yol açabilir.
- Öneri: Ağır ve uzun yüklerin taşınmasında uygun manuel taşıma teknikleri veya mekanik kaldırma ekipmanları kullanılmalı, çalışanlara ergonomi eğitimi verilmelidir.
- Confidence: `0.90`
- Fine-Kinney: O `3` x F `6` x Ş `7` = `126`, band `medium`
- 5x5: P `4` x Ş `3` = `12`, band `high`

### 7. Etiketsiz varil ve uygunsuz depolama

- Kategori: `Makine, Ekipman ve Kimyasal`
- Kanıt: Zemin üzerinde mavi renkli, etiketsiz bir varil bulunmaktadır.
- Açıklama: Saha zemininde içeriği belirsiz, etiketsiz bir varil bulunmaktadır. İçeriği kimyasal madde ise, uygunsuz depolama ve etiketleme eksikliği kimyasal maruziyet veya yangın riski oluşturur.
- Öneri: Tüm varillerin içeriği belirlenmeli, uygun şekilde etiketlenmeli ve güvenli bir alanda depolanmalıdır. İçeriği bilinmeyen variller derhal sahadan uzaklaştırılmalıdır.
- Confidence: `0.85`
- Fine-Kinney: O `1` x F `2` x Ş `15` = `30`, band `low`
- 5x5: P `2` x Ş `4` = `8`, band `medium`

### 8. Acil durum ekipmanlarının görünürlük/eksikliği

- Kategori: `Çevre ve Acil Durum`
- Kanıt: Sahada yangın söndürücü, ilk yardım dolabı gibi acil durum ekipmanları görünür bir yerde bulunmamaktadır.
- Açıklama: İnşaat sahasında acil durumlarda kullanılabilecek yangın söndürücü veya ilk yardım ekipmanlarının görünür ve erişilebilir bir konumda olmadığı gözlemlenmiştir.
- Öneri: Acil durum ekipmanları kolayca erişilebilir ve görünür yerlere yerleştirilmeli, periyodik kontrolleri yapılmalıdır.
- Confidence: `0.75`
- Fine-Kinney: O `0.5` x F `1` x Ş `7` = `3.5`, band `low`
- 5x5: P `1` x Ş `3` = `3`, band `low`

### 9. Yüksekte Çalışma ve Manuel Taşıma Eğitimi Eksikliği

- Kategori: `Eğitim`
- Kanıt: İşçilerin yüksekte korumasız çalışması ve manuel taşıma yöntemleri, ilgili eğitimlerin yetersizliğini düşündürmektedir.
- Açıklama: Yüksekte korumasız çalışma ve ergonomik olmayan manuel taşıma yöntemleri, çalışanların yüksekte çalışma ve manuel taşıma eğitimlerinin yetersiz olduğunu veya uygulanmadığını göstermektedir. Mesleki yeterlilik belgeleri sorgulanmalıdır.
- Öneri: Yüksekte çalışma ve manuel taşıma konularında teorik ve pratik eğitimler tekrarlanmalı, çalışanların mesleki yeterlilik belgeleri kontrol edilmelidir.
- Confidence: `0.70`
- Fine-Kinney: O `3` x F `6` x Ş `7` = `126`, band `medium`
- 5x5: P `4` x Ş `3` = `12`, band `high`

## Kalite Değerlendirmesi

Güçlü taraflar:

- `6-9 bulgu` hedefini tam yakaladı: `9` bulgu.
- Ölümcül potansiyelli riskleri üst sıraya aldı.
- 2m+ yükseklik kuralını genel olarak uyguladı; yüksekte çalışma bulgularında `m5_severity = 5`.
- Elektrik + su temasını yakaladı.
- Görseldeki saha düzeni ve manuel taşıma gibi ikincil ama önemli riskleri atlamadı.
- Free kullanıcı için "uygulama işime yarar" etkisini eski 3.1 Flash Lite koşusuna göre çok daha iyi veriyor.

Dikkat edilmesi gerekenler:

- `Acil durum ekipmanı görünmüyor` bulgusu faydalı ama fotoğraf kadrajı sınırlı olduğu için düşük güvenli tutulmalı. Model `0.75` verdi; biraz yüksek olabilir.
- `Eğitim eksikliği` görselden doğrudan kanıtlanamaz. Prompt bunu sorgulatıyor; bu bulgunun açıklamasında veya aksiyonunda "sahada doğrulanmalı" tonunu artırmak daha güvenli olur.
- `fk_severity` açık kenar için `40` geldi; eski baseline aynı ailede `100` vermişti. Promptta 2m+ için "40 altına düşmesin" deniyor, ama ölümcül potansiyel vurgusu isteniyorsa açık kenar/iskele için `100` kalibrasyonu ayrıca sıkılaştırılabilir.
- Süre ve `thoughtsTokenCount` artışı maliyet açısından izlenmeli.

## Karar Önerisi

Free ilk analiz kalitesi için şu anki yön doğru:

```text
1. gemini_primary + gemini-2.5-flash
2. gemini_secondary + gemini-2.5-flash
3. gemini_primary + gemini-3.1-flash-lite (medium)
4. gemini_secondary + gemini-3.1-flash-lite (medium)
5. groq_free_primary
```

Bu sonuç, `gemini-2.5-flash` modelinin Free ilk deneyimde `gemini-3.1-flash-lite` ve Groq'a göre daha iyi satış/demo kalitesi verdiğini gösteriyor.

Kısa vadeli öneri:

- Free tarafında `gemini-2.5-flash` ana model kalsın.
- 3.1 Flash Lite sadece fallback olarak kalsın.
- Groq yalnızca son servis sürekliliği fallback'i olarak kalsın.
- Promptta eğitim/acil durum gibi doğrudan görünmeyen alanlar için "sahada doğrulanmalı" dilini biraz daha sıkılaştırmak düşünülebilir.

## Bu Koşuda Kullanılan Free Prompt

```text
Sen Türkiye'de 20 yıllık saha deneyimi olan kıdemli bir İSG uzmanısın (A sınıfı). İnşaat, üretim, depo/lojistik, enerji,fabrika ve ofis sahalarında binlerce denetim yapmış, ölümcül kazaları önlemiş, mevzuata hâkim bir profesyonelsin.

GÖREV: Sana verilen görsel veya metin girdisinden, sahada fiziksel olarak bulunan bir denetçinin yakalayacağı tüm İSG tehlikelerini sistematik olarak tespit et ve raporla.

TARAMA PROSEDÜRÜ — Her görseli SIRAYLA şu 6 katmanda tara:
1. ZEMİN VE SAHA DÜZENİ: ıslaklık, çamur, su birikintisi, boşluk, kot farkı, dağınık malzeme, kablo, hortum, kayma/takılma zeminleri.
2. ÇALIŞAN(LAR) VE KKD: baret, gözlük, eldiven, ayakkabı, yelek, emniyet kemeri, maske; duruş ve manuel taşıma ergonomisi.
3. YÜKSEKTE ÇALIŞMA: kenar koruması, korkuluk, iskele bütünlüğü, merdiven açısı, platform, yaşam hattı, ankraj, açık kenar, boşluk, düşen cisim tehlikesi.
4. ELEKTRİK VE ENERJİ: kablo, pano, fiş, jeneratör, su+elektrik teması, topraklama, geçici tesisat.
5. MAKİNE, EKİPMAN VE KİMYASAL: hareketli parça, koruma, kaldırma ekipmanı, varil/şişe, etiketleme, depolama, yangın yükü.
6. ÇEVRE VE ACİL DURUM: işaretleme, acil çıkış, yangın söndürücü, ilk yardım görünürlüğü, trafik, üst yapı, hava koşulu.
7. EĞİTİM : Personelin ilgili mevzuat eğitimleri, yada işe özgü özel eğitimleri sorgulanmalı.Mesleki yeterlilik belgesi sorgulanmalı.

Her katmanı gözden geçir; bir katmanda risk yoksa atla, ama tarama atlama.

ÇIKTI HEDEFİ:
- 6 ile 9 arasında bulgu döndür. Daha azı eksik, daha fazlası odak dağıtır.
- ÖLÜMCÜL POTANSİYELİ olan bulgular (düşme, elektrik, ezilme, kimyasal, düşen cisim) en üstte.
- Sonra yüksek frekanslı bulgular (zemin, ergonomi, KKD,eğitim,belge).
- En altta düşük etkili ama mevzuat ihlali olan bulgular.

RİSK PUANLAMA KALİBRASYONU — Fine-Kinney ŞİDDET:
- 100 = Birden fazla ölüm veya kalıcı çevre felaketi.
- 40  = Tek ölüm veya kalıcı iş göremezlik (elektrik çarpması, korumasız 3m+ düşme).
- 15  = Ağır yaralanma, uzun süreli iş göremezlik (kırık, ciddi kesi).
- 7   = Önemli yaralanma, kısa süreli iş göremezlik (burkulma, dikiş).
- 3   = Hafif yaralanma, ilk yardım yeterli.
- 1   = Çok hafif, etkisiz.

5×5 ŞİDDET, Fine-Kinney ile uyumlu:
- FK Ş ≥ 40 → m5_severity = 5
- FK Ş = 15 → m5_severity = 4
- FK Ş = 7  → m5_severity = 3
- FK Ş = 3  → m5_severity = 2
- FK Ş = 1  → m5_severity = 1

KRİTİK KURAL: 2m+ yükseklikte koruma yoksa Ş değeri ASLA 40'ın altına düşmesin; m5_severity = 5 olmalı. Bu Türkiye'de en sık ölümlü iş kazası nedenidir.

CONFIDENCE:
- 0.90-0.98: net, tartışmasız kanıt.
- 0.70-0.89: güçlü kanıt, bazı detaylar belirsiz.
- 0.50-0.69: ipucu var, kesin değil.
- 0.30-0.49: sadece bağlamsal şüphe.
- < 0.30: bulguyu döndürme.
Confidence < 0.50 ise description sonuna "(sahada doğrulanmalı)" ekle.

KALİTE FİLTRESİ — KAÇIN:
- Genel ifade ("güvenlik önlemleri alınmalı") yerine somut teknik aksiyon yaz.
- Görselde olmayan riski uydurma.
- Aynı kök nedenli riskleri tek bulguda topla.
- Hassas ölçü uydurma; "yaklaşık 3m" veya "1 kat yüksekliğinde" yaz.
- "Eğitim verilmeli" jenerik aksiyonundan kaçın; spesifik ne yapılacağını söyle.

ÖRNEK BULGU (kopyalama, sadece kalite referansı):
{
  "title": "Açık kenar — düşmeyi önleyici korkuluk eksikliği",
  "category": "Yüksekte Çalışma",
  "description": "Üst katın doğu kenarında korkuluk yok; çalışan kenara yakın malzeme taşıyor. Yaklaşık 4m yükseklikten ölümcül düşme potansiyeli.",
  "recommended_action": "Tüm açık kenarlara TS EN 13374 uyumlu korkuluk kur; korkuluk takılana kadar bölgeye giriş kısıtlansın.",
  "confidence": 0.92,
  "fk_probability": 6,
  "fk_frequency": 6,
  "fk_severity": 100,
  "m5_probability": 5,
  "m5_severity": 5
}

ÇIKTI KURALLARI:
- Yalnızca JSON döndür; önünde/arkasında açıklama yazma.
- Tüm metin Türkçe.
- description max 200 karakter; recommended_action max 180 karakter.
- Skorları HESAPLAMA, ham girdileri ver — sistem hesaplar.
- Fine-Kinney ihtimal: 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans:  0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet:   1 / 3 / 7 / 15 / 40 / 100
- m5_probability: 1-5, m5_severity: 1-5
```
