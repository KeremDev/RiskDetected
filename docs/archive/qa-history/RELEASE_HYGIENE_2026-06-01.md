# Release Hygiene Manifest - 2026-06-01

Scope: RiskDetected `1.0 (31)` App Review candidate.

Purpose: classify the current dirty worktree before final release staging. This is a staging guide only; it does not mean every listed file must be committed in one commit.

## Release-Critical Include

These are required for the current App Store candidate or backend production hardening:

- `RiskDetected.xcodeproj/project.pbxproj`
  - Aligns app target to `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 31`.
  - Keeps signing team settings needed for archive/export.
- `Config/RiskDetectedInfo.plist`
  - App bundle metadata used by the shipped app.
- `App/Services/SubscriptionManager.swift`
  - RevenueCat package logging/diagnostics and warning cleanup.
- Paywall/onboarding/legal UI files changed for the submitted experience:
  - `App/RootView.swift`
  - `App/Views/Auth/AuthView.swift`
  - `App/Services/NetworkMonitor.swift`
  - `App/Services/NotificationService.swift`
  - `App/Views/Paywall/PaywallView.swift`
  - `App/Views/Paywall/InAppPaywallView.swift`
  - `App/Views/Home/MainTabView.swift`
  - `App/Views/Onboarding/V2/OnboardingViewV2.swift`
  - `App/Views/Onboarding/V2/OnboardingV2State.swift`
  - `App/Views/Onboarding/V2/Screens/OBAuthView.swift`
  - `App/Views/Onboarding/V2/Screens/OBPaywallView.swift`
  - `App/Views/Onboarding/V2/Screens/OBSplashView.swift`
  - `App/Views/Onboarding/V2/Screens/OBTimelinePaywallView.swift`
  - `App/Views/Components/LegalAcceptanceNotice.swift`
- Runtime assets added for onboarding:
  - `App/Assets.xcassets/OBSplashPreview.imageset/`
  - `App/Assets.xcassets/OBSplashSafetyPattern.imageset/`
- Backend production code/hardening:
  - `supabase/functions/analyze/index.ts`
  - `supabase/functions/revenuecat-webhook/index.ts`
  - `supabase/functions/support-contact/index.ts`
  - `supabase/functions/sync-revenuecat-subscription/index.ts`
  - `supabase/functions/register-report/index.ts`
  - `supabase/config.toml`
  - `supabase/migrations/20260601064449_deep_security_remediation.sql`
  - `supabase/migrations/20260601154641_app_review_preflight_function_hardening.sql`
- Release verification tooling:
  - `scripts/app_review_preflight_collect.mjs`
  - `scripts/release_staging_guard.mjs`
- QA evidence that should stay with release history:
  - `QA/APP_STORE_PREFLIGHT_2026-06-01.md`
  - `QA/APP_REVIEW_GATE_MATRIX_2026-06-01.md`
  - `QA/APP_REVIEW_HANDOFF_FOR_CLAUDE_2026-06-01.md`
  - `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`
  - `QA/APP_REVIEW_REMAINING_ACTIONS_2026-06-02.md`
  - `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md`
  - `QA/APP_STORE_REVIEW_NOTES_2026-06-02.md`
  - `QA/APP_STORE_SCREENSHOT_PREFLIGHT_2026-06-02.md`
  - `QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md`
  - `QA/App_Review_Preflight_Evidence_2026-06-01.md`
  - `QA/App_Review_Preflight_Evidence_2026-06-02.md`
  - `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`
  - `QA/App_Store_Submission_Preparation_2026-05-16.md`

## Release-Critical Move

These files were intentionally moved out of the app bundle:

- From: `App/Marketing/AppIconConcepts/`
- To: `Marketing/AppIconConcepts/`

Reason: `App/` is synchronized into the Xcode app target, so marketing/mockup PNGs under `App/` can ship in the `.app`. The moved `Marketing/` folder is outside the app bundle path.

## Optional / Marketing Include

These are useful for App Store listing production but are not part of the iOS runtime binary:

- `AppStoreScreenshots/`
- `AppScreenshot/`

Recommendation: keep marketing assets in a separate commit from app runtime/backend release changes.

## Exclude From Release Commit

These are generated QA artifacts or local scratch outputs and should not be staged unless there is an explicit archival reason:

- `output/paywall-device-matrix/`
- `output/paywall-screenshots/`
- `output/imagegen/`
- `output/app-review-physical-smoke/`
- `.DS_Store` files
- `QA/tmp/`

`.gitignore` now protects the highest-risk accidental staging classes:

- `.DS_Store`
- `.env` / `*.env`
- `*.p8`
- `AuthKey_*.p8`
- `QA/tmp/`
- `output/paywall-device-matrix/`
- `output/paywall-screenshots/`
- `output/app-review-physical-smoke/`
- `output/imagegen/`

The final App Store screenshot upload candidates live under `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/`; raw `output/imagegen/` assets are local generation inputs/evidence and should not be staged.

## Staging Guard

Before committing or tagging a release candidate, run:

```bash
node scripts/release_staging_guard.mjs
node scripts/release_staging_guard.mjs --worktree
```

Current result:

- 2026-06-02 04:41 +03: `node scripts/release_staging_guard.mjs`
  - `Staged files checked: 0`
  - `PASS release staging guard: nothing is staged.`
- 2026-06-02 04:41 +03: `node scripts/release_staging_guard.mjs --worktree`
  - `Dirty worktree files checked: 179`
  - `PASS release staging guard: no forbidden dirty files.`
  - Warnings are expected for `.agents/skills/` and `AppStoreScreenshots/` marketing/tooling assets until staging is curated.

By default this guard inspects only the Git index/staging area. With `--worktree`, it also scans dirty tracked/untracked files before staging. It fails if `.DS_Store`, `.env`, `*.p8`, `AuthKey_*.p8`, `QA/tmp/`, raw paywall output folders, raw physical-device smoke output, raw `output/imagegen/` assets, or local archive/export products are staged or present in the dirty worktree scan. It warns on broad `output/`, raw media/evidence files, `AppStoreScreenshots/`, and `.agents/skills/` so those commits stay intentional.

## Review-Sensitive Checks Already Passed

- Current App Store export `1.0 (31)` contains no `Marketing`, `mockup`, `screenshot`, `AppStoreScreenshots`, `RiskDetectedUITests`, `QA`, `Temporary`, `.p8`, `.env`, or `AuthKey` files inside the exported `.app`.
- Narrow binary marker scan found no `RD_UI_TEST`, `AuthKey_*.p8`, `SERVICE_ROLE`, QA secret names, RevenueCat webhook secret name, APNS private key, Supabase secret markers, or `.p8`.
- Demo sign-in code is Debug-only, and the App Store export contains no demo account emails, demo passwords, or demo labels.
- Expanded localhost scan found no app-source `localhost` / `127.0.0.1` references. The remaining binary localhost strings are linked auth-library support, not app backend configuration.
- Build `1.0 (31)` exported with 12 privacy manifests; all report `NSPrivacyTracking = false`.
- The same 12 privacy manifests report zero tracking domains.
- Local app source and exported `Info.plist` show no ATT prompt, IDFA usage, ad network IDs, Google Ads IDs, Facebook IDs, or SKAdNetwork items.
- RevenueCat's binary contains dormant attribution support strings, but app source does not call RevenueCat attribution APIs and the exported binary does not link `AdSupport.framework`.
- Build `1.0 (31)` embedded App Store profile has production APNs, Sign in with Apple, and `get-task-allow = false`.
- Repo scan found no `.p8`, `.env`, or `AuthKey` files.

## Remaining Manual Gates

- Fill App Review contact details.
- Confirm App Privacy is completed/published.
- Attach all four `READY_TO_SUBMIT` subscriptions during App Review submission.
- Exclude China mainland for first release, or record a China-specific compliance decision. Latest ASC availability check shows `CHN available=true` and `availableInNewTerritories=true` while app metadata/legal docs disclose AI-assisted analysis and Google/Groq providers.
- Supabase leaked-password protection is accepted known risk for this submission path; treat enablement as optional post-release hardening if password login remains enabled later.
- Latest leaked-password automation investigation: `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md`. If hardening later, use Dashboard Auth password-security toggle or a reviewed minimal Management API patch; do not use broad `supabase config push` casually for this single setting.
- Supabase `register-report` was deployed on 2026-06-02 00:55 +03 after preflight found it was local-only while the app invokes it for PDF report metadata.
- Re-run Supabase `db lint` through the linked CLI profile; latest 2026-06-02 04:50 +03 collector re-check reported `No schema errors found` without recording a database password.
- Release simulation source gating passes in the collector. Supabase production secret enumeration is intentionally skipped by release decision and no longer counted as an App Review preflight blocker.
- Run final physical-device smoke test.
- Keep `output/app-review-physical-smoke/` as local evidence only; `.gitignore` excludes it and `scripts/release_staging_guard.mjs` fails if raw physical-device smoke logs/artifacts are staged.
- Keep `output/imagegen/` as local generation output only; `.gitignore` excludes it and `scripts/release_staging_guard.mjs` fails if raw imagegen assets are staged.
