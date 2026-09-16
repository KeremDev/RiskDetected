# İSGADA — 17 maddelik kullanım ve entegrasyon incelemesi

Tarih: 16 Eylül 2026. Başlangıç commit'i: `989f859e`. Kapsam: iOS pilot ekranları, mevcut servis sözleşmeleri ve depodaki migration/teslim kayıtları. Kullanıcının 16 Eylül kararları, önceki master plandaki çelişen ürün kararlarının önündedir. Bu rapor 15 Eylül boşluk raporunun güncel tamamlayıcısıdır; eski rapordaki “dosya depolama yok” tespiti artık güncel değildir.

## Son durum ve sınırlar

Claude ile eklenen eğitim akordiyonu, firma içinden doğrudan kayıt açılışı, dosya depolama bağlantıları, personel aramalı atama, ekipman ekleme girişleri ve tek işyeri otomatik seçimi mevcut. Bunları yeniden yazmak yerine ortak bileşenler ve kalan işleyiş boşlukları ele alındı.

İlk incelemenin ardından Supabase CLI üzerinden canlı şema ve pilot izinleri salt okunur doğrulandı. Üç dar ek paket izole PostgreSQL kontrollerinden sonra pilot servis ailesine uygulandı: firma sorumlusu iletişimi, ziyaret/toplantı dosyaları ve Onaylı Defter görsel arşivi. Genel migration klasörü push edilmedi; mevcut kullanıcı/firma verileri, hesap izinleri ve eski firma v1/v2 servisleri değiştirilmedi. Yeni defter modülü yalnız pilot/oturum/firma kontrolünden geçen süreç servisinde erişilebilir. Fiziksel cihazda gerçek kayıt kabulü ayrıca izlenir.

Önemli kapsam riski: `ISGADA_FILE_STORAGE_PILOT_2026-09-15.md` önceki dosya bayraklarının global açıldığını söylüyor. Derleme makrosu bir sunucu yetki sınırı değildir. Yeni servisler mevcut hesabın sahipliği + geçerli oturum + pilot hesap/firma izinlerini sunucuda doğrulamalı. Yeni migration yayımından önce mevcut file-library yolları bu bakımdan tekrar incelenmeli. Bu turda bayraklar değiştirilmedi.

## Madde bazında karşılaştırma

