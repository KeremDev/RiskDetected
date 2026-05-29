# RiskDetected Project Handoff

> Güncel tek yapılacaklar özeti için bkz. `PROJECT_STATUS_AND_NEXT_2026-05-12.md`.
> Bu handoff dosyası mimari ve tarihsel bağlamı korur; en güncel yapılacak sırası yeni status dosyasındadır.

Last updated: 2026-05-20

This file is the single-context handoff for continuing RiskDetected in a new Codex/Claude session.

## Project Identity

- App name: RiskDetected / SafeScope AI
- Purpose: AI-assisted occupational safety / HSE risk analysis for individual ISG experts.
- Platform: iOS SwiftUI app.
- Bundle ID: `com.riskdetected.app`
- Workspace root: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`
- Xcode project: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/RiskDetected.xcodeproj`
- Main app folder: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/App`
- Backend: Supabase PostgreSQL, Storage, Auth, Edge Functions.
- AI provider: Gemini via Supabase Edge Function.
- Supabase URL: `https://ppcrzemgiztzcgddbins.supabase.co`
- Current simulator default: iPhone 17 Pro, bundle `com.riskdetected.app`.

## Current Product Direction

RiskDetected is focused on a simple expert workflow:

1. User signs in.
2. User uploads/takes a field photo or enters text.
3. Optional photo annotation and optional user prompt are added.
4. User selects one or more AI analysis focuses/canvases.
5. Gemini analyzes hazards.
6. App scores findings with Fine-Kinney and 5x5 L-Type Matrix.
7. Results are shown in the app.
8. User can generate standard PDF reports or Pro detailed risk-analysis PDFs.

Corporate/OSGB multi-tenant dashboards are out of current MVP scope.

## Architecture

### iOS

- SwiftUI app shell with `AppState` controlling splash/onboarding/auth/main flow.
- Main tabs:
  - Home
  - Analyses
  - Reports
  - Profile
- Design system lives under `App/DesignSystem`.
- Core services live under `App/Services`.
- Core models live under `App/Models`.
- App uses Supabase Swift SDK.

Important iOS files:

- `App/RiskDetectedApp.swift`
- `App/AppState.swift`
- `App/RootView.swift`
- `App/Services/AuthService.swift`
- `App/Services/AnalysisService.swift`
- `App/Services/PDFReportService.swift`
- `App/Services/AppErrorMessage.swift`
- `App/Views/Auth/AuthView.swift`
- `App/Views/Home/HomeView.swift`
- `App/Views/Home/CanvasSheet.swift`
- `App/Views/Analyzing/AnalyzingView.swift`
- `App/Views/Result/ResultView.swift`
- `App/Views/Result/RiskDetailView.swift`
- `App/Views/Report/ReportView.swift`
- `App/Views/Profile/ProfileView.swift`

### Supabase

Core tables:

- `profiles`
- `analyses`
- `findings`
- `photos`
- `reports`
- `ai_usage_logs`
- `consents`
- `push_device_tokens`
- `notification_preferences`
- `notification_events`

Core buckets:

- `photos`
- `reports`
- `logos`

Important functions:

- `analyze`
- `retention-cleanup`
- `send-push-notification`

Important migrations:

- `supabase/migrations/20260506193000_reports_storage.sql`
- `supabase/migrations/20260508192153_add_report_request_support_ids.sql`
- `supabase/migrations/20260509001429_firebase_phone_auth_bridge.sql`

## AI and Risk Logic

### Gemini Model Routing

Current intended routing:

- Free users: `gemini_primary + gemini-2.5-flash`, then `gemini_secondary + gemini-2.5-flash`, then `gemini_primary + gemini-3.1-flash-lite`, then `gemini_secondary + gemini-3.1-flash-lite`; all Free Gemini retryable failures fall back to `groq_free_primary`.
- Plus/Pro users: paid-plan Gemini key pool only after backend subscription validation. Current paid order is `gemini_paid_primary + gemini-2.5-flash`, `gemini_paid_primary + gemini-2.5-pro`, `gemini_paid_primary + gemini-3.1-flash-lite`, `gemini_paid_secondary + gemini-2.5-flash`, then `gemini_paid_secondary + gemini-2.5-pro`; all Paid Gemini retryable failures fall back to `groq_plus_pro_primary`.
- Current product target: Free günde 1 standart analiz ve tek canvas; Plus/Pro gelişmiş canvas erişimi ve 11-14 bulgu hedefi.

