# RiskDetected Google Play Türkçe listing paketi

Durum: iOS `1.3.1/tr` ile eşlenen metadata Play Console taslağına kaydedildi; ikon ve feature
graphic hazır. Sekiz telefon görselini owner ayrıca tasarlatacak. Play'e varlık yükleme ile
zorunlu formlar release blocker'dır.

## Metadata

- Uygulama adı (30/30): `RiskDetected: İş Güvenliği İSG`
- Kısa açıklama (28/80): `Risk Analizi ve iş güvenliği`
- Kategori: Business
- Hedef kitle: 18+ iş güvenliği uzmanları, OSGB ekipleri, saha mühendisleri ve denetim ekipleri
- Birincil terimler: iş güvenliği, İSG risk analizi, tehlike tespiti, risk değerlendirme,
  Fine-Kinney, 5x5 matris, PDF raporu, Excel raporu

## Tam açıklama

RiskDetected, iş güvenliği ve İSG risk analizi süreçlerinde saha fotoğrafı ile tehlike,
uygunsuzluk ve riskleri değerlendirip PDF/Excel risk raporu hazırlamanıza yardımcı olur.

İş güvenliği uzmanları, OSGB ekipleri, işveren vekilleri ve saha sorumluları için geliştirilen
RiskDetected; Fine-Kinney ve 5x5 Matris yöntemleriyle riskleri önceliklendirmeyi, kontrol
tedbirlerini netleştirmeyi ve raporları arşivlemeyi kolaylaştırır.

Öne çıkan özellikler:

• Fotoğraf ile İSG risk analizi
• Fine-Kinney ve 5x5 Matris risk değerlendirme çıktıları
• PDF ve Excel risk raporu oluşturma
• Tehlike, uygunsuzluk ve kontrol tedbiri önerileri
• Rapor arşivi, indirme ve paylaşım
• Firma bilgisi, hazırlayan bilgisi ve logo ile rapor özelleştirme
• OSGB ve iş güvenliği uzmanları için saha denetim akışı
• KVKK ve gizlilik hassasiyetiyle veri yönetimi

RiskDetected; iş sağlığı ve güvenliği, risk değerlendirme, saha denetimi ve risk raporlama
süreçlerinde zaman kazanmak isteyen profesyoneller için tasarlanmıştır.

Uygulama yapay zeka destekli analizler sunar. AI çıktıları profesyonel değerlendirme, mevzuat
yorumu veya saha kontrolünün yerine geçmez. Nihai karar, kontrol ve uygunluk değerlendirmesi
yetkili iş güvenliği uzmanı veya sorumlu kişi tarafından yapılmalıdır.

Bazı gelişmiş özellikler uygulama içi abonelik gerektirebilir. Abonelikler Google Play üzerinden
yönetilir.

Kullanım Koşulları: https://riskdetected.com/kullanim-kosullari
Gizlilik Politikası: https://riskdetected.com/gizlilik

## iOS anahtar kelime eşlemesi

Google Play'de ayrı anahtar kelime alanı yoktur. iOS `1.3.1/tr` keyword seti
`osgb,is güvenliği,is guvenligi,isg,değerlendirme,uzmanı,sağlığı,tehlike,tespit,5x5,matris`
başlık, kısa açıklama ve uzun açıklama içinde doğal biçimde kapsanır; spam amaçlı tekrar eklenmez.

## Sekiz ekranlık yaratıcı plan

İlk üç ekran değer önerisini anlatır; giriş, ayarlar ve boş ekran ilk üçe alınmaz. Her ekran
gerçek Android release UI ve anonimleştirilmiş gerçek içerik kullanır.

| Slot | Başlık | Ekran | Durum |
| ---: | --- | --- | --- |
| 1 | Fotoğraftan saha risklerini görün | Gerçek analiz sonucu | owner tasarımı bekliyor |
| 2 | Kanıta dayalı bulgular oluşturun | Bulgu/risk detayı | owner tasarımı bekliyor |
| 3 | Fine-Kinney veya 5×5 ile önceliklendirin | Yöntem/risk dağılımı | owner tasarımı bekliyor |
| 4 | Analizi adım adım takip edin | Waiting/polling | owner tasarımı bekliyor |
| 5 | Birden fazla fotoğrafı inceleyin | Fotoğraf tepsisi/sonuç | owner tasarımı bekliyor |
| 6 | Profesyonel PDF ve Excel raporları hazırlayın | Rapor oluşturma | owner tasarımı bekliyor |
| 7 | Raporu firma bilgileriyle özelleştirin | Şirket/yöntem/format | owner tasarımı bekliyor |
| 8 | Tüm raporları tek yerde yönetin | Rapor arşivi | owner tasarımı bekliyor |

Görseller küçük, standart ve büyük Android telefonlarda doğrulanacak. Üst metin 4–6 kelime,
yüksek kontrast ve tek tip sistem sans kullanacak; fiyatlar görsele sabit yazılmayacak.

## Görsel kapılar

- Play icon: `android/play-store/riskdetected-play-store-icon-512.png`; 512×512, opak,
  full-bleed ve önceden yuvarlatılmamış.
- Adaptive foreground/background, round ve Android 13 monochrome kaynakları aynı onaylı master'dan
  üretildi. Fiziksel Pixel/Samsung maske kabulü dış cihaz kapısı olarak kalır.
- Feature graphic: `android/play-store/riskdetected-feature-graphic-1024x500.png`.
- Sekiz telefon ekranı owner tasarım tesliminden sonra eklenecek.
- Görsellerde e-posta, UID, gerçek kişi/şirket adı veya hassas saha verisi bulunamaz.

Mevcut ikon denetimi: küçük boyutta tanınırlık `8/10`, açık/koyu zeminde kontrast `8/10`,
sadelik `6/10`, marka uyumu `9/10`. Gömülü köşe/yuvarlatma kaldırıldı; merkezdeki onaylı baret ve
kontrol panosu uygulama ikonunda değiştirilmedi.

## İlk mağaza deneyi

Production açılışından sonra yeterli trafik oluştuğunda yalnız kısa açıklama veya yalnız ilk
ekran görseli değiştirilecek; iki değişken aynı deneyde karıştırılmayacak. Deney en az yedi gün
ve varyant başına yeterli gösterim olmadan sonuçlandırılmayacak.
