# RiskDetected Implementation Plan

## Current Phase

- FAZ 1: iOS app MVP + Supabase/Gemini analysis flow.
- Current focus: stabilize the real analysis/reporting flow, then harden privacy, auth, quota, provider fallback and Pro conversion.
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
- P0 plan alignment started:
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

## Partially Done - Revision Queue

These items exist in some form, but need revision before we treat them as production-ready.

1. Free/Pro hazard limits
   - Current state: Edge Function uses a higher free output budget than the external plan intended.
   - Target: Free returns max 4 hazards; Pro returns up to 14 hazards.
   - Reason: clearer product difference and better Gemini cost control.

2. AI usage logging
   - Current state: `ai_usage_logs` exists and logs core provider/model/token/error data.
   - Target additions: request/job id, latency, input image size, preprocessing version, estimated cost, fallback source, normalized fail reason.

3. Provider fallback
   - Current state: Gemini model-level fallback exists.
   - Target: provider abstraction interface with health/fallback routing.
   - Initial chain:
     - Free: Gemini Flash-Lite -> Gemini Flash -> fallback vision provider.
     - Pro: strongest available Gemini paid model -> Claude/OpenAI/OpenRouter fallback, depending on cost and API availability.

4. Image preprocessing
   - Current state: iOS resizes/compresses images before inline upload.
   - Target: backend preprocessing pipeline for EXIF removal, standard resize/quality, face blur and logo blur.
   - Storage rule target: store only cleaned/blurred images when possible; avoid long-term original image storage.

5. Error handling
   - Current state: quota, Gemini 429 and Gemini 503 are mapped to user-facing messages.
   - Target: structured error UX with "what happened", "what to do", support request id and retry/fallback state.

6. Pro AI confidence upgrade
   - Current state: confidence is displayed and Pro copy exists.
   - Target: actually improve Pro analysis quality using stronger models, higher image budget, multi-pass validation, sector/procedure checklists and low-confidence re-checking.
   - Copy rule: do not promise a fixed score. Preferred wording: "Pro analizlerde daha kapsamli model ve dogrulama katmani ile daha yuksek guven hedeflenir."

7. Pro report identity/logo
   - Current state: per-report company logo and identity fields can be selected in the PDF settings flow.
   - Target: persist company logo and default report identity under Profile so the user does not reselect them each time.

8. Reports tab and report storage
   - Current state: generated PDFs are uploaded to Supabase Storage, metadata is written to `reports`, and the Reports tab can download/regenerate reports.
   - Target additions: report archive filtering/search, report status labels and better empty/error states.

9. Phone auth
   - Current state: basic auth service placeholders/OTP path exist, but production phone verification is not finalized.
   - Target: support phone number registration and login.
   - Preferred direction to research/implement: Firebase Auth phone verification for SMS, then bridge the verified Firebase user into Supabase session/profile flow.
   - Decision checkpoint: verify the safest integration path before implementation:
     - Option A: Firebase verifies phone, backend validates Firebase ID token, then creates/links a Supabase user/profile.
     - Option B: Supabase native phone OTP if Firebase bridge adds too much auth/session complexity.
   - Security rule: never trust phone number from client alone; backend must verify Firebase ID token or Supabase OTP result.

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

### P1 - Privacy, Legal and Trust

1. Partially done: KVKK/Terms/Consent visibility:
   - login screen includes legal acceptance notice and a legal information link;
   - Home screen includes legal acceptance notice and a legal information link;
   - blocking first-analysis consent was intentionally removed for lower friction;
   - versioned `consents` table exists with RLS and minimum grants for a future explicit-consent/audit flow if needed.
   - Follow-up: replace summary copy with lawyer-reviewed final KVKK/terms text, add full document links and decide whether signup should persist accepted legal version.
2. Visual data policy:
   - EXIF cleanup;
   - face blur;
   - company logo blur;
   - cleaned-image-only storage policy where practical.
3. Clear retention/deletion policy:
   - define how long images, reports and raw AI responses are stored;
   - add user deletion/export path later.

### P2 - Auth and Subscription

1. Firebase phone verification + Supabase user/profile bridge research and implementation.
2. Apple Sign In production hardening.
3. Google Sign In production hardening.
4. RevenueCat subscription integration.
5. Replace local/mock Pro toggles with verified subscription/profile refresh only.

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
5. Is Free max 4 / Pro max 14 the final business rule, or should we A/B test it later?

## Deployment Notes

- Supabase CLI is available through `npx supabase`.
- Remote migration history contains older timestamped migrations from the previous setup that are not fully mirrored locally, so `supabase db push` reports a history mismatch.
- For the P0 reports migration, SQL was applied with:
  - `npx supabase db query --linked -f supabase/migrations/20260506_reports_storage.sql`
- Edge Function deploy was completed with:
  - `npx supabase functions deploy analyze --use-api`
