# Uzman Görüşü ve Eğitim — Doldurulacak Doküman

İki ayrı eşleşme sistemi var. Karıştırmamak için ikisi de burada.

- **Eğitim** → 19 katmandan sürülüyor. Eşleme kurulu ve çalışıyor; aşağıdaki
  tablo düzeltmen için.
- **Uzman Görüşü** → ekipman ailelerinden sürülüyor. Kayıt defterinin çoğu
  **boş**; asıl doldurulacak yer burası.

---

## BÖLÜM A — Uzman Görüşü kayıt defteri (asıl iş)

Model fotoğrafta gördüğü ekipmanın **yalnız kodunu** veriyor. Standart
numarası, periyot, ölçüm yöntemi — hepsi bizim. Model bunları hiç görmüyor.

### A.1 Durum: 22 aileden 8'i dolu

Dolu olanların tam metni A.3'te, boş olanların şablonu A.6'da.

| Kod | Türkçe | Durum |
|---|---|---|
| `overhead_crane` | Köprülü vinç | ✅ dolu |
| `lifting_accessory` | Sapan, zincir, halat, mapa, kanca | ✅ dolu |
| `storage_tank` | Atmosferik depolama tankı | ✅ dolu (API 653) |
| `pressure_vessel` | Basınçlı kap, hava tankı | ✅ dolu (API 510) |
| `process_piping` | Proses borulaması | ✅ dolu (API 570) |
| `electrical_panel` | Elektrik panosu, dağıtım tablosu | ✅ dolu |
| `earthing_system` | Gövde topraklaması gereken ekipman | ✅ dolu |
| `gas_cylinder` | Basınçlı gaz tüpü | ✅ dolu |
| `mobile_crane` | Mobil vinç | ⬜ **BOŞ** |
| `hoist` | Caraskal | ⬜ **BOŞ** |
| `forklift` | Forklift | ⬜ **BOŞ** |
| `mewp` | Yükseltilebilir çalışma platformu | ⬜ **BOŞ** |
| `earthmoving_equipment` | İş makinesi | ⬜ **BOŞ** |
| `boiler` | Kazan | ⬜ **BOŞ** |
| `compressor` | Kompresör | ⬜ **BOŞ** |
| `welding_machine` | Kaynak makinesi | ⬜ **BOŞ** |
| `machine_tool` | Tezgâh, pres, torna | ⬜ **BOŞ** |
| `fire_equipment` | Söndürücü, dolap, hidrant | ⬜ **BOŞ** |
| `ventilation_system` | Havalandırma, duman emiş | ⬜ **BOŞ** |
| `scaffold` | İskele | ⬜ **BOŞ** |
| `ladder` | Merdiven | ⬜ **BOŞ** |
| `conveyor` | Konveyör | ⬜ **BOŞ** |

Boş bir aile hiç kart üretmez. Uydurulmuş periyot yerine sessizlik — kasıtlı.
Model boş bir aileyi gördüğünde ize `expert_families_without_entry` olarak
düşüyor, yani hangi ailenin acil olduğunu sahadan öğreneceğiz.

### A.2 Her aile için doldurulacak alanlar

```
KOD:                  storage_tank
BAŞLIK:               Depolama Tankı — API 653 Muayenesi ve Et Kalınlığı Ölçümü
KATEGORİ:             Basınçlı ve Depolama Ekipmanları
SINIF:                periodic_inspection_record | measurement_record | site_verification

GÖZLEM (1 paragraf):
  "Sahada ... görülmektedir." ile başlar. Ne görüldüğünü ve neden fotoğrafla
  değerlendirilemeyeceğini söyler. Uzmanın açılış cümlesi.

GEREKLİLİKLER (4-8 madde):
  Dosyada bulunması gereken kayıt, ölçüm ve testler. Standart numarası,
  test katsayısı, ölçüm yöntemi burada geçer. Her madde tek bir şey ister.

VAR İSE:
  "Rapor mevcutsa; ... inceleyin." Neye bakılacağını söyler. Yalnız varlığı
  değil, sonucun uygunluğu sorulacaksa burada belirt.

YOK İSE:
  "... yaptırın." Emir kipi. Kullanım kısıtlanacaksa burada söylenir.

DAYANAKLAR (1-5 satır):
  "Mevzuat — ..." veya "Standart — ..." ile başlar. Her satır tek dayanak.
  Madde numarası yazılacaksa bu satırda.

PERİYOT (varsa):
  metin:    "Standartlarda aksi belirtilmedikçe yılda bir"
  dayanak:  TR-IS-EKIPMANLARI-EK3-KALDIRMA
  doğrulandı mı: EVET / HAYIR
```

