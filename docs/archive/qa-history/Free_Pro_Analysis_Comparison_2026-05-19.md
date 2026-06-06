# Free / Pro Analiz Karşılaştırması - 2026-05-19

Kaynak: Canlı Supabase `analyses`, `findings` ve `ai_usage_logs` kayıtları.  
Sorgu zamanı: 2026-05-19, Türkiye saati.  
Not: API key değerleri rapora yazılmadı; yalnızca güvenli key alias bilgileri kullanıldı.

## Kısa Özet

| Alan | Free analiz | Pro analiz |
| --- | --- | --- |
| Analysis ID | `70be3aca-e641-42fe-830e-1c11a4e38435` | `0c7174db-844c-4631-a4ca-3e7292368135` |
| Başlık | Genel · 19 May 00:12 | Genel Premium + Sektör + Yüksekte Çalışma · 19 May 00:13 |
| Plan | Free | Pro |
| Girdi | Fotoğraf | Fotoğraf |
| Mod | Standard | Detailed |
| Canvas | `general` | `general_premium`, `sector`, `working_at_height` |
| Model | `gemini-2.5-flash` | `gemini-2.5-pro` |
| Key pool / alias | `free` / `gemini_primary` | `paid` / `gemini_paid_primary` |
| Attempt | 1 | 1 |
| Fallback | Yok | Yok |
| Usage duration | 17.135 sn | 43.968 sn |
| DB started-completed | 16.512 sn | 43.679 sn |
| Input token | 749 | 1016 |
| Output token | 1012 | 2116 |
| Toplam token | 1761 | 3132 |
| Bulgu sayısı | 4 | 7 |
| Toplam Fine-Kinney | 5466 | 10770 |
| Toplam 5x5 | 53 | 112 |
| En yüksek FK bandı | critical | critical |
| En yüksek 5x5 bandı | critical | critical |
| Support ID | `RD-2F79E8D1` | `RD-CB442940` |

## Zaman Bilgisi

### Free

- Oluşturulma: `2026-05-19 00:12:32.638856`
- Başlama: `2026-05-19 00:12:34.474`
- Tamamlanma: `2026-05-19 00:12:50.986`
- `ai_usage_logs.duration_ms`: `17135`
- DB süre hesabı: `16.512` saniye

### Pro

- Oluşturulma: `2026-05-19 00:13:47.425752`
- Başlama: `2026-05-19 00:13:48.024`
- Tamamlanma: `2026-05-19 00:14:31.703`
- `ai_usage_logs.duration_ms`: `43968`
- DB süre hesabı: `43.679` saniye

## Input Audit

### Free

- `input_mode`: `photo`
- `inline_photo_count`: `1`
- `storage_photo_count`: `0`
- `persisted_photo_count`: `1`
- `gemini_image_part_count`: `1`
- `selected_canvas_ids`: `general`
- `user_prompt`: `null`
- `references_requested`: `false`
- `response_schema_includes_references`: `false`
- `gemini_key_aliases_available`: `gemini_primary`, `gemini_secondary`

Canvas prompt:

```text
Görüntüdeki tüm görünür İSG uygunsuzluklarını tara; düşme, çarpma, sıkışma, elektrik, yangın, kimyasal, düzen-temizlik, KKD, işaretleme, acil çıkış ve çalışma alanı risklerini önceliklendir.
```

### Pro

- `input_mode`: `photo`
- `inline_photo_count`: `1`
- `storage_photo_count`: `0`
- `persisted_photo_count`: `1`
- `gemini_image_part_count`: `1`
- `selected_canvas_ids`: `general_premium`, `sector`, `working_at_height`
- `user_prompt`: `null`
- `references_requested`: `true`
- `response_schema_includes_references`: `true`
- `gemini_key_aliases_available`: `gemini_paid_primary`

Canvas promptları:

```text
general_premium:
Tüm görünür İSG risklerini denetim odaklı ve ayrıntılı analiz et. Bulguları kritik seviyeden düşüğe sırala; her biri için kök neden, olası kaza senaryosu, acil aksiyon ve mevzuat karşılığını ver.

sector:
Sektör bağlamını tahmin et; inşaat, üretim, depo/lojistik, ofis veya saha çalışmasına özgü tipik İSG risklerini görünür bulgularla ilişkilendir. Tahmin belirsizse açıkça belirt.

working_at_height:
Düşme tehlikesi, korkuluk, iskele, merdiven, platform, yaşam hattı, ankraj, emniyet kemeri, boşluk/kenar koruması, düşen cisim ve erişim güvenliğini analiz et.
```