| # | İstek | İncelemede bulunan | Bu tur / kalan iş |
|---|---|---|---|
| 1 | Her sayfada menü, marka, çan, profil | Ana shell var; `NovaStandaloneHeader` yalnız marka gösteriyordu. Bazı header'lar menü yerine geri kullanıyordu. | Ortak shell header bağlamı tam ekran sayfalara taşındı; menü sabitlendi. Üst menü/çan/profil eylemi aynı oturumun açık kapaklarını kapatıp shell'e yönleniyor. Bütün bağımsız ekranların cihaz gezinme kabulü gerekiyor. |
| 2 | Başlık ve beyaz geri düğmesi | `screenTitle` ExtraBold 22; ortak geri ikonunun zemini kaldırılmıştı. | Pilot `NovaFont.spec` üzerinden SemiBold 20/27 yapıldı; NovaText ve native font aynı kaynaktan alıyor. 44 pt beyaz yuvarlatılmış geri düğmesi ortak bileşene eklendi. Elle sabit boyut kullanan bazı eski başlıkların taraması devam etmeli. |
| 3 | Ortak merkez popup | NovaPopup vardı; birçok tüketici native `.sheet` ile açıyordu. İç içe sunumda popup ortamı da taşınıyordu. | `novaPopup` item/bool sunum API'si eklendi; kontrol/atama/risk/plan/kurul/KKD iç formları taşındı. Yeni sunum kendi popup bağlamını sıfırlar. Ölçülen içerik yüksekliği ve ekran sınırı korunur; blur/dim/X tek kaynaktadır. Kamera, dosya seçici ve sistem paylaşımı native kalır; eğitim gibi tam sayfa akışları popup'a sıkıştırılmaz. |
| 4 | Firma sorumlusu telefon/e-posta | `NovaPilotCompanyIntent` ve create_v2 yalnız responsibleName taşıyor. | UYGULANDI: sorumlu eklenirse telefon/e-posta zorunlu; v3 atomik kayıt + normalize/hash/replay, v2 kalıcı eski istek uyumu, overview_v2 ve firma detayında iletişim. Pilot sunucuda yayımlandı; 10 DB ve 44 Swift servis kontrolü geçti. Firma ekle formundaki kaydetmeyen Sicil No alanı kaldırıldı; sahte kayıt izlenimi verilmez. |
| 5 | Evrak takibi yalnız birleşik süre listesi | `NovaDocumentTrackingScreen` ayrı obligation ekleme/düzenleme akışını sürdürüyor. Yeni modül dosyaları bu listeye birleşik olarak yansımıyor. | UYGULANDI: pilot `isg_pilot_followup_v1` modül kaynaklarını ve eski evrakları tek salt okunur listeye toplar. Firma/arama/durum filtreleri, kaynak açılışı, firma ve istatistik özetleri bağlı. Yeni obligation oluşturma ana girişten kaldırıldı; eski kayıtlar korundu. |
| 6 | Kısa ampullü kullanım açıklaması | NovaHelpHint var; yalnız bazı formlarda kullanılıyor. | Kontrol, risk, analiz sonucu, acil plan, tatbikat, atama, dosya, evrak, ekipman ve sözleşme ana girişlerine kısa açıklama eklendi. Ortak süreç türü açıklamaları `NovaProcessKind.help` içinde toplandı. Diğer detay/boş durum ekranlarının kabulü sürüyor. |
| 7 | Dosyalarım: modül+bağımsız dosya, etiket/not | Modül inline dosyaları aynı file-library altyapısını kullanıyor; not ve sabit kategori var. Ana ekran önce firma istiyor, ekle ancak sonra çıkıyor. | UYGULANDI: mevcut modül ve bağımsız firma dosyaları aynı kütüphanede; 12 adede kadar serbest etiket/not ekleme-düzenleme, etiket/not araması ve dosyadan kaynak modüle dönüş var. Yeni v2 yazma pilot hesabı doğrular. Firmasız kişisel dosya ekleme/düzenleme/arşivleme de aktiftir; liste tüm dosyalarla açılır ve firma filtresiyle daraltılır. |
| 8 | Onaylı Defter görsel arşivi | Analiz sonucu `approved_notebook` metin bölümü var; bu görsel arşivi değil. CompanySection'da ayrı defter yok. | UYGULANDI: önceki görsel arşivi korunuyor; Dosyalarım detayından ilgili defter kaydına ters bağlantı da eklendi. Süre/puan/signature iddiası yok. |
| 9 | Başarılı işlemlerde ortak mesaj | Başarı overlay'i yalnız firma/personel/eski eğitim formunda çağrılıyordu; açık popup altında kalabiliyordu. | Oturum sahipli ortak success store eklendi; popup da aynı olayı gösterir, form kapanınca kaybolmaz. Journal'ın doğrulanmış kayıt/atama/ekipman/kontrol/plan/zimmet/toplu olmayan kaydet işlemleri ve v3 eğitim bağlandı. Bildirim okuma/export/draft açma bu mesajı üretmez. Analiz→uygunsuzluk yalnız yeni kayıt için üretir. Dosya gerçekten arşivlenince ve manuel uygunsuzluk başarılı oluşturulunca da ortak mesaj bağlı. Fotoğraf analizi bitişi ve ayrı eski akışların taraması sürüyor. |
| 10 | Sınıfa göre otomatik süre, manuel değiştirme | Risk değerlendirmesi sınıftan tarih türetiyor; eğitim profilleri mevcut. Evrensel süre motoru yok, modüller farklı mantık kullanıyor. | KISMİ: kayıt tarihindeki sınıf snapshot'ı, hesaplanan tarih/uzman değişikliği/dayanak ayrımı ve tek sunucu kural sürümü gerekli. Tatbikat tarihi acil plan yenileme tarihiyle aynı kabul edilmemeli. |
| 11 | Ziyaret: tarih+not zorunlu, kişi/süre/foto opsiyonel ve istatistik | `site_visit` tarih/not/sorumlu/yer destekliyor; süre/fotoğraf yok. | UYGULANDI: tarih ve not zorunlu, kişi/süre/fotoğraf opsiyonel. Ziyaret listesinde genel toplam; İstatistikler ekranında seçilen firma ve ay aralığı için ziyaret adedi, süre girilen kayıt adedi ve toplam dakika/saat var. Boş süre sıfır gibi gösterilmez. |
| 12 | Bulgu detayından firmaya uygunsuzluk | Liste aktarımı var fakat analizi firmaya atamayı şart koşuyor; detay CTA yok. Çok işyerinde ilki sessizce seçiliyor; seçilmemiş önem derecesi “Orta” görünüyordu. | Detay CTA + aynı popup'ta firma seçimi eklendi; analiz sahipliğini değiştirmeden seçilen firma/kapsam istekle taşınıyor. Çok işyerinde seçim gerekli; bilinmeyen önem açıkça seçilir. Yeni pilot kaynak API’si gerçek analiz/bulgu sahipliğini doğrular; başlık/açıklama/önlem/mevzuat/seçili yöntem girdileri taşınır, tam kaynak snapshot’ı korunur. Aynı firma+bulgu tekrarında ikinci kayıt açılmaz; eski mutation/operation çakışması giderildi. |
| 13 | Gerçekleşmiş tatbikat; tür, haber, BEKRA, 10 foto, PDF, süre/senaryo/not | `plan_drill` ardından `record_result`, önce acil plan seçimi var. İstenen alanlar yok. | UYGULANDI: yeni pilot gerçekleşmiş tatbikat kaydı; acil durum/yangın, haberli/habersiz, BEKRA, süre/senaryo/not, en fazla 10 fotoğraf ve PDF. Tek atomik save/edit/delete/replay. Yıllık takip ve kayıtlı maden NACE kodunda 6 ay; manuel tarih ayrı override olarak saklanır. Eski planlar salt okunur geçmişte. Firma/istatistik/evrak/bildirim/dosya bağlantıları var. |
| 14 | Toplantı gündem/karar maddeleri, dosya | Toplantı gerçekleşmiş kaydediliyor. Gündem newline alanı, kararlar zaten ayrı child kayıtlar. Dosya alanı board sözleşmesinde yok. | UYGULANDI: gündem ve ilk kayıt kararları numaralı ekle/sil satırları. Toplantı ve kararlar aynı transaction içinde yazılır; tekrar gönderim kararları çoğaltmaz. Sonrasında kararların sorumlu/termin/durum yönetimi korunur. Toplantı dosyası bağlı; evrak obligation seçimi kaldırıldı. |
| 15 | Gereksiz işyeri seçimini kaldır | Claude düzeltmeleri birçok akışta tek işyerini dolduruyor. Sıfır işyeri durumunda bir kısmı hata gösteriyor. | Tek işyeri davranışı korunuyor; bulgu aktarımı düzeltildi. EKSİK: firma varsayılan işyerinin gerçekten var olması ve yoksa sunucuda kontrollü oluşturma; sıfır/tek/çok için ortak bileşen/kabul testi. Rastgele işyeri kimliği veya ilk taşeron seçilmeyecek. |
| 16 | Personel eğitim açığı: ör.16−4=12 saat, eksik konular | Eğitim v3 scope/konu/saat var; personel detayında hâlâ “Eğitim · —” bulunuyor. | UYGULANDI: personel detayında aynı işyeri + görev/içerik grubu + ilk/tekrar profili içindeki güncel scope öğretim dakikaları birikir. 16 ders saati gereksiniminde 4 saat kayıt 12 saat açık verir; aralar sayılmaz. Eksik resmî konular/G4/ilk eğitim ortak bütçesi ayrı gösterilir. Süresi dolmuş ve dağılımı tutarsız kapsamlar dahil edilmez; belge üretimi açığı kapatmaz. Bir ders saati 45 dakika öğretim olarak açıkça etiketlenir. |
| 17 | Personel sertifikaları | Eğitimden üretilen sertifika başka bir kavram; kişisel MYK/ilk yardım belge takip modülü yok. | UYGULANDI: personel ve firma içinden bağımsız ilk yardım/MYK/diğer belge ekle-düzelt-sil, ad/veriliş/geçerlilik/not/opsiyonel dosya. İlk yardım 3 yıl otomatik; MYK/diğer tarih kullanıcıdan alınır. Firma/evrak/bildirim/istatistik/Dosyalarım ilişkileri bağlı. |

