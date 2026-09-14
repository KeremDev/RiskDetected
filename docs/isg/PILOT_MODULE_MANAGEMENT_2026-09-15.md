# Operasyon modülleri — ekleme, düzeltme, silme, evrak bağlantısı

Kullanıcı geri bildirimi: açılan dört modülde temel kayıt yönetimi eksik ve firma/evrak ilişkileri tamamlanmalı.

## Yeni kullanıcı akışı

- Acil durum, tatbikat, KKD ve atama ekranında Ekle düğmesi Tüm firmalar görünümünde de görünür. Firma yoksa firma seçimini açar; seçim sonrası ilgili kataloğu yükler ve formu açar.
- Detay altında **Düzenle · Evrak bağla · Sil** paneli bulunur.
- Düzenleme alanları: acil planın işyeri/kapsam/tarih/dayanak/ekibi; tatbikatın plan/tarih/katılımcı/gözlem/iyileştirmesi; KKD'nin personel/ürün/miktar/birim/teslim tarihi/belge yeri; atamanın personel/işyeri/görev/tarih/dayanak/belge yeri.
- Firma kayıt oluşturulurken seçilir; mevcut kayıt düzenlemesi o firma kapsamını korur. Başka firmanın personeli/işyeri/evrakı bağlanamaz.
- Evrak bölümünde aynı firmaya ait evrak takip kaydı seçilir, değiştirilir veya bağlantısı kaldırılır. Firma evraklarını açma/ekleme düğmesi mevcut Evrak Takibi ekranını açar.
- Tüm firmalar listesinden açılan kayıtların iade/gerçekleşme/sonlandırma/yenileme işlemleri kendi firma kimliği ve kataloğuyla çalışır.

## Veri davranışı

- Acil plan düzeltmesi yeni sürüm üretir. Diğer kayıtların önceki halleri module_record_history tablosuna yazılır.
- Silme aktif listeden kaldırır, geçmişi fiziksel olarak yok etmez. Silinen atama aktif görev çakışma kontrolünden çıkar. Eski RPC yollarından silinmiş kayıtlar değiştirilemez.
- Aktif tatbikatı olan acil plan silinemez. İade toplamından küçük KKD teslim miktarı ve iade tarihini geçen teslim tarihi reddedilir. İade varsa personel/birim değiştirilemez.
- Düzenleme öncesi snapshot özeti optimistic concurrency kontrolüdür; eski ekran güncel kaydı ezemez. Kalıcı mutation kimliği ağ tekrarında aynı işlemi tekrarlar.
- Evrak bağlantısı mevcut document_obligations kaydına yapılır. **Bu teslim dosya upload/arşivleme değildir**; bu fark ekranda evrak takip kaydı ifadesiyle belirtilir.

## Yayın ve kanıt

- Canlı migration: `20260914211028_isg_pilot_module_management`.
- SHA-256: `2086906af5c7c4e8326e77079c34367f2e3694f96e69e5056a06b40c02ac69fa` — canlı ledger ve pilot-release aynası eşleşti.
- Önceki canlı modül paketi `20260914205319`; eski kayıtlar silinmedi.
- `node scripts/modules/run_pilot.mjs`: 186 kontrol geçti. Gece yarısı doğrulaması için test zamanı Europe/Istanbul ile eşlendi.
- Canlıda oluştur → düzelt → evrak bağla → oku → sil zinciri doğrulandı; geçici kayıtlar transaction geri alınarak kaldırıldı. Sonrasında management geçmiş sayısı sıfırdı.
- Yeni yönetim tablolarında RLS açık, anon/authenticated doğrudan tablo grant sayısı sıfır. Security advisor yalnız bu private tablolar için beklenen politikasız RLS bilgilendirmesi verdi; erişim kontrol edilmiş RPC üzerinden.
- iOS pilot 2.0.3 (108) fiziksel cihaz hedefiyle derlendi (`/tmp/nova-device-108.log`).

Fiziksel cihazda kullanıcının yeni kayıtlarıyla bütün formların görsel kabulü ayrıca yapılmalı. Android ve dosya yükleme bu teslimde tamamlandı sayılmıyor.

Cihaz teslimi: iPhone Kerem üzerine 2.0.3 (108) kurulumu başarılı.
