# App Review Handoff For Claude - 2026-06-01

This handoff summarizes the current App Review preflight state for continuing work in another assistant/thread.

## Project

- Workspace: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`
- App Store Connect app: `RiskDetected İş Güvenliği`
- Bundle ID: `com.riskdetected.app`
- ASC App ID: `6769498181`
- ASC Version ID: `e97f1de1-7e8c-448b-a5b9-80869f0a8816`
- Candidate: `1.0 (31)`
- Candidate build ID: `fca919e5-b12a-4129-8d82-cf46ce1736c8`
- Supabase project ref: `ppcrzemgiztzcgddbins`

Important: App Review contact fields are intentionally not filled yet, and App Review submission has not been started.

## Canonical QA Files

- `QA/APP_STORE_PREFLIGHT_2026-06-01.md` - main preflight report.
- `QA/APP_REVIEW_GATE_MATRIX_2026-06-01.md` - one-page pass/hold/warn gate matrix.
- `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md` - ordered submission-day checklist.
- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` - non-secret manual evidence form.
- `QA/App_Review_Preflight_Evidence_2026-06-02.md` - latest automated collector output.
- `QA/App_Review_Webmail_OTP_Access_2026-06-01.md` - App Review OTP/webmail notes template.
- `QA/RELEASE_HYGIENE_2026-06-01.md` - staging/commit hygiene manifest.
- `QA/APP_REVIEW_REMAINING_ACTIONS_2026-06-02.md` - current remaining blockers and smoke order.
- `QA/APP_STORE_SCREENSHOT_PREFLIGHT_2026-06-02.md` - App Store screenshot count/dimension/spec preflight.
- `QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md` - Codex visual/privacy QA for the final 10 screenshot upload candidates.
- `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md` - leaked-password protection automation investigation.

## Automation Added

Read-only preflight collector:

```bash
node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md
```

Latest result:

- `34 PASS`
- `2 WARN`
- `13 HOLD`
- `1 SKIP`
- `0 FAIL`

The collector is read-only. It does not fill ASC contact fields, does not submit the app, and does not change Supabase settings.

Release staging guard:

```bash
node scripts/release_staging_guard.mjs
```

Latest result:

- `Staged files checked: 0`
- `PASS release staging guard: nothing is staged.`

The guard checks only staged/index files. It fails if local keys, env files, raw paywall outputs, QA temp files, or archive/export products are staged.

## Current Passed Evidence

- ASC build `1.0 (31)` is `VALID`.
- Build ID `fca919e5-b12a-4129-8d82-cf46ce1736c8` is attached to ASC version `1.0`.
- `asc validate subscriptions` has `0` errors.
- Four subscriptions exist and are `READY_TO_SUBMIT`:
  - `riskdetected_plus_monthly`
  - `riskdetected_plus_yearly`
  - `riskdetected_pro_monthly`
  - `riskdetected_pro_yearly`
- Exported IPA path: `/tmp/RiskDetectedExport31/RiskDetected.ipa`
- Unpacked app path: `/tmp/RiskDetectedIPA31/Payload/RiskDetected.app`
- Exported app contains no QA folders, App Store screenshot tooling, `.p8`, `.env`, AuthKey, demo accounts, `RD_UI_TEST`, service-role markers, or marketing mockups.
- Exported app uses distribution signing, production APNs, Sign in with Apple, and `get-task-allow = false`.
- Exported IPA `Info.plist` has `ITSAppUsesNonExemptEncryption = false`.
- Exported IPA contains 12 privacy manifests.
- All privacy manifests report `NSPrivacyTracking = false` and zero tracking domains.
- Local source/exported `Info.plist` show no ATT prompt, IDFA, ad IDs, or SKAdNetwork items.
- RevenueCat binary includes dormant attribution-support strings, but app source does not call RevenueCat attribution APIs and the binary does not link `AdSupport.framework`.
- ASC metadata pull is clean for placeholders/test/beta/debug/staging/localhost and banned AI brand stuffing.
- Review notes template includes all six new-submission sections:
  - physical-device demo video
  - app purpose
  - access/test credentials
  - external services
  - regional differences
  - regulated-industry not-applicable explanation
- Supabase Edge Functions `deno check` passes.
- Supabase Auth baseline is restored and now checked by the collector: Email/Apple/Google enabled, phone disabled, signup enabled, and `mailer_autoconfirm=false`.
- Release simulation source gating is checked by the collector: iOS test-simulation helpers are DEBUG-only, Edge Function AI simulation requires explicit env flags, and the production runbook documents remote secret cleanup.
- Supabase critical security-definer/search-path warnings were remediated by migrations.

## Current Holds / Warnings

The automated collector currently reports:

- `HOLD`: ASC review is intentionally `NOT_SUBMITTED`.
- `HOLD`: ASC validation has only the intentionally missing App Review contact fields:
  - `contactFirstName`
  - `contactLastName`
  - `contactEmail`
  - `contactPhone`