## Kullanımı ağırlaştıran ortak sorunlar

1. **İki kayıt otoritesi:** modüle kayıt ve ayrıca evrak obligation oluşturma bekleniyor. Modül kaynak olmalı; Evrak Takibi yalnız ortak okuma ekranı olmalı.
2. **Gereksiz geçişler:** firma→boş liste→ekle→işyeri→dosyalarım yerine firma→form ve inline dosya. Claude'nin startInAddMode yaklaşımı korunmalı.
3. **Bitirilemeyen işlemler:** kaydet açık olsa da backend'in başka alan istemesi; sadece UI gizlemek yerine aynı sözleşmenin doğrulanması gerekli.
4. **Aşırı bilgi:** uzun katılımcı/konu listesi ana formda tek tek açılmamalı. Seçim popup'ı özet+adet döndürmeli; eğitim sayfasının mevcut adımlı akışı korunmalı.
5. **Sessiz varsayımlar:** çok işyerinde ilkini seçmek, boş süreyi sıfır göstermek, eksik eğitimi tamamlanmış saymak veri hatası üretir.
6. **Kaynak bağlantısı eksikliği:** dosyadan modüle, bildirimden ilgili firma/kayda, sayaçtan filtrelenmiş listeye geçişler aynı route sözleşmesi kullanmalı.
7. **Eski düzenleyiciler:** genel NovaModuleEditor içinde halen eski KKD miktar/birim alanları var. Kullanıcının yalnız zimmet kapsamına aykırı bu yolun erişilebilirliği kaldırılmalı/daraltılmalı.
8. **Pilot ve genel ürün sınırı:** UI makrosu yetki değildir. Shared RPC/storage her istekte hesap/pilot kapsamı doğrulamalı.