Known product note:

- Do not promise fixed confidence such as "Pro is always 90%".
- Preferred copy: Pro analyses use stronger model and validation layers to target higher confidence.

Gemini key routing and reliability bridge:

- Free users use the Free key pool only. Supported Free secrets:
  - `GEMINI_API_KEY_PRIMARY`
  - `GEMINI_API_KEY_SECONDARY`
  - `GEMINI_API_KEY_TERTIARY`
- Existing legacy `GEMINI_API_KEY` is treated as primary fallback for backward compatibility.
- Free model order is `gemini_primary + gemini-2.5-flash`, `gemini_secondary + gemini-2.5-flash`, `gemini_primary + gemini-3.1-flash-lite`, then `gemini_secondary + gemini-3.1-flash-lite` for retryable provider failures or limits.
- Free `gemini-3.1-flash-lite` requests use Gemini `thinkingConfig.thinkingLevel = "medium"` across all Free key aliases.
- Plus/Pro users use the Paid key pool only. Supported Paid secrets:
  - `GEMINI_API_KEY_PAID`
  - `GEMINI_API_KEY_PAID_SECONDARY` (optional fallback)
- Plus/Pro model order is `gemini_paid_primary + gemini-2.5-flash`, `gemini_paid_primary + gemini-2.5-pro`, `gemini_paid_primary + gemini-3.1-flash-lite`, `gemini_paid_secondary + gemini-2.5-flash`, then `gemini_paid_secondary + gemini-2.5-pro` for retryable provider failures or limits.
- Plus/Pro `gemini-3.1-flash-lite` requests use Gemini `thinkingConfig.thinkingLevel = "high"` across the paid primary alias.
- `GEMINI_PAID_API_KEY` is accepted as a backward-compatible alias for `GEMINI_API_KEY_PAID`, but `GEMINI_API_KEY_PAID` is preferred.
- Free traffic may use Groq only after the Free Gemini key/model pool is exhausted by retryable provider errors. Configure `GROQ_API_KEY_FREE`; optional `GROQ_FREE_MODEL` defaults to `meta-llama/llama-4-scout-17b-16e-instruct`.
- Plus/Pro traffic may use a separate Groq continuity fallback only after the Paid Gemini key/model pool is exhausted by retryable provider errors. Configure `GROQ_API_KEY_PLUS_PRO`; optional `GROQ_PLUS_PRO_MODEL` defaults to the same Groq vision model as Free. The Groq API may still be free tier, but the secret and log alias must stay separate from Free (`groq_plus_pro_primary`).
- Important: multiple keys in the same Google Cloud project share quota and should not be treated as separate capacity.
- The Edge Function resolves the effective plan from backend subscription state before selecting a key pool.
- If backend subscription lookup fails, analysis fails closed instead of silently treating the user as Free.
- No cross-pool fallback is allowed: Free traffic never uses Paid keys, and Plus/Pro traffic never falls back to Free keys. Missing Paid secrets fail closed with a support code.
- Retry/fallback only on retryable provider failures such as `429 RESOURCE_EXHAUSTED`, quota/rate-limit, 5xx and timeout.
- Do not fallback on invalid input/user errors.
- Logs store only key aliases (`gemini_primary`, `gemini_secondary`, `gemini_tertiary`, `gemini_paid_primary`, `gemini_paid_secondary`), never raw keys.
- `ai_usage_logs` includes `api_key_alias` and `attempt_count`.
- This is the MVP launch buffer until broader provider fallback is added.

Plus/Pro fallback note:

- Plus/Pro-only Groq continuity fallback is implemented after Paid Gemini pool exhaustion. It uses `GROQ_API_KEY_PLUS_PRO` / `GROQ_PLUS_PRO_MODEL` and logs as `groq_plus_pro_primary`.
- Plus/Pro traffic must still never fall back to Free Gemini keys.
- Next telemetry pass should verify `ai_usage_logs.api_key_alias`, model, attempt count, token count and support codes across Paid Gemini and Groq fallback paths.

Later Prompt/Context Caching note:

