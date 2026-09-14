# NOVA cihaz teslimi — build 98

Tarih: **14 Eylül 2026**
Dal: `codex/isg-transition-foundation`
Cihaz: **iPhone Kerem** (`F8EB649B-8963-59F6-90D0-CE4176B7D1DE`)

## Teslim sonucu

NOVA pilot tasarımının build 98 sürümü başarıyla derlendi, imzalandı, iPhone Kerem’e kuruldu ve başlatıldı. Bundle sürümü `98`, uygulama sürümü `2.0.3` olarak doğrulandı.

Bu turda:

- Ana firma çalışma alanı akordeonlarının önceki daha ferah kart yüksekliği geri getirildi.
- Açık ana başlıklarda çerçeve koyu griye alındı.
- Firma Bilgileri içindeki Firma Logosu ve Personel Listesi gibi nested satırlarda ikinci çerçeve kaldırıldı.
- Popup içerikleri için üstte makul başlık boşluğu ayrıldı; yuvarlak X kapatma düğmesi sağ üstte korunarak başlık/ekle aksiyonlarının üst üste binmesi önlendi.

Kullanıcı isteği doğrultusunda tam test paketi çalıştırılmadı; yalnızca build, imza, cihaz kurulumu ve başlatma doğrulandı. Canlı veriler ve backend değişmedi.

## Kanıtlar

- Build logu: `output/isg/pilot/device-build-98.log`
- Result bundle: `output/isg/pilot/DeviceBuild98.xcresult`
- Kurulum çıktısı: `output/isg/pilot/device-install-98.json`
- Başlatma çıktısı: `output/isg/pilot/device-launch-98.json`
- Cihaz uygulama bilgisi: `output/isg/pilot/device-app-98.json`
- Uygulama: `output/isg/pilot/DeviceDerivedData98/Build/Products/Debug-iphoneos/RiskDetected.app`
