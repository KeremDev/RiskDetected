# Sektör profili v2 — vNext için aktif sektör rehberi

**Tarih:** 2026-08-24
**Durum:** içerik taslağı, İSG uzmanı onayı bekliyor
**Hedef:** `sector-profile-v2` yapısı — vNext'in ilk incelemesinde, hedefli ikinci incelemesinde, modül önceliklendirmesinde, kontrol üretiminde ve mevzuat eşleştirmesinde ölçülebilir biçimde kullanılabilir

---

## 0. Tasarım ilkeleri

Mevcut v1 rehberi "risk aileleri" listesi. Prompt'a giriyor ama modele *ne yapacağını* söylemiyor, sadece *neyi düşüneceğini* söylüyor. v2'nin farkı: her madde vNext'te bir kancaya bağlanıyor.

**İlke 1 — Yalnız kameranın çözebildiği şey yazılır.**
"Eğitim kayıtlarını kontrol et" bir fotoğraf analizcisi için kullanılamaz. Rehber, görüntüde ayırt edilebilen fiziksel bileşen, konum, durum ve ilişkiden ibaret olmalı. Görülemeyecek şeyler `assurance` (saha teyidi) tarafına gider, bulgu tarafına değil.

**İlke 2 — Her sektör modül önceliği verir, modül eklemez.**
`MODULE_IDS` sabit 20 modül. Sektör bunları yeniden sıralar ve hangilerinin "bu sektörde atlanamaz" olduğunu söyler. Yeni modül icat etmez.

**İlke 3 — Sektör şiddeti yükseltmez, mekanizmayı adlandırır.**
Sektör bilgisi `fk_severity` çarpanı değildir. Sektörün katkısı şudur: *"bu sektörde tek ölüme giden mekanizmalar şunlardır"*. Şiddet yine görünen mekanizmadan gelir.

**İlke 4 — Frekans için sektör priorı, kesinlik değil.**
Fotoğraftan maruziyet sıklığı çıkarılamıyor. Sektör, savunulabilir bir başlangıç değeri verir ve bu değer `frequency_basis = sector_prior` olarak işaretlenir — `unknown_from_photo` ile aynı şeffaflıkta.

**İlke 5 — Görsel kanıt sektörü ezer.**
Ofis seçilmiş ama fotoğrafta forklift varsa, forklift analiz edilir. Sektör önceliktir, filtre değil.

---

## 1. Profil şeması

Her sektör aşağıdaki alanları taşır:

```
sector_id                     : AnalysisSectorId
label_tr                      : kullanıcıya görünen ad
typical_hazard_class          : az_tehlikeli | tehlikeli | cok_tehlikeli  (6331 Tebliği, NACE'ye göre değişir)
mandatory_modules             : bu sektörde atlanamayacak MODULE_IDS
priority_modules              : öncelik sırasıyla kalan modüller
critical_equipment            : [{ equipment_family, components[], check_codes[] }]
fatal_mechanisms              : bu sektörde tek/çoklu ölüme giden somut mekanizmalar
frequency_prior               : { default_f, rationale }
control_preferences           : kontrol hiyerarşisinde bu sektörde uygulanabilir olanlar
regulation_anchors            : [{ ad, kapsam }]
negative_rules                : bu sektörde uydurulmaması gereken varsayımlar
assurance_scope               : fotoğraftan doğrulanamayan, saha teyidine gidecek başlıklar
```

> **Not:** `typical_hazard_class` değerleri NACE koduna göre işletme bazında değişir. Profil bunu *tipik* olarak taşır; hukuki sınıflandırma iddiası değildir ve skorlamada kullanılmaz.

---

## 2. Sektör profilleri

### 1. Genel İSG · `general`

**Tehlike sınıfı:** belirsiz — varsayım yapma

**Zorunlu modüller:** `egress_housekeeping`, `ppe`, `emergency_equipment`
**Öncelik:** görüntüden çıkan ekipmana göre dinamik; sabit sıra yok

**Kural:** Kullanıcı sektör belirtmemiştir. Sektöre özel varsayım yapma, sektör-tipik ekipman arama. Görüntüde fiilen bulunan ekipman ve koşullara göre modül seç. Bir ekipman ailesi tanımlandığında (vinç, tank, pano, raf, iş makinesi) o ekipmanın kendi kritik bileşen kontrolleri devreye girer.

**Frekans priorı:** yok — `unknown_from_photo` kullan
**Negatif kural:** Sahne "fabrika gibi görünüyor" diye imalat profili uygulanmaz.

---

### 2. İnşaat · `construction`

**Tehlike sınıfı:** tipik olarak **çok tehlikeli**

**Zorunlu modüller:** `access_and_work_at_height`, `scaffold_and_ladder`, `excavation_slope_shoring`, `lifting_operations`, `mobile_equipment_traffic`, `ppe`
**Öncelik:** `structural_mechanical_integrity` → `electrical_safety` → `egress_housekeeping` → `hot_work_fire_explosion` → `emergency_equipment`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| İskele | dikme tabanı/taban plakası, çapraz, ankraj, platform tahtası, ara korkuluk, süpürgelik | `guard_barrier_integrity`, `structural_support_integrity` |
| Kenar koruma | ana korkuluk (~1.10 m), ara korkuluk, topuk levhası, bağlantı elemanı | `guard_barrier_integrity` |
| Kule/mobil vinç | kanca mandalı, halat tel kırığı, sapan/kanca gözü, ağırlık, outrigger pabuç | `pin_retainer_joint_integrity`, `load_path_integrity` |
| Kazı | şev açısı, tahkimat/iksa, kazı kenarı yükü, su birikintisi, giriş-çıkış merdiveni | `slope_shoring_integrity`, `edge_load_clearance` |
| Geçici elektrik | pano kapağı, kaçak akım rölesi, kablo ekleri, seyyar kablo güzergâhı | `electrical_enclosure_integrity` |
| Beton pompası | boru kelepçesi, hortum ucu emniyeti, outrigger, boru destek | `pipe_hose_connection_integrity` |

**Ölümcül mekanizmalar:** korumasız kenardan/döşeme boşluğundan düşme; kazı göçüğü altında kalma; kaldırılan yükün altında ezilme; iş makinesi ile ezilme/çarpma; yüksekten düşen malzeme; enerjili iletkene temas.

**Frekans priorı:** `default_f = 3` (haftalık) — şantiye kadrajı çoğunlukla aktif çalışma alanıdır ama vardiya sürekliliği fotoğraftan doğrulanamaz. Çalışan görünüyorsa ve iş halindeyse `6` (günlük) kullanılabilir; gerekçe `visible_active_work`.

