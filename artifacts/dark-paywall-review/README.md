# Koyu paywall doğrulaması

## Uygulama

Paywall.dc.html tasarımı ortak native SwiftUI ekranına aktarıldı. Onboarding ve uygulama içindeki tüm PLUS/PRO girişleri aynı ekranı kullanır. Paywall ve hukuki bilgi sheet'leri koyu temadadır; diğer ekranların tema seçimi değiştirilmedi.

Fiyat, yıllık fiyatın aylık karşılığı, indirim oranı ve ücretsiz deneme süresi RevenueCat paketlerinden gelir. Deneme yalnız uygunluk kontrolü olumluysa sunulur. Mevcut satın alma, geri yükleme ve paywall kaynak takibi korunmuştur. HTML'deki örnek fiyatlar ve örnek paket hakları üretime kopyalanmadı.

## Kontrol edilenler

- Simulator Debug build-for-testing başarılı.
- iPhone 13: PLUS/PRO, aylık/yıllık fiyatlar, karşılaştırma, çapraz paket bağlantısı ve onboarding geçişi geçti.
- iPhone 17 Pro Max: PLUS/PRO, aylık/yıllık fiyatlar, karşılaştırma ve çapraz paket bağlantısı geçti.
- Denemeye uygun olmayan kullanıcıda ücretsiz deneme vaadinin gösterilmemesi kontrol edildi.
- En büyük Dynamic Type'ta planların, CTA'nın ve hukuki bağlantıların erişilebilirlik testi geçti.
- Hukuki bilgi sheet'leri ve geri yükleme aksiyonu UI testi geçti.
- Normal metin boyutunda iPhone 13 ve 17 Pro Max'te iki plan, çapraz paket kartı ve CTA ilk açılışta ulaşılabilir; büyük erişilebilirlik metninde gövde kaydırılır.
- Lokalizasyon katalog eşliği, placeholder, çoğul ve Swift metin kontrolleri geçti. Ayrı backend lokalizasyon snapshot kontrolü mevcut 743/248 sayım uyuşmazlığında başarısız; bu çalışma backend'i değiştirmedi.

## Görseller

Dosya isimleri cihazı ve PLUS/PRO aylık/yıllık seçimini belirtir. Ekran görüntülerindeki fiyatlar yalnız DEBUG UI-test fixture verisidir; gerçek satın alma devre dışıdır. Üretim RevenueCat verisi kullanır.

Gerçek App Store sandbox satın alma, yenileme ve fiziksel cihaz kontrolü bu doğrulamaya dahil değildir. Canlı satın alma akışı yayın öncesinde sandbox hesabıyla ayrıca doğrulanmalıdır.
