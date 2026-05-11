# 07 - Son Commit Dosyaları

Bu dosya yeni sohbette son commitlerin hangi dosyalara dokunduğunu hızlı görmek için eklendi.

Kısaltmalar:

- `M`: değişti
- `A`: eklendi
- `D`: silindi

## `ba58afa` - Polish mobile reporting and analysis flows

```text
M App/AppState.swift
M App/Models/AnalysisCanvas.swift
M App/Models/HistoryItem.swift
M App/RiskDetectedApp.swift
M App/Services/AnalysisService.swift
M App/Services/RDConfig.swift
M App/Views/Analyzing/AnalyzingView.swift
M App/Views/Annotate/AnnotateView.swift
M App/Views/Auth/AuthView.swift
A App/Views/Common/DocumentPreview.swift
M App/Views/Components/RDTabBar.swift
M App/Views/History/FilterSheet.swift
M App/Views/History/HistoryView.swift
M App/Views/Home/CanvasSheet.swift
M App/Views/Home/HomeView.swift
M App/Views/Home/MainTabView.swift
M App/Views/Legal/LegalInfoSheet.swift
M App/Views/Profile/ProfileView.swift
M App/Views/Report/ReportView.swift
M App/Views/Result/ResultView.swift
M App/Views/Result/RiskDetailView.swift
M IMPLEMENTATION_PLAN.md
M PROJECT_HANDOFF.md
M supabase/functions/analyze/index.ts
A supabase/functions/generate-excel-report/index.ts
A supabase/migrations/20260510180047_add_excel_report_exports.sql
```

## `fa00b0e` - Polish dark mode CTA contrast

```text
M App/DesignSystem/RDColor.swift
M App/Views/Analyzing/AnalyzingView.swift
M App/Views/Annotate/AnnotateView.swift
M App/Views/Components/RDButton.swift
M App/Views/History/FilterSheet.swift
M App/Views/History/HistoryView.swift
M App/Views/Home/CanvasSheet.swift
M App/Views/Home/HomeView.swift
M App/Views/Paywall/PaywallView.swift
M App/Views/Profile/ProfileView.swift
M App/Views/Report/ReportView.swift
M App/Views/Result/ResultView.swift
M App/Views/Result/RiskDetailView.swift
M IMPLEMENTATION_PLAN.md
M PROJECT_HANDOFF.md
```

## `76c1e77` - Polish theme and header menu UI

```text
M App/AppState.swift
M App/DesignSystem/RDColor.swift
M App/RiskDetectedApp.swift
M App/Views/Auth/AuthView.swift
M App/Views/Components/AnalysisThumbnail.swift
M App/Views/Components/PDFGenerationOverlay.swift
M App/Views/Components/RDAvatar.swift
M App/Views/Components/RDButton.swift
M App/Views/Components/RDLogo.swift
M App/Views/Components/RDTabBar.swift
M App/Views/Components/RDUpgradeCTA.swift
M App/Views/History/HistoryView.swift
M App/Views/Home/HomeView.swift
M App/Views/Home/MainTabView.swift
M App/Views/Profile/ProfileView.swift
M App/Views/Report/ReportView.swift
M App/Views/Result/ResultView.swift
M IMPLEMENTATION_PLAN.md
M PROJECT_HANDOFF.md
```

## `1e82afa` - Add profile, notification, and AI reliability updates

```text
M AUTH_SETUP.md
M App/AppState.swift
M App/Models/HistoryItem.swift
M App/Models/RecentAnalysis.swift
M App/RiskDetected.entitlements
M App/RiskDetectedApp.swift
M App/Services/AnalysisService.swift
M App/Services/AppErrorMessage.swift
M App/Services/AuthService.swift
A App/Services/DataActionFailureSimulation.swift
A App/Services/NotificationService.swift
M App/Services/PDFReportService.swift
M App/Services/RDConfig.swift
M App/Views/Auth/AuthView.swift
M App/Views/Components/AnalysisThumbnail.swift
M App/Views/Components/RDUpgradeCTA.swift
M App/Views/History/HistoryView.swift
M App/Views/Home/HomeView.swift
M App/Views/Paywall/PaywallView.swift
M App/Views/Profile/ProfileView.swift
M App/Views/Report/ReportView.swift
M App/Views/Result/ResultView.swift
M IMPLEMENTATION_PLAN.md
M PROJECT_HANDOFF.md
M QA/P1_5_Error_Test_Matrix.md
M supabase/functions/analyze/index.ts
A supabase/functions/send-push-notification/index.ts
A supabase/migrations/20260509230500_profile_edit_and_logos.sql
A supabase/migrations/20260510002500_push_notifications.sql
A supabase/migrations/20260510004500_ai_usage_gemini_key_alias.sql
A supabase/templates/email-otp-confirmation.html
A supabase/templates/email-otp-magic-link.html
```

## `8248430` - Update auth handoff and plan

```text
M AUTH_SETUP.md
M App/Services/AppErrorMessage.swift
M App/Views/Auth/AuthView.swift
M IMPLEMENTATION_PLAN.md
A PROJECT_HANDOFF.md
```

## `7944c14` - Fix report sheet flow and disable phone bridge

```text
M .gitignore
M AUTH_SETUP.md
D App/GoogleService-Info.plist
A App/GoogleService-Info.plist.example
M App/Views/Report/ReportView.swift
M IMPLEMENTATION_PLAN.md
M supabase/functions/firebase-phone-bridge/index.ts
```

## `ef44224` - Update auth flow and report UI

```text
A AUTH_SETUP.md
M App/DesignSystem/RDFont.swift
A App/GoogleService-Info.plist
A App/RiskDetected.entitlements
M App/RiskDetectedApp.swift
M App/Services/AppErrorMessage.swift
A App/Services/AppleSignInService.swift
M App/Services/AuthService.swift
A App/Services/FirebaseBootstrap.swift
A App/Services/FirebasePhoneAuthService.swift
M App/Services/RDConfig.swift
M App/Views/Analyzing/AnalyzingView.swift
M App/Views/Annotate/AnnotateView.swift
M App/Views/Auth/AuthView.swift
M App/Views/Components/PDFGenerationOverlay.swift
M App/Views/Components/RDAvatar.swift
M App/Views/Components/RDButton.swift
M App/Views/Components/RDCard.swift
M App/Views/Components/RDChip.swift
M App/Views/Components/RDProBadge.swift
M App/Views/Components/RDTabBar.swift
M App/Views/Components/RDUpgradeCTA.swift
M App/Views/History/FilterSheet.swift
M App/Views/History/HistoryView.swift
M App/Views/Home/CanvasSheet.swift
M App/Views/Home/HomeView.swift
M App/Views/Legal/LegalInfoSheet.swift
M App/Views/Onboarding/OnboardingView.swift
M App/Views/Paywall/PaywallView.swift
M App/Views/Profile/ProfileView.swift
M App/Views/Report/ReportView.swift
M App/Views/Result/ResultView.swift
M App/Views/Result/RiskDetailView.swift
A Config/RiskDetectedInfo.plist
M IMPLEMENTATION_PLAN.md
M RiskDetected.xcodeproj/project.pbxproj
A supabase/functions/firebase-phone-bridge/index.ts
A supabase/migrations/20260509001429_firebase_phone_auth_bridge.sql
```

## `83f7f80` - test: add report failure simulation coverage

```text
M App/Services/AnalysisService.swift
M App/Services/AppErrorMessage.swift
M App/Services/PDFReportService.swift
A App/Services/ReportFailureSimulation.swift
M IMPLEMENTATION_PLAN.md
M QA/P1_5_Error_Test_Matrix.md
```

