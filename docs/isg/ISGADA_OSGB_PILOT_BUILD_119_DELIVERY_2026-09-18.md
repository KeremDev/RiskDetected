# İSGADA OSGB Pilot — Build 119 Teslim Notu

Tarih: 18 Eylül 2026

Ortam: OSGB staging (`qlymhrrlhklcudveknih`)

Uygulama kimliği: `com.riskdetected.app.osgbpilot`
Build: `119`

## Ürün düzeltmeleri

- Tek firmalı OSGB çalışma alanlarında firma otomatik seçiliyor. Firma seçilmediği için pasif kalan eğitim, personel ve operasyon modülleri açılıyor.
- Firma ekleme/düzenleme formu firma adı ve tehlike sınıfının yanında sektör, e-posta, çalışan sayısı, adres ve isteğe bağlı sorumlu kişi bilgilerini kaydediyor.
- Firma formunun ana işlemi `Firmayı kaydet`; personel metni firma akışından çıkarıldı.
- Firma kartında tehlike sınıfı, sektör ve beyan edilen çalışan sayısı birlikte gösteriliyor.
- Eğitim formu firma personelini arayıp birden çok katılımcı seçebiliyor; eğitmen, yöntem, konum, başlangıç, süre, geçerlilik ve not alanlarını kaydediyor.
- Eğitim, periyodik kontrol, uygunsuzluk ve diğer workspace kayıtlarında API enum/değerleri Türkçe ürün metinlerine dönüştürülüyor.
- Operasyon sayfalarındaki özetler ortak dört kartlık istatistik düzenine alındı. Eğitimde eğitim saati, eğitim alan kişi, adam × saat ve eğitimi eksik kişi öne çıkarılıyor.
- Personel ileri kayıtlarındaki ham İngilizce durum adları Türkçe gösteriliyor.

## Staging veri katmanı

- `20260918010000_osgb_company_profile_product_parity.sql` staging'e uygulandı.
- Firma profili tenant ve firma kapsamlı, RLS korumalı, idempotent ve eski firma kayıtlarıyla geriye uyumlu çalışıyor.
- Profil değişiklikleri mevcut `company` denetim/outbox varlık türünü kullanıyor. İlk gerçek kayıt denemesinde bulunan geçersiz `company_profile` türü düzeltilerek işlem geri alma hatası kapatıldı.
- Pilot örnek firmaya sektör ve çalışan sayısı profili kaydedildi ve liste RPC'sinden tekrar okundu.
- Personel dizini başlatıldı; örnek personel ve bir katılımcılı planlı eğitim kaydı oluşturuldu. Eğitim liste ve metrik RPC'leriyle sonuç doğrulandı.

## Doğrulama

- `node --test scripts/isg/*.test.mjs`: geçti.
- Kritik manifest, firma profili, workspace API ve store testleri: 15/15 geçti.
- iOS simülatör Debug derlemesi: geçti.
- Fiziksel iPhone Debug derlemesi, imza doğrulaması ve kurulum: geçti.
- Telefonda kurulu uygulama: `İSGADA`, bundle `com.riskdetected.app.osgbpilot`, build `119`.
- Üretim projesine migration veya rollout değişikliği uygulanmadı.

Telefon ekranı kilitli/kapalı olduğu için uzaktan ön plan açma çağrısı zaman aşımına uğradı; build başarıyla kuruldu ve cihaz uygulama envanterinde 119 olarak doğrulandı.
