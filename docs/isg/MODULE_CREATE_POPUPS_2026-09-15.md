# Modül oluşturma popup akışı

Plan yayınla, tatbikat planla, görev ver ve KKD zimmeti düğmeleri doğrudan kayıt popup'ını açar. İlk adım firma arama/seçimidir. Firma kataloğu yüklenince aynı modal içindeki form gösterilir. Liste filtresi ile kayıt firmasının state'i ayrıdır; kayıt işlemi liste filtresini kullanarak yanlış firmaya yönlenmez. Firma değiştiğinde şirkete bağlı form state'i yeniden oluşturulur.

Ortak `NovaCompanyCreateFlow` yükleniyor, arama sonucu yok, firma yok ve yeniden deneme durumlarını içerir. `NovaPopup` iç içe arkaplan/X üretmeden bileşik formu gösterir. Form içerik ölçümleri pencere yüksekliğini belirler; ekran/klavye sınırını aşan içerik ScrollView'da kayar. Kaydetme sırasında firma değiştirme ve popup kapatma devre dışıdır.

Mevcut acil durum planı revizyonu kendi firmasına bağlı kalır; yeni firma seçme adımına girmez. KKD miktar/iade işlevleri yeniden eklenmez.

Doğrulama: iOS 2.0.3 (110) cihaz derlemesi başarılı; kaynak akışında eski pendingCreate/listede firma seçimini bekleme yolu üç aktif modülden kaldırıldı. Canlı veritabanı değişikliği yok. Fiziksel cihazda tüm form adımlarının kullanıcı kabulü ayrıca yapılmalıdır.
