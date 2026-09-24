# İSGADA — Sihirbaz geliştirme ve bakım takibi

Güncelleme: **24.09.2026**  
Katalog: **isgada-v5.0.0** · Motor: **isgada-engine-5.0.0**  
Durum: Risk Analizi ve Acil Durum Planı için cihazda taslak üretme, indirme ve mevcut dosya arşivine gönderme akışı kodda eklendi. Üretim ortamına dağıtım yapılmadı. Arşiv yüklemesinin gerçek hesapla uçtan uca kontrolü henüz yapılmadı.

Bu belge yapılan işleri ve sonraki geliştirmeleri takip etmek içindir. Kullanıcının kararları, teslim edilen V4 paketindeki zorunlu işyeri ve uzman doğrulaması önerilerinin yerine geçer. İndirilen kaynak paket değiştirilmedi; uyarlanan kaynaklar proje içine alındı.

## 1. Kesin ürün kararları

- [x] Uzman onayı, uzman doğrulaması, yayın onayı veya bunları bekleyen bir durum yok.
- [x] Firma seçmeden Risk Analizi ve Acil Durum Planı taslağı oluşturulabilir.
- [x] Firma altında işyeri tanımlıysa seçim sunulur. Seçim isteğe bağlıdır.
- [x] İşyeri tanımlı değilse alan gösterilmez; devam etmek için kayıt açılması istenmez.
- [x] İşyeri listesi yüklenemezse kullanıcı işyeri seçmeden devam edebilir.
- [x] Firma değiştiğinde önceki firmanın işyeri seçimi temizlenir.
- [x] Tek sayfada, açılıp kapanan adımlarla ilerlenir; önceki soruya dönülebilir.
- [x] Soru bütçesi artırıldı: Risk Analizi 13, Acil Durum Planı 11 soru.
- [x] Yeni sektör, ekipman, iş ve risk bilgileri sürümlenen kaynak kataloğa eklenebilir.

Soruların tamamı isteğe bağlıdır. Eksik bilgiler belgede görünür; cevaplanmamış bir soru kendiliğinden “yok” sayılmaz. Firma listesine erişilememesi yerel taslak üretimini engellemez.

## 2. Kullanıcının ulaşacağı akış

1. Risk Değerlendirmesi veya Acil Durum Planları ekranındaki **Sihirbaz ile taslak oluştur** düğmesi açılır.
2. İstenirse firma ve mevcut işyeri seçilir.
3. Faaliyetler, alanlar, ekipmanlar, işler, özel tehlikeler ve çalışma düzeni seçilir. Seçeneklerde kelime araması yapılabilir.
4. Dört yeni soru grubu ile kapsam netleştirilir: özel süreçler, enerji/akışkan sistemleri, maruz kalan kişiler, kritik acil durum sistemleri.
5. Risk akışında yöntem ve belge kapsamı seçilir; mevcut Fine–Kinney ve Standart varsayılanları görünürdür.
6. Taslak oluşturulur. İçerik, kapsamı netleşmemiş konular ve satır sınırı dışında kalan konular görülebilir.
7. **Word, Excel veya PDF** indirilebilir. Word ve Excel çıktıları dışarıda düzenlenebilir.
8. İstenirse **Word dosyasını arşive ekle** ile mevcut Dosyalarım servisine gönderilir. Firma seçimi yoksa kişisel kapsam kullanılır.

Sihirbaz otomatik olarak tarihli risk değerlendirmesi/plan kaydı açmaz. Dosyanın üretilmesi, bir değerlendirme veya geçerlilik tarihi belirlenmesi anlamına gelmez. Tarihli modül kaydı ve evrak süresi takibi mevcut kayıt ekranlarından yapılır.

## 3. Entegrasyon yapısı

| Katman | Uygulama |
|---|---|
| Ortak içerik | `content/isg/wizard/source/` içindeki düzenlenebilir kaynaklar |
| Katalog üretimi | `content/isg/wizard/build.py` ve `scripts/isg/wizard/catalogue.py` |
| Paketlenen içerik | `App/WizardAssets/isg_wizard/isgada-catalog.json` |
| Ortak seçim motoru | `App/WizardAssets/isg_wizard/engine.js` |
| Word / Excel üretimi | `App/WizardAssets/isg_wizard/export.js` |
| iOS | SwiftUI ekranı; JavaScriptCore ile ortak motor; yerel PDF üretimi |
| Android | Compose ekranı; ağ erişimi kapalı, görünmeyen WebView içinde ortak motor; yerel PDF üretimi |
| Arşiv | Mevcut `NovaFileLibraryClient`; mevcut kimlik, kapsam ve dosya denetimi |

