# RiskDetected Implementation Plan

> Güncel tek yapılacaklar özeti için bkz. `PROJECT_STATUS_AND_NEXT_2026-05-12.md`.
> Bu dosya tarihsel plan detaylarını korur; bazı maddeler son commitlerle tamamlanmış veya değişmiştir.

## Current Phase

- FAZ 1: iOS app MVP + Supabase/Gemini analysis flow.
- Current focus: finish P1 privacy/legal trust work, then move into error/message hardening, auth/subscription hardening and AI reliability.
- Product scope: individual HSE/ISG expert workflow. OSGB/corporate multi-tenant panels are out of scope for now.

## Completed

- SwiftUI app shell, onboarding, auth and main tab flow.
- Supabase Auth, profiles, analyses, findings, photos and AI usage wiring.
- Gemini Edge Function for photo/text risk analysis.
- Free standard analysis limit is now 1 per day.
- Demo Pro and Free users added to login screen.
- Home, History, Result and Report screens now use live analysis data instead of mock-heavy data.
- Inline photo analysis persists analyzed images into Supabase Storage and `photos`.
- Result screen can generate a local A4 landscape PDF report from the live analysis bundle, including logo, analysis metadata, uploaded photo, AI summary, risk counts and sorted finding details.
- iOS share sheet is wired to the PDF report action for local export/sharing.
- Free users keep the fixed RiskDetected PDF template. Pro users have a report settings entry point for detailed risk analysis output, method selection (Fine-Kinney / 5x5), editable report identity fields and per-report company logo selection.
- Pro detailed risk analysis output now uses a separate landscape form format instead of the standard PDF layout:
  - Fine-Kinney output includes Olasilik/Frekans/Siddet reference tables, risk band/action table and a wide hazard-control assessment form.
  - 5x5 output includes Olasilik/Siddet definitions, 5x5 matrix reference and a method-specific hazard-control assessment form.
- Quota/paywall UX has started:
  - Free users are blocked after the daily limit and routed to Pro.
  - The photo upload area also communicates the exhausted limit instead of letting the user start a blocked photo flow.
  - Header Pro CTA is visible as a lightweight conversion entry point.
- PDF/plan comparison completed against `RiskDetected Is Plani.pdf`.
- P0 plan alignment completed for the current MVP scope:
  - Edge Function plan limits now follow Free / Plus / Pro subscription tiers.
  - Current Free rule: 1 standard analysis per day and 1 canvas.
  - Current Pro rule: up to 10 detailed findings.
  - `reports` table + private `reports` Storage bucket migration added and applied to the linked Supabase project.
  - Generated PDFs are uploaded to Storage and written to `reports` metadata when possible.
  - Reports tab can regenerate a standard PDF for the selected analysis and download/share stored PDF reports.
  - Stale auth/app debug prints and normal Edge Function audit logs were removed.
- P1 privacy/legal work started:
  - `consents` table migration added and applied to the linked Supabase project.
  - RLS enabled; authenticated users can only read/insert their own consent rows.
  - Blocking first-analysis consent was removed for better UX.
  - Legal notice/link copy is shown on the login screen and Home screen instead.
  - Users are informed that signing in, registering or starting analysis means accepting the terms and relevant data processing notices.
  - Login/session creates a non-blocking background `consents` audit row with legal versions, timestamp, app version and device id when missing.
  - Consent audit failures are logged with retry backoff instead of being silently swallowed.
  - Client photo preparation re-renders selected images before analysis/upload so EXIF/location/camera metadata is stripped.
  - Edge Function also strips common JPEG/PNG metadata from inline images before sending them to Gemini and before persisting them to Storage.
  - Client-side face blur is applied before analysis/upload, and Result/Detail screens prefer the cleaned Storage image over the local original preview.
  - Retention fields and cleanup function added on Supabase:
    - Free analysis photos expire after 30 days.
    - Pro analysis photos expire after 365 days.
    - Raw AI responses expire after 30 days.
    - Reports are not auto-deleted; they remain until the user deletes them.
    - `retention-cleanup` Edge Function deployed for Storage API based photo cleanup.
    - Supabase Cron runs `retention-cleanup` daily at 02:15 UTC.
  - User-facing deletion started:
    - Reports tab can delete stored PDF report files and metadata.
    - Analyses tab can delete an analysis, its findings, photos and related report records/files.
    - Profile > Verilerim provides export, bulk report delete, bulk analysis delete and account deletion request entry points.