**`doğrulandı mı` alanı önemli.** Bir sayıyı mevzuat metninden okuyarak
yazdıysan EVET. Meslek bilgisinden yazdıysan HAYIR. Rapor sayıyı iki durumda
da gösterir; fark, doğrulanmamış bir sayının hiçbir yerde doğrulanmış dayanak
iddiasında bulunmamasıdır. Eğitim kataloğu da aynı kuralı kullanıyor.

### A.3 Dolu olan 8 girdinin tam içeriği

Yeni aileleri bunlara bakarak yaz. Aradığın ton bu: ne görüldüğü, neden
fotoğrafla değerlendirilemeyeceği, dosyada ne bulunması gerektiği, varsa ne
sorulacağı, yoksa ne yaptırılacağı.

#### `overhead_crane` — köprülü vinç

```
KOD:        overhead_crane
BAŞLIK:     Köprülü Vinç — Periyodik Kontrol Raporunun Doğrulanması
KATEGORİ:   Kaldırma Ekipmanları
SINIF:      periodic_inspection_record
ETİKET:     köprülü vinç

GÖZLEM:
  Sahada köprülü vinç görülmektedir. Kaldırma ve iletme ekipmanları, fiziksel durumları kusursuz görünse dahi, mevzuatın aradığı periyodik kontrol raporu olmadan yük altına alınamaz. Ekipmanın kendisi değil, kaydı sorgulanmaktadır.

GEREKLİLİKLER:
  1. Periyodik kontrol raporu, makine mühendisi veya yetkilendirilmiş muayene kuruluşu tarafından düzenlenmiş ve imzalanmış olmalıdır.
  2. Rapor; kanca ve mandalı, halat veya zinciri, tamburu, frenleri, limit anahtarlarını, kumanda düzenini ve acil durdurmayı ayrı ayrı kapsamalıdır.
  3. Statik yük deneyi beyan edilen kapasitenin 1,25 katı, dinamik yük deneyi 1,1 katı ile yapılmış olmalıdır.
  4. Beyan edilen kaldırma kapasitesi, ekipman üzerinde uzaktan okunabilir şekilde bulunmalıdır.
  5. Raporda uygunsuzluk kaydedilmişse, kapatıldığına dair takip kaydı da dosyada bulunmalıdır.

VAR İSE:
  Rapor mevcutsa; düzenleme tarihini, raporu düzenleyen kişinin yetki belgesini ve uygunsuzluk maddelerinin kapatılıp kapatılmadığını inceleyin.

YOK İSE:
  Rapor yoksa veya süresi dolmuşsa, ekipmanı yük altına almadan önce periyodik kontrolü yetkili kişiye yaptırın ve kontrol sonuçlanana kadar kullanımı kısıtlayın.

DAYANAKLAR:
  Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.
  Standart — TS ISO 9927-1 Vinçlerin Muayenesi.
  Standart — TS EN 13001 Kaldırma Makineleri, Genel Tasarım Esasları.

PERİYOT:
  metin:      Standartlarda aksi belirtilmedikçe yılda bir
  dayanak:    TR-IS-EKIPMANLARI-EK3-KALDIRMA
  doğrulandı: HAYIR

İLGİLİ KATMANLAR: 7
```

#### `lifting_accessory` — kaldırma aksesuarı