Bu teslim için yeni veritabanı tablosu, RLS kuralı, Storage bucket veya sunucu görevi eklenmedi. V4 paketindeki SQL adayları çalıştırılmadı. Yerel üretim şirket verisini harici bir yapay zekâ servisine göndermez.

Android'de büyük kataloğun tek bir `data:` adresi ile yüklenmesi cihaz testinde başarısız oldu. Başlangıç sayfası küçültüldü; paket içindeki katalog 32.000 karakterlik parçalarla çalışma zamanına aktarılıyor. JavaScript arayüzü, ağ, dosya ve içerik erişimi açılmadı.

### İçerik kapasitesi

| İçerik | Adet |
|---|---:|
| Risk kaydı | 621 |
| Risk ailesi | 52 |
| Acil durum eylem kartı | 72 |
| Sektör | 181 |
| Ekipman | 305 |
| İş / görev | 246 |

Bu sayılar katalog kapasitesidir; her belgeye bütün kayıtlar eklenmez. Seçimler ve koşullar ilgili kayıtları belirler. Katalog tüm olası saha koşullarının eksiksiz listesi olarak sunulmaz.

## 4. V4 incelemesi sonucunda yapılan iyileştirmeler

| Konu | Durum ve uygulama |
|---|---|
| Erişilemeyen risk/kart koşulları | Hidrolik, vakum, tank içine girme, asit seyreltme, solventli kurutma, gaz çıkaran akü şarjı, organik öğütme, taşınabilir ısıtıcı ve kritik sistem seçenekleri eklendi/düzeltildi. |
| Aile koşullarının atlanması | Kayıt ve risk ailesi koşulları birlikte uygulanıyor. Koşul grubu içindeki alternatifler korunuyor. |
| Yanlış kapsam çıkarımı | Tankın bulunması tanka girildiği anlamına gelmiyor. Her forklift gaz çıkaran akü şarjı varmış gibi değerlendirilmiyor. |
| Ofis yanlış eşleşmeleri | R-26-10 kritik proses/sistem seçimine bağlandı. R-26-11 yoğun iş veya kesintisiz personel ihtiyacı koşuluna bağlandı; otomatik ofis önerisinden çıkarıldı. |
| Sıcak ortam | Genel sıcak ortam için R-23-13 eklendi; yalnız fırın işine özgü senaryoya dayanılmıyor. |
| Deprem sonrası dönüş | AD-039 seçimi AD-040 kartını da getiriyor. |
| Kimyasal olayın büyümesi | AD-021 ile AD-022 birlikte erişilebilir; daha geniş olay akışı kaybolmuyor. |
| Belgeden kaybolan adaylar | Kapsamı netleşmemiş adaylar kimlik, senaryo, zarar ve eksik bilgilerle ek bölüme taşınıyor. Arayüzde de görülebiliyor. |
| Kapsam sınırı | Dışarıda kalan uygun kayıtların kimlik/başlıkları ve ağır zarar işareti belgede korunuyor. |
| Yalnız kimlik gösteren özet | Özet senaryo ve olası zararı da içeriyor. |
| Kısa örnek paket | Ortak tahliye konusu için yer ayrılıyor; aile çeşitliliği seçimde dikkate alınıyor. |
| Önlem dili | İlk 600 kaydın birinci önlemleri açık fiil eşlemeleriyle aynı hitap biçimine getirildi. |
| Sorumlu roller | Genel rol kodları eklendi; ofis ergonomisi ve psikososyal konularda işveren/işveren vekili gösteriliyor. Kişi adı uydurulmuyor. |
| Önlem hiyerarşisi | R-42-07, R-27-02 ve R-38-10 etiketleri düzeltildi. Kalan bileşik önlemler aşağıdaki içerik iş listesinde. |
| Ağır zarar işareti | Üretim sırasında anahtar kelime tahmini yerine kaynakta açık boolean değerler kullanılıyor. Bu işaret risk puanı değildir. |
| Boş / yok ayrımı | “Yok”, “Bilmiyorum” ve seçilmiş değerler ayrı tutuluyor. Çelişkili “yok” cevabı ekipmanla bildirilen riski silmiyor. |
| Tekrarlı kaynak tanımları | V4'teki etkin değerler birleştirildi; her yapılandırma sabiti tek tanımda tutuluyor. |
| Tehlike sınıfı sözlüğü | Referans verisi mevcut `low / medium / high` sözlüğüyle uyumlu. Bu sürüm otomatik ekip sayısı veya yenileme tarihi hesaplamıyor. |
| Manifest üreticisi | Kaynakları ve üretilen dosyaları SHA-256 ile izleyen üretim/kontrol komutu eklendi. |
| Eşdeğer riskler | Tanımlı eşdeğer topraklama kayıtları birleştiriliyor; kaynak kayıt kimlikleri korunuyor. |
| Belge kimliği | Katalog, motor ve yöntem profili sürümü ile içerik özeti çıktıya ekleniyor. Word/Excel aynı tam JSON görüntüsünü de içeriyor. |

