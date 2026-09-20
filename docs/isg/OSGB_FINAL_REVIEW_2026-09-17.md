# OSGB entegrasyonu — son genel inceleme

> Bu raporun staging, sağlayıcı ve Android UI açıkları daha sonra kapatıldı. Güncel kabul sonucu için [OSGB_STAGING_ACCEPTANCE_2026-09-17.md](OSGB_STAGING_ACCEPTANCE_2026-09-17.md) esas alınmalıdır. Aşağıdaki eski “staging/provider/Android UI açık” ifadeleri tarihsel inceleme bulgusudur.

17 Eylül 2026 · Dal: `codex/isg-transition-foundation` · İnceleme tabanı: `c6b53166`

## Sonuç

Raporda öncelikli kalan kod riskleri kapatıldı: D1–D7 liste sayfalaması, belirsiz ağ sonucundan sonra çift kayıt oluşturabilen istemci tekrarları, D2–D6 ayrıntılarındaki yaşam döngüsü işlemleri ve D1/D2 tenant-native ileri modülleri. D1 artık görev/unvan, dış firma, sözleşme ve tarihçeli personel görevlendirmelerini; D2 sürümlü müfredat, konu, sınav, yıllık plan ve doğrulanabilir sertifikaları workspace kapsamında yönetiyor. Kontrol listesi akışındaki açık uzman seçimi de korunuyor.

Değişiklikler yalnız yerel çalışma ağacında ve henüz dağıtılmamış migration adaylarındadır. Production veya staging veritabanına migration uygulanmadı; rollout açılmadı; gerçek kullanıcı verisi, object storage, AI, export, e-posta, push veya mağaza sağlayıcısı kullanılmadı. Kişisel kullanıcı kökü ve mevcut personal servisler değiştirilmedi. Admin arayüzü, sağlanacak UI kit sonrasına bırakıldı.

Bu paket yerel entegrasyon ve deneme adayıdır; canlı yayın kabulü değildir. Gerçek ortam/sağlayıcı ve ürün kararlarına bağlı işler aşağıda ayrı gösterilir.

## Bu turda kapatılan bulgular

