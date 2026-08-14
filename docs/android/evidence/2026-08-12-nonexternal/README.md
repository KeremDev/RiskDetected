# Android dış bağımlılıksız kapanış kanıtı — 2026-08-12

Bu kayıt production runtime gate'i açmadan, yeni Gemini/FCM/RevenueCat çağrısı yapmadan ve iOS
`App/` kaynaklarını değiştirmeden tamamlanan yerel doğrulamaları belgeler.

## Otomatik kalite kapısı

- JDK: Temurin/OpenJDK 17 (`/opt/homebrew/opt/openjdk@17`)
- `testDebugUnitTest`: geçti; ana modüllerde toplam 114 test, sıfır hata
- `verifyRoborazziDebug`: 32 exact baseline, threshold `0`, geçti
- `lintDebug`: bütün Android modülleri geçti
- `:app:assembleDebug`: geçti
- `:app:verifyEnvironmentIsolation`: geçti
- `:app:verifyAndroidLegalBundle`: geçti
- Android kaynak secret/PII-log/`AD_ID` taraması: geçti
- iOS build-81 tag → çalışma ağacı `App/` diff'i: sıfır

Yeni otomatik kapsam:

- in-flight analiz kaydının store yeniden oluşturulmasından sonra devam etmesi
- süre aşımı, bozuk kayıt ve farklı hesaptan devam etmeme
- submission ID'nin yalnız aynı kullanıcı + aynı input fingerprint için tekrar kullanılması
- terminal durumların recovery kaydını temizlemesi; timeout/in-progress durumlarının koruması
- submit yanıtı kaybolduğunda yalnız okunabilir ve `pending` dışı server durumunun recovery sayılması
- Free/Plus/Pro detaylı analiz, fotoğraf, bulgu, saklama ve fail-closed capability matrisi
- FK ve 5×5 görünümünün doğru server skor/band alanını seçmesi
- bulgu düzenleme/silme capability kapısı ile metin, FK, 5×5 ve önlem patch doğrulaması
- Free günlük ve Plus/Pro aylık rapor kotasının `Europe/Istanbul` sınırı
- geçmiş analiz arama, kritik/KKD/hafta, şirket ve focused-ID filtre birleşimi
- risk analizi PDF bölüm sırası: yöntem referansı → risk değerlendirme tablosu; standart rapor
  kapak/bulgu sayfalarının bu rapora karışmaması
- risk tablosunda bulgu açıklaması, O/F/Ş veya O/Ş, server skoru/bandı, önlemler, kök neden ve
  mevzuat/referans alanlarının korunması

## API 36 emülatör smoke

APK: temiz kaynaklardan bu turda üretilen `app-debug.apk`.

- fresh install, onboarding ve UI-tree koordinatıyla `Atla → Yine de atla → bağımsız Auth`
- font scale `1.0`, açık sistem teması
- font scale `1.3`, koyu sistem teması; auth ekranının bilinçli açık-tema iOS paritesi korunuyor
- iki auth durumunda da e-posta ve Google CTA'ları ile dört hukuk bağlantısı UI tree'de mevcut
- crash buffer: boş

## Gerçek rapor artefaktı incelemesi

Yeni analiz veya ücretli API çağrısı yapılmadan, 11 Ağustos üç fotoğraf staging E2E'sinde üretilen
gerçek artefaktlar yeniden doğrulandı.

### Standart PDF

- Kaynak: `2026-08-11-staging-e2e/three-photo/generated-standard.pdf`
- Geçerli PDF, 3 gerçek sayfa, 915.412 byte
- Üç sayfanın tamamı PNG'ye rasterize edilip görsel incelendi
- Kapak, hazırlayan/odak/yöntem/tarih, 5 bulgu ve `2 kritik + 2 yüksek + 1 orta` dağılımı tutarlı
- Bulgu açıklaması, kaynak fotoğraf, AI güveni, kök neden ve önlemler eksiksiz
- Sayfa numaraları `1/2/3`; kırpılma, taşma veya bozuk karakter yok

Raster kanıtları `pdf-render/` altındadır.

### Risk analizi XLSX

- Kaynak: `2026-08-11-staging-e2e/three-photo/generated-risk-analysis.xlsx`
- Beş sayfa: Kapak ve Özet, Risk Analiz Tablosu, Risk Dağılımı, Metot Referansı, Rapor Bilgileri
- 5 bulgu, Fine-Kinney toplam skoru 4.950 ve `2 kritik + 2 yüksek + 1 orta` dağılımı tutarlı
- Ana tabloda O/F/Ş, skor, risk seviyesi, önlem/kontrol, kök neden, mevzuat/referans, termin ve durum
  alanları mevcut
- Firma ve hazırlayan metadata alanları mevcut; bu E2E firmasız üretildiği için firma değeri bilinçli boş
- Formül hata taraması sıfır; beş sayfanın tamamı render edilip görsel incelendi

Raster kanıtları ve PII içermeyen formül tarama sonucu `xlsx-render/` altındadır. İnceleme aracının
test kullanıcı/analiz kimliklerini içeren geçici özet çıktıları kanıt paketine alınmadı.

Dosyalar:

- `font-1.0-light.png` / `.xml`
- `auth-font-1.0-light.png` / `.xml`
- `auth-font-1.3-dark-system.png` / `.xml`
- `*-crash.log`

Fiziksel cihaz, gerçek yenilenmiş FCM token, Play billing, Play'den yeniden imzalanmış paket ve
mağaza/owner işlemleri bu kaydın kapsamı dışındadır.
