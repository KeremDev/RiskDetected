# NOVA telefon teslimi — 2.0.3 (97)

14 Eylül 2026.

- Yeni `NOVA_PILOT_BUILD` kaynak düzenlemeleriyle cihaz Debug build'i alındı; `com.riskdetected.app` mevcut uygulamanın üzerine iPhone Kerem'e kuruldu ve açıldı.
- Firmalar ve personel başlığındaki ekleme düğmeleri genişletildi, içerik başlığı ile NOVA header arasına nefes alanı eklendi.
- Popup üstündeki gereksiz başlık boşluğu azaltıldı; X kapatma düğmesi korunarak popup içeriği daha sıkı hale getirildi.
- Firma kartı sade gri yüzeye taşındı. Accordion açıldığında yalnız başlık satırı gri, tüm accordion kartı siyah çerçeveli görünür.
- Menüden/tab'dan Firmalar seçimi, açık firma detay kapsamını temizleyerek firma listesine döner.
- Canlı mevcut veriler, migration, allowlist ve izinler değiştirilmedi. Yeni görsel düzenlemeler pilot UI kapsamındadır.

## Kanıtlar

- `output/isg/pilot/DeviceBuild97.xcresult`
- `output/isg/pilot/device-build-97.log`
- `output/isg/pilot/device-install-97.json`
- `output/isg/pilot/device-launch-97.json`
- `output/isg/pilot/device-app-97.json`

## Sınır

Kullanıcı isteğiyle test koşusu çalıştırılmadı; teslim build, imza, kurulum, açılış ve cihaz sürüm doğrulamasına dayanır.