Claude incelemesindeki R-42-09'un `public_area` içinde bulunduğu iddiası V4'ün etkin yapılandırmasında doğrulanmadı; zaten çıkarılmış olan eşleme ikinci kez değiştirilmedi. İnceleme listesindeki öneriler otomatik talimat kabul edilmedi; kullanıcının ürün kararlarıyla ve gerçek kaynaklarla karşılaştırıldı.

## 5. Test ve doğrulama kaydı

24.09.2026 çalıştırmaları:

| Kontrol | Sonuç / kapsam |
|---|---|
| Katalog yeniden üretimi ve manifest | Geçti; kaynaklardan yeniden üretim aynı dosyaları veriyor. |
| Ortak JavaScript testleri | **35 / 35 geçti.** Dört V4 profilinin korunması, firmasız üretim, isteğe bağlı işyeri, özel senaryolar, çelişkiler, sıralama, hash, dosya üretimi dahil. |
| Mevcut dosya denetleyicisi | **4 / 4 geçti.** Risk ve acil durum Word/Excel dosyaları yerel sunucu denetleyicisinden geçti. |
| iOS simülatör derlemesi | Geçti. |
| iOS yerel çalışma zamanı | **2 / 2 geçti.** Paket içi kaynak yükleme, firmasız/işyerisiz üretim, Word/Excel/PDF, acil kartlar. |
| iOS arayüz akışı | **1 / 1 geçti.** Firma seçmeden ilerleme, işyeri alanının gizlenmesi, taslak oluşturma ve üç indirme düğmesine ulaşma. |
| Android Kotlin derlemesi | Geçti. |
| Android API 33 cihaz testi | **1 / 1 geçti.** Gerçek WebView yükleme/üretim, iki ZIP çıktısındaki tam JSON eşitliği, çok sayfalı PDF, firmasız ve işyerisiz üretim. |
| Word görsel kontrolü | Risk örneği 7 sayfa, acil durum örneği 8 sayfa render edildi; bütün sayfalar incelendi. Tablo başlıkları, metin taşması ve sayfa bölünmeleri kontrol edildi. |
| Excel/OOXML kontrolü | ZIP bütünlüğü ve XML ayrıştırması geçti. Çalışma sayfaları açıldı; başlık sabitleme ve metin hücreleri kontrol edildi. Kullanıcı metni formül olarak yazılmıyor. |

Test kaynakları:

- `scripts/isg/wizard/engine.test.mjs`
- `scripts/isg/wizard/file_inspector.test.ts`
- `RiskDetectedSnapshotTests/NovaDocumentWizardTests.swift`
- `RiskDetectedUITests/NovaDocumentWizardUITests.swift`
- `android/feature/nova/src/androidTest/kotlin/com/riskdetectedan/feature/nova/NovaDocumentWizardRuntimeTest.kt`

Bu sonuçlar canlı hesapla dosya yüklenmesini, bütün cihaz boyutlarını veya tüm katalog metinlerinin içerik incelemesini tamamlanmış saymaz. Kullanıcı akışına uzman onayı gerektiren bir adım eklenmez.

## 6. Yayın öncesi kalan kontroller

Bu liste ürün geliştirme takibidir; mevcut kullanıcı akışında bir onay ekranı oluşturmaz.

