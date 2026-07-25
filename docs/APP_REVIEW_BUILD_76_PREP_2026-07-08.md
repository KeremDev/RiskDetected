# App Review Build 76 Prep

RiskDetected iOS version `1.2.3` build `76` App Review hazırlık notudur.

## Değişiklik Özeti

- Yeni analizler yalnızca fotoğraf yükleme veya kamera çekimiyle başlatılır.
- Metinle analiz girişi uygulama arayüzünden kaldırıldı.
- Eski build'lerden gelen metin analizi istekleri backend'de `TEXT_ANALYSIS_REMOVED` hatasıyla hızlı reddedilir; kota tüketmez ve kuyruğa girmez.
- Geçmiş metin analizleri kullanıcı arayüzünde gizlenir; veri dışa aktarma ve hesap silme kapsamı korunur.
- Standart PDF kapak görselleri küçültülerek rapor oluşturma süresi ve dosya boyutu kontrol altında tutulur.
- Build `76`, mevcut build-gated çoklu fotoğraf allowlist akışına eklenir.

## App Review Notes Taslağı

```text
RiskDetected is an occupational safety risk analysis app. Users upload or capture field photos, select the analysis scope, and receive AI-assisted safety findings, risk scores, and PDF/XLSX reports. The AI output is decision support only and does not replace a certified occupational safety professional, official inspection, legal advice, or engineering assessment.

Version 1.2.3 (build 76) removes text-only analysis from the app. New analyses are photo-based only. Legacy text-analysis requests from older builds are rejected server-side with an update message and do not consume quota.

External services used: Supabase for authentication, database, storage, edge functions, and account deletion; Google AI/Gemini and Groq fallback for AI analysis; RevenueCat and Apple App Store for subscription entitlement management; APNs for notifications; Apple Sign-In and Google Sign-In for authentication.

The app functions consistently across supported regions. If a demo account is required, use the App Review test account provided in App Store Connect review information.
```

## What's New Taslağı

```text
Analiz akışı sadeleştirildi: yeni analizler artık fotoğrafla başlatılır. Rapor oluşturma performansı ve App Review hazırlığı için altyapı iyileştirmeleri yapıldı.
```

## Manuel Kontroller

- App Store Connect review information içinde geçerli demo/test hesabı bulunduğunu doğrula.
- App description içinde Terms of Use ve Privacy Policy linklerinin çalıştığını doğrula.
- Paywall ekranlarında abonelik adı, süre, fiyat, gizlilik ve şartlar linklerinin göründüğünü doğrula.
- Privacy nutrition cevaplarında fotoğraf/kullanıcı içeriği, hesap, abonelik ve destek verilerinin mevcut ürün kapsamına uygun kaldığını doğrula.
- Screen recording'i gerçek cihazda güncelle: kayıt, fotoğrafla analiz başlatma, sonuç, rapor oluşturma, paywall ve hesap silme yolunu göstermeli.
