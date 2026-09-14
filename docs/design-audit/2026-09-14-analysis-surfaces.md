# NOVA ISG · Analiz yüzeyleri tasarım denetimi

## Kapsam

Denetim, RiskDetected çizgisini koruyup daha sakin, modern ve kurumsal bir arayüz hedefiyle yapıldı. İncelenen yüzeyler:

- Analizlerim listesi ve Analiz Sonucu ekranı
- Risk analizindeki bulgu detay popup'ı
- Uzman Görüşü
- Eğitim Önerileri
- Onaylı Defter
- Uygunsuzluklar listesi ve kayıt detayı

Ekranlar iPhone 17 Pro simülatöründe, açık tema ve sentetik inceleme verisiyle açıldı. Veriler canlı hesaba bağlı değil. Görsel kanıtlar:

- [Analizlerim listesi](../../artifacts/design-audit/2026-09-14/analysis-v3/96221598-771D-46D1-A5F6-453FDBEF90A6.png)
- [Analiz Sonucu · Risk Analizi](../../artifacts/design-audit/2026-09-14/analysis-v3/6E0F7E18-A2D1-4C7E-9B68-98BE71BE6804.png)
- [Bulgu detay popup'ı](../../artifacts/design-audit/2026-09-14/analysis-v3/B8B05884-6AA0-4C78-9B3B-27699E23BEAE.png)
- [Uzman Görüşü](../../artifacts/design-audit/2026-09-14/analysis-v3/8DE1A766-AC59-4246-B0BD-238AD028C851.png)
- [Eğitim Önerileri](../../artifacts/design-audit/2026-09-14/analysis-v3/37C52132-E040-4BAA-9CF1-F592F5B2B762.png)
- [Onaylı Defter](../../artifacts/design-audit/2026-09-14/analysis-v3/D80D19CC-D3F4-4CE9-982E-1A9CDF05F5E2.png)
- [Uygunsuzluklar listesi](../../artifacts/design-audit/2026-09-14/finding/BD540BB6-5AB1-49B7-B45F-20DFC759BA06.png)
- [Uygunsuzluk kayıt detayı](../../artifacts/design-audit/2026-09-14/finding/94A201F0-B775-43B4-89D5-4BEA8A954956.png)

## Güçlü taraflar

- Açık gri zemin, beyaz kart ve güçlü başlık hiyerarşisi RiskDetected ailesiyle tutarlı.
- Liste satırlarında firma, işyeri, tarih ve durum ikonlarla kısa tutulmuş.
- Analiz sekmeleri kayıt sayılarını gösteriyor; kullanıcı hangi bölümde ne kadar içerik olduğunu hemen görüyor.
- Bulgu detayında açıklama, önlem, mevzuat ve puan aynı akışta bulunuyor.
- Yüzeylerde gerçek eylemler metinle adlandırılmış: “Devamını incele”, “Rapor oluştur”, “Düzenle”.

## Öncelikli UX bulguları

### 1. Renk semantiği ekranın önüne geçiyor — P0

Analiz sonucu aynı anda açık yeşil özet alanı, siyah istatistik kutuları, kırmızı risk alanı, yeşil yöntem seçimi ve dört ayrı seviye rengi kullanıyor. Sekmelerde Uzman Görüşü sarı, Eğitim Önerileri mavi, Onaylı Defter gri bir ürün gibi davranıyor. Renk, önem bilgisini taşımak yerine bölümleri ayıran ana navigasyon aracına dönüşüyor.

Kod karşılığı: `NovaAnalysisSectionTone` her bölüme ayrı durum paleti veriyor; `NovaAnalysisSectionHeader` bu paleti doğrudan arka plana taşıyor (`App/DesignSystem/ISG/NovaAnalysisSectionViews.swift:3-16`, `71-101`).

### 2. Kritik içerik ilk bakışta aşağıda kalıyor — P0

Analiz Sonucu ekranında başlık, fotoğraf özeti, firma atama satırı, dört sekme, uzun bölüm açıklaması, istatistik kartı ve metot seçimi bulgu listesinden önce geliyor. İlk risk kartının yalnızca üst satırı ekranın altına sığıyor. Sabit “Rapor oluştur” çubuğu da kullanılabilir yüksekliği azaltıyor.

Kod karşılığı: içerik için ayrı `ScrollView` ve altta sürekli `safeAreaInset` action bar kullanılıyor (`App/DesignSystem/ISG/NovaAnalysisDetailScreens.swift:51-72`).

### 3. Aynı bilgi farklı görsel dillerle tekrar ediliyor — P1

Sekme başlığı, renkli bölüm başlığı ve kart üzerindeki ikon/etiket aynı bölümün kimliğini üç kez anlatıyor. Uzman Görüşü ve Eğitim Önerileri içerik olarak aynı kart kalıbını kullanmasına rağmen renk değiştiği için kullanıcı önce renge, sonra başlığa bakıyor. Bu, sakin kurumsal bir rapor yerine dashboard hissi yaratıyor.

Kanıt: [Uzman Görüşü](../../artifacts/design-audit/2026-09-14/analysis-v3/8DE1A766-AC59-4246-B0BD-238AD028C851.png) ve [Eğitim Önerileri](../../artifacts/design-audit/2026-09-14/analysis-v3/37C52132-E040-4BAA-9CF1-F592F5B2B762.png).

### 4. Eylem sayısı karar anını kalabalıklaştırıyor — P1

Risk kartında metot seçimi, tümünü seç, kişi bazlı seçim, beğen/beğenme, devamını incele, düzenle ve sil aynı akışta bulunuyor. Seçim yapıldığında alt ana eylem “Rapor oluştur”dan “Firmaya Aktar”a dönüyor. Kullanıcı hangi eylemin kalıcı, hangisinin geçici olduğunu yeniden öğrenmek zorunda kalıyor.

### 5. Onaylı Defter metaforu içeriği gölgeliyor — P1

Kırmızı kenar çizgisi ve yatay çizgiler fiziksel defter hissi veriyor. Bu, kurumsal kayıt ekranında içerikten daha görünür ve diğer üç bölümden farklı bir görsel metafor oluşturuyor.

Kanıt: [Onaylı Defter](../../artifacts/design-audit/2026-09-14/analysis-v3/D80D19CC-D3F4-4CE9-982E-1A9CDF05F5E2.png).

Kod karşılığı: `NovaNotebookPanel` içinde çizgili sayfa düzeni kullanılıyor (`App/DesignSystem/ISG/NovaAnalysisSectionViews.swift:500-560`).

### 6. Bulgu detayı fazla dramatik — P1

Bulgu popup'ı 200 px fotoğraf, koyu gradyan, iki dairesel geri bildirim düğmesi, renkli puan kutusu ve kırmızı/sarı/yeşil/mavi alan şeritlerini aynı anda gösteriyor. Bu sunum yapay zekâ sonucu veya sosyal kart hissi veriyor; uzman kaydının sakin, taranabilir yapısını zayıflatıyor.

Kanıt: [Bulgu detay popup'ı](../../artifacts/design-audit/2026-09-14/analysis-v3/B8B05884-6AA0-4C78-9B3B-27699E23BEAE.png).

Kod karşılığı: fotoğraf hero'su ve gradyan `NovaAnalysisItemSheet.hero` içinde; alan panelleri durum paletleriyle boyanıyor (`App/DesignSystem/ISG/NovaAnalysisSheets.swift:45-86`, `203-220`).

## Erişilebilirlik ve okunabilirlik riskleri

- Durum ve bölüm ayrımı büyük ölçüde renkle veriliyor. İkon ve metin çoğu yerde mevcut, fakat renk tamamen kaldırıldığında anlam sırasının bozulmaması test edilmeli.
- `micro` ve `badge` metinleri; uzun sekme adları ve firma etiketleri küçük ekranda yoğunlaşıyor. Büyük metin ve Dynamic Type ile gerçek cihaz denemesi yapılmadı.
- Sabit alt eylem alanı ve popup içindeki çok sayıda kart, büyütülmüş yazı boyutunda içeriği aşağı itebilir.
- 34–40 pt aralığındaki bazı ikon ve seçim alanları ölçü olarak 44 pt hedefinin altında kalabilir. Görsel testte VoiceOver odak sırası ve gerçek dokunma alanı ölçülmedi.
- Renkli arka planların kontrastı açık temada genel olarak okunur, ancak kırmızı/sarı/mavi ikincil metinler için kontrast doğrulaması yapılmalı.

## Önerilen tasarım yönü: Sakin Kurumsal / Kanıt odaklı

Tek bir ana vurgu rengi ve nötr yüzeyler kullanılmalı. Risk seviyesi yalnızca küçük bir durum etiketi ve gerektiğinde tek bir kırmızı işaretle gösterilmeli.

### Görsel dil

- Zemin: çok açık soğuk gri; kart: beyaz; gövde metni: koyu lacivert-gri; ikincil metin: orta gri.
- Ana vurgu: NOVA yeşili. Seçili sekme, birincil buton ve bağlantılar bu rengi kullanır.
- Bölüm renkleri kaldırılır; bölüm başlıkları aynı nötr yüzeyde, solda 2 px vurgu çizgisi ve ikonla ayrılır.
- Siyah ters yüzey yalnızca birincil eylemde kullanılır; istatistik kartı beyaz/nötr bilgi satırına dönüşür.
- Kart yarıçapı 12–14 pt, tek hairline border, daha az iç içe kutu.

### Bilgi hiyerarşisi

1. Üstte tek satırlık bağlam: analiz adı, firma, tarih.
2. Altında üç kısa özet: bulgu sayısı, en yüksek skor, fotoğraf sayısı.
3. Sekmeler yalnız başlık + sayı gösterir; uzun açıklama sekme içindeki sakin bilgi notuna taşınır.
4. İçerik listesi başlık → kısa açıklama → tek satır metadata sırasını izler.
5. Eylem çubuğu tek bir birincil eylem taşır. Seçim yapıldığında eylem, listenin hemen üzerinde bağlamsal satır olarak görünür.

### Yüzey bazlı uygulama

- **Analiz Sonucu:** Özet ve sekmeler ekranın ilk yarısında bitecek; risk istatistiği tek satırlık nötr özet olacak; ilk bulgu kartı kaydırmadan görünür.
- **Bulgu detayı:** Fotoğraf 96–112 pt; başlık ve durum üstte; puan tek satırda; açıklama/önlem/mevzuat etiket-değer çiftleri halinde; geri bildirim ikonları ikincil.
- **Uzman Görüşü / Eğitim Önerileri:** Aynı nötr `EvidenceCard` şablonu; bölüm farkı yalnız başlık ve küçük ikonla verilecek. Kategori ve hedef kitle sessiz metadata olacak.
- **Onaylı Defter:** Çizgili kâğıt yerine tarih, kayıt başlığı ve metin içeren kronolojik kayıt listesi; gerekiyorsa sol kenarda ince yeşil işaret.
- **Analizlerim:** Yeşil büyük sayaç bloğu yerine tek satır özet ve daha kısa filtre çipleri; kritik etiketi liste satırında küçük ve tutarlı.

## Uygulama sırası

1. **P0 — Palette ve hiyerarşi:** Bölüm durum arka planlarını kaldır, nötr bölüm şablonunu ve tek vurgu rengini tanımla; analiz özeti/istatistiği sıkıştır.
2. **P0 — Eylem akışı:** Alt çubuğu tek bir birincil eyleme indir, seçim eylemini liste bağlamına taşı.
3. **P1 — Ortak kartlar:** Bulgu, görüş ve eğitim önerisini `EvidenceCard` ailesine ayır; detay popup'ını kompakt bilgi paneline çevir.
4. **P1 — Onaylı Defter:** Çizgili defter görünümünü kronolojik kayıt görünümüne dönüştür.
5. **P1 — Erişilebilirlik:** Dynamic Type, VoiceOver sırası, 44 pt dokunma alanları ve renk kontrastı için gerçek cihaz kabul senaryoları ekle.
6. **P2 — Son rötuş:** Logo/fotoğraf oranları, siyah-beyaz baskı ve koyu tema paritesini kontrol et.

Bu yön, mevcut NOVA/RiskDetected kimliğini korurken ekranları tek bir ürün ailesi gibi hissettirir: önce bağlam, sonra kanıt, en son eylem.

## Uygulanan takip düzenlemesi

Risk Analizi bölümü bu denetimden sonra kompakt karta taşındı. Uzun açıklama ve siyah istatistik kutuları kaldırıldı; başlık, kısa “Skorlanan bulgular” alt metni, küçük metrik etiketleri ve kritik/yüksek/orta/düşük/bilinmiyor dağılım barı tek kartta birleşti. İlk bulgu artık aynı ekran akışında daha erken görünür.