- Evaluate Gemini context caching after launch telemetry is stable.
- First add passive measurement only: cached input token count, hit ratio, prompt version/hash, model, latency and API key alias.
- Explicit cache should be considered mainly for Plus/Pro paid traffic, especially `gemini-2.5-pro`; Free can remain on implicit caching plus usage logs unless volume/cost changes.
- Cache only static RiskDetected material: HSE/ISG instructions, Fine-Kinney/5x5 methodology, legislation/checklist guidance and JSON output rules. Never cache user photos, text input, company data or user-specific prompts.
- Keep model-specific cache entries for `gemini-2.5-pro` and fallback `gemini-2.5-flash`.
- Cache failures/expiry must fall back to a normal non-cached paid call. Paid traffic must never fall back to Free Gemini keys.

### Risk Methods

The app supports two methods:

- Fine-Kinney:
  - `R = Olasilik x Frekans x Siddet`
  - Valid probability values: `[0.2, 0.5, 1, 3, 6, 10]`
  - Valid frequency values: `[0.5, 1, 2, 3, 6, 10]`
  - Valid severity values: `[1, 3, 7, 15, 40, 100]`
  - `fk_score` is DB-generated and must not be inserted manually.
- 5x5 L-Type Matrix:
  - `R = Olasilik x Siddet`
  - Probability/severity values are 1-5.
  - `m5_score` is DB-generated and must not be inserted manually.

Result findings should be sorted from highest risk to lowest risk.

## Authentication Status

Current MVP auth decision:

- Phone/Firebase login has been removed from MVP scope.
- User-facing passwordless login is Supabase Email OTP.
- Demo Pro and Free login buttons remain available for testing.
- Apple, Google and Email OTP auth flows are implemented; Email OTP, Google native sign-in and Apple native sign-in have passed live/TestFlight verification.

Current auth implementation:

- `AuthService.sendEmailOTP(email:)`
- `AuthService.verifyEmailOTP(email:token:)`
- Supabase Email provider smoke test passed.
- Admin `generate_link` + `/auth/v1/verify` token hash flow produced an access token.
- Supabase built-in email rate limits were hit during testing (`over_email_send_rate_limit`).
- App maps invalid email, expired OTP, invalid OTP and email rate-limit errors to Turkish user messages.

Required external auth work:

- Configure custom SMTP in Supabase Auth.
  - Preferred: Resend or Postmark with verified domain.
  - Alternatives: SendGrid, Mailgun.
- Replace Supabase `Confirm signup` and `Magic Link` email templates with the repo templates under `supabase/templates/`, so real mailboxes receive a 6-digit OTP using `{{ .Token }}` instead of a confirmation link.
- Apple provider was verified with a real Apple account on TestFlight. Supabase Apple provider must keep both the Services ID and native iOS bundle id `com.riskdetected.app` in `Client IDs`.
- Verify Google OAuth redirect.

Phone/Firebase status:

- Firebase iOS SDK, `GoogleService-Info` files and Firebase URL scheme were removed from the app.
- Live Supabase `firebase-phone-bridge` Edge Function was deleted.
- If phone login returns later, design it as a fresh auth/security task.

## Latest Auth UI Notes

Latest UI changes:

- Onboarding V2 is active from `RootView` for first install / reset flows.
- Onboarding final step now runs Apple, Google and Email OTP directly inside the onboarding screen instead of redirecting users back to the legacy auth landing screen.
- Onboarding email and OTP panels use a floating keyboard-aware layer so the base page stays visually stable.
- Onboarding completion shows a separate Plus-first onboarding paywall variant, kept independent from the in-app paywall for later personalization.
- Auth hero photo-to-white transition is softened.
- Logo and slogan in email entry screen are lifted upward.
- Google button uses a lightweight colored Google wordmark style.
- Email button label is `E-posta ile giriş yap`.
- Apple button no longer shows the generic right-side paper-plane action icon.
- Email placeholder is grey, not blue.
- `Diğer giriş yöntemleri` link is slightly more prominent.
- Email error cards use normalized red/pink message UI with support-friendly wording.

## Latest UI and Theme Notes

Completed in the latest UI polish pass:

- App-level dark mode foundation exists:
  - `AppState.isDarkModeEnabled` persists locally;
  - `AppState.themePreference` supports `Sistem`, `Aydinlik`, `Karanlik`;
  - `AppState.languagePreference` is backed by `RDLanguage`, currently exposes only `Turkce`, and normalizes older `Sistem` / `English` stored values back to `Turkce`;
  - `RDLocalization` / `RDReportLocalization` provide the real localization lookup layer for app/report strings;
  - `PDFReportOptions.language` carries the current report output language for future PDF/XLSX language selection;
  - `RiskDetectedApp` applies `.preferredColorScheme`;
  - core color tokens in `RDColor` adapt to light/dark mode;
  - fixed black CTA surfaces use `rdOnyx` so they do not turn into dynamic text colors.
