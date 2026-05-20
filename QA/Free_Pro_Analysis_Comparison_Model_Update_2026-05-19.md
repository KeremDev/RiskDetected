# Free / Pro Analiz Karşılaştırması - Model Güncellemesi Sonrası - 2026-05-19

Kaynaklar:
- Canlı Supabase `analyses`, `findings`, `photos` ve `ai_usage_logs` kayıtlarından başarılı sorgular.
- Önceki karşılaştırma raporu: `QA/Free_Pro_Analysis_Comparison_2026-05-19.md`

Notlar:
- API key değerleri rapora yazılmadı; yalnızca güvenli alias bilgileri kullanıldı.
- Bu rapordaki token değerleri uygulamanın `ai_usage_logs` tablosuna yazdığı değerlerdir. Gemini Console tarafında görünen faturalandırma tokenları, özellikle thinking/internal reasoning tokenları nedeniyle farklı olabilir.
- Supabase CLI son ek tekrar sorgusunda geçici bağlantı circuit-breaker hatasına düştü. Ana analiz, bulgu, prompt, token ve fotoğraf verileri daha önceki başarılı sorgulardan alınmıştır.

## Kısa Sonuç

Model değişikliği sonrası aynı görselde iki hesap da ilk denemede ve fallback'e düşmeden sonuçlandı.

- Free: `gemini_primary` + `gemini-3.1-flash-lite`, `thinkingLevel: low`
- Pro: `gemini_paid_primary` + `gemini-3.1-flash-lite`, `thinkingLevel: medium`
- İki analizde de aynı görsel kullanılmış görünüyor: `351x522`, `202536 byte`, `1` fotoğraf.
- Yeni model ailesi ciddi hız kazandırdı: Free yaklaşık `%63.5`, Pro yaklaşık `%84.8` daha hızlı.
- Pro analiz artık çok hızlı; ancak eski `gemini-2.5-pro` koşusuna göre daha az bulgu üretti: `7` yerine `4`.
- Yeni Pro analizi, yüksekte çalışma riskini daha yüksek öncelik ve mevzuat referansı ile verdi; fakat Free analizde yakalanan elektrik kablosu/su teması bulgusunu bu koşuda döndürmedi.

## Yeni Analizler

| Alan | Free analiz | Pro analiz |
| --- | --- | --- |
| Analysis ID | `af3ac756-d4c0-4d2c-b46c-dc7026237490` | `a406ec24-c07f-476e-a2d3-a1ea46983844` |
| User ID | `70cc0ebb-0d32-42f1-ac9b-976b13bd2295` | `b009a2bf-5d95-4521-8b11-467c462e7d43` |
| Başlık | `Genel · 19 May 22:25` | `Genel Premium + Sektör + Yüksekte Çalışma · 19 May 22:27` |
| Plan | `free` | `pro` |
| Girdi | Fotoğraf | Fotoğraf |
| Mod | `standard` | `detailed` |
| Canvas | `general` | `general_premium`, `sector`, `working_at_height` |
| Provider | `gemini` | `gemini` |
| Model | `gemini-3.1-flash-lite` | `gemini-3.1-flash-lite` |
| Key pool / alias | `free` / `gemini_primary` | `paid` / `gemini_paid_primary` |
| Thinking config | `{ "thinkingLevel": "low" }` | `{ "thinkingLevel": "medium" }` |
| Attempt | `1` | `1` |
| Fallback | Yok | Yok |
| Support ID | `RD-159CC3E5` | `RD-ABF595F1` |
| Request ID | `72481BEA-6E6F-4292-BC36-DE67B722DE5D` | `935E7FB9-F4A5-4271-A935-5F1B4570D491` |

## Fotoğraf Kanıtı

| Alan | Free | Pro |
| --- | --- | --- |
| Fotoğraf sayısı | `1` | `1` |
| Genişlik | `351` | `351` |
| Yükseklik | `522` | `522` |
| Byte | `202536` | `202536` |
| Storage path | `70cc0ebb-0d32-42f1-ac9b-976b13bd2295/AF3AC756-D4C0-4D2C-B46C-DC7026237490/p1.jpg` | `b009a2bf-5d95-4521-8b11-467c462e7d43/A406EC24-C07F-476E-A2D3-A1EA46983844/p1.jpg` |

