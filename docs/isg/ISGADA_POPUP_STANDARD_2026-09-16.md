# İSGADA popup standardı — 16 Eylül 2026

Kapsam: özel iOS pilot. Sunucu, veri modeli, kayıt/geçerlilik kuralları ve genel rollout değiştirilmedi.

- `NovaPopupStyle`: arka plan malzeme opaklığı 0.28, karartma 0.10; hızlı ekle panelinin kaynak bulanıklığı 2 pt. Personel onayı da aynı değerleri kullanır. Reduce Transparency tercihi korunur.
- `NovaPopupHeading`: 18 pt Plus Jakarta Sans SemiBold başlık, siyah çizgi ikon, isteğe bağlı kısa açıklama. Risk, acil plan, atama, İSG-KATİP, tatbikat, kontrol listesi ve KKD formları ortak başlık dilini kullanır.
- `NovaPopupOption`: beyaz, köşeleri yuvarlatılmış, ikon + başlık + isteğe bağlı açıklama + ok. Firma ve risk yeni/revizyon seçenekleri ortak bileşenle gösterilir.
- `NovaCompanyCreateFlow`: seçilen firma satırının yüksekliği ölçülür; içerik yüksekliğine tahminî sabit boşluk eklenmez. Formdan firma seçimine dönüş korunur.
- Risk hızlı kayıt formu iç boşlukları olan bir ScrollView içinde ölçülür; uzun içerik ve klavyede kaydırılır. Kontrol başlatma formu da kaydırılabilir.
- `NovaFormValueRow` / `NovaDayField`: normal yazı boyutunda alan adı solda, tarih/değer sağda. Erişilebilirlik boyutlarında içerik alt alta büyüyebilir. Opsiyonel tarih boşken tarih uydurulmaz; seçme/temizleme korunur. Risk geçerlilik süresi ve süreçlerin tarih alanları aynı satır düzenini kullanır. Kurul işyeri/tarih alanları dar yarım kolonlara sıkıştırılmaz.
- Popup içindeki `NovaButton`: küçük yazı ve ikon, merkezli metin, minimum 46 pt dokunma alanı, içerik uzadığında büyüme. Popup dışındaki temel buton ölçüleri korunur.
- Dosya seçimi: sade ikonlu satır; uzun tür/boyut ve denetim açıklaması “Dosya bilgileri” altında açılır. Dosya seçilmeden boş yükleme düğmesi gösterilmez. Yükleme, tür/boyut denetimi ve arşiv durumu sunucu sözleşmesine bağlı kalır.

Sentetik görsel prova, `NovaPilotReviewHarness` altında yalnız DEBUG + NOVA_PILOT_BUILD + simulator koşulunda gerçek risk ekranlarını mock istemciyle açar; canlı hesap/veri kullanmaz. Firma seçimi, önceki kayıt seçenekleri ve yeni kayıt ekranlarının görüntüleri `output/isg/popup-standard-2026-09-16/` altında tutulur.

## Doğrulama

- 48 mevcut istemci/tasarım sözleşmesi kontrolü geçti. Eski dosya testleri, açıklamanın açılabilir bölüme taşınması ve sunucudan gelen tür/boyut bilgisinin korunmasına göre güncellendi.
- iOS Simulator ve fiziksel pilot build başarılı; 2.0.3 (116) iPhone Kerem’e yeniden kuruldu.
- Üç risk popup aşaması normal yazı boyutunda, kayıt formu ayrıca Accessibility Large boyutunda görsel olarak incelendi. Uzun içerik kaydırılır; normal boyutta tarih ve süre aynı satırdadır.
- Tüm bağımsız eski popup’ların her cihaz/klavye kombinasyonu tek tek denenmedi; ortak bileşenler ve şirket/modül form aileleri güncellendi.

## Kontrast güncellemesi

Kullanıcının son geri bildirimiyle popup zemini açık temada beyaza, iç kartlar ve alanlar açık griye taşındı. Renkler `NovaPopupStyle` üzerinden, iç yüzeyler `novaControlBackground` ve `NovaCard` ile yönetiliyor; normal sayfa yüzeyleri aynı kalır. Koyu tema mevcut yüzey tokenlarını kullanır.

Arka plan için thin material opaklığı 0.60, siyah karartma 0.18; hızlı ekleme kaynak bulanıklığı 4 pt. Popup üzerine ayrıca beyaz örtü eklenmiyor. Kullanıcının tercihi uyarınca bu düzeltme sonrasında ekran görüntüsü üretilmedi veya görüntülenmedi; doğrulama cihaz derlemesiyle yapılıyor.
