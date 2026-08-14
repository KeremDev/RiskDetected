# API 36 QA ADB Kanıtı

- Tarih: 10 Ağustos 2026
- APK: temiz kaynaklardan üretilmiş `app-qa.apk`
- Package: `com.riskdetectedan.app.qa`
- Cihaz: `emulator-5554`, `sdk_gphone64_arm64`
- API: 36
- Ekran: 1080 × 2400, 420 dpi
- Ana font scale: 1.0

## Geçen senaryolar

1. Fresh QA kurulumu onboarding başlangıç ekranını açtı.
2. `Atla` önce iOS ile uyumlu kayıp-fayda onayını gösterdi.
3. `Yine de atla` bağımsız giriş ekranına yönlendirdi.
4. Bağımsız giriş ekranında e-posta ve Google CTA'ları görüldü.
5. Android v1 kararı gereği Apple CTA'sı görünmedi.
6. Onboarding'e özel `Son adım.` ekranı skip sonrasında görünmedi.
7. Force-stop + cold relaunch sonrasında onboarding yerine bağımsız giriş ekranı korundu.
8. Font scale 1.3 durumunda e-posta ve Google CTA'ları görünür kaldı.
9. E-posta CTA'sı bağımsız e-posta giriş panelini açtı; adres alanı ve kod gönderme CTA'sı görünür kaldı.
10. Filtrelenmiş `ActivityTaskManager` / `AndroidRuntime` buffer'ında crash veya ANR işareti bulunmadı.

`adb-filtered-logcat.txt` yalnız sistem yaşam döngüsü ve crash tag'lerini içerir. Ağ, token,
e-posta, kullanıcı kimliği veya ham uygulama mesajı kaydedilmemiştir.
