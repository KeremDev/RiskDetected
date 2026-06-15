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
- Reports archive development:
  - Search and format/type filters added for stored reports.
  - PDF/XLSX, method and ready/loading/deleting status labels added to report rows.
  - Better empty, filtered-empty and error states added.
  - Load-more behavior now pages through filtered results instead of dumping the whole archive.
- Pro/Plus report defaults now come from Profile:
  - company logo is loaded from the saved profile logo;
  - preparer name, title, certificate/belge no, company name/info and default risk method prefill PDF settings;
  - standard PDF, detailed PDF and XLSX output metadata use the same profile defaults.
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
     - Free: Free Gemini key pool only (`GEMINI_API_KEY_PRIMARY` / legacy `GEMINI_API_KEY`, then secondary/tertiary) with `gemini-2.5-flash` primary -> `gemini-2.5-flash-lite` fallback.
     - Plus/Pro: Paid Gemini key pool only (`GEMINI_API_KEY_PAID`, optional paid secondary) after backend subscription validation; `gemini-2.5-pro` primary -> `gemini-2.5-flash` fallback; no fallback to Free secrets.

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

6. Email OTP auth
   - Current state: phone/Firebase auth has been removed from the app; the user-facing passwordless flow is Supabase Email OTP.
   - Target: support registration and login with e-mail verification code, without forcing phone verification in MVP.
   - Supabase requirement: Email provider enabled and OTP template shows the 6-digit token.
   - Test requirement: verify send code -> enter code -> profile load -> main app flow with a real mailbox.
   - Removed phone auth: Firebase iOS SDK, Firebase URL scheme and `firebase-phone-bridge` are no longer part of the active app/backend surface.

7. App preferences
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

### Active Release Checklist - 2026-05-18

#### Done / Completed

1. Google OAuth production/branding setup completed and documented.
2. Public legal URLs are live and app/legal references use the current short paths:
   - `https://riskdetected.com/gizlilik`
   - `https://riskdetected.com/kullanim-kosullari`
   - `https://riskdetected.com/kvkk`
3. Email OTP live smoke test passed with real Supabase session issuance.
4. RevenueCat/App Store Connect products, entitlements and offerings were checked for Plus monthly/yearly and Pro monthly/yearly.
5. TestFlight purchase, restore, expiration/downgrade checks completed; TL price display was verified.
6. Archive / Organizer review completed by owner:
   - embedded entitlements;
   - APNs production;
   - distribution signing;
   - privacy report;
   - GoogleSignIn / RevenueCat privacy manifests.
7. Xcode signing conflict fixed by removing manual `Apple Distribution` signing override and letting automatic signing choose the correct identity/profile.
8. Support mail service is configured and verified through Resend/Supabase Edge Function.
9. Support form now supports multiple attachments in the backend path; final UI/device check remains useful after attachment UX changes.
10. Paywall V2 was created as the Plus-first paywall and Free quota/upgrade paths now route to it.
11. Paywall V2 layout polish completed:
    - Plus-first full-width card;
    - Pro preview opens Paywall V1;
    - headline contrast improved;
    - Free selectable card removed;
    - Free continuation moved to a low-contrast CTA link.
12. Home logo tap navigates back to the home tab.
13. Bottom tab center label changed from `Tara` to `Analiz` and spacing/font were adjusted.
14. Auth email/OTP screens received readability fixes for dark/light backgrounds.
15. Supabase auth session handling updated for `emitLocalSessionAsInitialSession` and expired-session filtering.
16. Result screen fixed truncated `Mevzuat` info card text.
17. PDF report wording changed from `AI Özeti` to `Uygunsuzluk Özeti`, and report detail text fitting was improved.
18. Report/PDF logo behavior updated: if a profile/company logo exists, the report header uses it instead of the RiskDetected logo; RiskDetected remains the fallback.
19. Free quota state now uses local cache to reduce the short delay where exhausted users could briefly see upload entry points again.

#### Still To Do Before Submission

1. Onboarding redesign:
   - build the new first-launch onboarding flow;
   - explain photo/text analysis, focus selection, reporting and Plus/Pro value;
   - persist completion locally.
2. App Store Connect metadata entry:
   - App Store Name: `RiskDetected İSG Analizi`;
   - Subtitle: `Fotoğrafla Risk Tespiti`;
   - Keywords: `isg,risk,analiz,iş,güvenliği,saha,denetim,rapor,fine,kinney,5x5,matris,kkd,pdf,excel`.
3. Enter/confirm App Store privacy nutrition form from `QA/App_Store_Privacy_Nutrition_2026-05-16.md`.
4. Provide App Review test account and OTP access plan.
   - Prepared: review account path is `riskdetected_appreview@fastmail.com` with real email OTP; copy-ready notes live at `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`.
   - Do not commit the actual webmail password. Paste it only into App Store Connect Notes.
   - Before submission, verify Fastmail webmail access, confirm Supabase Email OTP Expiration is `3600` seconds, and run a physical-device TestFlight OTP smoke test.
