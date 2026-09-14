# NOVA ekran tutarlılığı — 15 Eylül 2026

Kullanıcı isteği: aynı tür yazılarda aynı font/boyut/renk, sayfalarda header ve başlığın yanında geri dönüş, dekoratif arka plansız çizgi ikonlar.

## Uygulanan ortak kurallar

- Ekran metinlerinde Plus Jakarta Sans ailesi. Eski profil/rapor SwiftUI font eşlemesi de aynı aileye alındı; UIKit PDF font sözleşmesi değiştirilmedi.
- Ekran başlığı 19, kart başlığı 14, gövde 13, yardımcı metin 11.5–12, düğme 13.5–15 punto token'ları. Dynamic Type korunur; "aynı boyut" aynı anlamsal rol içindir.
- NovaText ve NovaSizedText nötr renkleri rolünden çözer: başlık/düğme/ana metin ana mürekkep, açıklama/meta tek ikincil renk. Durum, hata ve koyu zemindeki beyaz metin ayrımı korunur. Native kontrollerin varsayılan fontu ortaklaştırıldı.
- NovaPageSurface shell dışında tam ekran açıldığında NOVA header ekler. Shell içinde ikinci header oluşturmaz. Tam ekran sunum sarmalayıcısı header bağlamını sıfırlar; analiz sonucundaki özel ikinci header kaldırıldı.
- Acil durum, tatbikat, atama, KKD, KATİP, kontrol listesi ve risk başlıkları geri düğmesiyle aynı satıra taşındı. Personel/dizin/süreç sayfası başlıkları aynı ölçeğe alındı. Profil ve rapor arşivine geri dönüş eklendi. Popup formları mevcut X ile kapanır.
- NovaIcon çizgi SF sembollerine geçirildi. İkon-only dekoratif kutu/daireler ve geri/X arka planı kaldırıldı. Etiket, kart, durum göstergesi ve metinli eylem düğmesi zeminleri ikon arka planı değildir ve korundu. Kontrastı kaybolan alt Ekle ve rapor gönder sembolleri düzeltildi.
- Firma Bilgileri/Firma süreçleri açılır bölümlerinin çakışan erişilebilirlik kimlikleri ayrıldı.

## Doğrulama ve sınır

- iOS cihaz hedefi 2.0.3 (115) derlendi. Fiziksel telefona kurulum bu tasarım turunda yapılmadı.
- Üç simülatör UI testi PASS: analiz listesi→sonuç→uzman görüşü/eğitim sekmeleri, bulgu detayı, firma→personel popup→aynı açık bölüme geri dönüş.
- Sekiz ekran görüntüsü `artifacts/style-consistency-2026-09-15` altında; analiz sonucu ve personel popup görüntüleri görsel olarak incelendi. Son küçük seçim düğmesi rolü/uzman görüşü sembolü düzeltmesi bu görüntülerden sonradır.
- Statik tarama ortak NOVA ekranları ve pilot modül kapılarını kapsar. Bütün canlı kayıt kombinasyonları, ödeme/OS ekranları ve tüm erişilebilirlik metin boyutları cihazda tek tek gezilmiş değildir. Android'e bu turda tasarım portu yapılmadı.
