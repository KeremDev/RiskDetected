# RiskDetected Yeni Sohbet Handoff - 2026-05-25

Bu dosya yeni sohbet penceresine aktarılacak kısa bağlamdır. Detay arşiv dosyaları: `NEW_CHAT_CONTEXT_2026-05-20.md`, `PROJECT_STATUS_AND_NEXT_2026-05-12.md`, `QA/Hybrid_QA_2026-05-22.md`.

## Proje Özeti

- iOS SwiftUI uygulaması: RiskDetected, saha fotoğrafı/metin üzerinden İSG risk analizi, PDF/XLSX rapor, rapor arşivi, firma bazlı takip.
- Backend: Supabase DB, RLS, Storage, Edge Functions, pgmq/Queues, Resend, APNs, RevenueCat webhook/sync.
- Auth: Email OTP, Apple, Google. Onboarding V2 içinde auth akışı var.
- AI: Gemini/Groq routing; Free/Plus/Pro davranışı ayrılmış. Paid analizlerde `gemini-2.5-flash`, `thinkingBudget: 1024`.
- Release odağı: TestFlight gerçek cihaz QA, abonelik görünümü, push, firma akışı, onboarding/paywall polish.

## 2026-05-27 Güncel Durum

- GitHub repo oluşturuldu:
  - `https://github.com/KeremDev/RiskDetected`
  - Remote: `origin`
  - Branch: `main`
- Son commit:
  - `1b000b1 Prevent fallback subscription sync downgrades`
- Önceki büyük progress commitleri:
  - `ebc25ed Polish professional progress UI`
  - `c294f0c Add professional progress module`
- Supabase migration durumu remote'da hizalı:
  - `20260526163303_professional_progress_weekly_tracking.sql`
  - `20260526184023_profile_avatars.sql`
- `sync-revenuecat-subscription` remote'a deploy edildi.
- Plus limit bug'ı düzeltildi:
  - RevenueCat fallback sync artık aktif backend Plus/Pro aboneliğini geçici/free RevenueCat cevabıyla downgrade etmiyor.
  - Simulator'da Plus kullanıcı `Rapor Oluştur` sheet'i kontrol edildi; yanlış `LİMİT DOLDU` görünmüyor.
- Fiziksel cihaz build/install/launch geçti:
  - Kerem iPhone, iPhone 14 Pro Max.
  - Debug iPhoneOS build başarılı.
  - App cihaza yüklendi ve launch edildi.
- Profil avatar QA:
  - Simulator'da fotoğraf seçme çalıştı.
  - Daire içinde crop/ortalanma doğru.
  - Plus taç rozeti doğru.
  - Backend'de `avatar_url` yazıldı ve `avatars` storage objesi oluştu.
- Paid Firmalarım backend/RLS QA:
  - Free ekleme engelli.
  - Plus ekle/düzenle/arşivle ve 5 firma limiti çalışıyor.
  - Pro ekleme çalışıyor.
  - Başka kullanıcının firmasını analiz/raporda seçme engelleniyor.
- Account deletion avatar cleanup:
  - Worker `deno check` geçti.
  - Destructive remote invoke gerçek kullanıcıya yapılmadı.
  - Temp-user destructive test için `service_role` HTTP key veya `ACCOUNT_DELETION_ADMIN_SECRET` gerekiyor.

## Yapılan Ana İşler

- Onboarding cevapları DB'ye bağlandı ve kullanıcıya atanıyor.
- Onboarding cevapları analiz prompt'una kontrollü context olarak giriyor; görsel kanıtı filtrelemiyor, öncelik/ton/derinlik etkiliyor.
- Prompt mimarisi parçalandı: sabit `CORE_ANALYSIS_PROMPT`, onboarding/company/tier context ayrı bloklar.
- Free/Plus/Pro analiz çıktıları ayrıldı:
  - Free: references/root cause kilitli veya sınırlı.
  - Plus: kısa references + kısa root cause.
  - Pro: daha kapsamlı references + teknik root cause.
