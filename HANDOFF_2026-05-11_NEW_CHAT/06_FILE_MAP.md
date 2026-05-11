# 06 - Dosya Haritası

## App State / Root

- `App/RiskDetectedApp.swift`
  - App entry.
  - Global theme `.preferredColorScheme`.
- `App/AppState.swift`
  - Auth/main/onboarding flow.
  - Active tab.
  - Theme/language preference.
  - Quick scan request state.
- `App/RootView.swift`
  - Splash/onboarding/auth/main switch.

## Design System

- `App/DesignSystem/RDColor.swift`
  - Light/dark adaptive colors.
- `App/Views/Components/RDButton.swift`
  - CTA button style.
- `App/Views/Components/RDTabBar.swift`
  - Bottom tab bar and center `Tara` button.
- `App/Views/Components/RDUpgradeCTA.swift`
  - Pro CTA components.
- `App/Views/Common/DocumentPreview.swift`
  - PDF/XLSX preview wrapper with close/download/share controls.

## Auth

- `App/Views/Auth/AuthView.swift`
  - Apple/Google/e-posta OTP UI.
- `App/Services/AuthService.swift`
  - Supabase auth operations.
- `AUTH_SETUP.md`
  - Auth setup notes.

## Home / Analysis Start

- `App/Views/Home/HomeView.swift`
  - Main home.
  - Photo/text input.
  - Recent analyses.
  - Generated reports.
  - Photo source sheet.
  - Quick scan request handler.
- `App/Views/Home/MainTabView.swift`
  - Main tabs.
  - Central `Tara` quick scan behavior.
- `App/Views/Home/CanvasSheet.swift`
  - AI focus/canvas selection.
- `App/Views/Annotate/AnnotateView.swift`
  - Photo marking screen.
- `App/Views/Analyzing/AnalyzingView.swift`
  - Waiting/AI analyzing screen.

## Analysis / Results

- `App/Views/History/HistoryView.swift`
  - Analyses tab.
  - Cards, filters, search.
- `App/Views/History/FilterSheet.swift`
  - Filter UI.
- `App/Views/Result/ResultView.swift`
  - Main result screen.
  - Free Pro teaser cards.
  - Report create flow.
  - PDF/Excel actions.
- `App/Views/Result/RiskDetailView.swift`
  - Finding detail.
  - Method comparison.
  - Pro locked references.

## Reports

- `App/Views/Report/ReportView.swift`
  - Reports tab.
  - Stored report list.
  - Report preview/download/delete.
- `App/Services/PDFReportService.swift`
  - Standard PDF and detailed risk analysis PDF generation.
- `supabase/functions/generate-excel-report/index.ts`
  - Pro XLSX generation.
- `supabase/migrations/20260510180047_add_excel_report_exports.sql`
  - XLSX support in report storage/metadata.

## Services / Models

- `App/Services/AnalysisService.swift`
  - Analysis creation.
  - Photo upload/download.
  - PDF upload/report metadata.
  - Excel function invocation.
  - Profile stats/daily quota.
- `App/Services/AppErrorMessage.swift`
  - Turkish normalized errors/support IDs.
- `App/Services/NotificationService.swift`
  - APNs registration/settings.
- `App/Models/AnalysisCanvas.swift`
  - Canvas list and Pro flags.
- `App/Models/HistoryItem.swift`
  - Analysis list item mapping.
- `App/Models/Finding.swift`
  - Risk finding model and scoring helpers.

## Profile / Legal

- `App/Views/Profile/ProfileView.swift`
  - Profile screen.
  - Profile editor.
  - Preferences.
  - Notifications.
  - Data controls.
- `App/Views/Legal/LegalInfoSheet.swift`
  - KVKK / Kullanım koşulları / AI veri işleme legal center.

## Supabase

- `supabase/functions/analyze/index.ts`
  - Gemini analysis.
  - Multi-key fallback.
  - AI focus prompt routing.
  - Support/request ID logging.
- `supabase/functions/send-push-notification`
  - APNs push scaffold.
- `supabase/functions/retention-cleanup`
  - Storage cleanup.
- `supabase/migrations`
  - DB schema changes.

