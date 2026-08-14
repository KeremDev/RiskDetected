# Android uygulama ikonu kabul kaydı

Tarih: 10 Ağustos 2026

Kullanıcı tarafından sağlanan 1254×1254, opak, kare ve full-bleed PNG Android ikon master'ı
olarak kabul edildi. iOS `App/` kaynakları değiştirilmedi.

Üretilen çıktılar:

- Launcher full-bleed master: `android/app/src/main/res/drawable-nodpi/rd_app_icon.png` — 1024×1024
- Adaptive foreground: `android/app/src/main/res/drawable-nodpi/rd_app_icon_foreground.png` — 1024×1024 RGBA, nesne sınırı `(192, 231)–(832, 817)`
- Play master: `android/play-store/riskdetected-play-store-icon-master-1024.png` — 1024×1024
- Play upload: `android/play-store/riskdetected-play-store-icon-512.png` — 512×512
- Android 13+ monochrome: baret ve denetim panosu silueti

1024×1024 master SHA-256:
`721237148e86b40fac8ed290146ed71a24f9782857c490dd17ef84b6308b15bf`

512×512 Play ikonu SHA-256:
`8e2c978d8cfb6dcfb60a151b34a55b60618ef594e1d91ae2733473a7543eb932`

Adaptive foreground SHA-256:
`cc8219740803c4d6463fbd06350b574ec7683edae981d60c4939febbd61d3a38`

`android-icon-mask-preview.png` circle, squircle ve rounded-square launcher maskelerini;
`android-icon-60px.png` ise küçük-boyut okunabilirlik kontrolünü gösterir. Beklenmeyen kırpılma,
şeffaf köşe veya ikon içine gömülmüş yuvarlatma bulunmamaktadır.

`api36-launcher.png` debug APK'nın gerçek Pixel Launcher çekimidir. İlk full-bleed foreground
denemesinde Android'in ek zoom'u baret altını kırptığı için foreground safe-zone içine alınmış ve
çekim yeniden üretilmiştir; final görüntüde baret ile denetim panosunun tamamı görünür.

İkon değişikliğinden sonra temiz kalite kapısı 655 Gradle göreviyle geçti. Minified QA çıktıları:

- AAB SHA-256: `a61cb977a909b53d7150080334a8ac9c5a6f8864b67e817fad10b12f38a228a7`
- APK SHA-256: `011a57af4b4230ceecb7bd8e614e067073054d80fb86e2a4d28a853b970b4c34`
- Native symbols SHA-256: `13f93498c65e6a23f7327b62e52b2c62e7c017a0ec0dc5f1aeac2d2fd8a798a1`

Bundletool doğrulaması, JAR imzası, 16 KB zip/ELF hizalaması, QA Firebase anahtar allowlist'i,
iOS asset sızıntısı ve APK source-secret/PII-log/`AD_ID` taraması geçti.
