# Google Play kapalı test — RiskDetected 2.0.0 (9)

- Paket: `com.riskdetectedan.app`
- Kanal: Closed testing / kapalı test
- Sürüm adı: `2.0.0 (9) — Kapalı Test`
- Artifact: minify edilmiş ve upload key ile imzalanmış `app-release.aab`
- Üretim veya açık test yayını: bu paket kapsamında yapılmayacak
- Release notes: aynı klasördeki Türkçe ve İngilizce metinler
- Native debug symbols ve `mapping.txt`: AAB ile birlikte saklanacak/yüklenecek
- Play pre-launch report tamamlanmadan daha geniş kanala çıkılmayacak
- Test grubu yorumları bulgu, analiz, rapor, onboarding ve ödeme giriş noktası bazında izlenecek
- Build 9 mağazada işlenip tester erişimi doğrulanmadan `android_release_policy.latest_build` 9 yapılmayacak

## Yükleme sonrası doğrulama

1. Play Console artifact özetinde `versionCode=8`, `versionName=2.0.0` değerlerini doğrula.
2. App Signing sertifikası ile upload sertifikasının beklenen zincirde olduğunu doğrula.
3. Kapalı test grubuna sürümü yayınla; production/açık test seçme.
4. Fiziksel Android cihazda Play üzerinden güncelleme/temiz kurulum, Google girişi, analiz, dört sonuç bölümü, geri bildirim, rapor ve satın alma akışını doğrula.
5. Crash/ANR, analiz başarısızlığı, paywall giriş kaynağı ve bulgu geri bildirimlerini izleyerek test grubu dönüşlerini kaydet.