- Push notification foundation added:
  - iOS APNs permission/token registration service;
  - Profile > Bildirimler settings sheet;
  - Supabase push token/preference/event tables with RLS;
  - `send-push-notification` Edge Function deployed for APNs delivery after APNs secrets are configured.
- UI polish and theme foundation:
  - App no longer forces light mode; Profile > Ayarlar > Tercihler has persistent System / Aydinlik / Karanlik theme choices.
  - Core color tokens now adapt to dark/light mode while fixed black CTA surfaces use `rdOnyx`.
  - Header profile avatar opens a compact overlay menu with Analizlerim, Raporlarim, Pro status/upgrade, sign-out and theme toggle actions.
  - Pro users see `Pro uyesiniz` in the header menu instead of a plan-upgrade link.
  - Header profile menu closes on outside tap or scroll/drag and no longer changes page layout.
  - Bottom tab inactive text/icons are black in light mode while active icon remains green.
  - Main CTA button style has a right-side action capsule; auth Apple button opts out of that action icon.
  - Dark mode CTA contrast QA completed for Taramayi Baslat, Standart Rapor, Risk Analizi and PDF creation actions; dark-mode primary CTAs use green background with white text/icons.
  - Standart Rapor action button is tuned to stay single-line and centered in light/dark mode.
  - Reports tab visual refresh completed with report center summary, Pro value panel, premium saved-report rows and clearer report-source selection.
  - Analyses tab visual refresh completed with analysis center summary, modern search/filter surface, cleaner filter sheet and more scannable analysis cards.
  - Analysis thumbnails are clipped to a fixed box so images of any aspect ratio cannot overlap list/result text.
  - Text-only analyses now use a standard Metin Analizi artwork in recent/history/result/report surfaces instead of blank photo placeholders.
  - Free users see a compact daily trial quota hint under upload/text input, with dynamic `2/2`, `1/2`, `0/2` display.

## Partially Done - Revision Queue

These items exist in some form, but need revision before we treat them as production-ready.

1. AI usage logging
   - Current state: `ai_usage_logs` exists and logs core provider/model/token/error data.
   - Target additions: request/job id, latency, input image size, preprocessing version, estimated cost, fallback source, normalized fail reason.

2. Provider fallback
   - Current state: Gemini model-level fallback exists.
   - Target: provider abstraction interface with health/fallback routing.
   - Initial chain:
     - Free: Gemini Flash-Lite -> Gemini Flash -> fallback vision provider.
     - Pro: strongest available Gemini paid model -> Claude/OpenAI/OpenRouter fallback, depending on cost and API availability.

3. Image preprocessing
   - Current state: iOS resizes/compresses images before inline upload; Edge Function strips common JPEG/PNG metadata chunks/segments before AI + Storage persistence.
   - Target: full backend preprocessing pipeline for standard resize/quality, face blur and logo blur.
   - Storage rule target: store only cleaned/blurred images when possible; avoid long-term original image storage.

4. Error handling and error-message system
   - Current state: quota, Gemini 429/503 and several PDF/report errors are mapped to user-facing messages, but the system is still fragmented.
   - Target: comprehensive error research and implementation pass across iOS, Supabase, Storage, Edge Functions, Gemini, PDF generation and auth.
   - Scope:
     - inventory every known error source and user-visible failure path;
     - normalize technical errors into stable app error categories;
     - show clear Turkish user messages with "ne oldu", "ne yapmalisin" and optional retry/pro action;
     - keep raw technical detail out of normal alerts, but attach support/debug id for follow-up;
     - record provider/status/request ids in logs where available;
     - handle retry/fallback states for AI 429/503/timeouts and invalid JSON;
     - improve PDF/report archive errors so user sees whether local PDF was created, upload failed or DB metadata failed;
     - add QA checklist for forcing each error path in simulator and Supabase logs.

