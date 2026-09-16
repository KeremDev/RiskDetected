# Uygulama genelinde klavye kapatma

Boş alan veya metin girişi olmayan bir alana dokunulduğunda klavye kapanır. Davranış `RiskDetectedApp` köküne bağlı `RDKeyboardDismissBehavior` üzerinden uygulama penceresine bir kez eklenir. Sayfa veya tam ekran popup değişimi sırasında aynı pencereye bağlı kalır; eski forma özel bağlayıcılar kaldırılmıştır.

- Metin alanı, çok satırlı düzenleyici ve klavye içindeki dokunuşlar kapatma hareketinin dışında tutulur.
- Hareket diğer dokunuşları tüketmez; butonlar aynı dokunuşta çalışmaya devam eder.
- Her pencere yalnız kendi düzenlemesini sonlandırır. Ek pencereler birbirinin klavyesini kapatmaz.
- Yazılmış içerik değiştirilmez; kayıt/gönderim yapılmaz.

Doğrulama: iki XCTest UI senaryosu geçti. Risk popup sayısal klavyesi, değerin korunması, tekrar odaklanma/yazma, X düğmesinin ilk dokunuşta çalışması; normal sayfa araması ve filtre seçiminin klavye ile birlikte çalışması kontrol edildi. Sonuç: `/tmp/isgada-keyboard-tests.xcresult`. Görsel açılmadı ve ayrıca ekran görüntüsü üretilmedi.

Dağıtım yalnız fiziksel iPhone pilot derlemesidir; sunucu veya mağaza dağıtımı yapılmaz.
