# RiskDetected Yeni Sohbet Kısa Bağlamı

Tarih: 2026-05-20  
Repo: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`  
Son commit: `Add company flows and welcome email automation`
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

- 2026-05-20 canlı backend: `20260520161706_add_root_cause_and_ai_usage_telemetry.sql` production Supabase DB'ye uygulandı; remote/local migration listesi eşit.
- 2026-05-20 canlı Edge Functions: `analyze` version 76, `generate-excel-report` version 30 deploy edildi.
- `supabase/functions/analyze/index.ts`: prompt mimarisi parçalandı; sabit `CORE_ANALYSIS_PROMPT` korunuyor, onboarding/company/tier context ayrı küçük bloklar olarak modele gidiyor.
- Onboarding cevapları analiz context'ine kontrollü şekilde giriyor; görsel kanıtı filtrelemiyor, sadece öncelik/ton/derinlik etkiliyor.
- Tier davranışı güncel: Free references/root cause üretmez; Plus kısa references + kısa root cause; Pro daha kapsamlı references + teknik root cause üretir.
- `findings.root_cause_text` ve `ai_usage_logs` prompt/personalization/context/cache/thinking/token telemetry kolonları canlı DB'de doğrulandı.
- iOS tarafında `FindingRow`/`Finding` root cause alanı, sonuç detay/kart, PDF ve Excel raporlarında "Kök neden" görünürlüğü eklendi; Plus için de kısa referans ve kök neden görünür.
- Çoklu firma backend'i canlıda: `companies`, `analyses.company_id`, `reports.company_id`, `reports.company_snapshot`; `analyze` ve `generate-excel-report` firma doğrulama, prompt context ve report snapshot destekli.
- Çoklu firma iOS UI'sı lokal build'de hazır: Profil > Firmalarım, analiz öncesi firma seçimi, rapor firma seçimi, analiz/rapor firma filtreleri. Kullanıcı cihazına görünmesi için yeni TestFlight/App Store build'i dağıtılmalı.
- Firma RLS production fix canlıda: `private.company_limit_for_user(uuid)` için `authenticated` execute grant eklendi; `Firmalarım` ekranındaki `permission denied for function company_limit_for_user` hatası giderildi.
- İlk üyelik hoş geldin maili backend'i canlıda: `send-welcome-email` Edge Function Resend ile gönderir, onboarding cevaplarına göre kısa kişiselleştirme ekler ve `profiles.welcome_email_*` alanlarıyla idempotency sağlar.
- RevenueCat Plus/Pro plan yansıması düzeltildi: `PRODUCT_CHANGE` webhook'u `new_product_id` esas alır; iOS ve sync function aktif subscription product ve en güncel purchase tarihine göre tier çözer.
- Profil dark tema polish yapıldı: avatar, istatistik kartları, liste yüzeyleri, ikon arka planları ve Pro kart vurgusu dark mode'da daha koyu/mat hale getirildi.
- `App/RootView.swift`, `App/AppState.swift`: Onboarding V2 ilk kurulum akışına bağlandı.
- `App/Views/Onboarding/V2/`: yeni onboarding ekranları, onboarding içi Apple/Google/Email OTP, ayrı onboarding paywall.
- `App/Views/Onboarding/V2/Screens/OBAuthView.swift`: email/OTP paneli floating layer; klavye üstüne yerleşiyor. Gerçek cihazda email ve OTP klavye davranışı doğrulandı.
- `App/Views/Onboarding/V2/OnboardingViewV2.swift`: Onboarding `Atla` linki artık üzgün yüz ikonlu onay ekranı gösteriyor; onaylanırsa onboarding bitip auth/main akışına geçiyor.
- `App/Views/Onboarding/V2/OnboardingViewV2.swift`: Onboarding V2 color scheme light'a kilitlendi; global dark mode ayarından etkilenmez.
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

1. Yeni iOS build'i TestFlight/App Store'a dağıt: çoklu firma UI'sı, root cause/references görünürlüğü, hoş geldin maili iOS tetikleyicisi, RevenueCat Plus/Pro UI fix'i ve profil dark tema polish'i cihazlara ancak yeni build ile görünür.
2. Onboarding paywall'u sonradan onboarding cevaplarına göre kişiselleştir.
3. Hoş geldin maili için TestFlight yeni kullanıcı uçtan uca testi yapılacak: onboarding cevapları + mail teslimi + tekrar girişte duplicate olmaması.
4. Bildirimler ile ilgili tüm akışları gözden geçir: izin, cihaz token kaydı, kullanıcı tercihleri, APNs backend triggerları ve TestFlight teslimatı.
5. Analiz başlatıldıktan sonra kullanıcı uygulamadan çıksa bile backend tarafında analiz devam etmeli; analiz tamamlanınca push bildirim gönderilmeli ve uygulama açıldığında sonuç senkron görünmeli.
6. Termin tarihi ve sorumlu alanları için ürün kararı verilecek: kullanıcı serbest mi girecek, varsayılan/sabit mi gelecek, yoksa firma/profil bazlı mı önerilecek.
7. Onboarding ve uygulama içi bazı metin/sloganlarda revizyon yapılacak.
8. Onboarding cevaplarına göre farklı paywall sayfaları veya paywall varyasyonları gösterilecek.
9. APNs production gerçek cihaz/TestFlight testi.
10. Final screenshot seti ve opsiyonel 15-30 sn app preview.
11. App Store Connect privacy nutrition ve metadata girişlerini finalleştir.
12. AI maliyet/kalite dashboard'u: yeni telemetry kolonları üzerinden cache hit, token, fallback, latency ve prompt version/hash takibi.

## Dikkat

- Bundle ID, Supabase redirect URL scheme, Google OAuth client ID'leri değiştirme.
- `CFBundleDisplayName` ikon altında `RiskDetected` kalabilir.
- AI çıktılarında kesin uyumluluk/garanti dili kullanma; karar destek dili korunmalı.
- Raporlarda firma logosu varsa RiskDetected logosu yerine firma logosu görünmeli.
