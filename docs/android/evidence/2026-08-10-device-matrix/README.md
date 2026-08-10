# Android QA emülatör matrisi

Tarih: 10 Ağustos 2026

Final minified QA APK SHA-256: `67931585a5117ac58cf15402bce5a02545ae3dd71ff19e6f8efb66445ec2a39e`

Bu klasör temiz kurulumdan bağımsız giriş ekranına kadar olan release-kritik bootstrap smoke
kanıtını taşır. Her cihazda koordinatlar önceden sabitlenmedi; `uiautomator` XML ağacındaki
`Atla` ve `Yine de atla` düğmelerinin gerçek `bounds` değerlerinden hesaplandı.

## Matris

| Profil | API | Fiziksel çözünürlük | Yoğunluk | Akış |
| --- | ---: | ---: | ---: | --- |
| Nexus 4 / küçük | 26 | 768×1280 | 320 dpi | fresh install → Atla → onay → auth → cold relaunch |
| Pixel 5 / standart | 33 | 1080×2340 | 440 dpi | fresh install → Atla → onay → auth → cold relaunch |
| Pixel 9 Pro XL / büyük | 37 | 1344×2992 | 480 dpi | fresh install → Atla → onay → auth → cold relaunch |

Her klasörde başlangıç, atlama onayı, auth ve cold-relaunch için ekran görüntüsü ile UI tree;
ayrıca APK SHA-256, cihaz metadata'sı, filtrelenmiş logcat ve crash buffer bulunur. Test şu
sözleşmeleri fail-closed doğrular:

- bağımsız auth ekranında e-posta ve Google CTA'ları vardır;
- Android v1'de Apple CTA'sı yoktur;
- onboarding'e özel `Son adım.` ekranı skip veya cold relaunch sonrasında açılmaz;
- crash/ANR işareti yoktur.

Tekrarlanabilir koşu:

```sh
android/scripts/capture_qa_emulator_smoke.sh <serial> <etiket> <kanıt-klasörü>
```

Bu paket fiziksel Pixel/Samsung, Google hesaplı Credential Manager ve giriş yapılmış gerçek
staging analiz/rapor testlerinin yerine geçmez; onlar ayrı release kapılarıdır.