**Kontrol tercihleri:** Toplu koruma bireysel korumadan önce gelir. Sıra: kenar/boşluk kapatma → bariyerleme ve erişim kısıtlama → geçici platform/iksa → çalışma izni ve yetkilendirme → KKD. "Emniyet kemeri taksın" tek başına kenar koruma eksikliğinin cevabı değildir; ankraj noktası gösterilemiyorsa kemer önerisi eksik kalır.

**Mevzuat çapaları:** Yapı İşlerinde İSG Yönetmeliği; İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği (EK-III periyodik kontrol); KKD Kullanılması Hakkında Yönetmelik; TS EN 13374 (geçici kenar koruma), TS EN 12811 (iskele).

**Negatif kurallar:** İskele etiketi/kontrol kartı görünmüyorsa "iskele kontrolsüz" bulgusu üretme — bu saha teyidi maddesidir. Kazı derinliğini tahmin ederken kesin ölçü yazma. Baret görünmeyen kişi kabin içindeyse KKD bulgusu üretme.

**Saha teyidine giden:** iskele kontrol kartı, kaldırma ekipmanı periyodik muayenesi, yetki belgeleri, kazı statik hesabı, elektrik tesisatı ölçüm raporu.

---

### 3. İmalat / Fabrika · `manufacturing`

**Tehlike sınıfı:** tipik olarak **tehlikeli** — bazı NACE kodlarında çok tehlikeli

**Zorunlu modüller:** `machine_safety_loto`, `structural_mechanical_integrity`, `mobile_equipment_traffic`, `egress_housekeeping`, `ppe`
**Öncelik:** `electrical_safety` → `storage_racking` → `lifting_operations` → `pressure_process_safety` → `ergonomics` → `hot_work_fire_explosion` → `emergency_equipment`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Tezgâh / pres | nokta operasyon koruyucusu, iki el kumandası, ışık perdesi, acil durdurma | `machine_guard_integrity`, `emergency_stop_presence` |
| Dönen tahrik | kayış-kasnak muhafazası, kaplin kapağı, açık mil, zincir-dişli | `machine_guard_integrity` |
| Konveyör | sıkışma noktası (nip point), kuyruk tamburu, çekme halatı acil durdurma | `nip_point_guard_integrity` |
| Köprü vinç | kanca mandalı, halat tel kırığı/kuş kafesi, kanca gözü deformasyonu, limit switch, kumanda askısı | `pin_retainer_joint_integrity`, `load_path_integrity` |
| Forklift | çatal aşınması, koruma kafesi, ayna, ikaz sesi/ışığı, park pozisyonu | `mobile_equipment_integrity` |
| Elektrik panosu | kapak, kilit, IP bütünlüğü, etiket, önündeki serbest alan | `electrical_enclosure_integrity` |
| Basınçlı kap | manometre, emniyet ventili, tahliye hattı yönü, etiket/plaka, ankraj | `pressure_relief_integrity` |

**Ölümcül mekanizmalar:** koruyucusuz makineye yakalanma/uzuv kaybı; enerji izole edilmeden bakım sırasında beklenmedik çalışma; asılı yükün düşmesi; forklift altında/arasında ezilme; basınçlı kap patlaması; elektrik çarpması ve ark.

**Frekans priorı:** `default_f = 6` (günlük) — üretim alanı kadrajı sürekli maruziyet varsayımını destekler. Makine durmuş/bakımda görünüyorsa `2` (aylık), gerekçe `maintenance_state_visible`.

**Kontrol tercihleri:** Mühendislik kontrolü baskın. Sıra: sabit muhafaza → kilitli/enterlok muhafaza → ışık perdesi/iki el kumandası → EKED (LOTO) prosedürü ve kilit noktası → işaretleme → KKD. Üretimi durdurmadan uygulanabilir seçenek varsa onu önce yaz; yoksa durdurma kriterini açıkça belirt.

**Mevzuat çapaları:** İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği (EK-II bakım/kullanım, EK-III periyodik kontrol); Makine Emniyeti Yönetmeliği; Çalışanların Gürültü ile İlgili Risklerden Korunmaları Hakkında Yönetmelik; TS EN ISO 14120 (muhafazalar), TS EN ISO 13857 (güvenlik mesafeleri), TS EN ISO 13850 (acil durdurma).

**Negatif kurallar:** Makinenin CE/uygunluk durumunu fotoğraftan iddia etme. Gürültü seviyesini desibel olarak tahmin etme. "EKED yok" demek için kilit noktası ve enerji kaynağı görünür olmalı; görünmüyorsa saha teyidi maddesidir.

**Saha teyidine giden:** periyodik kontrol raporları (vinç, kompresör, basınçlı kap, kaldırma ekipmanı), EKED prosedürü ve kilit envanteri, gürültü/toz ölçümleri, operatör yetki belgeleri.

---

### 4. Maden · `mining`

**Tehlike sınıfı:** **çok tehlikeli**

**Zorunlu modüller:** `excavation_slope_shoring`, `mobile_equipment_traffic`, `structural_mechanical_integrity`, `emergency_equipment`, `ppe`
**Öncelik:** `hot_work_fire_explosion` → `electrical_safety` → `lifting_operations` → `environmental_release_leak` → `egress_housekeeping`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Tahkimat | bağ/direk aralığı, deformasyon, ayak tahkimatı, tavan cıvatası (rock bolt) plaka | `ground_support_integrity` |
| Şev / basamak | basamak yüksekliği-genişliği oranı, gevşek blok, çatlak, drenaj, şev topuğu yükü | `slope_shoring_integrity` |
| Nakliyat | bant konveyör sıkışma noktası, kuyruk tamburu, çekme halatı acil durdurma, bant hizası | `nip_point_guard_integrity` |
| Ağır ekipman | geri manevra ikazı, ayna/kamera, kör nokta, lastik durumu, ROPS/FOPS kabin | `mobile_equipment_integrity` |
| Havalandırma | vantüp bütünlüğü, hava perdesi, kapı/regülatör | `ventilation_path_integrity` |
| Elektrik | ex-proof armatür, kablo askısı, pano bütünlüğü | `electrical_enclosure_integrity` |

**Ölümcül mekanizmalar:** göçük ve altında kalma; şevden kaya/blok düşmesi; grizu/toz patlaması; ağır ekipman altında ezilme veya çarpma; nakliyat sisteminde yakalanma; ani su baskını; havasız ortamda boğulma.