- `findings.root_cause_text` ve `ai_usage_logs` telemetry alanları production DB'de canlı.
- Plus/Pro için Gemini thinking budget `1024` ile sınırlandı.
- Çoklu firma sistemi eklendi:
  - `companies`, `analyses.company_id`, `reports.company_id`, `reports.company_snapshot`.
  - Plus limit 5 firma, Pro limit 25 firma.
  - Firma adı + tehlike sınıfı zorunlu, logo opsiyonel.
  - Kullanıcı bazlı firma ayrımı var; aynı firma adı farklı kullanıcılarda karışmaz.
  - Analiz öncesi, analiz sonrası/rapor sırasında firma seçimi ve hızlı firma ekleme akışı hazır.
  - Firma filtreleri analiz geçmişi ve rapor arşivinde var.
- Rapor snapshot mantığı eklendi: firma sonradan değişse bile eski rapor aynı firma bilgisiyle kalır.
- Firma RLS helper execute grant hatası production'da düzeltildi.
- İlk üyelik hoş geldin maili eklendi:
  - `send-welcome-email` Edge Function, Resend ile gönderir.
  - `profiles.welcome_email_*` ile idempotent.
  - TestFlight gerçek cihaz QA tamam: onboarding cevapları kaydoluyor, mail gidiyor, tekrar girişte duplicate engelleniyor.
- Async analiz sistemi eklendi:
  - `analyze` artık enqueue endpoint gibi çalışıyor.
  - `analysis_jobs` queue, `queued/analyzing/completed/failed` akışı, `process-analysis-jobs` worker.
  - Uygulama kapanırsa backend analize devam ediyor.
  - iOS tarafında polling ile sonuç bekleniyor.
- Push sistemi:
  - APNs production secrets girildi ve doğrulandı.
  - Analiz tamamlanınca `analysis_complete` push tetikleniyor.
  - Rapor hazır olunca `report_ready` push tetikleniyor.
  - RevenueCat/sync/account deletion eventlerinde `account_updates` push tetikleniyor.
  - Push tap yönlendirmesi: analiz -> Analiz geçmişi, rapor -> Raporlar, account -> Profil.
  - Foreground'da izlenen analiz için banner bastırılıyor.
- Push metni güncellendi:
  - Başlık: `Analiz Hazır !`
  - Mesaj: `Risk analizin seni bekliyor, hemen incele.`
- Rapor V1 kararları uygulandı:
  - `Sorumlu` PDF/XLSX raporlardan kaldırıldı.
  - `Termin` risk seviyesine göre otomatik öneriliyor.
- Profil dark tema düzeltildi.
- Onboarding V2 her zaman light/beyaz temada sabitlendi.
- Onboarding `Atla` linkine onay ekranı eklendi.
- Onboarding email OTP kodu 6 haneye ulaşınca otomatik doğrulama yapıyor.
- Silinen kullanıcıdan kalan local Supabase session için koruma eklendi; profile bootstrap FK/user-missing durumunda local session temizleniyor.
- Onboarding paywall kişiselleştirmesi kaldırıldı; kişiselleştirme paywall öncesi "kişisel plan" ekranına taşındı.
- Yeni onboarding akışı:
  - Sorular -> kişiselleştiriliyor animasyonu -> kişisel plan ekranı -> hesap oluşturma -> ücretsiz deneme davet ekranı -> sabit Time Paywall.
- Kişisel plan ekranı onboarding cevaplarına göre metin/timeline/chip gösteriyor.
- Paywall event logging eklendi:
  - `paywall_events`, `PaywallEventService`, variant: `onboarding_personal_plan_time_paywall_v1`.
- Hybrid QA Runner eklendi:
  - `scripts/qa_hybrid_runner.mjs`
  - Rapor: `QA/Hybrid_QA_2026-05-22.md`
  - Son rapor: PASS=25, WARN=0, FAIL=0.
- UI Test altyapısı eklendi:
  - `RiskDetectedUITests`
  - Debug-only UI reset/auth bypass
  - Onboarding personal plan ve trial invite/time paywall smoke testleri geçti.
- Professional Progress modülü eklendi:
  - MDP, mesleki ünvan, rozetler, yetkinlik haritası, haftalık takip.
  - Feature ayrı modül olarak konumlandı.
  - Profile/Home UI polish yapıldı.
  - Mesleki Ünvanlar, Başarılarım ve Rütbe Puanlama sheet'leri eklendi.
  - Progress/weekly tracking mesajları kısa ve ürün diline uygun hale getirildi.