```
KOD:        lifting_accessory
BAŞLIK:     Sapan, Zincir ve Kaldırma Aksesuarları — Kontrol Kaydı
KATEGORİ:   Kaldırma Ekipmanları
SINIF:      periodic_inspection_record
ETİKET:     kaldırma aksesuarı

GÖZLEM:
  Sahada sapan, zincir, halat, mapa veya kanca türü kaldırma aksesuarı görülmektedir. Bu elemanlar vinçten bağımsız birer iş ekipmanıdır ve kendi kontrol kayıtlarını gerektirir; vincin raporu bunları kapsamaz.

GEREKLİLİKLER:
  1. Her aksesuarın üzerinde okunabilir bir tanıtım etiketi ve beyan edilen çalışma yükü limiti bulunmalıdır.
  2. Etiket numarası ile eşleşen periyodik kontrol kaydı ve imalatçı uygunluk beyanı dosyada olmalıdır.
  3. Kontrolde; kopmuş tel, bükülme, düğüm, aşınma, korozyon, deformasyon, kanca ağız açıklığı ve mandal işlevi kayıt altına alınmış olmalıdır.
  4. Kullanım öncesi gözle muayenenin kim tarafından ve hangi sıklıkta yapıldığı tanımlı olmalıdır.

VAR İSE:
  Kayıt mevcutsa; etiket numaralarının sahadaki aksesuarlarla birebir eşleştiğini ve hurdaya ayırma ölçütlerinin uygulandığını doğrulayın.

YOK İSE:
  Kayıt yoksa, etiketsiz ve kaydı bulunmayan aksesuarları kullanım dışı bırakın ve yetkili kişiye kontrol ettirerek envanteri etiketleyin.

DAYANAKLAR:
  Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.
  Standart — TS EN 818 Kaldırma Zincirleri.
  Standart — TS EN 13414 Çelik Tel Halat Sapanlar.

PERİYOT:
  metin:      Standartlarda aksi belirtilmedikçe yılda bir
  dayanak:    TR-IS-EKIPMANLARI-EK3-KALDIRMA
  doğrulandı: HAYIR

İLGİLİ KATMANLAR: 7
```

#### `storage_tank` — depolama tankı

```
KOD:        storage_tank
BAŞLIK:     Depolama Tankı — API 653 Muayenesi ve Et Kalınlığı Ölçümü
KATEGORİ:   Basınçlı ve Depolama Ekipmanları
SINIF:      measurement_record
ETİKET:     depolama tankı

GÖZLEM:
  Sahada atmosferik depolama tankı görülmektedir. Bu ekipmanlarda kabuk, taban ve çatı kalınlığı işletme süresince korozyonla azalır ve kayıp gözle görülmez; bu nedenle tankın durumu yalnızca ölçüm kayıtlarıyla bilinebilir.

GEREKLİLİKLER:
  1. Tank, API 653 kapsamında yetkili muayene personeli tarafından muayene edilmiş olmalıdır.
  2. Kabuk, taban ve çatı için ultrasonik et kalınlığı ölçüm raporu bulunmalı; ölçülen değerler hesaplanan minimum kalınlığın üzerinde olmalıdır.
  3. Ölçüm noktaları krokilendirilmiş olmalı ve önceki ölçümle karşılaştırılarak korozyon hızı hesaplanmış olmalıdır.
  4. Bir sonraki muayene tarihi, hesaplanan korozyon hızı ve kalan ömür üzerinden belirlenmiş olmalıdır.
  5. Tankın imalat dayanağı (API 650 veya eşdeğeri) ve varsa tamir-tadilat kayıtları dosyada bulunmalıdır.
  6. Katodik koruma uygulanıyorsa API 651 kapsamındaki ölçüm kayıtları da istenmelidir.

VAR İSE:
  Rapor mevcutsa; ölçüm tarihini, ölçülen minimum kalınlığı, hesaplanan korozyon hızını ve bir sonraki muayene tarihinin geçilip geçilmediğini inceleyin.

YOK İSE:
  Ölçüm kaydı yoksa, API 653 kapsamında dış muayene ve ultrasonik et kalınlığı ölçümü yaptırın; taban ve alt kabuk bölgesini öncelikli ölçüm alanı olarak tanımlayın.

DAYANAKLAR:
  Standart — API 653 Tank Inspection, Repair, Alteration and Reconstruction.
  Standart — API 650 Welded Tanks for Oil Storage.
  Standart — API 651 Cathodic Protection of Aboveground Storage Tanks.
  Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.

PERİYOT:
  metin:      Dış muayene en çok 5 yılda bir; iç muayene hesaplanan korozyon hızına göre
  dayanak:    API-653-INSPECTION-INTERVAL
  doğrulandı: HAYIR

İLGİLİ KATMANLAR: 11, 12
```