- Profile > Ayarlar > Tercihler opens a full preferences sheet with theme and language choices.
- Top-right profile avatar opens a compact overlay menu:
  - `Analizlerim` navigates to the Analyses tab;
  - `Raporlarim` navigates to the Reports tab;
  - Free users see `Plan Yukselt`; Pro users see passive `Pro uyesiniz`;
  - bottom icon row includes sign-out and dark/light mode toggle.
- Header profile menu:
  - does not affect page layout;
  - closes on outside tap;
  - closes on scroll/drag.
- Main CTA button style uses the right-side icon capsule, with fixed white text/icon where needed in dark mode.
- Dark mode CTA contrast QA is complete for `Taramayi Baslat`, `Standart Rapor`, `Risk Analizi` and `Bu ayarlarla PDF olustur`; primary actions use green background with white text/icons in dark mode.
- `Standart Rapor` is tuned to remain single-line and visually centered in both light and dark mode.
- Reports tab has been redesigned with a report-center summary panel, Pro value panel, premium saved-report cards and clearer report-source rows.
- Analyses tab has been redesigned with an analysis-center summary panel, modern search/filter surface, cleaner filter sheet and more scannable analysis cards.
- Free daily quota hint is shown under input for Free users and displays dynamic `2/2`, `1/2`, `0/2` state.
- Analysis thumbnails are standardized with clipping so any image aspect ratio stays inside its box.
- Text-only analyses use a standard Metin Analizi artwork instead of empty photo placeholders.
- Bottom tab inactive labels/icons are black in light mode; active icon remains green.

Remaining theme/design follow-up:

- Expand the localization key coverage when a second app/report language is ready to ship.
- Continue final contrast QA when new Result, Report, Paywall or sheet UI changes are made.
- Continue planned Profile page tab/content work.

## Reports and PDF Status

Completed:

- Standard PDF generation works.
- Detailed Pro risk-analysis PDF generation works for Fine-Kinney and 5x5.
- PDF progress overlay exists and shows staged percentage progress.
- Standard PDF includes:
  - RiskDetected logo
  - analysis metadata
  - uploaded/cleaned photo when available
  - AI summary
  - risk counts
  - sorted findings
- Pro detailed risk analysis PDFs use landscape form-like output and method-specific tables.
- Generated PDFs upload to Supabase Storage and metadata is written to `reports`.
- Reports tab can show stored reports and regenerate/share reports.
- Report settings button was moved into the report source sheet flow.

Known report design/product rules:

- Free users can generate only the fixed RiskDetected standard PDF template.
- Free users cannot customize report identity/logo.
- Pro users can use report settings:
  - company logo
  - company/report identity fields
  - detailed risk-analysis output
  - Fine-Kinney or 5x5 method selection

Known follow-ups:

- Persist default company logo/report identity in Profile so Pro users do not reselect each time.
- Improve saved report filtering/search/status labels.
- Continue PDF QA; this is a core feature and must remain stable.

## Push Notification Status

Push notification foundation is in place:

- iOS uses APNs directly, not Firebase Messaging.
- `NotificationService` requests notification permission, registers for APNs and stores the device token in Supabase.
- Profile > Bildirimler opens a notification settings sheet.
- Supabase migration `20260510002500_push_notifications.sql` creates token, preference and event tables with RLS.
- Edge Function `send-push-notification` is deployed.
- Simulator smoke test passed: settings sheet opens, permission flow enables, sandbox iOS token is stored, notification preferences are enabled.

Required before real production push delivery:

- Apple Developer > Keys: create APNs Auth Key (`.p8`).
- Set Supabase Edge Function secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, `APNS_ENV`.
- Use `APNS_ENV=sandbox` for development and `production` for production/TestFlight delivery.
- Final Archive / Xcode Organizer check is complete; release signing, APNs production entitlement and privacy manifests were verified.
- Add trusted backend calls/triggers for analysis complete, report ready and account/security updates.

## Privacy, Legal and Retention

Completed/started:

