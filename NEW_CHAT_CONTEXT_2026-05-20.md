# RiskDetected Yeni Sohbet Kısa Bağlamı

Tarih: 2026-05-20  
Repo: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`  
Son commit: `ab9fd68 Prepare onboarding v2 and AI report updates`  
Önce oku: `PROJECT_STATUS_AND_NEXT_2026-05-12.md`, sonra gerekirse `PROJECT_HANDOFF.md`.

## Kritik Kimlikler

- Bundle ID: `com.riskdetected.app`
- Supabase URL: `https://ppcrzemgiztzcgddbins.supabase.co`
- Supabase callback: `io.supabase.riskdetected://login-callback`
- Google iOS URL scheme: `com.googleusercontent.apps.200539603330-p0o5ddmuqf1m7fobof5omtca28k0mk7b`
- GIDClientID: `200539603330-p0o5ddmuqf1m7fobof5omtca28k0mk7b.apps.googleusercontent.com`
- GIDServerClientID: `200539603330-52rbngma5qs4717qnhff1rgr3pu9rv5i.apps.googleusercontent.com`
- Legal canlı URL: `https://riskdetected.com/gizlilik`, `https://riskdetected.com/kullanim-kosullari`, `https://riskdetected.com/kvkk`
- ASO plan: App Store Name `RiskDetected İSG Analizi`, Subtitle `Fotoğrafla Risk Tespiti`, Keywords `isg,risk,analiz,iş,güvenliği,saha,denetim,rapor,fine,kinney,5x5,matris,kkd,pdf,excel`

## Mevcut Durum

- SwiftUI + Supabase + RevenueCat + Google/Apple/Email OTP auth + Gemini/Groq AI + PDF/XLSX raporlama.
- XcodeBuildMCP son build/run başarılı, warning yok.
- iPhone-only hedef; Bundle ID, target adı, auth callback ve OAuth ID'leri değiştirilmemeli.
- Google OAuth production, branding/legal URL/domain ayarları tamam.
- Email OTP/SMTP Resend ile canlı çalışıyor.
- RevenueCat/App Store ürün eşleşmeleri ve TL gösterimi kontrol edildi; restore/Pro/Plus testleri tamamlandı.

## Son Büyük Değişiklikler

- `App/RootView.swift`, `App/AppState.swift`: Onboarding V2 ilk kurulum akışına bağlandı.
- `App/Views/Onboarding/V2/`: yeni onboarding ekranları, onboarding içi Apple/Google/Email OTP, ayrı onboarding paywall.
- `App/Views/Onboarding/V2/Screens/OBAuthView.swift`: email/OTP paneli floating layer; klavye üstüne yerleşiyor. Son sorun: gerçek cihaz/simülatörde email ve OTP klavye davranışı tekrar dikkatli test edilmeli.
- `supabase/functions/analyze/index.ts`: AI routing güncel.
- `App/Services/PDFReportService.swift`: şirket logosu, dinamik PDF satır yüksekliği, `Sayfa X/Y`, sorumlu alanı düzeltmeleri.
- `supabase/functions/generate-excel-report/index.ts`: XLSX sorumlu alanı sabit: `İşveren/Vekili, Bölüm Yöneticisi`.
- `AppStoreScreenshots/` ve `.agents/skills/app-store-screenshots/`: App Store screenshot editor ve mevcut görseller eklendi.

## AI Hiyerarşisi

Free:
1. `gemini_primary + gemini-2.5-flash`
2. `gemini_secondary + gemini-2.5-flash`
3. `gemini_primary + gemini-3.1-flash-lite`, `thinkingLevel: medium`
4. `gemini_secondary + gemini-3.1-flash-lite`, `thinkingLevel: medium`
5. Tüm Free Gemini retryable hata/limit sonrası `groq_free_primary`

Plus/Pro:
1. `gemini_paid_primary + gemini-2.5-flash`
2. `gemini_paid_primary + gemini-2.5-pro`
3. `gemini_paid_primary + gemini-3.1-flash-lite`, `thinkingLevel: high`
4. `gemini_paid_secondary + gemini-2.5-flash`
5. `gemini_paid_secondary + gemini-2.5-pro`
6. Tüm Paid Gemini retryable hata/limit sonrası `groq_plus_pro_primary`

Kurallar:
- Free yalnız Free key pool kullanır.
- Plus/Pro yalnız Paid key pool kullanır; Paid secret/subscription lookup sorununda Free key'e düşmez, fail-closed olur.
- Free bulgu kırpması kaldırıldı; prompt hedefi 6-9 bulgu.
- Plus/Pro bulgu hedefi 11-14.

## Önemli Dosyalar

- Durum: `PROJECT_STATUS_AND_NEXT_2026-05-12.md`
- Handoff: `PROJECT_HANDOFF.md`
- Auth: `AUTH_SETUP.md`, `AUTH_LIVE_VERIFICATION_2026-05-12.md`
- Root/state: `App/RootView.swift`, `App/AppState.swift`
- Auth services: `App/Services/AuthService.swift`, `AppleSignInService.swift`, `GoogleSignInService.swift`
- Subscription: `App/Services/SubscriptionManager.swift`
- Analysis client: `App/Services/AnalysisService.swift`
- AI backend: `supabase/functions/analyze/index.ts`
- PDF: `App/Services/PDFReportService.swift`
- XLSX: `supabase/functions/generate-excel-report/index.ts`
- Onboarding V2: `App/Views/Onboarding/V2/`
- App Store docs: `QA/App_Store_Submission_Preparation_2026-05-16.md`, `QA/App_Store_Privacy_Nutrition_2026-05-16.md`
- AI QA: `QA/Free_Current_Prompt_Model_Retest_2026-05-20.md`, `QA/Free_Pro_Analysis_Comparison_Model_Update_2026-05-19.md`, `QA/Groq_Free_Pro_Comparison_2026-05-19.md`

## Kalan İşler

1. TestFlight clean install: Onboarding V2 -> Email OTP/Apple/Google -> onboarding paywall -> çarpı ile ana sayfa.
2. Onboarding email/OTP klavye davranışını gerçek cihazda tekrar doğrula.
3. Onboarding paywall'u sonradan onboarding cevaplarına göre kişiselleştir.
4. Destek formunda birden fazla ek desteği.
5. APNs production gerçek cihaz/TestFlight testi.
6. Final screenshot seti ve opsiyonel 15-30 sn app preview.
7. App Store Connect privacy nutrition ve metadata girişlerini finalleştir.
8. AI maliyet/kalite telemetry pass; context caching / batch API daha sonra.

## Dikkat

- Bundle ID, Supabase redirect URL scheme, Google OAuth client ID'leri değiştirme.
- `CFBundleDisplayName` ikon altında `RiskDetected` kalabilir.
- AI çıktılarında kesin uyumluluk/garanti dili kullanma; karar destek dili korunmalı.
- Raporlarda firma logosu varsa RiskDetected logosu yerine firma logosu görünmeli.