5. Pro AI confidence upgrade
   - Current state: confidence is displayed and Pro copy exists.
   - Target: actually improve Pro analysis quality using stronger models, higher image budget, multi-pass validation, sector/procedure checklists and low-confidence re-checking.
   - Copy rule: do not promise a fixed score. Preferred wording: "Pro analizlerde daha kapsamli model ve dogrulama katmani ile daha yuksek guven hedeflenir."

6. Pro report identity/logo
   - Current state: per-report company logo and identity fields can be selected in the PDF settings flow.
   - Target: persist company logo and default report identity under Profile so the user does not reselect them each time.

7. Reports tab and report storage
   - Current state: generated PDFs are uploaded to Supabase Storage, metadata is written to `reports`, and the Reports tab can download/regenerate reports.
   - Target additions: report archive filtering/search, report status labels and better empty/error states.

8. Email OTP auth
   - Current state: phone/Firebase auth has been removed from the app; the user-facing passwordless flow is Supabase Email OTP.
   - Target: support registration and login with e-mail verification code, without forcing phone verification in MVP.
   - Supabase requirement: Email provider enabled and OTP template shows the 6-digit token.
   - Test requirement: verify send code -> enter code -> profile load -> main app flow with a real mailbox.
   - Removed phone auth: Firebase iOS SDK, Firebase URL scheme and `firebase-phone-bridge` are no longer part of the active app/backend surface.

9. App preferences
   - Current state: Profile/Settings screen has a persistent quick dark-mode toggle. Full preferences screen and language selection are still pending.
   - Target: add persistent user preferences under Profile > Tercihler.
   - Theme options:
     - System / Cihaz ayarını kullan;
     - Aydınlık;
     - Karanlık.
   - Language options:
     - Türkçe;
     - English;
     - System / Cihaz dili.
   - Persistence target: local app storage for instant UX, then optional Supabase profile preference sync after auth/subscription hardening.
   - Product note: report language and app language may need separate control later; MVP can keep them tied unless user feedback says otherwise.

## Next Priority Backlog

### P0.5 - First Launch Onboarding

1. Add first-install onboarding before the Auth screen:
   - show only for users who have not completed onboarding before;
   - include app visuals/screenshots and short educational copy;
   - explain what RiskDetected does, how photo/text analysis works, AI focus selection, reports and Pro value;
   - use step-by-step `İlerle` flow and finish with the existing Apple/Google/e-mail login screen;
   - persist completion locally so returning users go directly to Auth/Main as appropriate.

### P0 - Stabilize MVP and Plan Alignment

1. Done: Replace old Free/Pro-only limits with Free / Plus / Pro plan rules.
2. Done: Persist report metadata/files:
   - create/verify `reports` table fields;
   - upload generated PDF to Storage;
   - show downloadable report rows in Reports tab.
3. Done: Add real report regeneration/download flow from Reports tab.
4. Done: Remove remaining stale/debug logs once analysis/report flow is stable.
5. Follow-up verification: run an end-to-end simulator test after the next build/install:
   - generate a PDF from ResultView;
   - confirm it appears in Reports tab;
   - download/share the stored PDF from Reports tab.
6. Done: code review hardening pass:
   - photo preprocessing moved off the main actor;
   - Edge Function strips common inline image metadata before AI + Storage;
   - consent audit failures log with retry backoff.

### P1 - Privacy, Legal and Trust