- [ ] Gerçek staging hesabında firmasız Word arşivleme, firma seçerek arşivleme, indirme ve sonradan açma akışını dene.
- [ ] Firma altında sıfır/bir/birden fazla işyeri için gerçek API yanıtlarıyla seçim davranışını kontrol et.
- [ ] OSGB/uzman kapsamı, oturum değişimi, erişimi kaldırılan firma, yükleme hatası ve yeniden denemeyi gerçek yetkilerle kontrol et.
- [ ] Arşiv düğmesinin aynı görünümde tekrar gönderimi engellediğini; sayfa yeniden açıldıktan sonraki kopya dosya davranışının mevcut arşiv kurallarıyla uyumunu kontrol et.
- [ ] Küçük ekran ve büyük yazı boyutunda iOS/Android soru ve indirme akışını dene; Android'in sistem dosya kaydetme ekranını ve iOS dosya dışa aktarımını fiziksel cihazda kontrol et.
- [ ] Uygulama dağıtımı sırasında üç ortak varlığın birlikte paketlendiğini kontrol et: `engine.js`, `export.js`, `isgada-catalog.json`.

## 7. Sonraki geliştirmeler — açık iş listesi

### A. Belge üzerinde çalışma

- [ ] Uygulama içinde taslak oturumunu kaydetme, yeniden açma ve silme. Şu anda yanıtlar ekranın belleğinde tutulur; ekran kapatıldığında kalıcı oturum yoktur.
- [ ] Risk satırı ekleme/çıkarma ve metin düzenleme; sonradan eklenen kullanıcı içeriğini katalog kaydından ayırma.
- [ ] Kullanıcının girdiği değerlendirme faktörlerini aynı yöntem profiliyle hesaplama. Türkçe ondalık gösterim, sayısal Excel hücreleri ve profil uyuşmazlığı testleri ekleme.
- [ ] Mevcut önlemler, planlanan önlemler, sorumlu kişi, değerlendirme tarihi ve diğer belge alanlarını isteğe bağlı düzenleme. Kullanıcının vermediği değerleri doldurmama.
- [ ] İstenirse üretilen dosyayı mevcut tarihli risk/plan kaydına bağlayan açık bir işlem ekleme; belge üretim zamanını geçerlilik başlangıcı yerine kullanmama.
- [ ] Kapsamı netleşmemiş bir konudan ilgili soruya doğrudan geçiş ekleme. Şu anda kullanıcı ilgili soru başlığına geri dönebilir.

### B. Mevcut verileri kullanma

- [ ] Önceki bulgu ve değerlendirmeleri isteğe bağlı kullanacak yetkili bir adaptör ekleme. Şu an motor `context`, `reuse`, `assessed_scores` gibi dış bağlam alanlarını kabul etmiyor.
- [ ] Aktarımda kullanıcı/çalışma alanı/firma/işyeri ilişkisini mevcut servis üzerinden kontrol etme; istemciden gelen kimliği yetki kanıtı saymama.
- [ ] Eski skorları yalnız aynı yöntem ve profil sürümüyle taşıma; uyuşmazlıkta yeniden hesaplamadan sessizce kullanmama.
- [ ] Kalıcı oturum eklenirse hesap silme, erişim kaldırma, dosya yaşam döngüsü ve eski sürüm korunması testlerini birlikte ekleme.

### C. İçerik kalitesi ve genişleme

- [ ] Yeni sektör taleplerini aşağıdaki standartla ekleme; her yeni kayıt için olumlu ve olumsuz örnek yanıt oluşturma.
- [ ] Arama eş anlamlılarını genişletme. NACE eşlemesini tahmin yerine sağlanan/doğrulanmış kapsamla kurma.
- [ ] Bileşik önlemleri tek hiyerarşi düzeyindeki ayrı önlemlere ayırma. İlk liste: R-12-01, R-12-03, R-37-07, R-15-01, R-14-11, R-01-09, R-22-06, R-04-11, R-36-07, R-14-04, R-15-09. Kayıt başına 2–4 somut önlem sınırını koruma.
- [ ] Ağır zarar işaretlerini içerik değiştikçe açıkça güncelleme; puan veya saha bulgusu yerine kullanmama.
- [ ] Yeni mevzuat konu bağlantıları için birincil kaynak, kapsam ve kontrol tarihi tutma. Topraklama, büyük endüstriyel kazalar, kanserojen/mutajen maddeler ve mesleki eğitim önerileri bu sürümde genişletilmedi.
- [ ] Kullanıcı tarih ve tehlike sınıfı sağlarsa “önerilen yenileme tarihi” ve referans ekip sayıları ekleme. Gerçek belge tarihi/atanmış ekip üyesiyle karıştırmama.
- [ ] Yeni eşdeğer kayıt gruplarını tek tek tanımlama; benzer görünen farklı tehlikeleri otomatik birleştirmeme.