Değerlendirme: Boyut ve byte değerleri bire bir aynı olduğu için iki analizde aynı görselin kullanıldığı çok güçlü şekilde doğrulanıyor.

## Süre ve Token

| Metrik | Free | Pro |
| --- | ---: | ---: |
| `ai_usage_logs.duration_ms` | `6253 ms` | `6682 ms` |
| DB started-completed | `5.732 sn` | `6.456 sn` |
| Input token | `1571` | `1838` |
| Output token | `978` | `1023` |
| Toplam kayıtlı token | `2549` | `2861` |
| Bulgu sayısı | `4` | `4` |
| Toplam Fine-Kinney | `1746` | `4506` |
| Toplam 5x5 | `41` | `51` |
| En yüksek FK bandı | `critical` | `critical` |
| En yüksek 5x5 bandı | `high` | `critical` |

Yeni Pro, yeni Free'e göre:

- Süre: `%6.9` daha uzun.
- Input token: `%17.0` daha fazla.
- Output token: `%4.6` daha fazla.
- Toplam kayıtlı token: `%12.2` daha fazla.
- Fine-Kinney toplamı: `%158.1` daha yüksek.
- 5x5 toplamı: `%24.4` daha yüksek.

## Dünkü Raporla Karşılaştırma

Önceki raporda kullanılan modeller:

- Eski Free: `gemini-2.5-flash`
- Eski Pro: `gemini-2.5-pro`

Bugünkü yeni modeller:

- Yeni Free: `gemini-3.1-flash-lite`
- Yeni Pro: `gemini-3.1-flash-lite`

| Metrik | Eski Free | Yeni Free | Değişim |
| --- | ---: | ---: | ---: |
| Usage duration | `17.135 sn` | `6.253 sn` | `-63.5%` |
| DB duration | `16.512 sn` | `5.732 sn` | `-65.3%` |
| Input token | `749` | `1571` | `+109.7%` |
| Output token | `1012` | `978` | `-3.4%` |
| Toplam token | `1761` | `2549` | `+44.7%` |
| Bulgu sayısı | `4` | `4` | `0.0%` |
| Toplam Fine-Kinney | `5466` | `1746` | `-68.1%` |
| Toplam 5x5 | `53` | `41` | `-22.6%` |

| Metrik | Eski Pro | Yeni Pro | Değişim |
| --- | ---: | ---: | ---: |
| Usage duration | `43.968 sn` | `6.682 sn` | `-84.8%` |
| DB duration | `43.679 sn` | `6.456 sn` | `-85.2%` |
| Input token | `1016` | `1838` | `+80.9%` |
| Output token | `2116` | `1023` | `-51.7%` |
| Toplam token | `3132` | `2861` | `-8.7%` |
| Bulgu sayısı | `7` | `4` | `-42.9%` |
| Toplam Fine-Kinney | `10770` | `4506` | `-58.2%` |
| Toplam 5x5 | `112` | `51` | `-54.5%` |

## Input Audit

### Free

- `analysis_mode`: `standard`
- `input_mode`: `photo`
- `inline_photo_count`: `1`
- `storage_photo_count`: `0`
- `persisted_photo_count`: `1`
- `gemini_image_part_count`: `1`
- `selected_canvas_ids`: `general`
- `references_requested`: `false`
- `response_schema_includes_references`: `false`
- `gemini_key_aliases_available`: `gemini_primary`, `gemini_secondary`
- `gemini_key_pool`: `free`
- `gemini_thinking_config`: `{ "thinkingLevel": "low" }`
- `groq_free_fallback_configured`: `true`
- `groq_free_model`: `meta-llama/llama-4-scout-17b-16e-instruct`
- `groq_plus_pro_fallback_configured`: `false`

Canvas prompt:

