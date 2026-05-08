# RiskDetected Implementation Plan

## Current Phase

- FAZ 1: iOS app MVP + Supabase/Gemini analysis flow.
- Current focus: finish P1 privacy/legal trust work, then move into error/message hardening, auth/subscription hardening and AI reliability.
- Product scope: individual HSE/ISG expert workflow. OSGB/corporate multi-tenant panels are out of scope for now.

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
  - Edge Function hazard budget aligned to Free max 4 and Pro max 14.
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

8. Phone auth
   - Current state: basic auth service placeholders/OTP path exist, but production phone verification is not finalized.
   - Target: support phone number registration and login.
   - Preferred direction to research/implement: Firebase Auth phone verification for SMS, then bridge the verified Firebase user into Supabase session/profile flow.
   - Decision checkpoint: verify the safest integration path before implementation:
     - Option A: Firebase verifies phone, backend validates Firebase ID token, then creates/links a Supabase user/profile.
     - Option B: Supabase native phone OTP if Firebase bridge adds too much auth/session complexity.
   - Security rule: never trust phone number from client alone; backend must verify Firebase ID token or Supabase OTP result.

9. App preferences
   - Current state: Profile/Settings screen exists, but theme and language preferences are not implemented.
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

### P0 - Stabilize MVP and Plan Alignment

1. Done: Change Free/Pro hazard limits to Free max 4 and Pro max 14.
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
   - Follow-up: replace summary copy with lawyer-reviewed final KVKK/terms text and add full document links.
   - Follow-up: find a calmer in-app placement for KVKK/terms access, likely Profile > Güvenlik ve gizlilik or first-run/account settings instead of Home CTA area.
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
   - add controlled retry for Gemini 429/503/timeouts;
   - show "tekrar deneniyor" / fallback provider state when applicable;
   - avoid duplicate analysis/report creation on retry.
5. QA and simulator test matrix:
   - create a checklist to manually trigger quota full, offline/network fail, invalid API key, Gemini 429/503, Storage policy failure, PDF archive failure, missing photo and expired session;
   - verify each case displays the intended message and does not leave the UI stuck.

### P2 - Auth and Subscription

1. Firebase phone verification + Supabase user/profile bridge research and implementation.
2. Apple Sign In production hardening.
3. Google Sign In production hardening.
4. RevenueCat subscription integration.
5. Replace local/mock Pro toggles with verified subscription/profile refresh only.

### P2.5 - App Preferences and Localization

1. Theme preference:
   - add Profile > Tercihler screen;
   - support System / Aydınlık / Karanlık;
   - persist selected theme locally;
   - apply theme consistently across app surfaces, PDF preview screens and paywall.
2. Language preference:
   - add Turkish / English / System language selector;
   - introduce localized string structure before hardcoding grows further;
   - first target screens: Auth, Home, Analysis, Result, Reports, Profile;
   - later target: PDF/report output language selection.
3. Preference sync:
   - keep MVP local-first;
   - later store preferred theme/language in `profiles` or a dedicated `user_preferences` table.

### P3 - AI Reliability and Cost Control

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
2. Use Firebase phone verification bridge or Supabase native phone OTP?
3. Which paid Pro AI model/provider becomes the primary production route?
4. How strict should image retention be for KVKK and user trust?
   - Current decision: Free analysis photos 30 days, Pro analysis photos 365 days, raw AI responses 30 days, reports until user deletion.
5. Is Free max 4 / Pro max 14 the final business rule, or should we A/B test it later?

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
