# NOVA telefon teslimi — 2.0.3 (96)

14 Eylül 2026.

- `com.riskdetected.app`, **iPhone Kerem / iPhone 17 Pro Max** üzerinde mevcut uygulama kaldırılmadan build 96 olarak güncellendi.
- Cihaz derlemesi `NOVA_PILOT_BUILD` ile üretildi; `NOVAPilotOwnerID` hesabı `f3be34f9-6707-46d3-b827-a7dbcdfe1f66` ile sınırlandı.
- Uygulama cihazda başarıyla başlatıldı ve açık tema zorlaması korunuyor. Bu teslim eski ana uygulama ekranı değil, NOVA pilot tasarımıdır.
- Bu pakette kompakt firma/personel akışları, heading yanındaki ekleme düğmeleri, merkez popup X kapatma, iki durumlu renkli rozetler, dinamik skor halkası, görev alanı ve opsiyonel sicil no görsel formu bulunur.
- Kullanıcı tarafından özellikle ertelenen sunucu bağlantıları (bazı görsel düzenleme/silme ve yeni modül kayıtları) bu build'de yazma yapmaz; canlı mevcut veriler değiştirilmedi.

## Kanıtlar

- `output/isg/pilot/DeviceBuild96.xcresult`
- `output/isg/pilot/device-build-96.log`
- `output/isg/pilot/device-install-96.json`
- `output/isg/pilot/device-launch-96.json`
- `output/isg/pilot/device-app-96.json` (cihazdaki bundle/version doğrulaması)
- `output/isg/pilot/device-processes-96.json` (başlatılan süreç doğrulaması)

## Sınır

Tam UI test koşusu onboarding ekranında takıldığı için kullanıcı isteğiyle durduruldu; bu nedenle bu teslim cihaz build/install/launch kanıtıdır, tam XCUI geçiş iddiası değildir.