5. APNs production real-device/TestFlight push test.
6. Full TestFlight release pass:
   - clean install;
   - onboarding;
   - Email OTP;
   - Apple login;
   - Google login;
   - Free daily limit and Paywall V2 route;
   - Plus/Pro purchase and restore;
   - camera/gallery permissions;
   - analysis -> result -> PDF/XLSX -> share;
   - dark mode;
   - account deletion request.
7. Home `Son uygunsuzluklar` final verification:
   - recent completed analyses must appear immediately after result close;
   - photo analyses must show circular thumbnails;
   - text analyses may show the text placeholder state.
8. Support attachment UX final check:
   - multiple attachments should remain attached and arrive together.
9. Profile page future refresh:
   - tabs/sections for account, preferences, reports, analyses, notifications and data/privacy.
10. Final iPhone screenshot set:
    - 6.9-inch primary set;
    - optional 6.5/5.5 fallback;
    - sequence: photo risk analysis, focus selection, score result, PDF/XLSX report, archive, Plus/Pro paywall.
11. Optional App Preview video:
    - 15-30 seconds;
    - photo select -> analysis -> report -> share.
12. Full App Review preflight gate:
    - run a repo hygiene pass for generated artifacts, QA-only files, screenshots, unused images and review-invisible debug/test surfaces;
    - verify the final Xcode archive, entitlements, privacy manifest, Info.plist, Release build and app binary contents;
    - re-check App Store Connect metadata, privacy nutrition, IAP/subscription products, review notes, support/privacy/terms URLs and screenshot sets;
    - run backend production readiness checks for Supabase functions, secrets, RLS/migrations, RevenueCat webhook/sync, APNs production and support/contact flows;
    - run physical-device TestFlight smoke for onboarding, auth, paywalls, purchase/restore, analysis, PDF/XLSX, account deletion, support and push;
    - create/update `QA/APP_STORE_PREFLIGHT_<date>.md` and `QA/APP_STORE_REVIEW_NOTES_<date>.md` before tapping `Add for Review`.
13. Pro AI quality upgrade after launch or before paid scale-up:
    - stronger paid Gemini model or provider fallback;
    - multi-pass validation;
    - sector/procedure checklist;
    - low-confidence re-check.

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
   - Done: public legal URLs are live at `https://riskdetected.com/gizlilik`, `https://riskdetected.com/kullanim-kosullari` and `https://riskdetected.com/kvkk`.
   - Done: App Store privacy nutrition disclosure draft prepared at `QA/App_Store_Privacy_Nutrition_2026-05-16.md`.
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
   - Done: privileged `account-deletion-complete` Edge Function and migration added for account deletion request completion;
   - Done: completion flow removes user Storage prefixes, deletes the Supabase Auth user with admin privileges and preserves the request row as completed audit evidence;
   - Follow-up: deploy the function, set `ACCOUNT_DELETION_ADMIN_SECRET` if needed and run one disposable-account production spot-check.

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
   - Done: production log privacy pass completed on 2026-05-16; Edge Function logs now avoid raw user ids, Storage paths, provider details and token-like values where practical.
   - Done: support id lookup runbook added at `QA/Production_Log_Privacy_Support_Runbook_2026-05-16.md`.
   - Done: production Supabase secrets scan found no active simulation flag names.
   - Done: updated Edge Functions deployed: `analyze`, `generate-excel-report`, `support-contact`, `send-push-notification`, `retention-cleanup`, `account-deletion-complete`.
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
   - Done: 2026-05-17 live OTP smoke test passed with `POST /auth/v1/otp` returning `200 {}` and `/auth/v1/verify` returning `200` plus a real Supabase session for the delivered code.
   - Done: Resend/Supabase SMTP delivery was verified with a real mailbox; OTP for an address already linked to Google identity produced a session for the same existing user.
   - Done: Email send rate-limit and invalid email errors are normalized into auth-specific Turkish user messages instead of generic AI/rate-limit messaging.
   - Done: Auth screen visual polish pass:
     - softened hero image to white transition;
     - lifted logo/slogan block in the email entry state;
     - changed Google button to a branded colored wordmark style;
     - changed email placeholder to muted grey and made the "Diger giris yontemleri" link more readable.
   - Done: Supabase Email provider is enabled, and the `Confirm signup` / `Magic Link` templates expose the 6-digit token using the repo templates under `supabase/templates/`.
   - Done: custom SMTP is configured in Supabase Auth to avoid low built-in email rate limits and improve delivery.
   - Remaining manual check: release-candidate TestFlight smoke can repeat new-user and existing-user OTP once more before submission.

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
   - Done: Apple provider credentials were configured in Supabase Dashboard and Apple Developer portal.
   - Done: 2026-05-15 TestFlight real-device Apple Sign In passed; Supabase `apple` identity and default `profiles` row were verified.
