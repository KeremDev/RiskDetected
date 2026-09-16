# İSGADA — kalan ana özelliklerin pilot teslimi

16 Eylül 2026; başlangıç `989f859e`. Önceki Claude/kullanıcı değişiklikleri korundu. Commit alınmadı. Bu teslim yalnız özel iOS pilot derlemesine ve pilot yetkili servis ailesine yöneliktir; App Store yayını veya genel rollout değişikliği yapılmadı.

## Çalışan akışlar

- Gerçekleşmiş tatbikat: plan/acil plan seçimi gerekmeden kayıt. Acil durum/yangın, haberli/habersiz ve BEKRA ayrı alanlar. Süre, senaryo, not, 10 fotoğraf sınırı ve opsiyonel PDF. Atomik ekle/düzenle/sil, sahiplik/işyeri/dosya doğrulaması, geçmiş ve idempotent tekrar gönderim. Eski tatbikat ekranı salt okunur geçmiş olarak korunur.
- Personel sertifikası: personel detayından veya firma süreç kartından ilk yardım/MYK/diğer belge. Ad, düzenleme/geçerlilik, not ve opsiyonel dosya. İlk yardım üç takvim yılı önerir; MYK/diğer için tarih açıkça girilir. Dosya eklemek belge kaydının ön şartı değildir.
- Personel eğitim özeti: sabit ve yanıltıcı “Eğitim — / Temsilci Hayır / Destek Hayır” etiketleri kaldırıldı. Eğitim kapsamlarından güncel net öğretim ve açık hesaplanır; örneğin 720 dk gereksinimde 180 dk kayıt, 540 dk açık (=16−4=12 ders saati). Bir ders saati 45 dk öğretim olarak belirtilir; aralar dahil edilmez. İşyerleri, ilk/tekrar, görev/içerik grupları ve farklı profiller birleştirilmez. Eksik resmî konular, G4 ve ilk eğitim ortak bütçesi gösterilir. Süresi dolmuş veya ders dağılımı tutarsız kapsamlar sayılmaz. Bu hesap sertifika, yoklama veya sınav sonucu üretmez.
- Birleşik Evrak Takibi: modüllerin süreli kayıtlarından türetilen firma/arama/durum listesi. Yeni obligation ekleme ana girişten kaldırıldı; önceki evrak kayıtları okunabilir kalır. Kaynak modüle geçiş, firma kartı, istatistik ve bildirimler bağlıdır.
- Dosyalarım: modül dosyaları, modülden bağımsız firma dosyaları ve firmasız kişisel dosyalar aynı kütüphanede. Liste tüm dosyalarla açılır; firma filtresi popup içinden seçilir. Firma içinden açılan yükleme o firmada kalır. Kişisel dosyayı ekleme/düzenleme/arşivleme hesap sahipliği ve pilot/abonelik denetiminden geçer. En fazla 12 serbest etiket, not, düzenleme ve arama. Dosya detayından bağlı defter, ziyaret, tatbikat, personel belgesi, kurul, sözleşme, risk, acil plan ve ekipman kaydına geçiş. Dosya yazma v2 yolu ayrıca pilot hesabını doğrular; eski v1 istemci sözleşmesi korunur.
- Bulgu aktarımı: pilot aktarım API’si gerçek `findings → analyses → owner` bağlantısını doğrular. İstemcinin başlık/band beyanı yerine kaynak başlığı ve seçilen yöntemin bandı kullanılır; açıkça seçilen önem derecesi korunur. Açıklama, önlem, mevzuat ve uygun skor girdileri uygunsuzluğa aktarılır; tam kaynak metin ayrı değişmez snapshot’ta saklanır. Kaynak düzenlenince önceki uygunsuzluk değişmez. Firma+bulgu kilidi tekrar tıklamalarını, mutation receipt ağ tekrarını korur. Bulgu kimliğini farklı operation ile aynı mutation olarak tekrar kullanma hatası kaldırıldı; firma/istatistik/bildirim yenileme olayı gönderilir.
- Paylaşılan dosya içeriği: Storage aynı hesabın aynı içeriğini tekrar kullanır. Yeni süreçler, ziyaret/kurul/defter, tatbikat ve personel belgelerinde blob’un ilk firma etiketi yerine temiz dosya + sahiplik + **hedef firmada aktif kütüphane kaydı** doğrulanır. Kişisel dosya tek başına firma modülüne bağlanamaz.
- Kurul: toplantı oluştururken gündem ve kararları numaralı satırlar halinde ekleme. Kararlar toplantıyla aynı transaction içinde açılır; tekrar gönderim çoğaltmaz. Sonradan karar bazlı sorumlu/termin/durum yönetimi korunur.
- İstatistikler: ziyaret adedi, süre belirtilen kayıt sayısı ve toplam süre, seçilen firma ve ay aralığına göre okunur. Bilinmeyen süre sıfır sayılmaz.
- Bildirim: yeni sertifika/tatbikat/eğitim kaynakları; çandan açılışta firma/kayıt bağlamı taşınır. Eğitim düzenleyicisi tam sayfa akışında kalır. Eski KKD genel düzenleyicisindeki miktar/birim alanları da kaldırıldı.

## Süreler

Tatbikatın yıllık aralığı, acil durum planının tehlike sınıfına göre yenilenmesiyle karıştırılmaz. Kaydedilmiş maden NACE kodunda altı ay uygulanır. NACE bilgisi yoksa genel 12 ay önerisi ve manuel tarih seçeneği görünür. BEKRA işareti tek başına genel süreyi uzatmaz. Tarih değişikliği `due_override`, hesaplanan tarih ayrı alanda saklanır.