1. Partially done: KVKK/Terms/Consent visibility:
   - login screen includes legal acceptance notice and a legal information link;
   - Home screen legal notice was removed because CTA altında tasarımı yoruyordu;
   - blocking first-analysis consent was intentionally removed for lower friction;
   - versioned `consents` table exists with RLS and minimum grants;
   - login/session creates a non-blocking background audit row with legal versions, timestamp, app version and device id when missing.
   - Done: consent audit failures are logged with retry backoff;
   - Done: legal information link opens a full legal center with KVKK, Kullanım koşulları and Gizlilik Politikası documents;
   - Done: Profile > Güvenlik ve gizlilik opens the same legal center for in-app access;
   - Done: legal center now renders the long-form markdown documents directly in a scrollable document window;
   - Done: legal documents use Riskdetected, `info@riskdetected.com`, Eskişehir and `https://riskdetected.com` as the public contact/site details.
   - Follow-up: publish these same documents on the website under `https://riskdetected.com/kvkk-aydinlatma-ve-acik-riza-metni`, `https://riskdetected.com/kullanim-kosullari` and `https://riskdetected.com/gizlilik-politikasi`.
2. Visual data policy:
   - Done: client-side EXIF cleanup by pixel-only re-render before AI analysis/upload;
   - Done: Edge Function strips common JPEG/PNG metadata before Gemini and Storage persistence;
   - Done: client-side face blur is applied to sanitized analysis/upload images using Vision face detection;
   - Done: Result and detail screens prefer cleaned Storage thumbnails/images over local original previews;
   - company logo blur;
   - cleaned-image-only storage policy where practical.
3. Clear retention/deletion policy:
   - Done: policy defined as Free photos 30 days, Pro photos 365 days, raw AI responses 30 days, reports until user deletion;
   - Done: `analyses.raw_ai_response_expires_at`, `photos.retention_expires_at` and `photos.retention_policy` added;
   - Done: DB triggers automatically assign retention windows for new analyses/photos;
   - Done: `private.cleanup_expired_retention(batch_size)` added for scheduled/admin cleanup;
   - Done: `retention-cleanup` Edge Function deployed to delete expired Storage objects through the supported Storage API path;
   - Done: Reports tab exposes per-report delete action;
   - Done: Analyses tab exposes per-analysis delete action;
   - Done: scheduled daily execution through Supabase Cron (`riskdetected-retention-cleanup-daily`, `15 2 * * *`);
   - Done: Profile > Verilerim section added for JSON export, bulk report delete, bulk analysis delete and account deletion request capture;
   - Follow-up: implement privileged backend/admin completion flow for account deletion requests.

### P1.5 - Error Handling, Messages and Supportability

1. Error inventory and taxonomy:
   - Started: central `AppErrorMessage` taxonomy added on iOS for primary user-facing categories and support codes;
   - map all app error sources: auth, profile, quota, photo picker/camera permission, preprocessing/face blur, Storage upload/download, Supabase RLS/DB, Edge Function, Gemini, JSON decoding, PDF generation, report archive upload, network/offline and subscription state;
   - create stable categories such as `quotaExceeded`, `authRequired`, `networkUnavailable`, `storageDenied`, `aiRateLimited`, `aiUnavailable`, `reportArchiveFailed`, `pdfRenderFailed`, `validationFailed`, `unknown`;
   - define which errors are user-actionable, retryable, support-only or silently logged.
2. User-facing message rewrite:
   - Started: Home, Auth, History, Result, Report and Profile data-action alerts now route major failures through normalized Turkish messages instead of raw backend text;
   - replace raw backend/HTTP/enum/RLS messages in alerts with short Turkish product messages;
   - include one clear next action: retry, choose another photo, sign in again, upgrade to Pro, wait and retry, or contact support;
   - keep technical details behind a collapsible/debug copy action or support id, not in the main alert.
3. Error logging and support ids:
   - Started: iOS analysis requests now send `request_id` and `support_id` to the `analyze` Edge Function;
   - Started: `analyze` returns `request_id`, `support_id` and normalized `code` in function-level error JSON;
   - Started: `ai_usage_logs` now has `request_id`, `support_id`, `error_code`, `http_status` and `fallback_source` columns;
   - Started: Edge Function writes trace/support metadata into AI usage logs and raw analysis input audit;
   - Started: generated PDF reports now write `request_id` and `support_id` into `reports` metadata;
   - Started: PDF Storage upload, report metadata save, stored report download and single report delete paths share the same support code between app logs and user-facing messages;
   - generate a client-side request/support id for analysis and PDF flows;
   - pass request id to Edge Function and log it in `ai_usage_logs` / report metadata where relevant;
   - log normalized error code, provider/model, status code, latency and retry/fallback outcome.
