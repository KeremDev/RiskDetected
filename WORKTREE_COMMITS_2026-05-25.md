# RiskDetected Commit ve Worktree Bilgisi - 2026-05-25

## Worktree

- Repo: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`
- Branch: `main`
- Remote: `origin -> https://github.com/KeremDev/RiskDetected.git`
- GitHub repo: `https://github.com/KeremDev/RiskDetected`
- Son kontrol: `main` remote'u takip ediyor.
- Not: App icon varyantları ve bu handoff dosyaları oluşturulduktan sonra worktree'de untracked/modified görünebilir.

## 2026-05-29 Commit Güncellemesi

- Hash: `9a2beea`
- Mesaj: `Verify report quotas and polish app UI`
- Remote: `origin/main` branch'e pushlandı.
- İçerik özeti:
  - Free kullanıcı risk analiz tablosu deneme hakkının standart rapor hakkını bozmaması için UI/test kapsamı eklendi.
  - `testFreeRiskAnalysisTrialDoesNotLockStandardReport` UI testi eklendi ve geçti.
  - Report sheet, onboarding/paywall, tab bar clearance ve kart derinliği polish değişiklikleri commitlendi.
  - Account deletion avatar cleanup temp-user destructive QA tamamlandı.
  - XLSX logo/snapshot/uzun metin QA gerçek local Edge Function çağrısı ve indirilen workbook ile doğrulandı.

- Hash: bu handoff güncellemesini içeren mevcut commit
- Mesaj: `Disable dark mode card shadows`
- İçerik özeti:
  - `App/DesignSystem/RDShadow.swift` merkezi tasarım token'ı güncellendi.
  - `rdCardShadow` ve `rdRowShadow` dark mode'da gölge basmayacak.
  - Light mode sağ-alt net gölge sistemi korunacak.
  - Tasarım kararı: Dark mode'da kart ayrımı shadow yerine yüzey/stroke ile yapılacak.
  - Doğrulama: iOS Simulator Debug build/run geçti.

## 2026-05-27 Commit Güncellemesi

- Hash: `1b000b1`
- Mesaj: `Prevent fallback subscription sync downgrades`
- İçerik özeti:
  - `sync-revenuecat-subscription` fallback fonksiyonu RevenueCat geçici/free döndüğünde aktif backend Plus/Pro kaydını düşürmeyecek şekilde düzeltildi.
  - Webhook downgrade/cancel için source of truth olarak bırakıldı.
  - `deno check` geçti.
  - Fonksiyon remote Supabase'e deploy edildi.
  - Simulator'da Plus kullanıcı için `Rapor Oluştur` sheet'i tekrar test edildi; yanlış `LİMİT DOLDU` görünmüyor.

## 2026-05-28 Çalışma Güncellemesi

- İçerik özeti:
  - Analiz kuyruğu kullanıcı metni teknik/backend dilden arındırıldı.
  - Firma seçimi/filtresi sheet'leri kompakt detent ile açılacak şekilde ayarlandı.
  - Firma filtresi UI kartları ve satırları daha sakin font/ölçü düzenine çekildi.
  - `Yeni firma ekle` CTA'sı gri yerine siyah olarak tasarlandı.
  - Simulator build/run geçti ve `Analiz firma filtresi` görsel QA yapıldı.

## 2026-05-26 Commit Güncellemesi

- Hash: `ebc25ed`
- Mesaj: `Polish professional progress UI`
- İçerik özeti:
  - Professional Progress UI tasarım polish.
  - Profil üst kartı, progress kartları, weekly tracking, rozet/ünvan sheet'leri.
  - Profil avatar UI ve Plus/Pro rozet görünümleri.
  - Çarpı kapatma butonları ve sheet yükseklik düzeltmeleri.

- Hash: `c294f0c`
- Mesaj: `Add professional progress module`
- İçerik özeti:
  - `ProfessionalProgress` modülü.
  - MDP, ünvan, rozet, yetkinlik sınıflandırma ve haftalık takip altyapısı.
  - Supabase professional progress migration'ları.
  - Profil/avatar migration'ları.

## Son Commit

- Hash: `9a2beea`
- Mesaj: `Verify report quotas and polish app UI`
- İçerik özeti:
  - Free rapor/risk analiz hakkı QA kapsamı, report flow polish ve UI test doğrulamaları.

## Son Commit Geçmişi

```text
9a2beea Verify report quotas and polish app UI
53f45ec Fix UI test analysis result fixture
12a7b11 Polish report flows and card depth
c22c51f Polish company picker sheets
59bae77 Update handoff and TODO status
1b000b1 Prevent fallback subscription sync downgrades
ebc25ed Polish professional progress UI
c294f0c Add professional progress module
f15701b Add async analysis, onboarding paywall, and QA automation
875e8a2 Add company flows and welcome email automation
d34b637 Persist onboarding answers and clean AI prompt audit
ab9fd68 Prepare onboarding v2 and AI report updates
7b276ea Finalize paid Gemini routing and analysis QA
a64746f Fix photo thumbnails and release polish
3173a61 Polish paywall and release readiness flows
faff000 Polish release support and subscription flows
```

## Son QA / Build Bilgisi

- Hybrid QA raporu: `QA/Hybrid_QA_2026-05-22.md`
- Hybrid QA sonucu: `PASS=25`, `WARN=0`, `FAIL=0`
- UI tests: 2 test geçti.
- iOS Simulator Debug build/run geçti.
- Edge Function `deno check` kontrolleri geçti.
- Supabase migration list remote/local hizası kontrol edildi:
  - `20260526163303_professional_progress_weekly_tracking.sql`
  - `20260526184023_profile_avatars.sql`
- Fiziksel cihaz build/install/launch doğrulandı:
  - Cihaz: Kerem iPhone, iPhone 14 Pro Max.
  - `xcodebuild` iPhoneOS Debug build geçti.
  - App cihaza yüklendi ve launch edildi.
- Plus kullanıcı rapor sheet'i simulator'da doğrulandı:
  - Yanlış `LİMİT DOLDU` artık görünmüyor.
  - `Standart Rapor` ve `Risk Analizi Tablosu` açık geliyor.
- Profil avatar simulator/backend QA:
  - Fotoğraf seçildi, daire içinde crop/ortalanma doğru.
  - `avatar_url` profile yazıldı.
  - `avatars` bucket'ında JPEG obje oluştu.
- Account deletion worker:
  - `deno check supabase/functions/account-deletion-complete/index.ts` geçti.
  - Destructive temp-user invoke için service/admin secret gerekiyor.

## Yeni Sohbette İlk Yapılacak Kontrol

Yeni sohbet başlarken şu komutlarla gerçek anlık durum kontrol edilmeli:

```bash
git status --short
git branch --show-current
git log --oneline -5
```

Eğer bu handoff dosyaları commitlenecekse önerilen commit mesajı:

```text
Add handoff context for next chat
```