```text
Görüntüdeki tüm görünür İSG uygunsuzluklarını tara; düşme, çarpma, sıkışma, elektrik, yangın, kimyasal, düzen-temizlik, KKD, işaretleme, acil çıkış ve çalışma alanı risklerini önceliklendir.
```

### Pro

- `analysis_mode`: `detailed`
- `input_mode`: `photo`
- `inline_photo_count`: `1`
- `storage_photo_count`: `0`
- `persisted_photo_count`: `1`
- `gemini_image_part_count`: `1`
- `selected_canvas_ids`: `general_premium`, `sector`, `working_at_height`
- `references_requested`: `true`
- `response_schema_includes_references`: `true`
- `gemini_key_aliases_available`: `gemini_paid_primary`
- `gemini_key_pool`: `paid`
- `gemini_thinking_config`: `{ "thinkingLevel": "medium" }`
- `groq_plus_pro_fallback_configured`: `true`
- `groq_plus_pro_model`: `meta-llama/llama-4-scout-17b-16e-instruct`
- `groq_free_fallback_configured`: `false`

Canvas promptları:

```text
general_premium:
Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver.

sector:
Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt.

working_at_height:
Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.
```

## Gönderilen Sistem Promptları

### Free Prompt

```text
Sen deneyimli bir iş güvenliği (HSE/İSG) uzmanısın. Görevin: verilen görsel ve/veya metin girdisinden İSG tehlikelerini ve risklerini tespit etmek.

ORTAK YAKLAŞIM:
Fotoğrafı iş güvenliği uzmanı saha gözlemi gibi analiz et. Sadece görüntüde görülen bulgulara dayan. Görünmeyen veya emin olmadığın noktaları "kontrol edilmeli" diye belirt.


ODAK: Görüntüdeki tüm görünür İSG uygunsuzluklarını tara; düşme, çarpma, sıkışma, elektrik, yangın, kimyasal, düzen-temizlik, KKD, işaretleme, acil çıkış ve çalışma alanı risklerini önceliklendir.

KURALLAR:
- Yalnızca fotoğrafta/metinde GÖZLEMLENEN kanıtlara dayan. Tahmin etme.
- Emin olmadığın noktalar için confidence değerini düşür (0.3–0.6).
- En fazla 4 tehlike döndür; önem sırasına göre sırala.
- Her tehlike için description alanını kısa tut; yalnızca görünen kanıt ve riskin özünü 1-2 kısa cümleyle anlat.
- Her tehlike için recommended_action alanını kısa, uygulanabilir ve en fazla 180 karakter olacak şekilde yaz.

- Her tehlike için Fine-Kinney girdilerini (fk_probability, fk_frequency, fk_severity) ve 5×5 girdilerini (m5_probability 1-5, m5_severity 1-5) öner.
- Fine-Kinney ihtimal değerleri (sadece bunlar): 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans değerleri (sadece bunlar): 0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet değerleri (sadece bunlar): 1 / 3 / 7 / 15 / 40 / 100
- Skorları hesaplama — yalnızca ham girdileri ver; sistem hesaplar.
- Türkçe yanıt ver.
- Yalnızca JSON döndür.
```

### Pro Prompt