#### `pressure_vessel` — basınçlı kap

```
KOD:        pressure_vessel
BAŞLIK:     Basınçlı Kap — Periyodik Kontrol ve API 510 Muayenesi
KATEGORİ:   Basınçlı ve Depolama Ekipmanları
SINIF:      measurement_record
ETİKET:     basınçlı kap

GÖZLEM:
  Sahada basınçlı kap, hava tankı veya kazan görülmektedir. Basınçlı ekipmanın iç yüzeyi ve cidar kalınlığı dışarıdan değerlendirilemez; güvenli olduğu yalnız basınç testi ve kalınlık ölçümü kayıtlarıyla söylenebilir.

GEREKLİLİKLER:
  1. Periyodik kontrol, makine mühendisi veya yetkilendirilmiş muayene kuruluşu tarafından yapılmış olmalıdır.
  2. Hidrostatik test, işletme basıncının 1,5 katı ile uygulanmış ve sonucu raporlanmış olmalıdır.
  3. Ultrasonik et kalınlığı ölçümü yapılmış ve ölçülen değerler hesaplanan minimum kalınlığın üzerinde olmalıdır.
  4. Emniyet ventili ayar basıncı, ekipmanın tasarım basıncına göre doğrulanmış ve mühürlenmiş olmalıdır.
  5. Manometre kalibrasyon kaydı bulunmalı ve gösterge işletme aralığında okunabilir olmalıdır.
  6. İmalatçı uygunluk beyanı, tasarım basıncı ve hacim bilgisi ekipman etiketinde bulunmalıdır.

VAR İSE:
  Rapor mevcutsa; test tarihini, uygulanan test basıncını, et kalınlığı sonuçlarını ve emniyet ventili ayar kaydını inceleyin.

YOK İSE:
  Kayıt yoksa, ekipmanı işletmeden çıkarmadan önce periyodik kontrolü planlayın; hidrostatik test, et kalınlığı ölçümü ve emniyet ventili doğrulamasını birlikte yaptırın.

DAYANAKLAR:
  Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.
  Mevzuat — Basınçlı Ekipmanlar Yönetmeliği.
  Standart — API 510 Pressure Vessel Inspection Code.
  Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.

PERİYOT:
  metin:      Standartlarda aksi belirtilmedikçe yılda bir
  dayanak:    TR-IS-EKIPMANLARI-EK3-BASINCLI
  doğrulandı: HAYIR

İLGİLİ KATMANLAR: 12, 14
```

#### `process_piping` — proses borulaması

```
KOD:        process_piping
BAŞLIK:     Proses Borulaması — API 570 Muayenesi
KATEGORİ:   Basınçlı ve Depolama Ekipmanları
SINIF:      measurement_record
ETİKET:     proses borulaması

GÖZLEM:
  Sahada proses borulaması ve bağlantı elemanları görülmektedir. Boru hatlarında incelme dirsek, redüksiyon ve destek noktalarında yoğunlaşır; bu bölgeler boyalı yüzey altında gözle değerlendirilemez.

GEREKLİLİKLER:
  1. Boru hatları API 570 kapsamında sınıflandırılmış ve muayene planına bağlanmış olmalıdır.
  2. Kalınlık ölçüm noktaları (TML) tanımlanmış ve ölçüm sonuçları kayıt altına alınmış olmalıdır.
  3. Destek, askı ve genleşme düzeninin muayene kaydı bulunmalıdır.
  4. Hat üzerindeki geçici tamirlerin kaydı ve kalıcı onarım planı dosyada olmalıdır.

VAR İSE:
  Kayıt mevcutsa; ölçüm noktalarının kroki ile eşleştiğini ve kalan ömür hesabının güncel olduğunu doğrulayın.

YOK İSE:
  Kayıt yoksa, hattı API 570 kapsamında sınıflandırın, kalınlık ölçüm noktalarını belirleyin ve ilk ölçümü yaptırın.

DAYANAKLAR:
  Standart — API 570 Piping Inspection Code.
  Standart — TS EN ISO 16809 Ultrasonik Kalınlık Ölçümü.

İLGİLİ KATMANLAR: 12, 14
```

