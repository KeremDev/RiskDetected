# Eğitim EDU-1.0 teslim kontrolü

Kapsam otoritesi: bu task içindeki kullanıcı onaylı uygulama planı. Kaynak şartnamenin sınav/yoklama/toplu çıktı ve imzalı arşiv maddeleri kapsam dışıdır; geçmiş sayılmamıştır.

## Uygulananlar

- Kullanıcı kaydı olarak gerçekleşmiş tek eğitim; firma/işyeri/görev/döngü kapsamları ve kararlı firma alt kayıtları.
- Altı profil, resmî 21 konu, G4 başlangıç içerikleri, tam sayı dakikalar, alt konular, kaynak checksum, idempotent katalog.
- Kişisel belge ön kontrolü, numarasız TASLAK, değişmez belge snapshot ve revizyonları, genel kapsam/yıl numarası.
- iOS müfredat, personel ve eğitici editörü; ders/gün/ara dağılımı; hesap bazında Keychain taslağı ve kalıcı mutation kimliği.
- iOS ön–arka PDF, Mulish font, uzun içerik devamı, çift taraflı boş sayfa, kişisel önbellek, kaydet/paylaş/yazdır.
- Android aynı v3 API üzerinde kapsam editörü ve kişi bazlı PDF karşılığı; hesap bazında şifreli taslak/işlem depolama.
- Mevcut güvenli firma logosundan alınan küçük PNG belge snapshot'ına sabitlenir. Logo bulunamazsa belge üretimi sürer.

## Çalıştırılan doğrulamalar

- `node scripts/education/run_database.mjs`: bağımsız, ağsız ve geçici PostgreSQL 17 konteynerinde dar migration + pozitif/negatif kayıt/sertifika kabul senaryoları.
- `node scripts/education/run_render.mjs`: gerçek sunucu test snapshot'larının Swift Codable ile çözülmesi, on normal iki sayfalık PDF, uzun altı sayfalık PDF, üç logo oranı, Türkçe metin, İstanbul gece yarısı gün ayrımı ve 370 dakika = 8 ders kontrolü.
- iOS simulator Debug + NOVA_PILOT_BUILD: derleme başarılı.
- Android `:app:assembleDebug` ve dört `EducationRulesTest`: başarılı. APK: `android/app/build/outputs/apk/debug/app-debug.apk`.
- PDF ön/arka sayfaları görsel olarak kontrol edildi.

## Canlı/pilot

Dar migration canlı pilotta uygulandı ve tek hesap için katalog/sertifika kontrolleri açıldı. Ana migration klasörü topluca uygulanmadı. Geçiş kanıtı aşağıdadır; fiziksel paylaşma/yazdırma kabulü ayrıca belirtilir.

## Bilinen kabul sınırları

- Fiziksel iPhone yazıcı hedefi ve gerçek paylaşım alıcısı cihaz üzerinde kullanıcı kabulü gerektirir. Paylaşmak imzalandı veya görüldü kaydı oluşturmaz.
- Sunucu rol/transaction probe'u gerçek HTTP/JWT veya kullanıcı cihaz kabulü yerine sunulmaz.
- PDF byte paritesi aranmaz; kişisel veri/alan/süre ve sayfa düzeni karşılaştırılır.
- Sınav, yoklama, tarama, imzalı nüsha arşivi, toplu PDF ve bulut PDF upload hattı kapsam dışıdır.

## 14 Eylül canlı pilot sonucu

- Migration ledger: `20260914130700` → `20260914162507_isg_education_curriculum_certificates`.
- Candidate / pilot mirror SHA256: `ed294dc184c4498dab7261fb30efe4d7cd6d69ff67a8b2d962e928a06cd34d6b`.
- Önce/sonra: 1 mevcut eğitim; session hash `025f142ef6b689c4a55b95c4016b7e6d`, kayıt hash `246b164810440f6342be3cec70734ba1`, personel hash `2fa77a599b6a0555ddbc691ba8351d25` değişmedi.
- Authenticated rol ile yeni kayıt, sertifika, tekrar gönderim, kararlı firma kimliği ve eski belge sürümü kontrolü geçti. Bütün test yazmaları ROLLBACK; canlı sertifika sayısı 0 olarak kaldı.
- Mevcut pilot hesabı sayısı 1 doğrulandıktan sonra katalog ve sertifika kontrolleri açıldı. P05 hesap/firma ve abonelik kapıları korunur; genel kullanıma açılmadı.
- Anon sertifika RPC erişimi ve authenticated doğrudan document_versions okuması kapalı.
- Android dört süre/dağılım birim testi geçti; APK üretildi. API 33 emülatöründe sekiz sunucu snapshot'ının iki sayfalık çıktısı, metin çizimi, aynı kişisel önbellek ve uzun çift taraflı çıktı testi geçti.
- Android derlemesini engelleyen mevcut eksik üç menü ikonu eşlemesi ve 32 İngilizce kaynak karşılığı tamamlandı; doğrulama kapısı atlanmadı.
- Auth/restore, abonelik, mevcut P07 eğitim yolu ve session host için 43 odaklı regresyon kontrolü geçti. Analiz/kota ve istemci akış sözleşmesi için 11, personel dizini ve işlem depolama için 40 ek kontrol geçti.

- İki ayrı PostgreSQL bağlantısında eşzamanlı, farklı firmalara belge üretimi farklı numaralar verdi.
- iOS ve Android PDF ön/arka düzeni görsel olarak karşılaştırıldı; imza alanları, Türkçe font ve devam sayfaları kontrol edildi.

## Fiziksel iOS teslimi

- iOS **2.0.3 (101)** son kaynaklarla derlendi, fiziksel iPhone’a kuruldu ve `devicectl` ile başarıyla açıldı.
- Açılış, kurulum ve paket sürümü doğrulandı; telefonda eğitim kaydetme → kişi seçme → paylaşma/yazdırma zincirinin kullanıcı kabulü henüz yapılmadı.
- Sentetik örnek belge: `artifacts/education/certificate-0.pdf`. Makinece okunabilir sonuç: `artifacts/education/verification-summary.json`.