## Gönderilen Sistem Promptu

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

Görselde bir inşaat sahasında yüksekten düşme, düzensiz çalışma alanı, elektrik ve manuel taşıma kaynaklı ciddi iş güvenliği riskleri tespit edilmiştir. Yüksekte çalışan işçilerde düşme koruması eksikliği, zemin koşullarının kayma/takılma riski oluşturması, su birikintisi yakınında elektrik kablosu bulunması ve ağır malzeme taşıma yöntemleri öncelikli müdahale gerektiren tehlikelerdir.

### Pro

Görüntüdeki inşaat sahası, birden fazla kritik iş güvenliği riski barındırmaktadır. En acil tehlikeler, bina kenarında ve iskele üzerinde herhangi bir toplu koruma önlemi olmaksızın yapılan yüksekte çalışmalardır. Bu durumlar, ölümle sonuçlanabilecek düşme riski taşımaktadır. Ayrıca, sahadaki genel düzensizlik, dağınık malzemeler, su birikintileri ve suyun içinden geçen elektrik kablosu; takılma, düşme, yaralanma ve elektrik çarpması gibi ciddi riskler oluşturmaktadır. Sahada acil olarak düzenleyici ve önleyici faaliyetlerin başlatılması gerekmektedir.

## Free Bulguları

### 1. Yüksekten Düşme Riski

- Kategori: Düşme
- Güven: 0.9
- Kanıt: Yapı üzerinde ve iskelede çalışan işçilerin kenarlarda düşmeye karşı toplu koruma (korkuluk, ağ) veya kişisel koruma (emniyet kemeri) ekipmanı kullandığı net olarak görülmemektedir.
- Risk/açıklama: Yüksekte çalışan işçiler, kenarlardan veya iskeleden düşme riski altındadır. Bu durum ciddi yaralanmalara veya ölüme yol açabilir.
- Öneri: Yüksekte çalışma yapılan tüm alanlarda uygun toplu koruma önlemleri (korkuluk) sağlanmalı veya kişisel düşüş durdurma sistemleri kullanılmalıdır.
- Fine-Kinney: O 6 × F 6 × Ş 100 = 3600, band `critical`
- 5x5: P 4 × Ş 5 = 20, band `critical`

### 2. Düzensiz Çalışma Alanı ve Kayma/Takılma Tehlikesi

- Kategori: Düzen-Temizlik
- Güven: 1.0
- Kanıt: Çalışma alanı genelinde dağınık malzemeler (demir, ahşap), su birikintileri ve çamurlu zemin bulunmaktadır.
- Risk/açıklama: Düzensiz ve çamurlu zemin, işçiler için kayma, takılma ve düşme riskini artırmaktadır. Özellikle malzeme taşıyan işçiler için tehlike büyüktür.
- Öneri: Çalışma alanı düzenli tutulmalı, zemin temizlenmeli, su birikintileri giderilmeli ve malzemeler uygun şekilde istiflenmelidir.
- Fine-Kinney: O 10 × F 10 × Ş 15 = 1500, band `critical`
- 5x5: P 5 × Ş 3 = 15, band `high`

### 3. Elektrik Tehlikesi

- Kategori: Elektrik
- Güven: 0.8
- Kanıt: Yerde, su birikintilerinin yakınında açıkta bir elektrik kablosu görülmektedir.
- Risk/açıklama: Su birikintileriyle temas eden veya hasarlı olabilecek elektrik kablosu, elektrik çarpması riskine neden olabilir.
- Öneri: Elektrik kablolarının durumu kontrol edilmeli, hasarlı olanlar onarılmalı veya değiştirilmeli, su birikintilerinden uzak tutulmalı ve yalıtımı sağlanmalıdır.
- Fine-Kinney: O 3 × F 2 × Ş 40 = 240, band `high`
- 5x5: P 3 × Ş 4 = 12, band `high`

### 4. Manuel Taşıma ve Ergonomi Riski