#### `electrical_panel` — elektrik panosu

```
KOD:        electrical_panel
BAŞLIK:     Elektrik Panosu — İç Tesisat ve Topraklama Ölçüm Raporları
KATEGORİ:   Elektrik Tesisatı
SINIF:      measurement_record
ETİKET:     elektrik panosu

GÖZLEM:
  Sahada elektrik panosu veya dağıtım tesisatı görülmektedir. Tesisatın güvenli olduğu gözle değil ölçümle bilinir; yalıtım direnci, topraklama direnci ve kaçak akım koruma işlevi ancak rapora bakılarak değerlendirilebilir.

GEREKLİLİKLER:
  1. Elektrik iç tesisat uygunluk raporu ve topraklama ölçüm raporu, yetkili elektrik mühendisi tarafından düzenlenmiş olmalıdır.
  2. Raporda ölçülen topraklama direnci değeri sayısal olarak yer almalı ve tesisatın koruma düzenine göre sınır değerin altında olmalıdır.
  3. Kaçak akım koruma rölesinin açma akımı ve açma süresi ölçülmüş, test butonu denemesi kayıt altına alınmış olmalıdır.
  4. Yalıtım direnci ölçüm sonuçları devre bazında raporlanmış olmalıdır.
  5. Rapor yalnız 'uygundur' ibaresi taşımamalı; ölçülen değerleri ve ölçüm cihazının kalibrasyon kaydını içermelidir.
  6. Pano önünde serbest çalışma alanı bırakılmış, pano kapağı kilitli ve ilgisiz kişilerin erişimine kapalı olmalıdır.

VAR İSE:
  Rapor mevcutsa; ölçüm tarihini, ölçülen direnç değerlerini ve bu değerlerin sınırların altında kalıp kalmadığını inceleyin. Raporun varlığı yeterli değildir, sonucun uygun olması gerekir.

YOK İSE:
  Rapor yoksa veya süresi dolmuşsa, elektrik iç tesisat ve topraklama ölçümlerini yetkili kişiye yaptırın; ölçüm sonucu uygun çıkmayan devrelerde düzeltme tamamlanana kadar kullanımı kısıtlayın.

DAYANAKLAR:
  Mevzuat — Elektrik Tesislerinde Topraklamalar Yönetmeliği.
  Mevzuat — Elektrik İç Tesisleri Yönetmeliği.
  Mevzuat — İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği, Ek-III.
  Standart — TS HD 60364 Alçak Gerilim Elektrik Tesisatı.

PERİYOT:
  metin:      Standartlarda aksi belirtilmedikçe yılda bir
  dayanak:    TR-TOPRAKLAMA-YONETMELIK
  doğrulandı: HAYIR

İLGİLİ KATMANLAR: 5
```

#### `earthing_system` — elektrikli ekipman

```
KOD:        earthing_system
BAŞLIK:     Ekipman Gövde Topraklamaları
KATEGORİ:   Elektrik Tesisatı
SINIF:      site_verification
ETİKET:     elektrikli ekipman

GÖZLEM:
  Sahada gövdesi iletken elektrikli ekipman görülmektedir. Yalıtım arızasında gövde üzerinde tehlikeli gerilim oluşur; gövde topraklaması, bu gerilimi koruma düzeninin açacağı seviyeye taşıyan tek düzenektir.

GEREKLİLİKLER:
  1. Tezgâh, kaynak makinesi, kompresör ve benzeri sabit ekipmanların gövdeleri koruma iletkeni ile topraklanmış olmalıdır.
  2. Gövde topraklaması ile pano toprak barası arasındaki süreklilik ölçülmüş ve kayıt altına alınmış olmalıdır.
  3. Topraklama iletkeninin kesiti, beslediği devrenin akımına göre seçilmiş olmalıdır.
  4. Seyyar ekipmanlarda topraklama iletkeninin fiş ve prizde kesintisiz olduğu doğrulanmalıdır.

VAR İSE:
  Süreklilik ölçüm kaydı mevcutsa; ölçümün ekipman bazında yapıldığını ve sahadaki envanterle eşleştiğini doğrulayın.

YOK İSE:
  Gövde topraklaması bulunmayan veya sürekliliği ölçülmemiş ekipmanların topraklamasını mutlaka yaptırın ve süreklilik ölçümünü ekipman bazında kayda geçirin.

DAYANAKLAR:
  Mevzuat — Elektrik Tesislerinde Topraklamalar Yönetmeliği.
  Standart — TS HD 60364 Alçak Gerilim Elektrik Tesisatı.

İLGİLİ KATMANLAR: 5, 6
```