| No | Öncelik | Önceki risk | Uygulanan düzeltme |
|---|---|---|---|
| N01 | P1 | Aynı firmada çakışan birincil uzman dönemleri oluşabiliyordu. | Firma düzeyi kilit, bütün dönemler için overlap kontrolü, gelecek atama iptali ve sonlu aktif atamayı erken bitirme eklendi. |
| N02 | P1 | Mutasyon sonrasında geç kalan dashboard yanıtı yeni seçimi bozabiliyordu. | Seçim, firma ve istek nesli her await sonrasında doğrulanıyor; eski yanıt yayınlanmıyor. |
| N03 | P2 | İşyeri, departman ve personel ilk 100 kayıtta kalıyordu. | UUID keyset cursor, tekrar/ilerlemeyen cursor koruması ve 101 kayıt testi eklendi. |
| N04 | P1 | Eğitim, risk, uygunsuzluk, checklist, acil durum/KKD, ekipman, operasyon ve dosya listeleri ilk sayfada kalıyordu. | D2–D7 SQL read sözleşmelerine `p_after`/`next` eklendi. iOS ve Android 100'lük sayfaları 10.000 kayıt güvenlik sınırına kadar topluyor; tekrar eden ID/cursor reddediliyor. |
| N05 | P1 | Sunucu kaydı tamamlayıp yanıt kaybolursa kullanıcı yeniden Kaydet'e basınca yeni UUID ile ikinci kayıt oluşabiliyordu. | Form ömrü boyunca payload imzasına bağlı sabit `IsgWorkspaceMutationAttempt` kullanılıyor. Payload değişince yeni anahtar, aynı payload tekrarında aynı anahtar gönderiliyor. Dosya oluşturma için mantıksal kayıt receipt sorgusu upload öncesine alındı. |
| N06 | P2 | Ayrıntı ekranları yalnız liste/detay gösteriyor, sunucudaki yaşam döngüsü komutlarını açmıyordu. | Eğitim tamamla/iptal, risk sonuçlandır, uygunsuzluk aksiyon/doğrulama/geçiş, checklist yanıt/gönder/iptal, tatbikat gerçekleştir/iptal, atama bitir, KKD iade, ekipman kontrol/arşiv, KATİP arşiv, yıllık plan maddesi/kapama, kurul toplantısı/karar/iptal, çalışma izni arşiv ve saha gözlemi işlemleri bağlandı. |
| N07 | P1 | Checklist oluştururken serbest şablon kodu isteniyor, maddeler gösterilmiyor ve yanıt girmeden gönderme aksiyonu sunuluyordu. | Sunucu yayımlanmış ve en az bir maddesi olan şablonları döndürüyor. Form gerçek şablonu seçiyor; ayrıntı tüm maddeleri ve mevcut cevapları gösteriyor. Uygunsuz cevap varsayılan olarak yalnız bulgu önerisidir; uzman ayrıca seçerse önem/termin ile aynı transaction'da tek uygunsuzluk yaratılıyor. Eksik liste gönderilemiyor. |
| N08 | P1 | KKD iade toplamı eşzamanlı isteklerde teslim miktarını aşabiliyor, eski ekran aynı sürümü tekrar kullanabiliyordu. | Kayıt satırı kilidi, beklenen sürüm ve kilit altında toplam iade kontrolü eklendi. Tam iade edilen kayıtta iade aksiyonu gizleniyor. |
| N09 | P2 | Eğitim kaydı katılımcısız oluşturulabiliyor ve tamamlanamıyordu. | Workspace eğitim oluşturma formunda şirket personeli zorunlu hale getirildi. |
| N10 | P2 | Atama/ekipman ayrıntısında artık geçersiz aksiyonlar gösterilebiliyordu. | Süresi dolmuş atamada bitir, arşivli ekipmanda kontrol/arşiv aksiyonları gizlendi. |
| N11 | P1 | Workspace checklist'te her olumsuz cevap otomatik uygunsuzluk açıyor ve mevcut ürün sözleşmesindeki uzman seçimi sınırını aşıyordu. | “Uygunsuzluk kaydı aç” seçeneği varsayılan kapalı eklendi. Sunucu bu açık bayrak olmadan kayıt üretmiyor; tekrar cevapta aynı kaynak kaydı korunuyor. |
| N12 | P2 | Gelecek tarihli checklist/atama ve farklı yıllı çalışma planında formun varsayılan tarihi sunucu kuralının dışında kalabiliyordu. | Checklist termini başlangıçtan, atama bitişi başlangıcın ertesi gününden önce seçilemiyor; faaliyet tarihi plan yılıyla sınırlandı. |
| N13 | P1 | Uygunsuzluk doğrulaması ayrıntıda görünmediği için aynı döngüde işlem yeniden sunuluyor ve yeni mutasyon anahtarında benzersizlik hatası oluşabiliyordu. | Doğrulama sonucu workspace detayına eklendi; kabulden sonra yalnız kapatma, redden sonra yalnız işleme dönüş gösteriliyor. Aynı sonuç farklı anahtarla yeniden gelirse sunucu mevcut kaydı güvenle kullanıyor. |
| N14 | P1 | D1'de görev/unvan, dış firma ve personel görev tarihçesi workspace kapsamında yoktu. | Composite tenant FK'leri, etkili tarih ve overlap kilidi olan görev, dış firma, sözleşme ve atama modeli; iOS yönetim ekranları ve Android transport sözleşmesi eklendi. |
| N15 | P1 | D2'de müfredat, sınav, yıllık eğitim planı ve sertifika personal servise düşmeden yönetilemiyordu. | Sürümlü müfredat/konu, yayımlama/retire, katılımcı sınavı, tam katılım setiyle tamamlama, yıllık plan/faaliyet ve sertifika doğrulama/iptal akışları eklendi. Açık faaliyetli plan kapatılamıyor. |
| N16 | P1 | Gelişmiş personel metrikleri çoklu one-to-many JOIN ile büyük firmalarda satırları üstel çoğaltabilirdi. | Görünür firmalar materialize edilip her alt alan bağımsız sayılıyor; aynı kayıt yalnız kendi metriğine giriyor. |
| N17 | P1 | Sertifika dosya ilişkisi yalnız workspace FK'siyle sınırlandırılırsa aynı workspace içindeki başka firma dosyasına bağlanabilirdi. | Dosya kaydına `(workspace, company, id)` benzersizliği ve sertifikaya aynı composite FK eklendi; RPC kontrolü de korunuyor. |