## Uygulama sırası ve kabul ölçütleri

### A — Ortak görünüm / gezinme (bu tur başladı)
- Tek font ölçeği, başlık/geri, işlevsel header, merkez popup, kısa yardım ve tek başarı olay sistemi.
- Telefon/dynamic type/klavye/uzun içerik/iç içe popup/hesap değişimi kabulü. Kaydet sırasında X kapalı olmalı; başarılı dönüşten önce konfeti gösterilmemeli.

### B — Ortak dosya ve takip sözleşmesi
- Dosya kaydı modülde; tek asset birden fazla listede görünür ama kopyalanmaz.
- Takip satırı: kaynak türü+kimlik, firma/personel, başlık, düzenleme/geçerlilik tarihi, otomatik kural+override, güncel/yaklaşan/bitti/tarih belirtilmedi, hedef route.
- Eski obligation kayıtları geçişte saklanır; yenilerin ikinci kez elle oluşturulması istenmez.
- Defter görsel arşivi ve firmasız dosya/etiket işi bu temelden sonra.

### C — Kayıt akışları
- Firma sorumlusu iletişimi; ziyaret; kurul madde ve dosya; gerçekleşmiş tatbikat.
- Yazmalar atomik, kalıcı mutation kimlikli; edit expected_version kontrollü. Fotoğraf sınırı sunucuda da uygulanır. Başka hesaptan dosya/personel/firma ilişkilendirilemez.

### D — Personel takibi
- Eğitim birikimi + eksik konular; bağımsız personel sertifikaları.
- Aynı eğitimi tekrar gönderme/kişi silme/firma değişimi/döngü değişimi ve belge tarihi güncelleme testleri. Belge üretimi eğitim açığını kapatmaz.

### E — Pilot kabulü
- Ayrı pilot RPC veya aynı fonksiyon içinde açık pilot dalı; genel istemci sözleşmesi korunur.
- İzole DB replay → pilot yetki testleri → dar migration → yeni pilot build → cihazda kayıt/okuma/düzeltme/silme/dosya indirme.
- Mevcut rollout bayrakları değişmedi. Üç yeni paket pilot servislerine dar transaction olarak uygulandı; defter için yeni modül kaydı eklendi. Uygulama mağaza sürümüne dağıtılmadı.