#### `gas_cylinder` — basınçlı gaz tüpü

```
KOD:        gas_cylinder
BAŞLIK:     Basınçlı Gaz Tüpleri — Depolama Düzeni ve Uyumluluk Matrisi
KATEGORİ:   Basınçlı ve Depolama Ekipmanları
SINIF:      site_verification
ETİKET:     basınçlı gaz tüpü

GÖZLEM:
  Sahada basınçlı gaz tüpü görülmektedir. Tüplerde asıl belirleyici olan tüpün kendi durumundan çok nasıl depolandığıdır; yanlış komşuluk, devrilme ve vana hasarı en sık görülen üç başlangıç olayıdır.

GEREKLİLİKLER:
  1. Tüplerin depolandığı alan için gaz uyumluluk (depolama) matrisi hazırlanmış ve alanda uygulanıyor olmalıdır.
  2. Yanıcı gaz tüpleri ile oksitleyici gaz tüpleri ayrı bölmelerde depolanmalı; ayrım mesafesi sağlanamıyorsa aralarına yanmaz bariyer konulmalıdır.
  3. Tüpler dik konumda, devrilmeye karşı zincir veya kelepçe ile sabitlenmiş olmalıdır.
  4. Kullanılmayan tüplerde vana koruma başlığı takılı olmalıdır.
  5. Dolu ve boş tüpler ayrı ve işaretlenmiş alanlarda bulunmalıdır.
  6. Depolama alanı üstten havalandırmalı, ısı kaynaklarından ve elektrik tesisatından uzak olmalıdır.
  7. Tüplerin periyodik hidrostatik test tarihleri, tüp omuzundaki damgadan okunabilir olmalıdır.

VAR İSE:
  Depolama matrisi mevcutsa; sahadaki yerleşimin matrisle uyuştuğunu, ayrım mesafelerinin korunduğunu ve test damgalarının süresinin geçmediğini doğrulayın.

YOK İSE:
  Depolama matrisi yoksa, sahadaki gaz envanterini çıkarın, uyumluluk matrisini hazırlayın ve yerleşimi matrise göre yeniden düzenleyin.

DAYANAKLAR:
  Mevzuat — Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik.
  Standart — TS EN ISO 11114 Gaz Tüpleri, Malzeme Uyumluluğu.
  Standart — TS 11891 Basınçlı Gaz Tüpleri, Depolama ve Taşıma Kuralları.

İLGİLİ KATMANLAR: 10, 13
```

### A.4 Bu alanlar kullanıcıya nasıl görünüyor

`storage_tank` girdisi uygulamada tek bir Uzman Görüşü kartına dönüşüyor:

| Kart alanı | Kaynak |
|---|---|
| Başlık | `BAŞLIK` |
| Kategori | `KATEGORİ` |
| Açıklama | `GÖZLEM` + boş satır + numaralandırılmış `GEREKLİLİKLER` + `Kontrol periyodu:` satırı |
| Önerilen eylem | `VAR İSE` |
| Düzeltici önlem ("Kayıt Yoksa") | `YOK İSE` |
| Önleyici kontrol ("Süreklilik") | `PERİYOT` metninden üretilir; periyot yoksa muayene planına bağlama cümlesi |
| Dayanak | `DAYANAKLAR`, her satır ayrı |

Kart puanlanmaz, Fine-Kinney almaz, toplam risk skoruna girmez. Saha
doğrulaması gerektiren madde olarak işaretlenir.