- Kategori: Ergonomi
- Güven: 0.9
- Kanıt: Bir işçi, uzun metal profilleri omuzunda taşımaktadır.
- Risk/açıklama: Uzun ve muhtemelen ağır metal profillerin manuel olarak taşınması, kas-iskelet sistemi rahatsızlıklarına, düşmelere veya çevredeki kişilere/nesnelere çarpma riskine yol açabilir.
- Öneri: Malzeme taşıma için uygun mekanik ekipman kullanılmalı veya taşıma yöntemleri ergonomik prensiplere göre gözden geçirilmelidir.
- Fine-Kinney: O 3 × F 6 × Ş 7 = 126, band `medium`
- 5x5: P 3 × Ş 2 = 6, band `medium`

## Pro Bulguları

### 1. Yüksekten Düşme Riski - Bina Kenarı

- Kategori: Yüksekte Çalışma
- Güven: 1.0
- Kanıt: Binanın üst katında, döşeme kenarına yakın çalışan bir personel görülmektedir. Çalışanın çevresinde herhangi bir toplu koruma önlemi (korkuluk, güvenlik ağı) veya kişisel koruyucu donanım (yaşam hattı bağlantısı) bulunmamaktadır.
- Risk/açıklama: Korumasız döşeme kenarında çalışan personel, dengesini kaybederek veya geri adım atarak yüksekten düşebilir. Bu durum ölüm veya çok ciddi yaralanmalarla sonuçlanabilir.
- Öneri: Çalışmayı derhal durdurun. Tüm döşeme kenarlarına standartlara uygun geçici kenar koruma sistemleri (korkuluk, ara korkuluk, tekmelik) monte edin.
- Mevzuat: Yapı İşlerinde İSG Yönetmeliği Ek-4
- Fine-Kinney: O 6 × F 6 × Ş 100 = 3600, band `critical`
- 5x5: P 5 × Ş 5 = 25, band `critical`

### 2. Güvensiz İskele ve Yüksekten Düşme Riski

- Kategori: Yüksekte Çalışma
- Güven: 1.0
- Kanıt: Sağ tarafta kurulu olan iskelenin en üst platformunda çalışan bir personel bulunmaktadır. Platformda standartlara uygun korkuluk (ana ve ara korkuluk) ve tekmelik mevcut değildir.
- Risk/açıklama: İskele platformunda korkuluk olmaması, çalışanın düşme riskini kritik seviyeye çıkarmaktadır. Ayrıca, tekmelik olmaması nedeniyle alet veya malzemeler aşağı düşebilir.
- Öneri: İskeledeki çalışmayı durdurun. İskele platformuna standartlara uygun ana korkuluk, ara korkuluk ve tekmelik monte edilene kadar iskelenin kullanımını yasaklayın.
- Mevzuat: Yapı İşlerinde İSG Yönetmeliği Ek-4
- Fine-Kinney: O 6 × F 6 × Ş 100 = 3600, band `critical`
- 5x5: P 5 × Ş 5 = 25, band `critical`

### 3. Saha Düzensizliği ve Takılıp Düşme Riski

- Kategori: Çalışma Ortamı ve Düzen
- Güven: 1.0
- Kanıt: Zemin genelinde dağınık halde inşaat demirleri, kalaslar, borular ve çeşitli malzemeler bulunmaktadır. Belirlenmiş ve temiz yürüme yolları yoktur.
- Risk/açıklama: Dağınık malzemeler ve düzensiz zemin, çalışanların yürürken takılıp düşmesine, burkulmalara ve kesici/delici malzemelerle yaralanmalarına neden olabilir.
- Öneri: Acilen saha temizliği ve düzenlemesi yapın. Malzemeleri istif alanlarına taşıyın, atıkları toplayın ve güvenli yürüme yolları oluşturun.
- Mevzuat: Yapı İşlerinde İSG Yönetmeliği Ek-4
- Fine-Kinney: O 10 × F 10 × Ş 15 = 1500, band `critical`
- 5x5: P 5 × Ş 3 = 15, band `high`

### 4. Elektrik Çarpması Riski

- Kategori: Elektrik Güvenliği
- Güven: 0.9
- Kanıt: Betoniyerin elektrik kablosu, dağınık malzemelerin arasından ve su birikintisinin içinden veya çok yakınından geçmektedir.
- Risk/açıklama: Kablonun ezilmesi, sıyrılması veya suyla teması durumunda elektrik kaçağı oluşabilir. Bu durum, temas eden kişiler için ölümcül elektrik çarpması riski taşır.
- Öneri: Elektrik kablosunu güvenli bir güzergahtan, mümkünse askıya alarak geçirin. Kablonun su ve ezilme riskinden korunmasını sağlayın. Pano ve bağlantıları kontrol edin.
- Mevzuat: Yapı İşlerinde İSG Yön. ve Elektrik Tesislerinde İSG Yön.
- Fine-Kinney: O 3 × F 6 × Ş 40 = 720, band `critical`
- 5x5: P 3 × Ş 5 = 15, band `high`

