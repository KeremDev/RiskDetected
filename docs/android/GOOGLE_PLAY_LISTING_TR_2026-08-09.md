# RiskDetected Google Play Türkçe listing paketi

Durum: metadata taslağı hazır; görsel ve Play Console kanıtları release blocker'dır.

## Metadata

- Uygulama adı (26/30): `RiskDetected: İSG Analizi`
- Kısa açıklama (75/80): `Fotoğraftan tehlike tespiti, Fine-Kinney ve 5x5 ile PDF/Excel İSG raporu.`
- Kategori: Business
- Hedef kitle: 18+ iş güvenliği uzmanları, OSGB ekipleri, saha mühendisleri ve denetim ekipleri
- Birincil terimler: iş güvenliği, İSG risk analizi, tehlike tespiti, risk değerlendirme,
  Fine-Kinney, 5x5 matris, PDF raporu, Excel raporu

## Tam açıklama

RiskDetected, saha fotoğraflarından yapay zekâ destekli iş güvenliği ve İSG risk analizi
hazırlamana yardımcı olur. Tehlike tespiti, risk değerlendirme ve raporlama adımlarını tek bir
akışta birleştirir; denetim notlarını düzenli çıktılara dönüştürür.

Fotoğrafını yükle, çalışma alanını seç ve tespit edilen bulguları gözden geçir. RiskDetected;
bulguları Fine-Kinney veya 5x5 Matris yöntemiyle önceliklendirmen, kontrol tedbirlerini
incelemen ve saha doğrulaması yapman için yapılandırılmış bir sonuç sunar.

Öne çıkan özellikler:

• Fotoğraftan tehlike tespiti: Saha görüntülerindeki olası tehlike ve uygunsuzlukları düzenli
bir bulgu listesinde incele.

• İSG risk analizi: Olasılık, şiddet ve maruziyet bilgileriyle risk seviyelerini karşılaştır.

• Fine-Kinney ve 5x5 Matris: Kurumunda kullanılan risk değerlendirme yöntemini seç.

• Kontrol tedbirleri: Her bulgu için önerilen aksiyonları ve saha doğrulama bilgilerini gör.

• PDF ve Excel raporu: Analiz sonuçlarını paylaşılabilir raporlara dönüştür.

• Şirket ve arşiv yönetimi: Analizleri, raporları ve şirket bilgilerini tek yerde düzenle.

• Çoklu fotoğraf: Plus ve Pro planlarında aynı analiz içinde birden fazla saha görüntüsünü
değerlendir.

• Plan seçenekleri: Free, Plus ve Pro sınırlarını uygulama içinde karşılaştır; satın alma
ekranında güncel Google Play fiyatlarını gör.

RiskDetected; iş güvenliği uzmanları, OSGB ekipleri, saha sorumluları, üretim ve depo ekipleri
ile düzenli saha denetimi yapan profesyoneller için tasarlanmıştır. İş güvenliği raporu
hazırlarken fotoğraf, bulgu, risk skoru ve şirket bilgilerini aynı süreçte yönetmeyi amaçlar.

Yapay zekâ çıktıları profesyonel İSG değerlendirmesinin, saha incelemesinin veya mevzuat
kontrolünün yerine geçmez. Kullanıcı tüm bulguları ve kontrol tedbirlerini doğrulamalıdır.

RiskDetected'i indir; fotoğraftan tehlike tespiti ile başlayan İSG risk analizi sürecini PDF ve
Excel raporuna kadar tek yerde yönet.

## Sekiz ekranlık yaratıcı plan

İlk üç ekran değer önerisini anlatır; giriş, ayarlar ve boş ekran ilk üçe alınmaz. Her ekran
gerçek Android release UI ve anonimleştirilmiş gerçek içerik kullanır.

| Slot | Başlık | Ekran | Durum |
| ---: | --- | --- | --- |
| 1 | Fotoğraftan tehlikeleri gör | Kaynak fotoğraf + analiz sonucu | gerçek corpus sonrası çekilecek |
| 2 | Riskleri doğru sırala | Risk dağılımı ve bulgu listesi | UI kanıtı var, store kompozisyonu bekliyor |
| 3 | Fine-Kinney ve 5x5 birlikte | Bulgu detay/risk yöntemi | UI kanıtı var, store kompozisyonu bekliyor |
| 4 | Raporun düzenli ve hazır | Rapor oluşturma sonucu | UI kanıtı var, gerçek PDF sonrası çekilecek |
| 5 | PDF ve Excel olarak paylaş | Rapor arşivi/paylaşım | gerçek E2E bekliyor |
| 6 | Birden fazla fotoğrafı incele | Fotoğraf tepsisi/sıralama | staging multi-photo E2E bekliyor |
| 7 | Şirketlerine göre arşivle | Şirket ve rapor filtresi | gerçek E2E bekliyor |
| 8 | İhtiyacına uygun planı seç | Free/Plus/Pro karşılaştırma | UI kanıtı var, store fiyatlı E2E bekliyor |

Görseller küçük, standart ve büyük Android telefonlarda doğrulanacak. Üst metin 4–6 kelime,
yüksek kontrast ve tek tip sistem sans kullanacak; fiyatlar görsele sabit yazılmayacak.

## Görsel kapılar

- Play icon: `android/app/src/main/res/drawable-nodpi/rd_app_icon.png` 512×512, alfa yok; ancak
  kaynak görsel önceden yuvarlatılmış köşe taşıdığı için yayınlanamaz. Tasarım kaynağından
  köşesiz/full-bleed Play master üretilmeli.
- Adaptive foreground/background ve Android 13 monochrome kaynakları uygulamada mevcut; ancak
  foreground mevcut ön-yuvarlatılmış bitmap'i kullandığından yeni full-bleed master ile Pixel ve
  Samsung maskelerinde görsel kabul tamamlanmadan yayın kapısı açılamaz.
- Feature graphic 1024×500 henüz onaylı değil.
- Sekiz ekran görüntüsünün nihai store kompozisyonu henüz üretilmedi.
- Görsellerde e-posta, UID, gerçek kişi/şirket adı veya hassas saha verisi bulunamaz.

Mevcut ikon denetimi: küçük boyutta tanınırlık `8/10`, açık/koyu zeminde kontrast `8/10`,
sadelik `6/10`, marka uyumu `9/10`; kategori farklılaşması Play rakip seti görülmeden
puanlanmadı. En önemli düzeltme, mağazanın uygulayacağı maskeden önce dosyaya gömülmüş beyaz
köşe/yuvarlatmayı kaldırmaktır. Merkezdeki baret ve kontrol panosu üretken yapay zekâ ile
yeniden çizilmeyecek.

## İlk mağaza deneyi

Production açılışından sonra yeterli trafik oluştuğunda yalnız kısa açıklama veya yalnız ilk
ekran görseli değiştirilecek; iki değişken aynı deneyde karıştırılmayacak. Deney en az yedi gün
ve varyant başına yeterli gösterim olmadan sonuçlandırılmayacak.
