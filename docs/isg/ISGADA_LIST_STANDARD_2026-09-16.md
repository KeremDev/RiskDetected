# İSGADA liste ve filtre standardı — 16 Eylül 2026

Pilot iOS 2.0.3 (116) için uygulandı. Bu çalışma sunucu migration'ı, canlı veri değişikliği veya App Store dağıtımı içermez.

## Ortak bileşenler

- `NovaListHeading`: mevcut `NovaPageHeading` üzerinden beyaz yuvarlatılmış geri düğmesi, ortak başlık fontu ve kompakt eylem. Başlık gerektiğinde sarılır; erişilebilirlik yazı boyutunda eylem alt satıra alınır.
- `NovaListStat`: siyah çizgi ikon, sayı ve tek başlık. Tekrarlayan alt açıklamalar kaldırıldı. Risk, acil durum, tatbikat ve İSG-KATİP normal boyutta dört sütun; erişilebilirlik boyutlarında iki sütun. Diğer modül sayaçları aynı görsel bileşeni kullanır.
- `NovaFileChooserPanel`: üstte canlı arama, altında yüksekliği sınırlı dikey liste. Arama sonucu değişirken panel yüksekliği korunur, uzun liste kendi içinde kayar. Türkçe ve aksan duyarlı sistem arama eşlemesi kullanılır. Seçim anında uygulanır ve panel kapanır.
- `NovaFilterField`: tekil filtreler için aynı açılır panel. Risk, acil durum, atama, tatbikat, KKD, İSG-KATİP, kontrol listeleri, dosya, ekipman, analiz, uygunsuzluk, eğitim, istatistik, evrak takibi ve süreç modüllerine bağlandı.

## Sayfa düzeltmeleri

- Risk listesinde firma adı tek kez, varsa farklı işyeri ayrıca gösterilir. Durum açıklaması tekrar edilmez. Geçerlilik tarihi gün.ay.yıl olarak görünür; süre ve sürüm korunur. Kaynak bilgisi listeyi doldurmaz, detay kaydı korunur.
- Risk ana girişinde kapatılmış geri düğmesi açıldı.
- Acil durum başlığı ve ekleme akışı `Plan Ekle` oldu. Yenileme süresi önerilmediğini söyleyen eski ürün açıklamaları kaldırıldı.
- Liste üstlerindeki gereksiz ürün açıklamaları kaldırıldı; kısa kullanım ipuçları kaldı.
- Risk, acil durum, tatbikat ve İSG-KATİP durum seçeneklerindeki aynı kimlikli yinelenen satırlar ayıklandı.

## Doğrulama

- Simulator pilot derlemesi başarılı.
- 48 mevcut Node kontrolü başarılı (`nova_analysis_flow`, `nova_file_library`, `nova_tokens`, `pilot_native`).
- İki gerçek XCTest UI senaryosu başarılı: riskte yazarken firma arama, seçme, durum seçme, tümüne dönme ve dört kartın aynı satırda olması; acil durumda başlık, sayaçlar ve firma paneli.
- Görsel inceleme: risk listesi, acil durum listesi, arama ve durum paneli; erişilebilirlik yazı boyutunda başlık/sayaç düzeni.
- Fiziksel iPhone için pilot derlemesi, kurulumu ve uygulamanın açılması başarılı. Fiziksel cihazda tüm modüller tek tek etkileşim testinden geçirilmedi.

Görseller `output/isg/list-standard-2026-09-16/` altında. UI sonuç paketi `/tmp/isgada-list-ui-final.xcresult`. Derleme/kurulum günlükleri `/tmp/isgada-list-device-*.log`.