3. Google Sign In production hardening.
   - Done: Google button uses native Google Sign-In SDK and passes the Google `idToken` to Supabase `signInWithIdToken(provider: .google)`.
   - Added: app URL scheme `io.supabase.riskdetected` is registered through `Config/RiskDetectedInfo.plist` for OAuth/magic-link callbacks.
   - Done: Google provider credentials and redirect URL are configured in Supabase Dashboard.
   - Done: Google native SDK sign-in passed live existing-user and new-user tests.
   - Done: Google Auth Platform Audience publishing status is `In production`; Branding URLs use `riskdetected.com`; Data Access only contains non-sensitive `userinfo.email`, `userinfo.profile` and `openid` scopes.
4. Done: RevenueCat subscription integration.
5. Done: RevenueCat/App Store Connect subscription products and entitlement/offering checks are complete.
6. Done: TestFlight paywall USD display is handled with a TL fallback when StoreKit/RevenueCat returns USD in a Turkish context.
7. Replace local/mock Pro toggles with verified subscription/profile refresh only.

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
   - Done: `RDLanguage`, `RDLocalization` and `RDReportLocalization` added as the real string localization layer;
   - Done: PDF report options now carry a `language` value and report settings show the current Turkce report language;
   - Done: PDF report titles/date locale are routed through the report language layer.
   - Follow-up: when another language ships, localize Auth, Home, Analysis, Result, Reports and Profile strings through the same key layer;
   - Follow-up: extend PDF/XLSX table labels and legal/report boilerplate to the new report language.
3. Long-term English localization rollout:
   - add English as a first-class language after launch priorities settle;
   - scope includes app UI, onboarding, auth, paywalls, reports, PDF/XLSX outputs, AI analysis output, backend notifications, e-mails, permission prompts and legal surfaces;
   - default behavior should follow the iOS system language, with Profile > Tercihler override for System / Turkce / English;
   - implementation prerequisites: approved English legal copy, localization key audit, backend `language` / `report_language` contract, Turkish + English UI tests, and PDF/XLSX + AI output language QA;
   - existing Turkish analyses/reports stay as-is; do not auto-migrate or machine-translate historical records.
4. Preference sync:
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
   - Done: report archive now has search/filter controls, status labels, stronger empty/error states and filtered load-more behavior.
   - Done: production telemetry/performance spot-check completed; duplicate report archive index removed and PII-free archive load/load-more telemetry added. Details: `QA/Reports_Archive_Production_Spot_Check_2026-05-16.md`.
4. Analyses page design refresh:
   - Done: redesigned Analyses tab visual hierarchy;
   - Done: retained quick filtering chips and improved the filter sheet presentation;
   - Done: modernized analysis cards with thumbnail, risk label, metadata and status.
   - Done: quota-exhausted photo upload card has dark-mode-specific colors and copy uses `Yükselt`.
5. Legal link destination refresh:
   - Done: updated pages opened from KVKK, Kullanım şartları and Gizlilik Politikası links;
   - Done: legal center uses separate document selectors and a scrollable plain-document reader;
   - Done: final markdown legal contents are bundled in-app from `App/LegalDocuments`;
   - Done: App Store privacy nutrition disclosure draft prepared at `QA/App_Store_Privacy_Nutrition_2026-05-16.md`.
6. Profile page tabs and content:
   - design and implement profile page sections/tabs;
   - fill missing content for account, preferences, reports, analyses, notifications and data/privacy areas.

7. Paywall page redesign:
   - Done: redesigned the Plus/Pro upgrade screen with the latest commercial limits;
   - Done: Plus shows 10 standard analyses/day, 2 detailed analyses/day and 150 reports/month;
   - Done: Pro shows 40 standard analyses/day, 10 detailed analyses/day and 750 reports/month;
   - Done: RevenueCat package loading, current-plan state, purchase, restore and error states are clearer;
   - Done: refreshed paywall purchase/restore QA completed on TestFlight.
   - Done: USD price display is handled with TL fallback pricing for Turkish-context paywall rendering.

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
4. QA: ✅ Done
   - generate an Excel report from an existing completed analysis;
   - verify it appears in Reports archive and opens via iOS share sheet;
   - verify PDF generation remains unchanged.
   - Done: Pro demo API smoke test generated `/tmp/riskdetected-test.xlsx`; workbook opened with sheets `Özet`, `Risk Analiz Tablosu`, `Aksiyon Planı`, `Rapor Bilgileri`.
   - Done: simulator Pro demo flow generated a standard PDF, archived it, opened its share sheet, then generated an Excel risk table, archived it and opened the iOS share sheet as an Office spreadsheet.
   - Done: 2026-05-16 final simulator QA covered home report preview/close/share, Pro canvas selection, Free quota-dolu report gating, Pro live analysis, standard PDF, Pro PDF and XLSX preview/share flows.
   - Done: report quota gating now prevents generation when exhausted and routes to `Yükselt`; generated PDF Storage paths are ASCII-safe; repeated PDF generation uses unique document numbers for archive metadata.

