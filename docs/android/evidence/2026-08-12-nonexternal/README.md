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

## API 36 emülatör smoke

APK: temiz kaynaklardan bu turda üretilen `app-debug.apk`.

- fresh install, onboarding ve UI-tree koordinatıyla `Atla → Yine de atla → bağımsız Auth`
- font scale `1.0`, açık sistem teması
- font scale `1.3`, koyu sistem teması; auth ekranının bilinçli açık-tema iOS paritesi korunuyor
- iki auth durumunda da e-posta ve Google CTA'ları ile dört hukuk bağlantısı UI tree'de mevcut
- crash buffer: boş

Dosyalar:

- `font-1.0-light.png` / `.xml`
- `auth-font-1.0-light.png` / `.xml`
- `auth-font-1.3-dark-system.png` / `.xml`
- `*-crash.log`

Fiziksel cihaz, gerçek yenilenmiş FCM token, Play billing, Play'den yeniden imzalanmış paket ve
mağaza/owner işlemleri bu kaydın kapsamı dışındadır.
