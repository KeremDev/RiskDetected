# Firma ve portföy süreç takibi

15 Eylül 2026. Yeni kayıt modülleri firma detayı, ana sayfa ve istatistik ekranına ortak bir takip projeksiyonuyla bağlandı.

## Ekranlar

- Firma detayında Süreçler ve Takip: KATİP, yıllık plan ve faaliyetleri, kurul ve kararları, ziyaret, çalışma izni, taşeron, acil durum, tatbikat, atama, KKD için 12 ayrı kayıt özeti. Bekleyen, tarihi geçmiş, 30 günde yaklaşan, süre bilgisi eksik ve sonraki tarih ayrı gösterilir. En fazla dört satırla açılır, tümü genişletilebilir.
- Mevcut temsilci/destek, acil durum, kurul, zimmet başlıklarında modülü açma ve kayıt sayıları. Atama sayısı toplam atama sayısıdır, temsilci yeterlilik sayısı değildir. Acil durum içinden tatbikata da giriş vardır.
- Firma içinde açılan acil durum/tatbikat/atama/KKD akışları seçili firmayı korur. Yeni kayıt popup'ı firmayı otomatik yükler, firma değiştirmeyi sunmaz. Ortak süreç gate'i zaten firma kapsamını kilitler.
- Ana sayfada aynı modüllerin portföy toplamları ve işlem girişleri; istatistikte seçili firma veya tüm firmalarla aynı projeksiyon. Bunlar güncel kayıt sayılarıdır; istatistikteki dönemsel etkinlik grafiği ile karıştırılmaz.
- Mevcut eğitim, risk, ekipman ve evrak özetleri kendi servislerini kullanmaya devam eder. Bu RPC bunların hukuki yükümlülük motoru veya birleşik skoru değildir.

## Otomatik güncelleme

Kayıt kaydet/düzenle/sil/işlem sonrası oturum doğrulanmış başarılı mutation ortak `isgada.records.changed` olayını yalnız hesap kimliğiyle yayınlar. Yeni takip kartları, firma özeti, ana sayfa ve istatistikler tekrar okur. Eğitim v3 kayıt başarısı da aynı sinyali yayınlar. Modülden geri dönme, uygulamanın öne gelmesi ve yenile düğmesi güncel sunucu hesabını alır. İstatistikte takip kartı yükleme sırasında da hiyerarşide kalır; alt form kendiliğinden kapanmaz.

Sunucu sayıları okuma anında hesaplar: tamamlanan faaliyet bekleyen/gecikmiş listesinden çıkar; silinen kayıt/ebeveyn özetlerden çıkar; eski acil durum sürümleri çift sayılmaz. Bağlı kaydı değiştirmek başka modülün durumunu otomatik tamamlamaz. Yeni puan veya yasal uygunluk kararı üretilmez. Bu otomasyon veri/ekran güncellemesidir; APNs/FCM hatırlatma dağıtımı bu dilimin parçası değildir.

## Sunucu ve doğrulama

- `isg_pilot_module_tracking_v1(p_company)` yeni dar read API. Aktif kullanıcı, pilot ve firma sahipliği; arşivlenmiş firma hariç. Modül okuma anahtarı kapalıysa null sayaç ve available=false; yanlış sıfır yok.
- Canlı migration `20260914225615_isg_pilot_module_tracking.sql`, kaynak aday `20260915090001`. SHA256 `43a15ca13e2e9394a3054fd7f44f66b940d4026f12643b15ce9579f0a95e6a69`.
- `node scripts/modules/run_pilot.mjs` PASS: mevcut modül regresyonları + takip sayısı, gerçekleşmede bekleyen sayısının düşmesi, kapalı kaynak ve başka firma/portföy izolasyonu.
- Canlı gerçek pilot oturum bağlamında portföy okuma ve firma sahipliği assertion'ları PASS. Test yazması yapılmadı.
- Değişen Swift kaynaklarında parse ve git diff whitespace kontrolü PASS. Tam Xcode derlemesi lisans onayı nedeniyle başlatılamadı; build/telefon kabulü yapılmış sayılmaz. Fiziksel kaydet→geri dön→sayaç ve çok cihazdan öne dönme kabulü bekliyor.