```text
Sen deneyimli bir iş güvenliği (HSE/İSG) uzmanısın. Görevin: verilen görsel ve/veya metin girdisinden İSG tehlikelerini ve risklerini tespit etmek.

ORTAK YAKLAŞIM:
Fotoğrafı iş güvenliği uzmanı saha gözlemi gibi analiz et. Sadece görüntüde görülen bulgulara dayan. Görünmeyen veya emin olmadığın noktaları "kontrol edilmeli" diye belirt.

PRO MEVZUAT REFERANSI:
Fotoğrafı Türkiye İSG mevzuatı perspektifiyle değerlendir. Her bulgu için Türkiye İSG mevzuatıyla ilişkili uygun kanun/yönetmelik başlığını references alanında kısa yaz. References alanı kısaltılmış kanun/yönetmelik adı ve biliyorsan kısa madde bilgisini içersin; emin değilsen madde uydurma, "mevzuat karşılığı kontrol edilmeli" yaz. Standart numarası, ölçüm değeri veya uzun açıklama uydurma.

ODAK: Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver. Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt. Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.

KURALLAR:
- Yalnızca fotoğrafta/metinde GÖZLEMLENEN kanıtlara dayan. Tahmin etme.
- Emin olmadığın noktalar için confidence değerini düşür (0.3–0.6).
- En fazla 10 tehlike döndür; önem sırasına göre sırala.
- Her tehlike için description alanını kısa tut; yalnızca görünen kanıt ve riskin özünü 1-2 kısa cümleyle anlat.
- Her tehlike için recommended_action alanını kısa, uygulanabilir ve en fazla 180 karakter olacak şekilde yaz.
- Her tehlike için references alanını kısa tut; kısaltılmış kanun/yönetmelik adı + varsa kısa madde bilgisini yaz veya "mevzuat karşılığı kontrol edilmeli" yaz.
- Her tehlike için Fine-Kinney girdilerini (fk_probability, fk_frequency, fk_severity) ve 5×5 girdilerini (m5_probability 1-5, m5_severity 1-5) öner.
- Fine-Kinney ihtimal değerleri (sadece bunlar): 0.2 / 0.5 / 1 / 3 / 6 / 10
- Fine-Kinney frekans değerleri (sadece bunlar): 0.5 / 1 / 2 / 3 / 6 / 10
- Fine-Kinney şiddet değerleri (sadece bunlar): 1 / 3 / 7 / 15 / 40 / 100
- Skorları hesaplama — yalnızca ham girdileri ver; sistem hesaplar.
- Türkçe yanıt ver.
- Yalnızca JSON döndür.
```

## AI Özetleri

### Free

İnşaat sahasında genel bir düzen eksikliği, yüksekte çalışma güvenliği zafiyetleri ve elektrik kablolarının suyla teması gibi kritik İSG riskleri gözlemlenmiştir. Saha düzeni ve kişisel koruyucu donanım kullanımı acilen iyileştirilmelidir.

### Pro

İnşaat sahasında yüksekten düşme riski en kritik tehlikedir. Özellikle yapı kenarlarındaki koruma eksikliği ve düzensiz zemin koşulları kaza potansiyelini artırmaktadır. Manuel yük taşıma ve iskele güvenliği de acil iyileştirme gerektiren alanlardır.

## Yeni Free Bulguları

### 1. Düzensiz ve Kaygan Çalışma Zemini

- Kategori: `Düzen ve Temizlik`
- Güven: `0.95`
- Kanıt/risk: Çalışma alanında su birikintileri, çamur ve dağınık inşaat malzemeleri görülüyor. Zemin koşulları takılma, düşme ve kayma riskini artırıyor.
- Öneri: Çalışma sahası düzenlenmeli, su birikintileri tahliye edilmeli ve malzemeler düzenli istiflenerek yürüme yolları temiz tutulmalıdır.
- Fine-Kinney: O `6` × F `6` × Ş `7` = `252`, band `high`
- 5x5: P `4` × Ş `2` = `8`, band `medium`

### 2. Yüksekte Çalışma ve Düşme Riski

- Kategori: `Yüksekte Çalışma`
- Güven: `0.8`
- Kanıt/risk: Arka planda iskele üzerinde ve betonarme yapının üst katında korkuluksuz veya korumasız alanlarda çalışanlar görülüyor. Düşmeyi önleyici sistemler net değil.
- Öneri: Yüksekte çalışma alanlarına standartlara uygun korkuluklar takılmalı, çalışanlar emniyet kemeri ve yaşam hattı kullanmalıdır.
- Fine-Kinney: O `3` × F `6` × Ş `40` = `720`, band `critical`
- 5x5: P `3` × Ş `5` = `15`, band `high`

### 3. Manuel Yük Taşıma ve Ergonomi