### 5. Kayma ve Düşme Riski - Islak ve Çamurlu Zemin

- Kategori: Çalışma Ortamı ve Düzen
- Güven: 1.0
- Kanıt: Çalışma alanında, yürüme güzergahları üzerinde geniş su birikintileri ve çamurlu alanlar mevcuttur.
- Risk/açıklama: Islak ve çamurlu zemin, çalışanların kayarak düşmesine ve yaralanmasına neden olabilir. Su birikintileri alttaki çukur veya engelleri gizleyebilir.
- Öneri: Su birikintilerinin drenajını sağlayın veya pompa ile boşaltın. Geçici olarak güvenli yürüme yolları için kalas veya platformlar kullanın.
- Mevzuat: İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik
- Fine-Kinney: O 6 × F 10 × Ş 7 = 420, band `critical`
- 5x5: P 4 × Ş 2 = 8, band `medium`

### 6. Yukarıdan Malzeme Düşmesi Riski

- Kategori: Düşen Cisimler
- Güven: 0.9
- Kanıt: Yüksekte çalışma yapılan kat kenarlarında ve iskelede, malzeme veya aletlerin düşmesini önleyecek tekmelik gibi önlemler bulunmamaktadır.
- Risk/açıklama: Üst katlardan düşebilecek en küçük bir alet veya malzeme bile aşağıdaki çalışanlar için ciddi yaralanmalara veya ölüme neden olabilir.
- Öneri: Yüksekte çalışma yapılan tüm kenarlara ve iskelelere standartlara uygun tekmelikler monte edin. Aşağıdaki tehlikeli alanları şeritlerle belirleyin ve girişi kısıtlayın.
- Mevzuat: Yapı İşlerinde İSG Yönetmeliği Ek-4
- Fine-Kinney: O 3 × F 6 × Ş 40 = 720, band `critical`
- 5x5: P 4 × Ş 4 = 16, band `high`

### 7. Manuel Taşıma ve Ergonomik Riskler

- Kategori: Ergonomi
- Güven: 1.0
- Kanıt: Ön plandaki çalışan, uzun metal profilleri omuzunda tek başına taşımaktadır. Bu taşıma şekli hem ergonomik değildir hem de görüş alanını kısıtlayabilir.
- Risk/açıklama: Uygun olmayan manuel taşıma yöntemleri, kas-iskelet sistemi rahatsızlıklarına (bel, omuz ağrıları) yol açabilir. Ayrıca, kısıtlı görüş nedeniyle takılıp düşme riski artar.
- Öneri: Ağır ve uzun malzemelerin taşınması için el arabası gibi mekanik yardımcılar kullanılmalı veya en az iki kişi ile taşıma yapılmalıdır. Çalışanlara eğitim verilmelidir.
- Mevzuat: Elle Taşıma İşleri Yönetmeliği
- Fine-Kinney: O 3 × F 10 × Ş 7 = 210, band `high`
- 5x5: P 4 × Ş 2 = 8, band `medium`

## Karşılaştırma Notları

- Pro analiz aynı fotoğraf türünde daha uzun sürdü: yaklaşık 44 sn; Free yaklaşık 17 sn.
- Pro analiz yaklaşık 1.78 kat daha fazla token kullandı: 3132 / 1761.
- Pro analiz 7 bulgu üretti; Free 4 bulgu üretti.
- Pro analizde mevzuat/references alanı istendi ve sonuçlarda mevzuat başlıkları döndü.
- Pro analiz `general_premium`, `sector`, `working_at_height` canvas birleşimiyle daha ayrıntılı odak aldı.
- Her iki analizde de fallback çalışmadı; ikisi de ilk attempt ile tamamlandı.
- Free analiz `gemini_primary`; Pro analiz `gemini_paid_primary` üzerinden tamamlandı.

## Ham Veri Dosyası

Karşılaştırma için kullanılan canlı sorgu çıktısı ayrıca geçici olarak burada tutuldu:

`QA/tmp/recent_free_pro_analysis_raw.json`