4. Retry and fallback UX:
   - Started: iOS analysis flow retries transient Edge Function / Gemini failures once for the same analysis record instead of creating duplicate analyses;
   - Started: Analyzing screen can show a compact "AI servisi yoğun, tekrar deneniyor" status card while retrying;
   - Started: retry attempts are logged with request/support ids in app logs;
   - add controlled retry for Gemini 429/503/timeouts;
   - show "tekrar deneniyor" / fallback provider state when applicable;
   - avoid duplicate analysis/report creation on retry.
5. QA and simulator test matrix:
   - Started: QA matrix created at `QA/P1_5_Error_Test_Matrix.md`;
   - checklist covers quota full, offline/network fail, expired session, Gemini 429/503, invalid AI response, Storage policy failure, PDF render/archive failure, report download/delete failure, missing photo/text validation and data/account actions;
   - verify each case displays the intended message and does not leave the UI stuck.
   - Done: deterministic test-only Edge Function flags added and deployed for AI 429/500/502/503/504 and invalid JSON simulation; guarded by `RISKDETECTED_ENABLE_TEST_SIMULATION=true`.
   - Done: simulator verified AI 429, AI 503 and invalid AI JSON paths; alerts show normalized Turkish messages and `ai_usage_logs` contains matching `support_id` rows.
   - Done: DEBUG-only iOS report failure simulation flags added for PDF render, Storage upload, reports metadata insert, stored report download and stored report delete paths.
   - Done: simulator verified PDF render failure simulation with normalized `PDF Hatası` and support id.
   - Done: simulator verified PDF Storage upload, reports metadata insert, stored report download and stored report delete simulations with normalized messages and support ids.
   - Added: DEBUG-only iOS data-action failure simulation flags for photo download, analysis delete, bulk report/analysis delete, data export and account deletion request paths.
   - Added: support/request id logging now covers photo thumbnail download failures, single analysis delete failures and Profile > Verilerim data-action failures.
   - Added: Free quota paywall route can show a quota notice with support id for traceable E01 verification.
   - Follow-up: manually verify remaining QA matrix rows E01-E05 and E09-E10/E16-E18 in simulator; code support is ready for the full remaining set.

### P2 - Auth and Subscription

1. Email OTP login.
   - Decision update 2026-05-09: phone login is temporarily canceled for MVP; user-facing passwordless auth is Supabase Email OTP.
   - Done: auth UI now shows "E-posta ile giriş yap" instead of phone number login.
   - Done: `AuthService.sendEmailOTP(email:)` and `verifyEmailOTP(email:token:)` are wired to Supabase Email OTP.
   - Done: Supabase Email provider smoke test passed with `POST /auth/v1/otp` returning 200 for a valid mailbox-shaped address.
   - Done: Auth session issuance verified through Admin `generate_link` + `/auth/v1/verify` token hash flow.
   - Done: Email send rate-limit and invalid email errors are normalized into auth-specific Turkish user messages instead of generic AI/rate-limit messaging.
   - Done: Auth screen visual polish pass:
     - softened hero image to white transition;
     - lifted logo/slogan block in the email entry state;
     - changed Google button to a branded colored wordmark style;
     - changed email placeholder to muted grey and made the "Diger giris yontemleri" link more readable.
   - Required external setup: Supabase Email provider must be enabled, and both `Confirm signup` and `Magic Link` templates must expose the 6-digit token using the repo templates under `supabase/templates/`.
   - Required external setup: configure custom SMTP in Supabase Auth to avoid low built-in email rate limits and improve delivery.
   - SMTP candidates: Resend, Postmark, SendGrid or Mailgun. Prefer verified-domain transactional SMTP before public launch.
   - Remaining manual check: use a real accessible mailbox and confirm new-user and existing-user emails render the 6-digit OTP token instead of a link.