- `HOLD`: App Privacy publish evidence is still manual/pending.
- `HOLD`: App Store screenshot visual approval/upload evidence is still manual/pending. Codex visual QA found no obvious private email/phone/token/support ID/private identifier, localhost/debug/beta label, or USD/fallback price at contact-sheet scale; owner/marketing approval and ASC upload remain open.
- `HOLD`: China mainland is currently available (`CHN available=true`, `availableInNewTerritories=true`) while the app discloses AI-assisted analysis and Google/Groq providers. Exclude China mainland for first release, or record a China-specific compliance decision before submission.
- `HOLD`: manual evidence form still has TODO/placeholders.
- `HOLD`: Review Notes draft still has ASC-only placeholders for the mailbox password and physical-device demo video URL.
- `HOLD`: Supabase leaked-password protection still needs dashboard enablement or an explicit accepted-risk decision.
- `SKIP`: Supabase production secret enumeration is intentionally skipped by release decision. Source gating passes and this is no longer counted as an App Review preflight blocker.
- `HOLD`: physical-device auth smoke still needs Email OTP, Apple login, and Google login evidence.
- `HOLD`: physical-device onboarding paywall smoke still needs Plus monthly/yearly TL and no-fallback evidence.
- `HOLD`: physical-device purchase/restore smoke still needs non-entitled sandbox purchase sheet, successful purchase, restore, and entitlement sync evidence.
- `HOLD`: physical-device fresh analysis/report smoke still needs one fresh free analysis plus fresh PDF/Excel generation evidence.
- `WARN`: RevenueCat dormant attribution strings need to remain understood as non-use unless app code changes.
- `WARN`: Supabase advisors still show:
  - `auth_leaked_password_protection: 1`
  - `auth_rls_initplan: 36`
  - `multiple_permissive_policies: 2`

Latest Supabase note:

- `supabase functions list --project-ref ppcrzemgiztzcgddbins --output json` confirms all 15 locally configured functions are remote `ACTIVE`; `register-report` is remote `ACTIVE` and `verify_jwt=true`.
- `supabase db lint --linked --level warning --fail-on none` completed again at 2026-06-02 02:08 +03 with `No schema errors found`.
- Supabase production secret enumeration is intentionally skipped by release decision. Source gating passes.
- `supabase config push --debug` accidentally drifted hosted Auth config at 2026-06-02 01:35 +03; it was restored at 01:38 +03 and verified with public `/auth/v1/settings`. See `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md`.
- Later exploratory `supabase db query --linked` metadata work hit temporary pooler auth failures. Do not keep retrying DB-query loops without the correct DB credential/env.

## Remaining Manual Gates

Do not mark the preflight goal complete until these are verified and recorded in `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`:

1. Fill App Review contact fields in ASC when the user is ready.
2. Replace ASC Notes placeholders:
   - `<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>`
   - `<PHYSICAL_DEVICE_DEMO_VIDEO_URL>`
3. Confirm/publish App Privacy in ASC UI.
4. Attach all four first-time subscriptions to the app review submission in ASC UI.
5. Confirm Turkey storefront prices in ASC and on physical-device paywalls:
   - Plus monthly: `₺199,99`
   - Plus yearly: `₺1.999,99`
   - Pro monthly: `₺499,99`
   - Pro yearly: `₺4.999,99`
6. Decide/enable Supabase leaked-password protection.
7. Rerun Supabase advisors after leaked-password decision; rerun `db lint` on submission day if DB credentials/env are available.
8. Run physical-device TestFlight smoke on build `1.0 (31)`:
   - Email OTP login with `riskdetected.appreview@fastmail.com`
   - Apple login
   - Google login
   - paywall product load
   - sandbox purchase flow
   - restore purchases
   - Free analysis
   - Plus/Pro entitlement sync
   - PDF/Excel report generation
   - account deletion request path
   - legal links
9. Rerun collector and final ASC validation commands.
10. Run staging guard after any staging and before commit/tag.

## Commands To Rerun

ASC:

```bash
asc builds info --app 6769498181 --build-number 31 --platform IOS --output json --pretty
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
asc validate subscriptions --app 6769498181 --output markdown
asc review status --app 6769498181 --output markdown
```

Supabase:

```bash
deno check $(find supabase/functions -maxdepth 2 -name index.ts | sort)
supabase db advisors --linked --type all --level warn --fail-on none --output json \
  | jq -r 'group_by(.name)[] | "\(.[0].name): \(length)"'

SUPABASE_DB_PASSWORD='<DB_PASSWORD>' \
supabase db lint --linked --level warning --fail-on none
```

Evidence:

```bash
node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md
node scripts/release_staging_guard.mjs
node scripts/release_staging_guard.mjs --worktree
git diff --check
```

## Safety Notes

- Do not write real Fastmail mailbox password, App Store Connect private key, Supabase DB password, sandbox Apple ID password, OTP codes, or private contact details into repo files.
- Do not revert unrelated dirty worktree changes.
- Do not submit the app until the user explicitly confirms.
- Do not fill App Review contact fields until the user explicitly says to proceed.
- Use `QA/RELEASE_HYGIENE_2026-06-01.md` before staging/committing.