**Frekans priorı:** `default_f = 6` (günlük). Yeraltı üretim alanında `10` (sürekli) savunulabilir; gerekçe `underground_production_face`.

**Kontrol tercihleri:** Erişim yasağı ve bölge kapatma en üst sırada. Sıra: bölge tahliyesi/erişim yasağı → tahkimat güçlendirme veya şev düzeltme → gaz/toz ölçümü ve havalandırma → ekipman trafiği ayrımı → izinli çalışma → KKD (ferdi kurtarıcı dâhil).

**Mevzuat çapaları:** Maden İşyerlerinde İş Sağlığı ve Güvenliği Yönetmeliği; Tozla Mücadele Yönetmeliği; Patlayıcı Ortamların Tehlikelerinden Çalışanların Korunması Hakkında Yönetmelik; Maden ve Taşocakları İşletmelerinde Yapılan Sondaj İşleri Yönetmeliği.

**Negatif kurallar:** Gaz konsantrasyonu, grizu varlığı veya toz maruziyet seviyesini fotoğraftan iddia etme. Tahkimat yeterliliğini statik hesap gibi yorumlama. Yüksek ölümcül potansiyel sektörün genel özelliğidir; **her bulguya otomatik olarak S=100 verme** — çoklu ölüm için aynı olayda birden fazla kişiyi etkileyecek görünür maruziyet gerekir.

**Saha teyidine giden:** gaz ölçüm kayıtları, tahkimat projesi, patlatma planı, kurtarma istasyonu ve tatbikat kayıtları, havalandırma ölçümü.

---

### 5. Enerji · `energy`

**Tehlike sınıfı:** tipik olarak **tehlikeli / çok tehlikeli**

**Zorunlu modüller:** `electrical_safety`, `machine_safety_loto`, `access_and_work_at_height`, `emergency_equipment`, `ppe`
**Öncelik:** `structural_mechanical_integrity` → `hot_work_fire_explosion` → `pressure_process_safety` → `lifting_operations` → `egress_housekeeping`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| OG/AG panosu | kapak, kilit, kilit dili, IP contası, uyarı levhası, önünde serbest alan | `electrical_enclosure_integrity` |
| Trafo | bariyer/çit, kapı kilidi, topraklama iletkeni, yağ toplama havuzu, mesafe levhası | `electrical_isolation_barrier` |
| Jeneratör | egzoz yönü, yakıt hattı, akü bağlantısı, susturucu, kabin kapağı | `fuel_line_integrity` |
| Şalt sahası | çit yüksekliği, kapı kilidi, emniyet mesafesi, ayırıcı konumu, topraklama seti | `electrical_isolation_barrier` |
| Akü odası | havalandırma, göz duşu, asit nötrleyici, kıvılcım kaynağı | `ventilation_path_integrity` |
| PV / rüzgâr | DC kablo güzergâhı, konnektör, yaşam hattı, tırmanma sistemi, kilitli kapak | `electrical_enclosure_integrity`, `fall_arrest_anchor_presence` |

**Ölümcül mekanizmalar:** enerjili iletkene doğrudan temas; ark patlaması (arc flash) ve termal yaralanma; enerji izole edilmeden çalışma sırasında geri besleme; yüksekte çalışma sırasında düşme; kapalı hacimde egzoz/gaz birikimi.

**Frekans priorı:** `default_f = 2` (aylık) — enerji tesislerinde çoğu alan sürekli insan bulundurmaz, erişim genelde bakım amaçlıdır. Operatör kabini/kontrol odası görünüyorsa `6`; gerekçe `manned_control_area`.

**Kontrol tercihleri:** Beş adımlı emniyet kuralı vurgusu. Sıra: enerjiyi kes → kesme noktasını kilitle/etiketle → gerilim yokluğunu doğrula → topraklama ve kısa devre → komşu enerjili bölümleri bariyerle. Ancak bunlar prosedürdür; fotoğrafta görünen fiziksel eksikliği (açık kapak, eksik kilit, bariyer boşluğu) somut bulgu yap.

**Mevzuat çapaları:** Elektrik Kuvvetli Akım Tesisleri Yönetmeliği; Elektrik Tesislerinde Topraklamalar Yönetmeliği; Elektrik ile İlgili Fen Adamlarının Yetki Yönetmeliği; İş Ekipmanları Yönetmeliği EK-III (topraklama ölçümü periyodu); KKD Yönetmeliği (ark dayanımlı giysi).

**Negatif kurallar:** Gerilim seviyesini (OG/AG) fotoğraftan kesin belirleme; belirsizse "gerilim seviyesi saha teyidi gerektirir" de. Topraklama ölçüm değerini iddia etme. Ark enerjisi hesabı yapma.

**Saha teyidine giden:** topraklama ölçüm raporu, arc flash çalışması ve etiketleri, yetkilendirme belgeleri, kilit-etiket envanteri, termal kamera raporu.

---

### 6. Ofis · `office`

**Tehlike sınıfı:** tipik olarak **az tehlikeli**

**Zorunlu modüller:** `egress_housekeeping`, `emergency_equipment`, `ergonomics`, `electrical_safety`
**Öncelik:** `storage_racking` → `structural_mechanical_integrity` → `ppe` (nadiren geçerli)

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Çalışma istasyonu | ekran yüksekliği, klavye mesafesi, koltuk destek, ayak desteği, kablo yönetimi | `ergonomic_setup_integrity` |
| Kaçış yolu | koridor genişliği, kapı önü, yönlendirme armatürü, kilit tipi | `egress_path_clearance` |
| Yangın ekipmanı | söndürücü erişimi, dolap önü, işaretleme, basınç göstergesi | `emergency_equipment_access` |
| Dolap / raf | devrilme sabitlemesi, üst raf yükü, ağırlık dağılımı | `storage_stability_integrity` |
| Elektrik | çoklu priz zinciri, hasarlı kablo, zeminde geçen kablo, panolu alan erişimi | `electrical_enclosure_integrity` |

**Ölümcül mekanizmalar:** ofiste ölümcül mekanizma nadirdir. Gerçekçi ağır sonuçlar: yangın sırasında tıkalı kaçış yolundan kaynaklı ölüm; devrilen ağır dolabın altında kalma; merdivenden düşme. **Sıradan ergonomi veya takılma bulgusuna 40+ şiddet verme.**

**Frekans priorı:** `default_f = 6` (günlük) — ofis alanı sürekli kullanılır.