2. Push notifications.
   - Done: APNs token registration and Supabase token/preference persistence.
   - Done: Profile > Bildirimler settings sheet.
   - Done: `send-push-notification` Edge Function scaffold deployed.
   - Follow-up: configure Apple APNs Auth Key secrets in Supabase.
   - Follow-up: connect trusted backend events for analysis complete, report ready and account/security updates.
   - Follow-up: real-device/TestFlight delivery QA because APNs production delivery cannot be fully proven by simulator alone.
   - Removed: Firebase phone verification and Supabase bridge are no longer part of the active app.
   - Removed: Firebase iOS SDK packages (`FirebaseCore`, `FirebaseAuth`) from the Xcode project.
   - Removed: `FirebaseBootstrap`, `FirebasePhoneAuthService`, Firebase URL scheme and `GoogleService-Info` template/local files.
   - Removed: `firebase-phone-bridge` from the live Supabase Edge Function list.
   - Removed: `firebase_phone_auth_links` table dropped from the remote Supabase database.
   - Previous Firebase bridge and billing blockers are obsolete because phone auth was removed from MVP scope.
   - Added: auth setup notes captured in `AUTH_SETUP.md`.
2. Apple Sign In production hardening.
   - Started: iOS Apple Sign In service added with nonce hashing and Supabase `signInWithIdToken(provider: .apple)`.
   - Started: Sign in with Apple entitlement added to the target.
   - Follow-up: configure Apple provider credentials in Supabase Dashboard and Apple Developer portal, then verify on a real Apple account.
3. Google Sign In production hardening.
   - Started: Google button is wired to Supabase OAuth/PKCE web flow.
   - Added: app URL scheme `io.supabase.riskdetected` is registered through `Config/RiskDetectedInfo.plist` for OAuth/magic-link callbacks.
   - Follow-up: configure Google provider credentials and redirect URL in Supabase Dashboard; verify callback URL handling.
4. RevenueCat subscription integration.
5. Replace local/mock Pro toggles with verified subscription/profile refresh only.

### P2.5 - App Preferences and Localization

1. Theme preference:
   - Done: Profile > Tercihler includes System / Aydinlik / Karanlik theme selection;
   - Done: theme applies globally through `preferredColorScheme`;
   - Done: core design tokens adapt to dark/light mode;
   - Done: dark-mode CTA contrast QA for Home, Result and Report settings primary actions;
   - Follow-up: continue final contrast QA only after new Result, Reports, Paywall or sheet UI changes.
2. Language preference:
   - Done: Profile > Tercihler currently exposes only Turkce because English localization is not shipped yet;
   - Done: stored System / English preferences are normalized back to Turkce until multi-language UI is implemented;
   - introduce localized string structure before hardcoding grows further;
   - first target screens: Auth, Home, Analysis, Result, Reports, Profile;
   - later target: PDF/report output language selection.
3. Preference sync:
   - keep MVP local-first;
   - later store preferred theme/language in `profiles` or a dedicated `user_preferences` table.

### P2.6 - UI/UX Backlog From Product Notes

1. Header profile quick menu:
   - Done: tapping the top-right profile avatar opens a compact dropdown/popover;
   - Done: includes `Analizlerim`, `Raporlarim`, plan upgrade for Free users and `Pro uyesiniz` for Pro users;
   - Done: includes sign-out icon/action;
   - Done: includes dark/light mode icon/action for quick theme switching;
   - Done: menu closes on outside tap and scroll/drag;
   - Done: menu is overlay-only and does not change page layout.
2. AI analysis focus refresh:
   - Done: focus sheet title now reads `Odaklı Analiz`;
   - Done: focus confirmation CTA uses the green detect style so it remains readable in dark mode;
   - user will provide fixed prompts for these focus modes;
   - store prompts clearly so frontend labels and backend prompt routing stay aligned.
3. Reports page design refresh:
   - Done: redesigned Reports tab visual hierarchy;
   - Done: improved saved reports, report source selection and actions;
   - Done: added calm Pro value presentation for detailed risk tables, company logo and PDF customization;
   - Done: standard report output no longer shows AI confidence percentages in the app preview, PDF or Excel.