- Kategori: `Ergonomi`
- Güven: `0.9`
- Kanıt/risk: Ön plandaki çalışan ağır bir metal profili omzunda tek başına taşıyor. Kas-iskelet sistemi yaralanması ve dengesizlik riski var.
- Öneri: Yükün ağırlığına göre ekipman kullanılmalı veya yük iki kişiyle taşınmalıdır. Çalışanlara doğru kaldırma teknikleri eğitimi verilmelidir.
- Fine-Kinney: O `3` × F `6` × Ş `3` = `54`, band `low`
- 5x5: P `3` × Ş `2` = `6`, band `medium`

### 4. Elektrik Kablosu ve Ekipman Güvenliği

- Kategori: `Elektrik`
- Güven: `0.85`
- Kanıt/risk: Betoniyerin yakınında yerde serili elektrik kabloları ve su birikintisine yakın temas görülüyor. Kısa devre, elektrik çarpması ve yangın riski var.
- Öneri: Kablolar yerden yükseltilmeli veya koruyucu kanallar içine alınmalıdır. Elektrik bağlantıları su temasından korunmalıdır.
- Fine-Kinney: O `3` × F `6` × Ş `40` = `720`, band `critical`
- 5x5: P `3` × Ş `4` = `12`, band `high`

Free limitations:

```text
Fotoğrafın statik olması nedeniyle, yüksekte çalışanların emniyet kemeri kullanıp kullanmadığı veya elektrik kablolarının enerjili olup olmadığı kesin olarak teyit edilememektedir.
```

## Yeni Pro Bulguları

### 1. Yüksekte Çalışma ve Kenar Koruması Eksikliği

- Kategori: `Düşme`
- Güven: `0.9`
- Kanıt/risk: Arka planda görülen betonarme yapının üst katlarında kenar koruması bulunmuyor. Açık kenarlarda düşmeyi önleyici korkuluk veya bariyer yok.
- Öneri: Tüm açık kenarlara standartlara uygun korkuluk sistemi kurulmalı, çalışma platformları güvenli hale getirilmelidir.
- Mevzuat: `Yapı İşlerinde İSG Yönetmeliği, Ek-4`
- Fine-Kinney: O `6` × F `6` × Ş `100` = `3600`, band `critical`
- 5x5: P `5` × Ş `5` = `25`, band `critical`

### 2. Düzensiz Saha ve Takılma/Düşme Riski

- Kategori: `Ergonomi ve Saha Düzeni`
- Güven: `0.9`
- Kanıt/risk: Zemin çamurlu, su birikintileri var ve etrafta dağınık inşaat malzemeleri bulunuyor. Takılıp düşme ve yaralanma riski var.
- Öneri: Saha düzenli tutulmalı, geçiş yolları temizlenmeli ve zemin drenajı sağlanmalıdır.
- Mevzuat: `İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik`
- Fine-Kinney: O `6` × F `10` × Ş `7` = `420`, band `critical`
- 5x5: P `4` × Ş `2` = `8`, band `medium`

### 3. Manuel Yük Taşıma

- Kategori: `Ergonomi`
- Güven: `0.8`
- Kanıt/risk: Ön plandaki çalışan omzunda ağır bir metal profil taşıyor. Uygunsuz taşıma yöntemi kas-iskelet yaralanması ve düşmeye yol açabilir.
- Öneri: Yükler mekanik taşıma araçları ile taşınmalı, manuel taşıma zorunluysa ergonomik kurallara uyulmalıdır.
- Mevzuat: `Elle Taşıma İşleri Yönetmeliği`
- Fine-Kinney: O `3` × F `6` × Ş `7` = `126`, band `medium`
- 5x5: P `3` × Ş `2` = `6`, band `medium`

### 4. İskele Güvenliği

- Kategori: `Yüksekte Çalışma`
- Güven: `0.6`
- Kanıt/risk: Sağ tarafta görülen iskele sisteminde eksiklikler ve platform sürekliliği belirsiz. Düşme riski barındırıyor.
- Öneri: İskele kurulumu yetkili personelce kontrol edilmeli, platformlar eksiksiz ve korkuluklu olmalıdır.
- Mevzuat: `Yapı İşlerinde İSG Yönetmeliği, İskeleler`
- Fine-Kinney: O `3` × F `3` × Ş `40` = `360`, band `high`
- 5x5: P `3` × Ş `4` = `12`, band `high`