**Kontrol tercihleri:** Düşük maliyetli, hızlı uygulanabilir. Kablo kanalı, dolap sabitleme aparatı, kaçış yolu işgal yasağı, ekran/koltuk ayarı, aydınlatma düzeltmesi. Prosedür yerine fiziksel düzenleme öner.

**Mevzuat çapaları:** İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik; Ekranlı Araçlarla Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik; Binaların Yangından Korunması Hakkında Yönetmelik.

**Negatif kurallar:** Psikososyal riski fotoğraftan çıkarma. Aydınlatma seviyesini lüks olarak tahmin etme. Ergonomi bulgusunu "kalıcı iş göremezlik" seviyesine çıkarma.

**Saha teyidine giden:** yangın tahliye planı ve tatbikat, elektrik tesisat kontrolü, ekranlı araç göz muayenesi, aydınlatma ölçümü.

---

### 7. Depo / Lojistik · `logistics_warehouse`

**Tehlike sınıfı:** tipik olarak **tehlikeli**

**Zorunlu modüller:** `mobile_equipment_traffic`, `storage_racking`, `egress_housekeeping`, `emergency_equipment`
**Öncelik:** `lifting_operations` → `structural_mechanical_integrity` → `ergonomics` → `electrical_safety` → `ppe`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Raf sistemi | ayak darbe hasarı, çapraz eğilme, kiriş emniyet pimi, taban plakası dübeli, yük etiketi | `racking_frame_integrity`, `beam_locking_pin_presence` |
| Forklift | çatal aşınma/çatlak, koruma kafesi, zincir, park pozisyonu (çatal indirilmiş mi), şarj alanı | `mobile_equipment_integrity` |
| Yaya-araç ayrımı | zemin çizgisi, bariyer, ayna, kör nokta, kapı geçişi, hız kesici | `pedestrian_segregation_integrity` |
| Yükleme rampası | rampa kenar koruma, dok tamponu, tekerlek takozu, seviye ayar platformu | `dock_edge_protection` |
| İstif | yük yüksekliği, palet durumu, sarkma, devrilme açısı, streç sabitleme | `storage_stability_integrity` |

**Ölümcül mekanizmalar:** forklift ile yaya çarpışması/ezilme; raf çökmesi ve altında kalma; yüksekten düşen palet/yük; rampadan araç veya kişi düşmesi; forklift devrilmesi ve operatörün kabin dışına savrulması.

**Frekans priorı:** `default_f = 6` (günlük). Aktif sevkiyat/araç hareketi görünüyorsa `10`; gerekçe `continuous_traffic_visible`.

**Kontrol tercihleri:** Fiziksel ayrım öncelikli. Sıra: yaya yolunu bariyerle fiziksel ayır → kör noktaya ayna/sensör → hasarlı raf ayağını devre dışı bırak ve yükü boşalt → yük etiketi ve istif limiti → trafik planı ve hız → operatör yetkisi → reflektif yelek.

**Mevzuat çapaları:** İş Ekipmanları Yönetmeliği (EK-III forklift/istif makinesi periyodik kontrol); İşyeri Bina ve Eklentileri Yönetmeliği; Elle Taşıma İşleri Yönetmeliği; TS EN 15635 (çelik raf sistemlerinin kullanımı ve bakımı).

**Negatif kurallar:** Raf taşıma kapasitesini fotoğraftan hesaplama. Forklift operatörünün yetkisini görüntüden çıkarma. Yük ağırlığını kesin sayıyla yazma.

**Saha teyidine giden:** raf periyodik muayene raporu (yetkin kişi), forklift periyodik kontrolü, operatör operatörlük belgesi, trafik planı, yük kapasite etiketlerinin doğruluğu.

---

### 8. Kimya / Laboratuvar · `chemical_laboratory`

**Tehlike sınıfı:** tipik olarak **çok tehlikeli**

**Zorunlu modüller:** `chemical_risk`, `environmental_release_leak`, `emergency_equipment`, `ppe`, `pressure_process_safety`
**Öncelik:** `pipe_hose_connections` → `hot_work_fire_explosion` → `electrical_safety` → `egress_housekeeping` → `machine_safety_loto`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Kimyasal depolama | etiket okunabilirliği, uyumsuz madde yakınlığı, ikincil tutma küveti, raf malzemesi, kapak sızdırmazlığı | `chemical_segregation_integrity`, `secondary_containment_presence` |
| Çeker ocak | ön cam yüksekliği, hava akış göstergesi, iç düzen, priz konumu | `ventilation_path_integrity` |
| Acil ekipman | göz duşu/vücut duşu erişimi, işaretleme, test etiketi, önündeki engel | `emergency_equipment_access` |
| Gaz tüpü | zincir/kelepçe sabitleme, dik konum, kapak, regülatör, hortum yaşı | `cylinder_restraint_integrity` |
| Proses hattı | flanş, conta sızıntısı izi, korozyon, hortum kelepçesi, etiketleme, tahliye yönü | `pipe_hose_connection_integrity` |
| Basınçlı kap/reaktör | manometre, emniyet ventili, patlama diski, tahliye yönü, ankraj, seviye göstergesi | `pressure_relief_integrity` |

**Ölümcül mekanizmalar:** uyumsuz kimyasalların karışmasıyla toksik gaz/ekzotermik reaksiyon; basınçlı kap patlaması; parlayıcı buhar tutuşması; korozif madde ile ağır kimyasal yanık; kapalı hacimde oksijen yetersizliği.

**Frekans priorı:** `default_f = 3` (haftalık) — laboratuvar ve kimyasal depo alanları sürekli maruziyet göstermez. Aktif çalışma görünüyorsa `6`; gerekçe `visible_active_work`.

**Kontrol tercihleri:** Kaynağında kontrol baskın. Sıra: uyumsuz maddeyi ayır/ikame et → kapalı sistem ve lokal havalandırma → ikincil tutma ve dökülme seti → etiketleme ve SDS erişimi → miktar sınırlama → KKD (madde bazlı eldiven seçimi dâhil).

**Mevzuat çapaları:** Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik; Kanserojen veya Mutajen Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik; Patlayıcı Ortamların Tehlikelerinden Çalışanların Korunması Hakkında Yönetmelik; SEA (CLP) Yönetmeliği; İş Ekipmanları Yönetmeliği EK-III (basınçlı kap periyodik kontrolü).

**Negatif kurallar:** **Etiketten okunamıyorsa kimyasalın türünü, konsantrasyonunu veya tehlike sınıfını yazma.** Maruziyet seviyesi (ppm, mg/m³) iddia etme. Renkten madde tahmini yapma. Uyumsuz depolama bulgusu için iki maddenin kimliği de görünür olmalı; değilse "etiketleme ve ayrım saha teyidi gerektirir" de.