### D. Katalog dağıtımı

- [x] Yeni içerik ekleme, test etme, sürümleme ve uygulama paketine dahil etme altyapısı.
- [ ] Uygulama güncellemesi beklemeden içerik dağıtılması gerekirse imzalı JSON kataloğu, şema uyumluluğu, indirme bütünlüğü, çevrimdışı son çalışan sürüm ve geri dönüş ekleme. Uzaktan çalıştırılabilir JavaScript dağıtmama.
- [ ] İçerik düzenleme iş yükü artarsa mevcut kaynak dosyalarını üreten yönetim aracı ekleme; risk kayıt kimliklerini yeniden kullanmama.

## 8. Yeni bilgi geldiğinde uygulanacak bakım yolu

1. **Kapsamı yaz:** sektör/faaliyet, ekipman, yapılan iş, özel madde/enerji, maruz kalan kişiler ve acil durumlar.
2. **Mevcut kayıtla karşılaştır:** var olan kayıt yeterliyse yeni kopya oluşturma; eşleme veya arama adı ekle.
3. **Yeni senaryoyu tanımla:** benzersiz kimlik, bağlam, olay, olası zarar, 2–4 somut önlem, rol, konu referansı, özellik ve aile koşulları.
4. **Seçilebilir yap:** ilgili ekipman/iş/ek soru üzerinden gerekli özelliğe gerçekten ulaşılabilsin. Cihazın varlığı ile belirli işi yapmayı ayrı tut.
5. **Test ekle:** ilgili seçimde kayıt gelmeli, benzer fakat ilgisiz seçimde gelmemeli. Acil kart bağımlılıklarını da kontrol et.
6. **Sürümü artır:** `source/extensions.json` içindeki katalog sürümünü güncelle. Eski kimlikleri başka anlamda tekrar kullanma.
7. **Üret ve doğrula:** aşağıdaki komutları çalıştır; örnek Word/Excel/PDF içeriğini kontrol et.
8. **Takibe yaz:** tarih, eklenen/değişen kimlikler, kaynak bilgi, test ve dağıtım durumu bu belgeye veya tarihli devam belgesine işlenir.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/isg/wizard/catalogue.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/isg/wizard/catalogue.py --check
node --test scripts/isg/wizard/engine.test.mjs
deno test --allow-read scripts/isg/wizard/file_inspector.test.ts
```

`data/` ve uygulama içindeki üretilmiş JSON elle düzenlenmez. İndirilmiş/arşivlenmiş belgeler yeni katalog geldiğinde kendiliğinden değişmez. Aynı içerikle yeniden üretim aynı içerik kimliğini verir. Kullanıcının Word/Excel içinde sonradan yaptığı değişiklikler gömülü JSON görüntüsünü otomatik güncellemez; bu görüntü ilk üretimin kaydıdır.

Kaynak dosyaların ayrıntılı açıklaması: [Katalog bakım rehberi](../../content/isg/wizard/README.md).

## 9. Son kontrol kaydı

- 24.09.2026: Katalog `isgada-v5.0.0`, 621 risk ve 72 kart ile üretildi.
- Katalog SHA-256: `deb614a951066b588ddc3ea1cbff2c34b585cb44bec64a9cc6520f726a8ef45e`.
- Ortak motor 35/35 ve yerel dosya denetimi 4/4 tekrar geçti.
- iOS arayüz testi 1/1 geçti; çalışma zamanı testleri iOS 2/2, Android 1/1 geçti. Toplam 43 hedefli test başarılı.
- 24.09.2026 fiziksel cihaz teslimi: `iPhone Kerem` üzerine `com.riskdetected.app.osgbpilot`, **2.0.3 (196)** kuruldu ve normal başlatma ile açıldı. Cihaz envanterinden build 196 geri okundu. Paket içindeki üç ortak sihirbaz dosyasının kaynaklarla SHA-256 eşleşmesi ve kod imzası doğrulandı. İlk kablosuz aktarım bağlantı kesintisiyle başarısız oldu; ikinci yükleme başarılı. Bu kayıt kurulum/açılış kanıtıdır; gerçek hesapla arşivleme ve elle sihirbaz kabulü hâlâ açık.
