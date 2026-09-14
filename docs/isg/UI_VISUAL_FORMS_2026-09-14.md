# Kapalı accordion ve görsel form paketi

14 Eylül. Kullanıcı bağlantıları sonraya bırakarak Görev ve firma Güncelle/Sil alanlarının görsel hazırlanmasını istedi.

- Firma Bilgileri ve tüm alt başlıklar başlangıçta kapalı.
- Durum rozeti chevron'un solunda; kırmızı/yeşil zeminli Eksik/Tamamlandı.
- Açılan accordion açık mavi zeminle ayırt ediliyor.
- Popup'lar sabit 560 pt yerine içeriğin ölçülen yüksekliği + X başlığı kadar boyutlanıyor. Form/listelerde ölçüm; ekran/klavye alanı üst sınır, taşınca mevcut ScrollView kaydırılır.
- Personel formunda isteğe bağlı Görev metin alanı var. Bu alan yeni pilot sözleşmesi bağlanana kadar yalnız görsel taslak; veri girildiğinde kaydedilmediği açıklanır. Mevcut ad/departman akışı değiştirilmedi.
- Firma kartında kalem Güncelle ve çöp kutusu Sil ikonları; ayrı merkez önizleme pencereleri. Güncelle formu firma adı/sektör/tehlike/mail/çalışan sayısı/sorumlu tasarımını, Sil penceresi onay görünümünü içerir. Hiçbir update/delete RPC çağrısı yapılmaz; düğmeler açık önizleme bildirimi verir, başarı taklidi yok.
- TR/EN yeni kopyalar katalogda. Sunucu bağlantıları ve gerçek silme/güncelleme semantiği sonraki iş; canlı veriler değişmedi.
- Telefon kurulumu yok, telefon build 93.

Beceri: SwiftUI UI Patterns.

## Doğrulama

- Tam Xcode simülatör derlemesi PASS. Mevcut 6 XCUI testi ve yeni görsel güncelle/sil/popup büyüme testi PASS (iki koşuda 7 senaryo).
- Yeni test sorumlu personel alanını açarak popup'ın üst kenarının yukarı kaydığını doğrular; Sil önizlemesi kayıt silmeden bilgi verir.
- İlk Node koşusunda ikon label kontrolü satır bazlı tarama nedeniyle iki yeni butonu işaretledi. Label'lar butonla aynı satıra alındı; 4 yerelleştirme testi yeniden PASS. Diğer 21 test önceki koşuda PASS.
- Son yeni test: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-09-13T22-52-42-758Z_pid84322_74f54cab.xcresult`.
- Diğer 6 test: `test_sim_2026-09-13T22-50-15-213Z_pid84322_dfc26518.xcresult`; görüntüler `output/isg/pilot/visual-forms-review/`.