### A.5 Şu an dolu olan 8 girdide senin kontrol etmen gerekenler

Bu sayıları ben yazdım ve **hiçbirini doğrulayamam**. Hepsi `doğrulandı: HAYIR`
olarak işaretli. Meslekî kontrolün gereken yerler:

| Girdi | Kontrol edilecek |
|---|---|
| `overhead_crane` | Statik 1,25 / dinamik 1,1 katsayıları; yıllık periyot |
| `lifting_accessory` | Yıllık periyot; TS EN 818 ve TS EN 13414 numaraları |
| `storage_tank` | Dış muayene "en çok 5 yıl"; API 651 kapsamı |
| `pressure_vessel` | Hidrostatik 1,5 kat; yıllık periyot |
| `electrical_panel` | Topraklama ölçüm periyodu; TS HD 60364 numarası |
| `gas_cylinder` | Ayrım mesafesi ve bariyer kuralı; TS 11891 numarası |

Yanlış olanı söyle, düzeltirim. Silmemi istediğini söyle, silerim.

---

### A.6 Doldurulacak 14 aile

Kodlar ve etiketler yazılı; gerisi senin. Boş bıraktığın aile kart
üretmez, hata vermez.

#### `mobile_crane` — mobil vinç

```
KOD:        mobile_crane
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     mobil vinç

GÖZLEM:
  Sahada mobil vinç görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `hoist` — caraskal

```
KOD:        hoist
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     caraskal

GÖZLEM:
  Sahada caraskal görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `forklift` — forklift

```
KOD:        forklift
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     forklift

GÖZLEM:
  Sahada forklift görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `mewp` — yükseltilebilir çalışma platformu

```
KOD:        mewp
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     yükseltilebilir çalışma platformu

GÖZLEM:
  Sahada yükseltilebilir çalışma platformu görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `earthmoving_equipment` — iş makinesi

```
KOD:        earthmoving_equipment
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     iş makinesi

GÖZLEM:
  Sahada iş makinesi görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `boiler` — kazan

```
KOD:        boiler
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     kazan

GÖZLEM:
  Sahada kazan görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `compressor` — kompresör

```
KOD:        compressor
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     kompresör

GÖZLEM:
  Sahada kompresör görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `welding_machine` — kaynak makinesi

```
KOD:        welding_machine
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     kaynak makinesi

GÖZLEM:
  Sahada kaynak makinesi görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `machine_tool` — tezgâh, pres, torna

```
KOD:        machine_tool
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     tezgâh, pres, torna

GÖZLEM:
  Sahada tezgâh, pres, torna görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `fire_equipment` — söndürücü, dolap, hidrant

```
KOD:        fire_equipment
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     söndürücü, dolap, hidrant

GÖZLEM:
  Sahada söndürücü, dolap, hidrant görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `ventilation_system` — havalandırma, duman emiş

```
KOD:        ventilation_system
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     havalandırma, duman emiş

GÖZLEM:
  Sahada havalandırma, duman emiş görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `scaffold` — iskele

```
KOD:        scaffold
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     iskele

GÖZLEM:
  Sahada iskele görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `ladder` — merdiven

```
KOD:        ladder
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     merdiven

GÖZLEM:
  Sahada merdiven görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

#### `conveyor` — konveyör

```
KOD:        conveyor
BAŞLIK:     
KATEGORİ:   
SINIF:      periodic_inspection_record | measurement_record | site_verification
ETİKET:     konveyör

GÖZLEM:
  Sahada konveyör görülmektedir. 

GEREKLİLİKLER:
  1. 
  2. 
  3. 
  4. 

VAR İSE:
  

YOK İSE:
  

DAYANAKLAR:
  Mevzuat — 
  Standart — 

PERİYOT:
  metin:      
  dayanak:    
  doğrulandı: EVET / HAYIR