- Profil avatar yükleme eklendi:
  - PhotosPicker ile görsel seçimi.
  - 512px centered square JPEG upload.
  - Daire içinde `scaledToFill` gösterim.
  - Plus crown / Pro star rozeti.

## Ürün Kararları

- Çoklu firma v1 Plus/Pro özelliği.
- Free kullanıcı firma alanlarında upgrade CTA görür.
- Firma silme yerine archive.
- Rapor üretiminde firma snapshot tutulur.
- Sorumlu alanı V1'de rapordan kaldırıldı; V2'de firma/bölüm şablonları düşünülecek.
- Termin V1'de otomatik önerilir, kullanıcıya ekstra zorunlu alan açılmaz.
- Time Paywall ilk etapta sabit olacak; onboarding cevapları sadece önceki kişisel plan ekranında kullanılacak.
- Bildirim izni ekranı ve App Store rating prompt planlandı, implementasyon bekliyor.
- Explicit cache düşünülüyor; cache'e kullanıcı fotoğrafı/metni/firma bilgisi girmemeli, sadece statik metodoloji/checklist/prompt kuralları girmeli.

## Önemli Dosyalar

- `App/Views/Onboarding/V2/OnboardingViewV2.swift`
- `App/Views/Onboarding/V2/Screens/OBPlanSummaryView.swift`
- `App/Views/Onboarding/V2/Screens/OBTrialInviteView.swift`
- `App/Views/Onboarding/V2/Screens/OBTimelinePaywallView.swift`
- `App/Models/OnboardingPersonalPlan.swift`
- `App/Views/Paywall/PaywallView.swift`
- `App/Services/PaywallEventService.swift`
- `App/Services/AnalysisService.swift`
- `App/Services/NotificationService.swift`
- `App/Services/AuthService.swift`
- `App/Services/PDFReportService.swift`
- `App/Views/Components/CompanyPickerSheet.swift`
- `supabase/functions/analyze/index.ts`
- `supabase/functions/process-analysis-jobs/index.ts`
- `supabase/functions/send-push-notification/index.ts`
- `supabase/functions/send-report-ready-notification/index.ts`
- `supabase/functions/send-welcome-email/index.ts`
- `supabase/functions/revenuecat-webhook/index.ts`
- `supabase/functions/sync-revenuecat-subscription/index.ts`
- `scripts/qa_hybrid_runner.mjs`
- `RiskDetectedUITests/RiskDetectedUITests.swift`

## Son Doğrulamalar

- Hybrid QA: `QA/Hybrid_QA_2026-05-22.md`, PASS=25/WARN=0/FAIL=0.
- iOS Simulator Debug build/run geçti.
- UI tests: onboarding personal plan + trial invite/time paywall smoke testleri geçti.
- `deno check` ilgili Edge Function dosyalarında geçti.
- `node --check scripts/qa_hybrid_runner.mjs` geçti.
- `plutil`/`xmllint` proje/scheme kontrolleri geçti.
- `deno check supabase/functions/sync-revenuecat-subscription/index.ts` geçti.
- `deno check supabase/functions/account-deletion-complete/index.ts` geçti.
- `supabase functions deploy sync-revenuecat-subscription` geçti.
- Plus user simulator QA:
  - Profile Plus görünüyor.
  - Raporlar ekranında Plus rapor paketi aktif.
  - Rapor oluşturma sheet'inde limit hatası yok.
- Physical device:
  - Build/install/launch geçti; telefon ekranındaki manuel Plus uçtan uca kullanım ayrıca yapılmalı.

## Kısa Notlar

- Yeni iOS özellikleri kullanıcı cihazına ancak yeni TestFlight/App Store build'i ile gelir.
- Production backend tarafında birçok fonksiyon/migration canlı.
- Gerçek cihaz push, RevenueCat package görünümü ve TestFlight/App Store satın alma/restore hâlâ pratik QA bekliyor.
- Account deletion destructive cleanup için gerçek kullanıcı yerine temp-user ile test yapılmalı; bunun için admin secret/service role HTTP key gerekli.
- `NEW_CHAT_CONTEXT_2026-05-20.md` ve `PROJECT_STATUS_AND_NEXT_2026-05-12.md` eski tarihli ama hâlâ detay arşivi olarak kullanılabilir; bazı maddeler yeni commitlerle tamamlanmış olabilir.