**Saha teyidine giden:** SDS envanteri ve erişilebilirliği, maruziyet ölçümleri, çeker ocak hava hızı ölçümü, acil duş test kayıtları, basınçlı kap muayene raporu, ATEX patlamadan korunma dokümanı.

---

### 9. Sağlık / Hastane · `healthcare`

**Tehlike sınıfı:** tipik olarak **tehlikeli / çok tehlikeli**

**Zorunlu modüller:** `egress_housekeeping`, `emergency_equipment`, `ergonomics`, `chemical_risk`
**Öncelik:** `electrical_safety` → `environmental_release_leak` → `storage_racking` → `ppe` → `pressure_process_safety` (medikal gaz)

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Atık istasyonu | tıbbi atık kabı rengi/işareti, delinmez kesici alet kabı doluluk çizgisi, kapak, ayrım | `waste_segregation_integrity` |
| Medikal gaz | tüp sabitleme, regülatör, hortum, oksijen alanı ayrımı, uyarı levhası | `cylinder_restraint_integrity` |
| Hasta transfer | lift/transfer ekipmanı varlığı, yatak frenleri, koridor genişliği | `ergonomic_transfer_support` |
| Zemin/geçiş | ıslak zemin uyarısı, kablo geçişi, kapı önü, tekerlekli sedye güzergâhı | `egress_path_clearance` |
| Dezenfektan | etiket, kapalı kap, havalandırma, göz duşu yakınlığı | `chemical_segregation_integrity` |
| Elektrik | çoklu priz, hasta yatağı çevresi kablo, UPS/jeneratör erişimi | `electrical_enclosure_integrity` |

**Ölümcül mekanizmalar:** yangın sırasında tahliyesi güç hasta grubunun kaçış yolunun kapalı olması; oksijen zenginleşmiş ortamda yangın; medikal gaz tüpünün devrilip regülatörünün kırılması; yüksek voltajlı cihaz çevresinde elektrik çarpması. Kesici-delici yaralanma ve enfeksiyon genelde ölümcül değildir — **S=40 vermeden önce mekanizmayı göster.**

**Frekans priorı:** `default_f = 10` (sürekli) — klinik alanlar 7/24 kullanılır.

**Kontrol tercihleri:** Klinik iş akışını kesmeyen fiziksel düzenlemeler. Sıra: kesici alet kabını doğru konuma ve doluluk sınırına al → atık ayrımını renk kodlu kapla → transfer ekipmanı sağla → kaçış yolunu boşalt → uyarı ve işaretleme → KKD.

**Mevzuat çapaları:** Biyolojik Etkenlere Maruziyet Risklerinin Önlenmesi Hakkında Yönetmelik; Tıbbi Atıkların Kontrolü Yönetmeliği; Sağlık Kurum ve Kuruluşlarında Hasta ve Çalışan Güvenliğinin Sağlanmasına Dair Yönetmelik; Binaların Yangından Korunması Hakkında Yönetmelik; Kimyasal Maddelerle Çalışmalarda Yönetmelik.

**Negatif kurallar:** Enfeksiyon riskini veya biyolojik etken sınıfını fotoğraftan iddia etme. Hasta mahremiyetine ilişkin çıkarım yapma. Sterilizasyon yeterliliğini görüntüden değerlendirme.

**Saha teyidine giden:** atık yönetim planı, biyolojik risk değerlendirmesi, medikal gaz sistemi periyodik kontrolü, tahliye planı ve hasta tahliye tatbikatı, personel bağışıklama kayıtları.

---

### 10. Gıda Üretimi · `food_production`

**Tehlike sınıfı:** tipik olarak **tehlikeli**

**Zorunlu modüller:** `machine_safety_loto`, `egress_housekeeping`, `chemical_risk`, `ergonomics`
**Öncelik:** `structural_mechanical_integrity` → `electrical_safety` → `pressure_process_safety` → `mobile_equipment_traffic` → `emergency_equipment` → `ppe`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Kesme/doğrama | bıçak muhafazası, itici aparat, acil durdurma, besleme ağzı | `machine_guard_integrity` |
| Karıştırıcı/hamur | kapak enterloku, palet koruyucu, açık kazan ağzı | `machine_guard_integrity` |
| Konveyör/dolum | sıkışma noktası, koruyucu, temizlik sırasında enerji izolasyonu | `nip_point_guard_integrity` |
| Buhar/sıcak hat | yalıtım bütünlüğü, kondenstop, vana etiketi, sıcak yüzey uyarısı | `hot_surface_protection` |
| Soğuk oda | içeriden açma mandalı, acil alarm, buzlanma, kapı contası | `cold_room_egress_integrity` |
| CIP / temizlik | kimyasal etiket, dozaj pompası, hortum, göz duşu, ayrık depolama | `chemical_segregation_integrity` |
| Zemin | ıslaklık, kaymaz yüzey, drenaj ızgarası, eğim | `slip_surface_integrity` |

**Ölümcül mekanizmalar:** temizlik sırasında enerji izole edilmeden makineye yakalanma; buhar/sıcak sıvı ile ağır haşlanma; soğuk odada mahsur kalma; amonyaklı soğutma sisteminden sızıntı; kapalı tank/silo içinde boğulma.

**Frekans priorı:** `default_f = 6` (günlük); üretim hattı kadrajında `10` savunulabilir, gerekçe `continuous_line_operation`.

**Kontrol tercihleri:** Hijyen ile çatışmayan mühendislik kontrolü. Paslanmaz/yıkanabilir muhafaza, enterlok, kaymaz zemin kaplaması ve drenaj, sıcak yüzey yalıtımı, soğuk oda iç açma ve alarm. Temizlik kimyasalını ikame et. KKD hijyen kurallarıyla uyumlu seçilmeli.

**Mevzuat çapaları:** İş Ekipmanları Yönetmeliği; Makine Emniyeti Yönetmeliği; Kimyasal Maddelerle Çalışmalarda Yönetmelik; İşyeri Bina ve Eklentileri Yönetmeliği; Elle Taşıma İşleri Yönetmeliği.

**Negatif kurallar:** Gıda güvenliği (HACCP) bulgusu üretme — bu ürün kapsamı dışındadır, iş güvenliğine odaklan. Soğutucu gaz türünü fotoğraftan iddia etme. Zemin kayganlığını sürtünme katsayısıyla ifade etme.