- `consents` table exists with RLS.
- Blocking first-analysis consent was intentionally removed for better UX.
- Login screen shows legal notice/link.
- Home legal text was removed because it visually hurt the CTA area.
- Session/login creates non-blocking consent audit row with legal versions, timestamp, app version and device id when missing.
- Legal information now opens a full legal center with KVKK, Kullanım koşulları and Gizlilik Politikası document selectors.
- Profile > Güvenlik ve gizlilik opens the same legal center for in-app access.
- Legal documents are long-form markdown files rendered directly in a scrollable document reader.
- Public website/domain: `https://riskdetected.com`.
- Public legal URLs are live:
  - `https://riskdetected.com/kvkk`
  - `https://riskdetected.com/kullanim-kosullari`
  - `https://riskdetected.com/gizlilik`
- Client photo preprocessing re-renders images before upload/analysis to strip EXIF/location/camera metadata.
- Edge Function strips common JPEG/PNG metadata before Gemini and Storage persistence.
- Client-side face blur is applied before upload/analysis.
- Result/detail screens prefer cleaned Storage image over local original preview.

Retention policy:

- Free analysis photos: 30 days.
- Pro analysis photos: 365 days.
- Raw AI responses: 30 days.
- PDF reports: kept until user deletes them.

Completed retention/delete work:

- Retention DB fields and triggers added.
- `retention-cleanup` Edge Function deployed.
- Supabase Cron runs retention cleanup daily at 02:15 UTC.
- Reports tab can delete stored report files/metadata.
- Analyses tab can delete analysis, findings, photos and related report records/files.
- Profile > Verilerim includes export, bulk delete and account deletion request entry points.

Follow-up:

- Account deletion completion flow is implemented and deployed as `account-deletion-complete`; run one disposable-account production spot-check before release.
- Public legal markdown contents have been published to the live website legal URLs.

## Error Handling and Supportability

Current state:

- Central iOS error mapping exists in `AppErrorMessage`.
- Analysis requests send `request_id` and `support_id` to `analyze`.
- Edge Function returns `request_id`, `support_id`, normalized `code` in errors.
- `ai_usage_logs` includes request/support metadata fields.
- PDF generation/storage/report metadata/download/delete paths share support code logic.
- AI 429/503/invalid JSON simulation paths were tested in simulator.
- PDF render/storage/metadata/download/delete simulation paths were tested.

Remaining P1.5 work:

- Finish remaining QA matrix rows:
  - auth/session
  - offline/network
  - picker/camera permission
  - report archive edge states
  - data/account actions
- Continue replacing any raw technical alert text with normalized Turkish messages.
- Add a support/debug copy action only where useful.

## Home and Result UX Status

Recent design decisions:

- Home "Saha modu aktif / date" strip was removed.
- Main "Taramayi Baslat" button is black with green text/icon.
- Photo upload dashed border is black and background is plain white/minimal.
- Recent analyses were redesigned several times and currently use smaller story-like circular items with soft critical ring and count badge.
- Annotate screen button should proceed directly to AI focus selection rather than forcing return to Home first.
- Canvas sheet includes optional 100-character user prompt to send a more specific instruction to Gemini.

Known image issue to keep checking:

- Recently analyzed images sometimes did not appear in Result header/detail immediately. Storage-cleaned image preference exists, but continue verifying new analyses.

## Known Constraints and Pitfalls

- Do not insert `fk_score` or `m5_score`; DB generates them.
- Do not expose raw RLS/HTTP/Gemini errors directly to users.
- Do not treat local `app.isPro = true` as real subscription entitlement.
- Real Pro tier should eventually be set only by verified RevenueCat/Supabase webhook/profile update.
- Phone auth is paused and should not be user-facing.
- Supabase built-in email sender has low limits; custom SMTP is needed.
- The user wants simulator automatically opened after app UI changes.

## Current Priority Plan

### P1 - Immediate

1. Finish Email OTP production readiness:
   - custom SMTP setup;
   - real mailbox OTP template validation;
   - Apple/Google provider verification.
2. Continue P1.5 error handling QA matrix and normalize remaining messages.
3. Keep PDF generation stable; any PDF regression is high priority.
4. Verify photo persistence/display for new analyses in:
   - Home recent items;
   - Result header;
   - Risk detail;
   - Reports/PDF.

### P2 - Product polish

1. Profile preferences:
   - Done: persistent System / Aydinlik / Karanlik theme choices under Profile > Tercihler.
   - Done: Turkish / English / System language preference is stored locally.
   - Follow-up: wire stored language preference into localized strings.