4. Analyses page design refresh:
   - Done: redesigned Analyses tab visual hierarchy;
   - Done: retained quick filtering chips and improved the filter sheet presentation;
   - Done: modernized analysis cards with thumbnail, risk label, metadata and status.
   - Done: quota-exhausted photo upload card has dark-mode-specific colors and copy uses `Yükselt`.
5. Legal link destination refresh:
   - Done: updated pages opened from KVKK, Kullanım şartları and Gizlilik Politikası links;
   - Done: legal center uses separate document selectors and a scrollable plain-document reader;
   - Done: final markdown legal contents are bundled in-app from `App/LegalDocuments`;
   - Follow-up: mirror the bundled legal documents to the public website legal URLs.
6. Profile page tabs and content:
   - design and implement profile page sections/tabs;
   - fill missing content for account, preferences, reports, analyses, notifications and data/privacy areas.

7. Paywall page redesign:
   - redesign the Plus/Pro upgrade screen with the latest commercial limits;
   - show Plus as 10 standard analyses/day, 2 detailed analyses/day and 150 reports/month;
   - show Pro as 40 standard analyses/day, 10 detailed analyses/day and 750 reports/month;
   - make RevenueCat package loading, current-plan state, purchase, restore and error states clearer;
   - verify the refreshed paywall on TestFlight with real-device purchase/restore QA.

### P2.7 - Excel Risk Analysis Export

1. Backend-generated XLSX export: ✅ Done
   - create Supabase Edge Function `generate-excel-report`;
   - function authenticates user JWT and reads only the requested user's analysis/finding/profile data;
   - generate `.xlsx` with Summary, Risk Analysis Table, Action Plan and Report Info sheets.
   - server-side Pro entitlement check is enforced before workbook generation.
2. Storage and metadata: ✅ Done
   - allow `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` in the private `reports` bucket;
   - store generated Excel files under the existing `reports` bucket;
   - save metadata in `public.reports` with `format = xlsx`, proper mime type, size and support/request ids.
3. iOS integration: ✅ Done
   - add client service method to invoke the Excel Edge Function;
   - download/share generated XLSX from the existing report archive flow;
   - show Excel as a Pro report action near detailed risk analysis/PDF settings.
4. QA: ✅ Backend smoke test done / manual app Pro flow pending
   - generate an Excel report from an existing completed analysis;
   - verify it appears in Reports archive and opens via iOS share sheet;
   - verify PDF generation remains unchanged.
   - Done: Pro demo API smoke test generated `/tmp/riskdetected-test.xlsx`; workbook opened with sheets `Özet`, `Risk Analiz Tablosu`, `Aksiyon Planı`, `Rapor Bilgileri`.
   - Pending: sign into Pro demo in simulator and run the full in-app tap/share flow.

### P3 - AI Reliability and Cost Control

0. Gemini multi-project API key pool for MVP launch buffer:
   - Status: backend implemented; wait until the user provides the additional Gemini API keys.
   - Context: keys will come from different Google accounts and different Google Cloud projects, so quota pools should be separate. Multiple keys in the same project would not increase quota.
   - Done: `analyze` Edge Function key pool implemented and deployed.
   - Done: `ai_usage_logs.api_key_alias` and `attempt_count` added.
   - Supabase Edge Function secrets target:
     - `GEMINI_API_KEY_PRIMARY`;
     - `GEMINI_API_KEY_SECONDARY`;
     - `GEMINI_API_KEY_TERTIARY`.
   - Backward compatibility: existing `GEMINI_API_KEY` is treated as primary if `GEMINI_API_KEY_PRIMARY` is absent.
   - Routing target:
     - normal traffic starts with `gemini_primary`;
     - on retryable provider failures such as `429 RESOURCE_EXHAUSTED`, quota/rate-limit, `503`, `500/502/504` or timeout, retry the same analysis record with `gemini_secondary`, then `gemini_tertiary`;
     - do not fallback for user/input errors such as invalid payload, unsupported image, validation failure or non-retryable `400`.
   - Logging target:
     - never log or return real API keys;
     - log only aliases such as `gemini_primary`, `gemini_secondary`, `gemini_tertiary`;
     - write `attempt`, `provider`, `api_key_alias`, `model`, `http_status`, `error_code`, `fallback_source`, `latency_ms`, `request_id` and `support_id` into `ai_usage_logs` where possible.
   - Operational guardrails:
     - add Google Cloud budget alerts / quota monitoring per project before public traffic;
     - treat this as a temporary MVP reliability bridge until paid quota, quota increase requests and broader provider fallback are in place.