Pro limitations:

```text
Fotoğrafın perspektifi nedeniyle iskele detayları ve yüksekteki çalışanların emniyet kemeri kullanımı tam olarak net değildir, bu noktalar sahada fiziksel olarak doğrulanmalıdır.
```

## Eski Raporun Bulgularıyla Fark

### Free Eski -> Yeni

Eski Free `gemini-2.5-flash` ile 4 bulgu üretmişti:

1. Yüksekten düşme riski
2. Düzensiz çalışma alanı ve kayma/takılma tehlikesi
3. Elektrik tehlikesi
4. Manuel taşıma ve ergonomi riski

Yeni Free `gemini-3.1-flash-lite` ile yine 4 bulgu üretti:

1. Düzensiz ve kaygan çalışma zemini
2. Yüksekte çalışma ve düşme riski
3. Manuel yük taşıma ve ergonomi
4. Elektrik kablosu ve ekipman güvenliği

Değerlendirme:

- Bulgu kapsamı büyük ölçüde aynı.
- Yeni Free risk puanlamasında daha konservatif davrandı.
- Eski Free yüksekte çalışma bulgusunu FK `3600`, 5x5 `20` olarak görürken, yeni Free FK `720`, 5x5 `15` verdi.
- Yeni Free zemin/düzen bulgusunu ilk sıraya aldı; bu, görseldeki saha düzensizliğini daha baskın algıladığını gösteriyor.
- Elektrik bulgusu her iki Free koşusunda da yakalandı.

### Pro Eski -> Yeni

Eski Pro `gemini-2.5-pro` ile 7 bulgu üretmişti:

1. Yüksekten düşme riski - bina kenarı
2. Güvensiz iskele ve yüksekten düşme riski
3. Saha düzensizliği ve takılıp düşme riski
4. Elektrik çarpması riski
5. Kayma ve düşme riski - ıslak ve çamurlu zemin
6. Yukarıdan malzeme düşmesi riski
7. Manuel taşıma ve ergonomik riskler

Yeni Pro `gemini-3.1-flash-lite` ile 4 bulgu üretti:

1. Yüksekte çalışma ve kenar koruması eksikliği
2. Düzensiz saha ve takılma/düşme riski
3. Manuel yük taşıma
4. İskele güvenliği

Değerlendirme:

- Yeni Pro çok daha hızlı ve ucuz olması beklenen yola geçti.
- Yeni Pro, ana ölümcül risk olan yüksekte çalışma/kenar korumasını doğru şekilde en kritik bulgu yaptı.
- Yeni Pro mevzuat referanslarını üretmeye devam etti.
- Eski Pro'da ayrı gelen `Elektrik Çarpması Riski`, `Kayma ve Düşme Riski`, `Yukarıdan Malzeme Düşmesi Riski` yeni Pro'da ayrı bulgu olarak dönmedi.
- Bunun nedeni büyük olasılıkla iki faktörün birleşimi:
  - Model değişimi: `gemini-2.5-pro` daha kapsamlı ve pahalı modeldi.
  - Canvas seçimi: Pro koşusu `working_at_height` odağı içerdiği için yüksekte çalışma bulguları daha baskın hale geldi.

## Kalite Değerlendirmesi

### Free Kalitesi

Yeni Free için sonuç tatmin edici:

- Aynı 4 ana risk ailesini yakaladı.
- 6.25 saniyelik süre mobil kullanıcı deneyimi için iyi.
- Elektrik + su temasını kaçırmadı.
- Free seviyesinde kısa ve anlaşılır çıktı verdi.

Risk:

- Yüksekte çalışma skoru eski Free'e göre düşük kaldı. Görselde ölümcül düşme potansiyeli bulunduğu için 5x5 tarafında `critical` yerine `high` vermesi tartışmalı.

### Pro Kalitesi

Yeni Pro için sonuç hızlı ve mevzuatlı:

- 6.68 saniyede Pro analiz üretmesi çok güçlü.
- Yüksekte çalışma bulgusunu doğru şekilde kritik verdi.
- Mevzuat alanı dolu geldi.
- Fine-Kinney en yüksek skor `3600`, 5x5 en yüksek skor `25`.

Risk:

- Eski Pro'ya göre kapsam belirgin daraldı: 7 bulgudan 4 bulguya indi.
- Elektrik riski Free'de yakalanırken Pro'da ayrı bulgu olarak dönmedi.
- Pro kullanıcısına "daha kapsamlı analiz" vaadi varsa, yalnızca `gemini-3.1-flash-lite` ile bu prompt altında kapsam kaybı oluşabilir.

## Token Notu

Bu rapordaki tokenlar uygulamanın tuttuğu `tokens_in` ve `tokens_out` değerleridir.

Önemli ayrım:

- `tokens_in`: Gemini tarafına gönderilen prompt + görsel girdisinin kaydedilen input token değeri.
- `tokens_out`: Uygulamada kaydedilen aday çıktı tokenı.
- Thinking/internal reasoning tokenları Gemini Console tarafında faturalandırmaya dahil edilebiliyor, fakat mevcut loglama bu ayrımı ayrı bir kolon olarak saklamıyor.

Bu yüzden:

- DB'deki `tokens_out` değeri ile Gemini Console'daki billable output token bire bir tutmayabilir.
- Özellikle `thinkingLevel: medium` kullanılan Pro koşusunda Console tarafında daha yüksek output/thinking token görülebilir.
- Dünkü `gemini-2.5-pro` farkı da aynı sınıfa giriyor: uygulama `2116` output yazmışken Console daha yüksek değer göstermişti.

Öneri:

- AI usage log şemasına `thoughts_tokens`, `total_billable_tokens`, `prompt_tokens`, `candidates_tokens` gibi ayrı kolonlar eklenmeli.
- Gemini response içindeki tüm `usageMetadata` ham olarak güvenli bir JSON kolonda saklanmalı.
- Böylece maliyet hesabı DB üzerinden gerçekçi yapılabilir.

## Teknik Yorum

Yeni yapı servis sürekliliği açısından doğru çalıştı:

- Free Gemini havuzu ilk sıradan sonuç verdi.
- Paid Gemini havuzu ilk sıradan sonuç verdi.
- Fallback tetiklenmedi.
- Groq fallback hazır ama bu koşuda kullanılmadı.

Model/kalite dengesi açısından:

- Free için `gemini-3.1-flash-lite` ilk sırada mantıklı görünüyor.
- Pro için `gemini-3.1-flash-lite` hızı çok iyi, fakat kapsamı artırmak için ek kalite önlemi gerekebilir.

Pro/Plus için düşünülebilecek iyileştirme:

1. `gemini-3.1-flash-lite` hızlı ilk analiz olarak kalsın.
2. Eğer Pro analizde bulgu sayısı `4` altında kalırsa veya yüksek riskli sahada elektrik/düşen cisim/zemin gibi ana risk aileleri hiç dönmezse, ikinci doğrulama geçişi çalışsın.
3. İkinci geçişte `gemini-2.5-flash` veya belirli durumlarda `gemini-2.5-pro` devreye girsin.
4. Bu ikinci geçiş yalnızca eksik risk ailelerini kontrol etsin; maliyet tam Pro analiz kadar artmasın.

## Sonuç

Bugünkü model değişikliği performans açısından çok başarılı:

- Free: 17.1 sn -> 6.25 sn
- Pro: 44.0 sn -> 6.68 sn

Fakat kalite/kapsam tarafında özellikle Pro için bir kontrol katmanı gerekiyor. Yeni Pro sonucu ana yüksekten düşme riskini doğru yakalıyor, ancak eski Pro'nun yakaladığı elektrik ve düşen cisim gibi bazı bulguları ayrı madde olarak döndürmedi. Bu nedenle Pro/Plus tarafında `3.1-flash-lite` hız avantajı korunurken, kapsam eksikliği durumunda ikinci geçiş veya risk ailesi doğrulaması eklemek en dengeli yol olur.