**Saha teyidine giden:** EKED prosedürü ve temizlik talimatı, soğutma sistemi (amonyak) acil planı, kapalı alan giriş izni sistemi, buhar kazanı periyodik kontrolü.

---

### 11. Tarım / Hayvancılık · `agriculture_livestock`

**Tehlike sınıfı:** tipik olarak **tehlikeli** — bazı alt kollarda az tehlikeli

**Zorunlu modüller:** `mobile_equipment_traffic`, `machine_safety_loto`, `chemical_risk`, `ppe`
**Öncelik:** `structural_mechanical_integrity` → `access_and_work_at_height` → `electrical_safety` → `hot_work_fire_explosion` → `ergonomics` → `emergency_equipment`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Traktör | ROPS/devrilme koruma çerçevesi, emniyet kemeri, PTO mili muhafazası, el freni, basamak | `rollover_protection_presence`, `pto_guard_integrity` |
| PTO / kuyruk mili | teleskopik mil kılıfı, zincir, bağlantı pimi | `pto_guard_integrity` |
| Balya / hasat makinesi | besleme ağzı koruyucusu, acil durdurma, bıçak muhafazası | `machine_guard_integrity` |
| Silo / yem deposu | giriş kapağı, düşme boşluğu, tırmanma merdiveni, kilit | `confined_space_access_control` |
| Hayvan alanı | kaçış yolu, ayırma bariyeri, kapı yönü, zemin kayganlığı, sıkışma noktası | `animal_handling_barrier_integrity` |
| Pestisit deposu | kilit, etiket, havalandırma, ayrık depolama, karışım alanı | `chemical_segregation_integrity` |

**Ölümcül mekanizmalar:** traktör devrilmesi ve altında kalma; korumasız PTO miline sarılma; hasat makinesi besleme ağzında yakalanma; silo içinde tahılda boğulma; büyükbaş hayvan tarafından ezilme/sıkıştırılma; kapalı gübre çukurunda gaz zehirlenmesi.

**Frekans priorı:** `default_f = 3` (haftalık) — tarımsal faaliyet mevsimlik ve değişkendir. Hayvan barınağı görünüyorsa `6` (günlük bakım), gerekçe `daily_animal_care`.

**Kontrol tercihleri:** Devrilme koruması ve mil muhafazası pazarlık dışı. Sıra: ROPS ve kemer → PTO kılıfı tamamla → besleme ağzı koruyucusu → hayvan alanında kaçış yolu ve bariyer → pestisit kilitli depolama → KKD (solunum koruması dâhil).

**Mevzuat çapaları:** İş Ekipmanları Yönetmeliği; Kimyasal Maddelerle Çalışmalarda Yönetmelik; Biyolojik Etkenlere Maruziyet Yönetmeliği (zoonoz); Bitki Koruma Ürünlerinin Uygulanmasına Dair Yönetmelik; Elle Taşıma İşleri Yönetmeliği.

**Negatif kurallar:** Pestisit türünü veya uygulama sonrası bekleme süresini fotoğraftan iddia etme. Zoonoz maruziyetini varsayma. Yalnız çalışma riskini fotoğrafta tek kişi görünmesinden çıkarma — kadraj dışında başkası olabilir.

**Saha teyidine giden:** traktör ve ekipman periyodik kontrolü, pestisit uygulama kayıtları ve reçete, hayvan sağlığı/zoonoz programı, yalnız çalışma prosedürü.

---

### 12. Perakende / Mağaza · `retail`

**Tehlike sınıfı:** tipik olarak **az tehlikeli**

**Zorunlu modüller:** `egress_housekeeping`, `storage_racking`, `emergency_equipment`
**Öncelik:** `ergonomics` → `electrical_safety` → `access_and_work_at_height` (merdiven) → `mobile_equipment_traffic` (depo arkası) → `structural_mechanical_integrity`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Teşhir rafı | duvara/zemine sabitleme, üst raf ağırlığı, devrilme açısı, köşe koruma | `storage_stability_integrity` |
| Kaçış yolu | koridor genişliği, kapı önü ürün, acil çıkış kilidi, yönlendirme armatürü | `egress_path_clearance` |
| Merdiven/basamak | ayak kaymazlığı, kilitlenme mekanizması, uygun yükseklik, kullanım konumu | `ladder_stability_integrity` |
| Depo arkası | istif yüksekliği, transpalet, geçiş genişliği, aydınlatma | `storage_stability_integrity` |
| Elektrik | çoklu priz, hasarlı kablo, aydınlatma armatürü, kasa çevresi | `electrical_enclosure_integrity` |
| Zemin | ıslaklık, uyarı dubası, halı kenarı, seviye farkı | `slip_surface_integrity` |

**Ölümcül mekanizmalar:** yangın sırasında tıkalı acil çıkış; ağır teşhir ünitesinin müşteri veya çalışan üzerine devrilmesi; yüksek istiften düşen ağır ürün. Diğer perakende riskleri genelde hafif-orta yaralanmadır — **S=40 için mekanizmayı göster.**

**Frekans priorı:** `default_f = 6` (günlük).

**Kontrol tercihleri:** Ucuz ve hızlı. Raf sabitleme aparatı, ağır ürünü alt rafa alma, kaçış yolu işgal yasağı ve zemin işaretlemesi, uygun basamak/merdiven sağlama, ıslak zemin prosedürü. Müşteri güvenliğini de kapsayacak biçimde yaz.

**Mevzuat çapaları:** İşyeri Bina ve Eklentileri Yönetmeliği; Binaların Yangından Korunması Hakkında Yönetmelik; Elle Taşıma İşleri Yönetmeliği; İş Ekipmanları Yönetmeliği (transpalet).

**Negatif kurallar:** Müşteri yoğunluğunu ve kalabalık yönetimini tek kareden çıkarma. Ürün ağırlığını kesin yazma. Kasiyer ergonomisini görünmeyen çalışma süresine dayandırma.

**Saha teyidine giden:** yangın tahliye planı, raf sabitleme uygunluğu, elektrik tesisat kontrolü, çalışan elle taşıma eğitimi.

---

### 13. Belediye / Kamu Saha İşleri · `municipal_field_services`

**Tehlike sınıfı:** tipik olarak **tehlikeli**