İlk yardım için [Sağlık Bakanlığı açıklaması](https://kocaelism.saglik.gov.tr/TR-203915/ilkyardim-sertifikasi-ne-kadar-sure-gecerlidir-guncelleme-icin-ne-yapmaliyim.html); tatbikat için [Bakanlık İSG rehberi](https://www.csgb.gov.tr/media/71237/kamudaisgrehberi.pdf) esas alındı. MYK belgelerinin tamamına tek bir süre uygulanmaz.

## Migration ve pilot sınırı

Dar paket, önceki ledger başı `20260916075100` ve değiştirilen fonksiyonların `pg_get_functiondef` MD5 değerleri doğrulanarak transaction içinde uygulandı. Toplu `db push` çalıştırılmadı. Her adayın exact SQL'i ledger statements alanına ve pilot-release mirror dosyasına yazıldı.

| Ledger | Paket |
|---|---|
| 20260916084130 | Gerçekleşmiş tatbikat ve personel belgesi |
| 20260916084131 | Personel eğitim birikimi |
| 20260916084132 | Birleşik takip, bildirimler, firma/istatistik v2 |
| 20260916084133 | Dosya etiketleri ve kaynak bağlantıları |
| 20260916084134 | Toplantıyla atomik kararlar |
| 20260916084509 | Pilot eğitim okumasının eski P07 anahtarından ayrılması |
| 20260916090111 | Kişisel dosyalar ve tüm dosya arşivi |
| 20260916090921 | Analiz bulgusundan doğrulanmış kaynak aktarımı |
| 20260916090922 | Aynı içeriğin farklı dosyalamalarda güvenli kullanımı |

Son düzeltme gerçek pilot salt okunur kontrolde bulundu: eski P07 training rollout kapalı, mevcut pilot eğitim kataloğu ayrı çalışıyordu. Yeni öğrenim okuma fonksiyonu P07 sınav/yoklama yolunu açmadan kendi oturum/pilot/firma/personel sınırlarını koruyarak düzeltildi. Katalog bildirimi kendi eğitim kontrolüne bağlandı. P07 tamamlanma şartları değiştirilmedi.

## Doğrulama

- `node scripts/modules/run_pilot.mjs --completed-records`: mevcut modül regresyonları ve yeni DB senaryoları geçti. Artık yıl, manuel tarih, gelecekte gerçekleşme reddi, 4/16 saat hesabı, eksik konu, G4 yöntemi, parent/grup ayrımı, tam dakika, sertifika personel kapsamı, silmenin takipten düşmesi, etiket düzenleme/arama/replay, kurul atomikliği ve P07 kapalıyken pilot okuma kapsandı.
- Kişisel dosyada hesap/firma ayrımı, ücretli/pilot sınırı, not/etiket düzenleme, arşivleme; bulguda yabancı/silinmiş kaynak reddi, gerçek başlık/puan, tam snapshot, farklı tıklama ve ağ tekrarı; yeniden kullanılan dosyada firma kaydı zorunluluğu ve ek açılışı test edildi.
- 56 istemci/yerel sözleşme kontrolü geçti (`pilot_native`, `nova_analysis_flow`, `nova_notices`, `nova_tokens`, `nova_file_library`). Eski dosya testindeki doğrudan `return detail` beklentisi, artık başarı olayından sonra aynı sunucu yanıtını döndüren akışa uyarlandı.
- iOS Simulator ve fiziksel iOS pilot derlemeleri başarılı. Fiziksel build: **2.0.3 (116)**, `NOVA_PILOT_BUILD` ve pilot sahibi seçicisiyle. Yeni build iPhone Kerem'e kuruldu; mevcut allowlist korundu.
- Gerçek pilot hesabın mevcut oturum bağlamıyla, authenticated rolünde read API kontrolü geçti: 2 takip satırı, 14 firma süreç satırı, yeni tatbikat/belge listeleri ve personel özeti okunuyor. Yeni kayıt bulunmayan alanlarda sıfır döndü; iş verisi test amacıyla oluşturulmadı.
- Yeni bulgu aktarımı gerçek pilot oturumunda gerçek kaynak üzerinden transaction içinde çalıştırıldı ve **ROLLBACK** ile hiçbir test uygunsuzluğu kalıcı bırakılmadı. Dokuz migration’ın canlı ledger SHA-256 değerleri yerel exact SQL ile eşleşti. Pilot kapsamında aktif işyeri olmayan firma sayısı **0**.
- İzole dosya testleri metadata ve transaction davranışını doğrular; gerçek Storage upload/download uçtan uca kabulü yerine geçmez.
- Fiziksel açılış ekran kilidine takıldı. Kurulum ile kullanıcının telefonda kayıt/ek/paylaşma kabulü ayrı tutuldu.

Kanıtlar: `output/isg/remaining-2026-09-16/` (git dışında). Manifest her migration'ın SHA-256 değerini içerir.

## Açık sınırlar

Bütün modüllerde tek sürümlü süre motoru ve tüm eski ekranların fiziksel erişilebilirlik/görünüm kabulü ayrı kalan işlerdir. Sıfır aktif işyerli eski firma kurtarma akışı genel durum için hâlâ ayrı çalışmadır; mevcut pilotta böyle firma yoktur. Eğitim birikimi ayrı geçerlilik dönemi kimliği yerine güncel scope aralığı ve profil/görev gruplaması kullanır; tarihleri çakışan ayrı tekrar döngülerinin daha ayrıntılı modeli bu teslimde yoktur. Tüm eski modüllerin aynı blob’u yeniden kullanma kabulü yerine yeni süreç bağlantıları doğrulanmıştır. Bu teslim tüm master planın tamamlandığı anlamına gelmez. Özellik matrisi [17 maddelik incelemede](ISGADA_USABILITY_AUDIT_2026-09-16.md) güncellendi.
