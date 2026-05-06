# RiskDetected Implementation Plan

## Current Phase

- FAZ 1: iOS app MVP + Supabase/Gemini analysis flow.
- Current focus: real analysis UX, free/pro conversion surfaces, live report and result screens.

## Completed

- SwiftUI app shell, onboarding, auth and main tab flow.
- Supabase Auth, profiles, analyses, findings, photos and AI usage wiring.
- Gemini Edge Function for photo/text risk analysis.
- Free daily analysis limit set to 2.
- Demo Pro and Free users added to login screen.
- Home, History, Result and Report screens now use live analysis data instead of mock-heavy data.
- Inline photo analysis persists analyzed images into Supabase Storage and `photos`.
- Result screen can generate a local A4 landscape PDF report from the live analysis bundle, including logo, analysis metadata, uploaded photo, AI summary, risk counts and sorted finding details.
- iOS share sheet is wired to the PDF report action for local export/sharing.
- Free users keep the fixed RiskDetected PDF template. Pro users have a report settings entry point for detailed risk analysis output, method selection (Fine-Kinney / 5×5), editable report identity fields and per-report company logo selection.
- Pro detailed risk analysis output now uses a separate landscape form format instead of the standard PDF layout:
  - Fine-Kinney output includes Olasılık/Frekans/Şiddet reference tables, risk band/action table and a wide hazard-control assessment form.
  - 5×5 output includes Olasılık/Şiddet definitions, 5×5 matrix reference and a method-specific hazard-control assessment form.

## Backlog

- Persist generated PDF metadata to Supabase `reports` and upload report files to Storage.
- Add report regeneration/download flow from the Reports tab.
- Persist company logo upload/selection under Profile so Pro reports can reuse it without selecting the logo each time.
- RevenueCat subscription integration.
- Apple, Google and phone OTP production auth hardening.
- History filters backed by real DB predicates.
- Report rows/table generation in Supabase `reports`.
- Pro AI confidence upgrade:
  - Free analysis should remain fast and cost-controlled with a lighter Gemini model, lower image budget and fewer validation passes.
  - Pro analysis can target higher confidence by using stronger Gemini models, higher-resolution image inputs, multi-pass prompt validation, sector/procedure-specific checklists and re-checking low-confidence findings.
  - Product copy must avoid guaranteeing a fixed confidence score. Preferred wording: "Pro analizlerde daha kapsamlı model ve doğrulama katmanı ile daha yüksek güven hedeflenir."