2. Persist Pro report defaults:
   - company logo;
   - company name;
   - expert/certificate data;
   - default report method.
3. Improve Reports tab:
   - search/filter;
   - status labels;
   - better empty/error states;
   - "load more" stored reports behavior.
4. Better Pro conversion states:
   - quota exhausted;
   - Pro AI confidence/quality messaging;
   - premium report features.
5. Header profile quick menu:
   - Done: tap top-right avatar to open compact overlay menu.
   - Done: include `Raporlarim`, `Analizlerim`, sign-out and night/light mode icon actions.
   - Done: Free users see `Plan Yukselt`; Pro users see passive `Pro uyesiniz`.
6. AI analysis focus refresh:
   - update analysis focus/canvas options;
   - user will provide fixed prompts for each focus;
   - keep frontend labels and backend prompt routing aligned.
7. Reports page design refresh.
   - Done: report-center summary panel, Pro value panel, saved-report card redesign and report-source selection redesign.
   - Done: production archive performance spot-check completed; duplicate `reports_user_id_idx` removed and Reports archive now logs PII-free initial/load-more timing telemetry.
8. Analyses page design refresh.
   - Done: analysis-center summary panel, search/filter surface, filter sheet polish and analysis card redesign.
9. Legal link destination refresh for KVKK, Kullanım şartları and Gizlilik Politikası pages.
   - Done: legal center with separate document selectors and long-content-ready section cards.
10. Profile page tabs and missing content sections.
11. Excel risk analysis export.
   - Done: `generate-excel-report` Edge Function generates XLSX workbooks for Pro users only.
   - Done: `reports` storage and metadata now support `xlsx` files.
   - Done: iOS can invoke Excel generation from the report source sheet and shows Excel files in the report archive.
   - Verified: Pro demo API smoke test generated a valid workbook with `Özet`, `Risk Analiz Tablosu`, `Aksiyon Planı`, `Rapor Bilgileri`.
   - Pending: simulator should be signed into Pro demo to manually test the full tap-to-share flow in-app.
12. First-install onboarding flow.
   - Pending: before the Apple/Google/e-mail Auth screen, show introduction, usage and short training screens with app visuals and concise copy.
   - Flow: user advances step by step with `İlerle`; after the last screen, continue to the existing login screen.
   - Persistence: save onboarding completion locally so it appears only on first install / first launch.

### P3 - Later

1. Provider fallback abstraction beyond Gemini.
2. Stronger Pro analysis flow:
   - stronger model;
   - multi-pass validation;
   - sector/procedure checklists;
   - low-confidence recheck.
3. Corporate/OSGB workflows only after individual MVP is stable.

## Build and Simulator

Preferred build/run workflow:

Use XcodeBuildMCP with defaults:

- project: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/RiskDetected.xcodeproj`
- scheme: `RiskDetected`
- configuration: `Debug`
- simulator: `iPhone 17 Pro`
- bundle id: `com.riskdetected.app`
- derived data: `/Users/keremkayalar/Library/Developer/Xcode/DerivedData/RiskDetected-codex`

Last verified after dark-mode card shadow change:

- Build succeeded.
- App launched on simulator.

## 2026-05-29 Design Decision

- Card depth is now centralized in `App/DesignSystem/RDShadow.swift`.
- Light mode keeps the right/bottom card depth shadow.
- Dark mode disables card and row shadows because the previous dark shadows created a muddy halo on dark surfaces.
- For dark mode, separate cards with surface tone and stroke instead of shadow activity.
- New cards should continue using `rdCardShadow` / `rdRowShadow`; the design token handles light/dark behavior.

## Supporting Docs

- `IMPLEMENTATION_PLAN.md`: master backlog/status plan.
- `AUTH_SETUP.md`: auth provider and dashboard setup.
- `QA/P1_5_Error_Test_Matrix.md`: error handling QA matrix.

## Git Notes

Before starting a new task, inspect:

```bash
git status --short
git log --oneline -8
```

Recent meaningful commits before this handoff included:

- `7944c14 Fix report sheet flow and disable phone bridge`
- `ef44224 Update auth flow and report UI`
- `83f7f80 test: add report failure simulation coverage`
- `ba2972a Harden AI error handling tests`
- `9ff7628 Add support ids to error handling`
- `81a4ae5 Refactor PDF progress handling`
- `4828a56 Improve PDF generation progress`
- `603e0af Fix risk analysis PDF reports`