Atama ve Store yarış düzeltmeleri önceki incelemenin N01–N07 bulgularını da kapsar. SQL adaylarının tamamı `NOT DEPLOYED` ve dark-default durumundadır.

## D1/D2 teslim kapsamı

- **D1 personel:** Görev/unvan kataloğu, dış firma, işyeri bazlı sözleşme, personelin departman/görev/işveren ataması, etkili başlangıç-bitiş tarihleri, geçmiş ve arşiv akışları tenant-native tablolar ve RPC'lerle çalışır. Aynı personelin çakışan tarih aralığı advisory lock altında reddedilir; farklı şirket kimlikleri composite FK ve komut doğrulamasından geçemez.
- **D2 eğitim:** Müfredat taslağı, konu ekleme/düzenleme/silme, yayımlama, yeni sürüm ve kullanımdan kaldırma; eğitime yayımlanmış müfredat bağlama; katılımcı sınavı; tam katılım setiyle bitirme; yıllık plan/faaliyet/gerçekleşme ve sertifika doğrulama/iptal akışları bulunur. Değerlendirmeli eğitim geçer sınav olmadan tamamlanamaz, açık faaliyetli yıllık plan kapatılamaz ve sertifika dosyası başka firmanın kaydına bağlanamaz.
- **iOS:** Personel ekranına görev, dış firma, sözleşme ve atama geçmişi; eğitim ekranına dört sekmeli müfredat, yıllık plan, sınav ve sertifika yönetimi eklendi. Formlar ortak kompakt Nova bileşenlerini ve standart başarı mesajını kullanır.
- **Android:** Aynı gelişmiş D1/D2 read/mutate sözleşmeleri gateway'de cursor, scope, receipt ve payload sınırlarıyla hazırdır. Android ürün UI'si bu teslimin dışında kalan ayrı kabul kalemidir.
- **Kişisel kullanım:** Legacy personal tablo/RPC'leri D1/D2 workspace yoluna bağlanmadı veya değiştirilmedi. Rollout kapalıyken OSGB RPC'leri fail-closed davranır; bireysel kullanıcı mevcut personal kökte kalır.

## Doğrulama

| Kontrol | Sonuç | Sınır |
|---|---|---|
| OSGB Node paketi | **106/106 geçti** | Kaynak sözleşmeleri ve çalıştırılabilir Swift kontrolleri; cihaz E2E değildir. |
| Foundation paketi | **761/761 geçti** | Kişisel/ortak altyapı regresyonları; canlı kabul değildir. |
| Nova tasarım paketi | **194/194 geçti** | Tasarım/yerelleştirme sözleşmeleri; fiziksel cihaz görsel kabulü değildir. |
| 25 aday migration bütünleşik prova | **Geçti** | Disposable PostgreSQL 17; D1/D2 gelişmiş akışları dahil, gerçek production upgrade değildir. |
| Dolu eski veri regresyonu | **Geçti, 10 grup** | İmzalı KKD, legacy personel/yazım, dosya mahremiyeti, arşiv ve silme köprüsü dahil sentetik veri. |
| Firma/uzman atama provası | **Geçti** | İzolasyon, overlap, tarihçe, plan iptali ve erken bitirme. |
| Asset taşıma provası | **Geçti** | Token/scope/finalize/silme; gerçek storage nesnesi taşımadı. |
| iOS Debug Simulator build | **BUILD SUCCEEDED** | Signing kapalı; fiziksel iPhone kurulumu değil. |
| Android core:data + core:designsystem | **BUILD SUCCESSFUL** | Gateway birim testleri; Android OSGB ekran kabulü değil. |
| Fonksiyon/test hash haritası | **16 kaynak, geçti** | Kaynak değişince kanıtı fail-closed yapar. |
| Manifest / diff | **Geçti** | 25 aday hash'i yenilendi; whitespace hatası yok. |

Kalıcı komut, sonuç ve kaynak hash kaydı: [verification.json](review-final-2026-09-17/verification.json).

## Plan karşılaştırması

Ana plan ve R001–R100 matrisi kaynak belgelerdeki tenant, rol, operasyon, dosya, analiz, muhasebe, mağaza, admin, devir, uyumluluk ve yayın güvenliği başlıklarını içeriyor. Bu turda tamamlanan üç öncelikli açık aşağıdaki tabloda artık kod eksiği değildir.