### P3 - AI Reliability and Cost Control

0. Gemini multi-project API key pool for MVP launch buffer:
   - Status: backend code now separates Free and Paid Gemini key pools; wait until the user provides the Paid Gemini API key before production deploy/use.
   - Context: keys will come from different Google accounts and different Google Cloud projects, so quota pools should be separate. Multiple keys in the same project would not increase quota.
   - Done: `analyze` Edge Function key pool implemented for Free and Plus/Pro routing.
   - Done: `ai_usage_logs.api_key_alias` and `attempt_count` added.
   - Supabase Edge Function Free secrets target:
     - `GEMINI_API_KEY_PRIMARY`;
     - `GEMINI_API_KEY_SECONDARY`;
     - `GEMINI_API_KEY_TERTIARY`.
   - Backward compatibility: existing `GEMINI_API_KEY` is treated as primary if `GEMINI_API_KEY_PRIMARY` is absent.
   - Supabase Edge Function Paid secrets target:
     - `GEMINI_API_KEY_PAID`;
     - `GEMINI_API_KEY_PAID_SECONDARY` (optional).
   - Backward compatibility: `GEMINI_PAID_API_KEY` is accepted as an alias for `GEMINI_API_KEY_PAID`; prefer `GEMINI_API_KEY_PAID`.
   - Routing target:
     - Free traffic starts with `gemini_primary`;
     - Free model order is `gemini-2.5-flash` first, then `gemini-2.5-flash-lite` on retryable provider failures or limits;
     - Plus/Pro traffic starts with `gemini_paid_primary`;
     - Plus/Pro model order is `gemini-2.5-pro` first, then `gemini-2.5-flash` on retryable provider failures or limits;
     - on retryable provider failures such as `429 RESOURCE_EXHAUSTED`, quota/rate-limit, `503`, `500/502/504` or timeout, retry the same analysis record within the same key pool only;
     - do not cross-fallback between Free and Paid key pools;
     - if subscription lookup fails, fail closed instead of falling back to the Free pool;
     - do not fallback for user/input errors such as invalid payload, unsupported image, validation failure or non-retryable `400`.
   - Logging target:
     - never log or return real API keys;
     - log only aliases such as `gemini_primary`, `gemini_secondary`, `gemini_tertiary`, `gemini_paid_primary`, `gemini_paid_secondary`;
     - write `attempt`, `provider`, `api_key_alias`, `model`, `http_status`, `error_code`, `fallback_source`, `latency_ms`, `request_id` and `support_id` into `ai_usage_logs` where possible.
   - Operational guardrails:
     - add Google Cloud budget alerts / quota monitoring per project before public traffic;
     - if Paid secret is missing, Plus/Pro analysis must fail closed with a support code instead of using Free keys;
     - treat this as a temporary MVP reliability bridge until broader provider fallback is in place.
   - Pending: Plus/Pro fallback hardening:
     - add/test `GEMINI_API_KEY_PAID_SECONDARY` from a separate paid Google project/account;
     - ensure retryable Plus/Pro failures fall back only within Paid pool;
     - verify `ai_usage_logs.api_key_alias` records `gemini_paid_primary` -> `gemini_paid_secondary`;
     - evaluate a later paid provider/model fallback, still gated by backend subscription checks.
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
   - Done: profile company logo is used automatically as the report logo default;
   - Done: preparer name, title, certificate/belge no, company name/info and preferred method are pulled from Profile into report defaults;
   - Done: PDF standard footer, detailed PDF info strip and XLSX metadata sheets use these defaults.
2. Detailed risk analysis outputs:
   - keep Fine-Kinney and 5x5 PDF formats;
   - XLSX export is now implemented for Pro detailed risk analysis.
3. Export backlog:
   - Word export is optional;
   - Word remains lower priority than stored PDFs, XLSX and report regeneration.

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
- Supabase migration history was repaired on 2026-05-15. Remote base migrations are now mirrored locally and `supabase migration list` is clean.
- Repair details live in `QA/Supabase_Migration_History_Repair_2026-05-15.md`.
- For the P0 reports migration, SQL was applied with:
  - `npx supabase db query --linked -f supabase/migrations/20260506193000_reports_storage.sql`
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