İLGİLİ KATMANLAR: 
```

---

## BÖLÜM B — Eğitim eşlemesi (kurulu, düzeltmen için)

Her katmanın tehlike görmesi, aşağıdaki kodlar üzerinden eğitim kartını
tetikliyor. Katalogda 18 kart var; üçü (`TRN-GEN-002` Temel İSG,
`TRN-GEN-001` Uyum, `TRN-EMR-001` Acil Durum) her analizde çıkıyor.

| # | Katman | mekanizma | teminat konusu |
|---|---|---|---|
| 1 | İnsan, görev, tehlike hattı, KKD | — | — |
| 2 | Zemin, erişim, düzen-tertip | `fall_same_level` | — |
| 3 | Yüksekte çalışma, düşen cisim | `fall_from_height` | `working_at_height_access` |
| 4 | Taşıyıcı sistem, geçici yapı | `falling_object` | — |
| 5 | Elektrik ve tehlikeli enerji | `electrical_contact_arc` | `electrical_internal_integrity` |
| 6 | Makine, iş ekipmanı, el aleti | `caught_in_pinch_shear` | `machine_protective_systems` |
| 7 | Kaldırma ve rigging | `falling_object` | `lifting_inspection` |
| 8 | Mobil ekipman, saha trafiği | `vehicle_equipment_strike` | `mobile_equipment_controls` |
| 9 | İstifleme, raf, malzeme | `falling_object` | — |
| 10 | Kimyasal, tehlikeli madde | `chemical_contact_release` | `chemical_identity_and_exposure` |
| 11 | Tank, silo, IBC, transfer | `mechanical_separation_release` | `process_containment_integrity` |
| 12 | Basınçlı ekipman, borulama | `hydraulic_pneumatic_release` | `process_containment_integrity` |
| 13 | Yangın, patlama, sıcak iş | `thermal_contact` | `hot_work_controls` |
| 14 | Proses güvenliği | `mechanical_separation_release` | `process_containment_integrity` |
| 15 | Kazı, kapalı alan, su | — | `confined_space_controls` |
| 16 | Fiziksel, kimyasal, biyolojik etkenler | `chemical_contact_release` | `chemical_identity_and_exposure` |
| 17 | Ergonomi, insan faktörleri | — | — |
| 18 | Acil durum, çevre, işaretleme | — | `fire_emergency_readiness` |
| 19 | Periyodik kontrol kayıtları | — | *(eğitime girmez, Uzman Görüşü'ne gider)* |

### B.1 Bilinen boşluklar

Katalogda karşılığı olmayan katmanlar. Katman eşlemesi eksik değil, **kart
yok**:

- **Katman 17 — Ergonomi.** Elle taşıma ve ergonomi eğitimi kartı yok.
- **Katman 15 — Kapalı alan.** `confined_space_controls` konusunu kullanan
  kural yok.
- **Katman 16 — Gürültü, titreşim, toz.** Şu an kimyasal kartına düşüyor;
  kendi kartı olmalı.

Bunlar için kart yazmamı istersen, aşağıdaki alanları doldur:

```
KOD:              TRN-ERG-001
BAŞLIK:           Elle Taşıma ve Ergonomi Eğitimi
SINIF:            statutory_ohs_training | task_specific_practical_training |
                  site_or_job_induction | ...
HEDEF KİTLE:      all_employees | ...
KONULAR:          5-6 madde
YASAL SÜRE:       saat / tazeleme yılı / dayanak kodu / doğrulandı mı
TETİKLEYEN:       hangi mekanizma veya katman
```

---

## Nasıl geri vereceksin

Bu dosyayı doldurup bana ver, ya da ayrı bir dosyada yaz. Kod dosyalarına
çeviririm:

- Uzman Görüşü → `supabase/functions/_shared/expert-recommendations/registry.tr.ts`
- Eğitim → `supabase/functions/_shared/training-recommendations/catalog.tr.ts`

**Kod dosyası mı, veritabanı tablosu mu?** Şu an kod. Kod olması; sürümlenmesi,
testten geçmesi ve her cümlenin gözden geçirilebilir olması demek — eğitim
kataloğu da öyle. Veritabanı olsaydı deploy beklemeden düzenleyebilirdin ama
metin testsiz ve sürümsüz kalırdı. Mevzuat metni için kodu öneriyorum. Sen
düzenleme hızını tercih edersen tabloya taşırım, kararı sen ver.