1. Provider abstraction interface:
   - `analyzePhoto`;
   - `analyzeText`;
   - `isAvailable`;
   - `estimateCost`;
   - normalized error mapping.
2. Provider/model fallback:
   - retry on 429, timeout, 5xx and invalid JSON;
   - log fallback source and final provider/model.
3. Async job architecture decision:
   - keep current sync flow for MVP if stable;
   - move Pro report generation and slower provider fallback to async job if timeout risk grows.
4. Expand `ai_usage_logs` fields and dashboards:
   - p95 latency;
   - success rate;
   - fallback rate;
   - daily cost;
   - model/provider split.

### P4 - Product Quality Loop

1. Per-finding feedback:
   - correct / missing / wrong;
   - optional note;
   - write to `feedback` table.
2. Confidence handling:
   - low-confidence findings appear as "dogrulanmali";
   - Pro can re-check low-confidence findings before final result.
3. Photo quality assistant:
   - blur/darkness detection;
   - minimum resolution warning;
   - re-take guidance before upload.

### P5 - Reporting and Exports

1. Pro report defaults:
   - persist company logo;
   - persist preparer name/title/certificate/company fields.
2. Detailed risk analysis outputs:
   - keep Fine-Kinney and 5x5 PDF formats;
   - later evaluate DOCX/XLSX only after PDF flow is stable.
3. Export backlog:
   - Excel export is optional;
   - Word export is optional;
   - both are lower priority than stored PDFs and report regeneration.

## Out of Scope for Now

- OSGB/corporate admin panel.
- Multi-company tenant management.
- Team/user role management beyond the individual expert profile.
- Long-term storage of original unprocessed images.
- Word/Excel as MVP blockers.

## Known Decision Points

1. Keep current synchronous `/analyze` flow or introduce async job processing?
2. If phone login returns later, should it be Supabase native phone OTP or a new audited backend-owned verification flow?
3. Which paid Pro AI model/provider becomes the primary production route?
4. How strict should image retention be for KVKK and user trust?
   - Current decision: Free analysis photos 30 days, Pro analysis photos 365 days, raw AI responses 30 days, reports until user deletion.
5. Free max 4 / Pro max 14 is no longer the active business rule; current rule is Free 1 standard analysis/day and Pro up to 10 detailed findings.

## Deployment Notes

- Supabase CLI is available through `npx supabase`.
- Remote migration history contains older timestamped migrations from the previous setup that are not fully mirrored locally, so `supabase db push` reports a history mismatch.
- For the P0 reports migration, SQL was applied with:
  - `npx supabase db query --linked -f supabase/migrations/20260506_reports_storage.sql`
- For the P1 retention migration, SQL was applied with:
  - `supabase db query --linked -f supabase/migrations/20260507221522_retention_policy.sql`
- P1 retention Edge Function deploy:
  - `supabase functions deploy retention-cleanup --use-api`
  - `supabase functions deploy retention-cleanup --use-api --no-verify-jwt`
- P1 retention Cron migration:
  - `supabase db query --linked -f supabase/migrations/20260508021838_retention_cron_schedule.sql`
- P1 account deletion request migration:
  - `supabase db query --linked -f supabase/migrations/20260508022421_account_deletion_requests.sql`
- Edge Function deploy was completed with:
  - `npx supabase functions deploy analyze --use-api`
  - `supabase functions deploy analyze --use-api`

## Last Checkpoint

- Last commit: `35b846c chore: harden photo privacy and consent audit`.
- Working tree now contains P1 retention/visual privacy follow-up changes pending commit.