**Zorunlu modüller:** `mobile_equipment_traffic`, `excavation_slope_shoring`, `ppe`, `egress_housekeeping`
**Öncelik:** `lifting_operations` → `electrical_safety` → `access_and_work_at_height` → `environmental_release_leak` → `structural_mechanical_integrity` → `emergency_equipment`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Trafik güvenliği | koni/delineatör dizilimi, ön uyarı mesafesi, levha, sarı ikaz lambası, geçiş koridoru | `traffic_control_zone_integrity` |
| Kazı (altyapı) | şev/iksa, kenar yükü, yaya geçiş köprüsü, gece aydınlatması, bariyer sürekliliği | `slope_shoring_integrity`, `public_barrier_continuity` |
| Rögar/kapalı alan | kapak, üçayak/vinç, gaz ölçer, havalandırma fanı, giriş bariyeri | `confined_space_access_control` |
| Çöp toplama aracı | sıkıştırma haznesi koruyucusu, basamak, geri manevra ikazı, ayna | `mobile_equipment_integrity` |
| Sepetli araç | outrigger pabuç, sepet korkuluğu, yaşam hattı ankrajı, enerji hattı mesafesi | `fall_arrest_anchor_presence` |
| Ağaç/budama | testere muhafazası, düşme bölgesi bariyeri, yaşam hattı | `machine_guard_integrity` |

**Ölümcül mekanizmalar:** trafik akışındaki araç tarafından çarpılma; kazı göçüğü; rögar/kapalı alanda gaz zehirlenmesi veya oksijensizlik; sepetli araçtan düşme veya enerji hattına temas; çöp aracı sıkıştırma haznesine kapılma; **üçüncü kişi (yaya/çocuk) kazı veya çalışma alanına düşmesi.**

**Frekans priorı:** `default_f = 3` (haftalık) — saha ekipleri iş bazlı çalışır. Aktif trafik ve çalışan görünüyorsa `6`, gerekçe `visible_active_work`.

**Kontrol tercihleri:** Kamu ayrımı en üstte. Sıra: çalışma alanını kamudan fiziksel olarak sürekli bariyerle ayır → trafik yönlendirme ve ön uyarı mesafesi → kazıyı iksala veya şevlendir → kapalı alan giriş izni ve gaz ölçümü → yüksek görünürlüklü giysi. Reflektif yelek asla tek başına trafik kontrolü sayılmaz.

**Mevzuat çapaları:** Yapı İşlerinde İSG Yönetmeliği; Karayolları Trafik Yönetmeliği (çalışma alanı işaretlemesi); İş Ekipmanları Yönetmeliği; Kimyasal Maddelerle Çalışmalarda Yönetmelik (kanalizasyon gazları); KKD Yönetmeliği (EN ISO 20471 yüksek görünürlük).

**Negatif kurallar:** Gaz konsantrasyonunu iddia etme. Trafik hızını tahmin etme. Bariyerin arkasında ne olduğunu varsayma.

**Saha teyidine giden:** trafik işaretleme planı onayı, kapalı alan giriş izni ve gaz ölçüm kaydı, sepetli araç periyodik kontrolü, kazı ruhsatı ve altyapı sorgusu.

---

### 14. Eğitim Kurumu · `education`

**Tehlike sınıfı:** tipik olarak **az tehlikeli**

**Zorunlu modüller:** `egress_housekeeping`, `emergency_equipment`, `structural_mechanical_integrity`
**Öncelik:** `chemical_risk` (laboratuvar) → `machine_safety_loto` (atölye) → `electrical_safety` → `access_and_work_at_height` → `storage_racking` → `ppe`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Merdiven/koridor | korkuluk yüksekliği, dikey çubuk aralığı (tırmanma engeli), basamak kaymazlığı, tahliye genişliği | `guard_barrier_integrity`, `egress_path_clearance` |
| Kaçış yolu | kapı açılma yönü, panik bar, kilit, yönlendirme, toplanma yönü | `egress_path_clearance` |
| Laboratuvar | çeker ocak, kimyasal dolabı kilidi, göz duşu, gaz vanası ana kesme | `chemical_segregation_integrity` |
| Atölye | tezgâh koruyucusu, acil durdurma, ana şalter erişimi, öğrenci mesafesi | `machine_guard_integrity` |
| Mobilya/dolap | duvara sabitleme, devrilme, keskin köşe, cam yüzey | `storage_stability_integrity` |
| Oyun/spor alanı | zemin darbe emici, ekipman ankrajı, düşme yüksekliği | `impact_surface_integrity` |

**Ölümcül mekanizmalar:** tahliye sırasında tıkalı kaçış yolu ve izdiham; korkuluk boşluğundan veya tırmanılabilir korkuluktan düşme; devrilen dolap altında kalma; laboratuvar/atölyede denetimsiz makine veya kimyasal erişimi.

**Frekans priorı:** `default_f = 6` (günlük, ders saatleri).

**Kontrol tercihleri:** Çocuk/genç kullanıcıya göre. Erişim kilitleme (kimyasal dolabı, atölye ana şalteri), tırmanmayı engelleyen korkuluk geometrisi, mobilya sabitleme, keskin köşe koruması, tahliye yolunu sürekli boş tutma. Prosedür değil fiziksel engel öner.

**Mevzuat çapaları:** İşyeri Bina ve Eklentileri Yönetmeliği; Binaların Yangından Korunması Hakkında Yönetmelik; Kimyasal Maddelerle Çalışmalarda Yönetmelik; Millî Eğitim Bakanlığı Kurum Açma ve Kapatma Yönetmeliği (fiziki şartlar).

**Negatif kurallar:** Öğrenci sayısı veya doluluk oranını fotoğraftan çıkarma. Denetim/gözetim yeterliliğini varsayma. Çocuk davranışını kesin risk faktörü olarak yazma; "erişilebilir" tespiti fiziksel ve yeterlidir.

**Saha teyidine giden:** tahliye planı ve tatbikat kayıtları, laboratuvar kimyasal envanteri, atölye ekipman periyodik kontrolü, oyun ekipmanı uygunluk belgesi.

---

### 15. Otel / Konaklama · `hospitality`

**Tehlike sınıfı:** tipik olarak **az tehlikeli / tehlikeli**

**Zorunlu modüller:** `egress_housekeeping`, `emergency_equipment`, `electrical_safety`
**Öncelik:** `chemical_risk` (temizlik/çamaşırhane) → `machine_safety_loto` (mutfak/çamaşırhane) → `ergonomics` → `access_and_work_at_height` → `pressure_process_safety` (kazan dairesi) → `storage_racking`

**Kritik ekipman ve bileşenler:**