| Plan alanı | Güncel durum |
|---|---|
| D1–D7 sayfalama | Tamamlandı ve 101 kayıt/tekrar-cursor testleriyle doğrulandı. |
| Mutasyon tekrar güvenliği | OSGB ekranlarında aynı payload aynı mutasyon anahtarını koruyor; dosya mantıksal kaydı receipt ile sorgulanıyor. Tamamlandı. |
| D2–D6 yaşam döngüsü | Sunucuda var olan ileri komutlar workspace ayrıntı ekranına bağlandı; checklist'in eksik cevap akışı tamamlandı. |
| D1 ileri personel | Tamamlandı: görev/unvan, dış firma, işyeri sözleşmesi, etkili tarihli görevlendirme ve geçmiş; tenant-native SQL, iOS UI ve iOS/Android transport aynı workspace sözleşmesinde. |
| D2 ileri eğitim | Tamamlandı: sürümlü müfredat/konu, katılımcı sınavı, kontrollü tamamlama, yıllık plan/faaliyet, sertifika/dosya bağlantısı ve gelişmiş ölçümler tenant-native yolda. |
| D7 gerçek storage | Mantıksal kayıt ve taşıma sözleşmesi hazır; gerçek bucket/Edge ortam kabulü gerekli. |
| D8 gerçek AI/export | Kuyruk, finansal rezervasyon, sonuç/filing ve export işi hazır; gerçek AI sağlayıcısı ve renderer adapter kabulü gerekli. |
| D9 bildirim | Dashboard/search/change-feed ve notification lease hazır; gerçek push/e-posta/realtime/deep-link teslimi gerekli. |
| E Android ürün | Data gateway hazır ve testli; Android OSGB UI kökü, takvim/ayar/bütçe ve cihaz E2E açık. |
| H–I mağaza | Provider-neutral muhasebe/state machine hazır; ürün kararları ve Apple/Google/RevenueCat sandbox adapter kabulü açık. |
| J devir/hafıza | Preview/execute ve kaynaklı deterministik kayıt hazır; sihirbaz, scheduler, bütün açık iş sorumluluk devri ve kapsamlı projector açık. |
| F admin | UI kit beklediği için bilinçli olarak ertelendi; backend komutları dark-default adaydır. |
| K–L yayın | Production benzeri auth/RLS upgrade, yük/EXPLAIN, DB+object restore, hesap silme/retention, fiziksel cihaz ve kademeli yayın kabulü yapılmadı. |

D1/D2 ileri akışları personal servisleri OSGB'de yeniden kullanmadan tenant-native olarak kapatıldı. Android için veri sözleşmesi hazırdır; Android OSGB ürün ekranı hâlâ ayrı kabul kalemidir. Gerçek sağlayıcı ve yayın satırları credential, ürün kararı veya production-benzeri ortam gerektirir. Bunlar yerel kodun yeşil olmasını canlı kabulüne dönüştürmez.

## Kullanım türleri

- **Bireysel kullanıcı:** Personal root ve legacy endpoint'ler korunuyor. Dolu eski veri provası geçti; bu tur hiçbir canlı kullanıcı verisini değiştirmedi.
- **OSGB sahibi/yöneticisi:** Workspace, firma, ekip/davet, uzman atama ve D1–D9 operasyonları iOS pilot kökünde workspace servisleriyle çalışıyor. D1 görev/dış firma/atama ve D2 müfredat/plan/sınav/sertifika akışları aynı yetki, sürüm ve idempotency sınırını kullanıyor.
- **OSGB uzmanı:** Yalnız atandığı firmalarda okuyup işlem yapabiliyor; scope her transport sonrasında tekrar doğrulanıyor. Personal servise fallback yok.
- **Firma personeli:** Çalışan kaydı OSGB üyeliğinden ayrı tutuluyor. Eğitim, acil durum, atama ve KKD seçimleri şirket personel envanterinden yapılıyor.

## Kabul kararı

Raporun önceliklendirdiği sayfalama, çift kayıt, yaşam döngüsü ve D1/D2 tenant-native ileri özellikleri yerel adayda kapatıldı. Paket, izole ortamda iOS OSGB akış denemelerine hazırdır. Production/staging, gerçek sağlayıcılar, Android UI ve admin UI tamamlanmadan “bütün ürün canlıya hazır” kabulü verilmedi.