## Sürelerin dayanağı

- Risk yenileme aralığının sınıfa göre 2/4/6 yıl olduğu [Sağlık Bakanlığı açıklamasında](https://isgdb.saglik.gov.tr/TR-117210/soru-14-risk-degerlendirmesinin-yenilenme-periyodu-nedir.html) yer alıyor. Olay/değişiklik tetikleyicileri süreyi beklemeyebilir.
- İlk yardım belgesi için 3 yıl [Sağlık Bakanlığı kaynağında](https://kocaelism.saglik.gov.tr/TR-203915/ilkyardim-sertifikasi-ne-kadar-sure-gecerlidir-guncelleme-icin-ne-yapmaliyim.html) belirtiliyor.
- [Bakanlık kamu İSG rehberi](https://www.csgb.gov.tr/Media/jt1a13o5/kamudaisgrehberi_30-01.pdf) tatbikat ile acil planın yenilenmesini ayrı ele alıyor. Güncel yönetmelik/işyeri kapsamı ve BEKRA ayrıca doğrulanmadan hepsine risk analizi periyodu kopyalanmamalı. Tatbikat için bu tur yeni süre kuralı yayımlanmadı.

## Doğrulama kaydı

- iOS pilot simülatör derlemesi: başarılı; ortak header ve merkez firma popup ekranı görsel kontrol edildi.
- `pilot_contacts_check.mjs`: gerçek P05 guard/create/read fonksiyonları ile 10 DB senaryosu geçti. Platform abonelik/limit yardımcıları test fixture'ıdır; tam canlı Auth E2E yerine geçmez.
- `pilot_native.test.mjs`: 44 firma servis kontrolü; eski v1/v2, yeni v3, oturum değişimi ve kesinti/retry kapsandı.
- `run_pilot.mjs --visit-details`: mevcut modül regresyonları + ziyaret/dosya/toplantı/defter senaryoları geçti. Dosya fixture'ı metadata kapsar; gerçek Storage upload/download kabulünün yerine geçmez.
- Pilot ledger paketleri: `20260916072930`, `20260916074000`, `20260916075100`. Aday ve mirror SQL içerikleri birebir.
- Gerçek firma/personel/ziyaret/defter kayıtları test amacıyla oluşturulmadı. Telefon kurulumu ve gerçek veriyle kullanıcı kabulü bu rapordaki kod/DB başarısıyla karıştırılmamalı.


## 16 Eylül devam teslimi

Ayrıntılar ve doğrulama: [devam teslim kaydı](ISGADA_REMAINING_FEATURES_DELIVERY_2026-09-16.md). Yukarıdaki 5/7/8/11/13/14/16/17 satırları bu teslimle güncellendi. Önceki "üç paket" bilgisi ilk teslimi anlatır; bu devamda dokuz dar paket daha pilot servis ailesine uygulandı. Ortak dosya okuma yanıtına geriye uyumlu etiket alanı eklendi; yeni yazma RPC'si pilot guard taşır. Genel rollout bayrakları değiştirilmedi.

## Açık kalan işler ve kabul sınırları

- Sıfır aktif işyeri kalan eski firmalar için kontrollü varsayılan işyeri oluşturma; normal tek işyerli firma akışları otomatik seçim yapar. Canlı pilot kontrolünde böyle firma sayısı 0; mevcut hesap için açık engel değil.
- Geçerlilik kurallarının bütün modüllerde tek sürümlü motor altında toplanması; eldeki modül kuralları ve snapshot'lar korunur.
- Kalan eski ekranlarda header/font/başarı olayı ve erişilebilirlik kabul taraması.
- Telefon kilidi nedeniyle yeni modüllerin dokunarak uçtan uca kayıt/ek/dosya paylaşma kabulü henüz tamamlanmadı. SQL ve derleme başarısı bunun yerine sayılmaz.

Tüm master plan veya 17 maddenin bütün kabul kriterleri tamamlandı iddiası yoktur. Ana kalan kayıt ve takip akışları pilotta etkinleştirildi.