| Ekipman ailesi | Bakılacak bileşen | Kritik kontrol |
|---|---|---|
| Kaçış yolu | koridor işgali, yangın kapısı kapalılığı, panik bar, acil aydınlatma, kat planı | `egress_path_clearance` |
| Mutfak | davlumbaz filtresi ve yağ birikimi, söndürme sistemi nozulu, fritöz çevresi, kesici ekipman koruyucusu | `kitchen_suppression_integrity`, `machine_guard_integrity` |
| Çamaşırhane | ütü/pres enterloku, sıcak yüzey, buhar hattı, kimyasal dozaj | `machine_guard_integrity`, `hot_surface_protection` |
| Kazan dairesi | manometre, emniyet ventili, gaz dedektörü, havalandırma menfezi, ana kesme vanası | `pressure_relief_integrity` |
| Havuz / ıslak alan | kaymaz zemin, derinlik işareti, cankurtaran ekipmanı, kimyasal odası kilidi | `slip_surface_integrity` |
| Misafir alanı | halı kenarı, seviye farkı, cam yüzey işareti, balkon korkuluğu yüksekliği | `guard_barrier_integrity` |

**Ölümcül mekanizmalar:** yangın sırasında kapalı olmayan yangın kapısı ve tıkalı kaçış yolu nedeniyle misafir kaybı; mutfak davlumbaz yangını; kazan patlaması veya gaz kaçağı; balkon/merdiven korkuluğundan düşme; havuz kimyasallarının karışmasıyla klor gazı.

**Frekans priorı:** `default_f = 10` (sürekli) — konaklama tesisi 7/24 misafir barındırır.

**Kontrol tercihleri:** Misafir güvenliği ile operasyon sürekliliğini birlikte koru. Yangın kapısını kapalı tutan otomatik kapatıcı, davlumbaz temizlik periyodu, kaymaz zemin, korkuluk yükseltme, kimyasal odası kilidi, personel alanında makine koruyucusu. Misafirin göremeyeceği teknik alanlarda mühendislik kontrolü, misafir alanında fiziksel düzenleme.

**Mevzuat çapaları:** Binaların Yangından Korunması Hakkında Yönetmelik; İşyeri Bina ve Eklentileri Yönetmeliği; İş Ekipmanları Yönetmeliği EK-III (kazan, asansör periyodik kontrol); Kimyasal Maddelerle Çalışmalarda Yönetmelik; Yüzme Havuzlarının Tabi Olacağı Sağlık Esasları Yönetmeliği.

**Negatif kurallar:** Doluluk oranını veya misafir sayısını çıkarma. Yangın algılama sisteminin çalışırlığını dedektör görüntüsünden iddia etme. Havuz kimyasal seviyesini yazma.

**Saha teyidine giden:** yangın algılama/söndürme sistemi periyodik kontrolü, davlumbaz temizlik kayıtları, kazan ve asansör muayene raporları, havuz su analizi, tahliye tatbikatı.

---

## 3. Bütün sektörlere uygulanan ortak kurallar (v2)

v1'deki sekiz kural korunuyor, üç yenisi ekleniyor:

1. Tehlikeleri sektörün saha gerçekliğine göre önceliklendir.
2. Terminolojiyi seçilen sektöre uygun kullan.
3. Düzeltici ve önleyici kontrolleri sektörde uygulanabilir şekilde yaz.
4. Mevzuat, iyi uygulama ve saha kontrol önerilerini sektörle uyumlu kur.
5. Görselde veya kullanıcı bilgisinde kanıtı olmayan sektör-tipik tehlikeleri uydurma.
6. Sektör ile görüntü çelişirse **görsel kanıtı üstün kabul et**.
7. Onboarding'de seçilen diğer sektörlerden ek tehlike üretme.
8. Sektör bilgisini tek başına Fine-Kinney veya 5×5 skorunu yükseltmek için kullanma.
9. **YENİ — Zorunlu modül atlanamaz.** Sektörün `mandatory_modules` listesindeki her modül için bir sonuç üret: `actionable`, `checked_no_hazard`, `not_visible` veya `uncertain`. Modülü hiç döndürmemek geçerli değildir.
10. **YENİ — Sektör frekans priorı şeffaf olmalı.** `frequency_prior` kullanıldığında `frequency_basis = "sector_prior"` yazılır ve bulgu saha teyidi bayrağı taşır. Prior asla `visible_active_work` gibi gösterilmez.
11. **YENİ — Sektörün kritik ekipmanı görülüp sonuç üretilemediyse bu kayıp değil, kayıttır.** `component_coverage` içine `unresolved_no_fact` yazılır ve hedefli ikinci inceleme tetiklenir. Yerine jenerik periyodik kontrol maddesi koyarak kapatma.

---

## 4. vNext'te nereye bağlanır

| Profil alanı | vNext kancası |
|---|---|
| `mandatory_modules` | ilk fotoğraf promptunda modül listesi; eksikse `module_audit_incomplete` |
| `priority_modules` | modül sıralaması ve çıktı token bütçesi dağılımı |
| `critical_equipment` | `asset-assurance-catalog` aktivasyonu ve `component_coverage` beklentisi |
| `fatal_mechanisms` | `consequence_class` seçiminde çapa; `single_fatality`/`multiple_fatality` iddiası bu listeyle eşleşmeli |
| `frequency_prior` | `frequency_basis = sector_prior` ve provisional F |
| `control_preferences` | kontrol niyeti seçiminde hiyerarşi sırası ve sektör uygulanabilirliği |
| `regulation_anchors` | `references_text` katalog eşleştirmesi |
| `negative_rules` | validator reddi ve `rejection_ledger` reason code |
| `assurance_scope` | fotoğraftan doğrulanamayan başlıkların güvence tarafına yönlendirilmesi |

---

## 5. Açık kararlar

1. **`typical_hazard_class` skorlamaya girsin mi?** Önerim **hayır** — yalnız mevzuat eşleştirmesi ve saha teyidi kapsamı için. Skora girerse sektör seçimi risk puanını şişirir.
2. **`frequency_prior` değerleri onaylanmalı.** Yukarıdaki F değerleri savunulabilir başlangıçlardır ama İSG uzmanı onayı gerekir; her biri sürümlenmeli.
3. **`critical_equipment` check_code adları** mevcut `asset-assurance-catalog` ile hizalanmalı. Bu dokümanda okunabilirlik için açıklayıcı adlar kullandım; kod tarafında kanonik anahtarlar kullanılmalı.
4. **Alt sektör gerekli mi?** İmalat çok geniş (metal, tekstil, plastik, mobilya). İkinci tur için `sub_sector` alanı düşünülebilir; ilk sürümde gerekmez.
5. **Genel İSG profili** modül önceliğini görüntüden dinamik kuruyor. Bu davranışın ayrı testi olmalı.
