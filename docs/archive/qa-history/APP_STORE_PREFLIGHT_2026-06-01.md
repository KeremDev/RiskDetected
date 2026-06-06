# App Store Preflight Report - 2026-06-01

Scope: RiskDetected iOS App Review submission gate.

Last live refresh: 2026-06-02 11:31 +03. `asc review status`, `asc validate`, `asc validate subscriptions`, `asc builds info`, Supabase Auth baseline checks, Supabase advisors, Supabase `db lint`, Supabase production simulation source gating, public URL checks, IPA scans, screenshot checks, screenshot visual QA evidence, physical-device readiness evidence, release local-evidence hygiene checks, and physical-device install discovery were re-run without filling App Review contact fields or submitting the app. Latest simulator build/UI smoke remains the 2026-06-02 00:23-00:25 +03 XcodeBuildMCP run.

App Store Connect:

- App ID: `6769498181`
- Bundle ID: `com.riskdetected.app`
- ASC app name: `RiskDetected İş Güvenliği`
- ASC version under review: `1.0`
- Local app build after fixes: `1.0 (31)`
- Supabase project: `ppcrzemgiztzcgddbins`

Gate matrix:

- `QA/APP_REVIEW_GATE_MATRIX_2026-06-01.md`
- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`
- `QA/APP_REVIEW_HANDOFF_FOR_CLAUDE_2026-06-01.md`

Read-only evidence collector:

- `scripts/app_review_preflight_collect.mjs`
- Latest output: `QA/App_Review_Preflight_Evidence_2026-06-02.md`

Applicable checklists:

- `.agents/skills/app-store-preflight-skills/references/guidelines/by-app-type/all_apps.md`
- `.agents/skills/app-store-preflight-skills/references/guidelines/by-app-type/subscription_iap.md`
- `.agents/skills/app-store-preflight-skills/references/guidelines/by-app-type/ai_apps.md`

Official references used:

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple privacy manifest guidance: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Apple required reason API guidance: https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api

## Executive Summary

Local binary/package readiness is now materially better than the first pass:

- Fixed local version mismatch by changing the app target `MARKETING_VERSION` from `0.1.0` to `1.0`.
- Incremented the app target `CURRENT_PROJECT_VERSION` to `31` so local source, exported IPA, and ASC attached build are aligned.
- Moved marketing-only App Icon concept images out of `App/` so they no longer ship inside the `.app`/`.ipa`.
- Produced a fresh Release archive and App Store export successfully.
- Uploaded build `1.0 (31)` to App Store Connect, waited for `VALID`, and attached it to ASC version `1.0`.
- Verified exported IPA uses distribution signing, production APNs, and `get-task-allow=false`.
- Verified exported IPA does not contain QA folders, App Store screenshot tooling, `.p8` files, `.env` files, `RD_UI_TEST` strings, service-role strings, or marketing mockup files.
- Applied the backend security hardening migrations to the linked Supabase project and re-ran lint/advisors.
- Re-ran an iPhone 17 Pro simulator build and targeted in-app paywall UI tests after the latest local fixes.
- Re-ran a current-worktree Release archive to confirm the latest source still archives.
- Exported, uploaded, and attached the current-worktree App Store build `1.0 (31)`.

The app is not yet ready to tap `Add for Review` in App Store Connect because ASC still reports missing App Review contact details. Per current release decision, these contact fields are intentionally not filled yet and submission has not been started.

## Rejections / Blocking Items

### [2.1] App Store review contact details are missing

- Severity: Blocking
- Evidence: `asc review status --app 6769498181 --output markdown` and `asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown`
- Latest status:
  - `reviewState = NOT_SUBMITTED`
  - `versionState = PREPARE_FOR_SUBMISSION`
  - `reviewDetail = not configured`
  - `blockerCount = 1`
- ASC validation errors:
  - `contactFirstName` missing
  - `contactLastName` missing
  - `contactEmail` missing
  - `contactPhone` missing
- Fix: Fill App Review contact details in App Store Connect for version `1.0`.

### [3.1.2 / 2.1(b)] First-time subscriptions still need review submission attachment

- Severity: Submission blocker until handled in ASC
- Evidence: `asc validate subscriptions --app 6769498181 --output markdown`
- Products exist and are `READY_TO_SUBMIT`, but first-time subscriptions must be submitted with the app version:
  - `riskdetected_plus_monthly`
  - `riskdetected_plus_yearly`
  - `riskdetected_pro_monthly`
  - `riskdetected_pro_yearly`
- Fix: Attach all four subscriptions to the app review submission in App Store Connect.

### [5.1.1] App Privacy publish state could not be verified through public ASC API

- Severity: Blocking until manually confirmed
- Evidence: ASC validation info `privacy.publish_state.unverified`.
- Fix: Confirm App Privacy is completed and published at:
  - `https://appstoreconnect.apple.com/apps/6769498181/appPrivacy`

## Warnings

### Review notes placeholders remain intentionally unresolved

- Severity: Submission-day warning
- Evidence: `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`, `QA/App_Store_Submission_Preparation_2026-05-16.md`, and `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md`
- Current placeholders:
  - `<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>`
  - `<PHYSICAL_DEVICE_DEMO_VIDEO_URL>`
- Impact: These placeholders must never be submitted to Apple as-is.
- Fix: Paste the real review mailbox password only into App Store Connect Notes and replace the physical-device demo video URL before tapping `Add for Review`.

### Subscription promotional images are missing

- Severity: Warning
- Evidence: ASC subscription validation reports `subscriptions.images.recommended` for all four subscriptions.
- Impact: Not blocking unless we want promoted purchases / offer-code redemption page polish.
- Fix: Optional. Add unique promotional images later if using App Store subscription promotion surfaces.

### Turkey storefront pricing still needs onboarding-device display confirmation

- Severity: Warning / physical-device smoke gate
- Evidence: `asc subscriptions pricing summary --app 6769498181 --territory Turkey --output markdown` confirms Turkey storefront prices:
  - Plus monthly: `199.99 TRY`
  - Plus yearly: `1999.99 TRY`
  - Pro monthly: `499.99 TRY`
  - Pro yearly: `4999.99 TRY`
- Context: An earlier non-territory ASC CLI summary showed base/default USD prices, which is not the Turkey storefront display. Physical-device in-app paywalls were later verified as Turkish lira through iPhone Mirroring; onboarding Plus monthly/yearly still needs a separate fresh-path visual check.
- Fix: On physical device, confirm onboarding Plus monthly/yearly display `₺199,99` and `₺1.999,99`, with no USD/fallback copy.

### China mainland availability decision is still needed

- Severity: Warning
- Evidence: `asc pricing availability territory-availabilities --availability 6769498181 --paginate --output json` now shows `CHN available=true` and `availableInNewTerritories=true`. App description says "yapay zeka"; legal docs disclose Google Gemini / Google AI and Groq.
- Impact: China mainland is currently enabled, so AI provider references and functionality can trigger extra scrutiny unless a China-specific compliance decision is made.
- Fix: Exclude China mainland for first release, or prepare and record a China-specific compliance plan before submission.

### Supabase advisors report remaining auth/performance warnings

- Severity: Warning
- Evidence: `supabase db advisors --linked --type all --level warn --fail-on none --output json`
- Current post-hardening summary:
  - `auth_leaked_password_protection`: 1 warning
  - `multiple_permissive_policies`: 2 performance warnings
- Resolved by migrations:
  - `function_search_path_mutable`: cleared
  - `anon_security_definer_function_executable`: cleared
  - `authenticated_security_definer_function_executable`: cleared
- Release decision:
  - Supabase leaked-password protection remains disabled, but the known risk is accepted for this submission path because the release auth surface uses Email OTP, Apple, and Google; password demo sign-in is `#if DEBUG` only.
- Fix: Treat leaked-password protection as optional post-release hardening. Treat `profiles` multiple-policy warnings as performance cleanup, not App Review blockers.

### Worktree is very dirty

- Severity: Release hygiene warning
- Evidence: `git status --short` shows many modified/untracked files, including screenshot tooling, generated screenshots, QA output, Supabase changes, and app changes.
- Impact: Not all dirty files ship in the iOS binary, but release branch/commit hygiene is poor until curated.
- Fix: Use `QA/RELEASE_HYGIENE_2026-06-01.md` as the staging manifest before release/tag. It separates release-critical app/backend changes, marketing-only assets, and generated QA artifacts that should stay out of the release commit. `.gitignore` now protects `.env`, `.p8`, `AuthKey_*.p8`, `.DS_Store`, `QA/tmp/`, `output/paywall-device-matrix/`, `output/paywall-screenshots/`, `output/app-review-physical-smoke/`, and `output/imagegen/` from accidental staging.

## Passed

### Current live preflight refresh

Commands/checks refreshed on 2026-06-02 02:08 +03:

- `asc auth status` / `asc auth doctor`: default profile `CliRiskdetected`, key `UC3J4MTYBX`, private key valid in Keychain, no issues found.
- `asc builds info --app 6769498181 --build-number 31 --platform IOS`: build ID `fca919e5-b12a-4129-8d82-cf46ce1736c8`, state `VALID`, min iOS `16.0`, non-exempt encryption `false`.
- `asc review status`: `NOT_SUBMITTED`, `PREPARE_FOR_SUBMISSION`, `reviewDetail = not configured`, blocker count `1`.
- `asc validate`: expected four blocking errors only: `contactFirstName`, `contactLastName`, `contactEmail`, `contactPhone`.
- `asc validate subscriptions`: four subscriptions, `0` errors, `8` warnings, `0` blocking.
- `SUPABASE_DB_PASSWORD="$(security find-generic-password -a "$USER" -s riskdetected_supabase_db_password -w)" node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md`: latest full collector wrote the report at 2026-06-02 11:31 +03 with `37 PASS`, `2 WARN`, `6 HOLD`, `2 FAIL`, `1 SKIP`. Supabase leaked-password decision evidence is PASS; remaining FAILs are separate collector cleanup items for old paywall legal-link marker expectations and old screenshot path probing.
- Release simulation source gating now passes: iOS test-simulation helpers are DEBUG-only, Edge Function AI simulation requires explicit env flags, and the production runbook documents remote secret cleanup.
- Supabase production secret enumeration is skipped by release decision and no longer counted as an App Review preflight blocker. Source gating passes.
- Physical-device readiness evidence now passes in the collector: candidate `1.0 (31)` installed on `iPhone Kerem`, display evidence is `1320 x 2868`, and the 04:30 refresh confirms lock-state/app-info/details through CoreDevice; foreground launch still requires an unlocked, awake, interactive iPhone.
- Release local-evidence hygiene now passes in the collector: `.gitignore` excludes raw physical-device smoke output and raw imagegen output, and the release staging guard fails if those local evidence files are staged.
- Supabase Auth baseline restored and verified after a temporary broad-config drift: Email/Apple/Google enabled, phone disabled, signup enabled, `mailer_autoconfirm=false`, and local config preserves the iOS callback allow-list.
- `node scripts/release_staging_guard.mjs`: passed; no staged files.
- `git diff --check`: passed.
- XcodeBuildMCP `build_sim CODE_SIGNING_ALLOWED=NO`: succeeded with `0` warnings and `0` errors.
- XcodeBuildMCP targeted paywall UI tests:
  - `RiskDetectedUITests/testInAppPaywallClaudePlusAndProRenderWithFreeTier`
  - `RiskDetectedUITests/testPaywallYearlyMonthlyToggleForPlusAndPro`
  - Result: `2 passed`, `0 failed`.

### ASC authentication and app lookup

Commands:

```bash
asc auth status
asc auth doctor
asc apps list --bundle-id com.riskdetected.app --output json --pretty
```

Result:

- Default profile: `CliRiskdetected`
- Key ID: `UC3J4MTYBX`
- `asc auth doctor`: no issues found
- App found: `6769498181`

### ASC metadata

Commands:

```bash
asc versions list --app 6769498181 --output json --pretty
asc metadata pull --app 6769498181 --version 1.0 --dir /tmp/rd-asc-metadata-current
asc apps info view --app 6769498181 --version 1.0 --platform IOS --output json --pretty
```

Result:

- Primary locale: `tr`
- Name length: `25`
- Subtitle length: `23`
- Description length: `1492`
- Keywords length: `95`
- Promotional text length: `156`
- What's New length: `0`
- Privacy Policy URL: `https://riskdetected.com/gizlilik`
- Marketing URL: `https://riskdetected.com`
- Support URL: `https://riskdetected.com`
- App description includes:
  - Terms URL
  - Privacy URL
  - Apple Standard EULA URL
  - Subscription note
  - AI/professional-review disclaimer
- Metadata placeholder/dev-word scan: no actionable placeholder/test/beta/debug/staging content found. The only `dev` hit is Apple's official EULA URL path `/itunes/dev/stdeula/`.
- Fresh ASC metadata pull to `/tmp/rd-asc-metadata-preflight-now` produced only the `tr` app-info/version metadata files; metadata scan found no placeholder, test, beta, debug, staging, localhost, AI brand-name stuffing, or China-specific banned AI brand terms.

URL checks:

- `https://riskdetected.com` -> `200`
- `https://riskdetected.com/gizlilik` -> `200`
- `https://riskdetected.com/kullanim-kosullari` -> `200`
- `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` -> `200`

### ASC subscription products

Commands:

```bash
asc subscriptions groups list --app 6769498181 --output json --pretty
asc subscriptions list --group-id 22089637 --output json --pretty
asc subscriptions pricing summary --app 6769498181 --output json --pretty
asc validate subscriptions --app 6769498181 --output markdown
```

Result:

- Group: `RiskDetected Plans` (`22089637`)
- Four subscriptions exist:
  - `6769501024` / `riskdetected_plus_monthly` / `ONE_MONTH` / `READY_TO_SUBMIT`
  - `6769501933` / `riskdetected_plus_yearly` / `ONE_YEAR` / `READY_TO_SUBMIT`
  - `6769504185` / `riskdetected_pro_monthly` / `ONE_MONTH` / `READY_TO_SUBMIT`
  - `6769504261` / `riskdetected_pro_yearly` / `ONE_YEAR` / `READY_TO_SUBMIT`
- No subscription validation errors.
- Eight warnings: four optional promotional image warnings and four `READY_TO_SUBMIT` review-readiness warnings.

### Local archive and App Store IPA export

Superseded first export evidence:

```bash
xcodebuild -project RiskDetected.xcodeproj \
  -scheme RiskDetected \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/RiskDetected-AppReview.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath /tmp/RiskDetected-AppReview.xcarchive \
  -exportOptionsPlist /tmp/RiskDetectedExportOptions.plist \
  -exportPath /tmp/RiskDetectedExport \
  -allowProvisioningUpdates
```

Results:

- `ARCHIVE SUCCEEDED`
- `EXPORT SUCCEEDED`
- Exported IPA: `/tmp/RiskDetectedExport/RiskDetected.ipa`
- Version: `1.0`
- Build: `28`
- Certificate: `Cloud Managed Apple Distribution`
- Profile: `iOS Team Store Provisioning Profile: com.riskdetected.app`
- Entitlements:
  - `aps-environment = production`
  - `get-task-allow = false`
  - `com.apple.developer.applesignin = Default`

Note: `asc xcode validate --ipa /tmp/RiskDetectedExport/RiskDetected.ipa` was attempted, but `altool` requires `--api-issuer` in addition to the key ID. The current `asc` profile works for App Store Connect API calls, but does not expose issuer information to `altool` automatically. Re-run IPA server-side validation after passing the Issuer ID explicitly or upload through Xcode Organizer / Transporter.

This first export is retained only as historical evidence. The active ASC candidate is the later current-worktree export/upload `1.0 (31)` below.

Current-worktree archive re-check:

```bash
xcodebuild -project RiskDetected.xcodeproj \
  -scheme RiskDetected \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/RiskDetected-AppReview-Current.xcarchive \
  archive
```

Result:

- `ARCHIVE SUCCEEDED`
- Xcode `Validate ... -validate-for-store` step ran successfully.
- Note: this archive step used the local development signing identity/profile for archive validation only. The final ASC-attached candidate is distribution-signed build `1.0 (31)`.

Current-worktree App Store export re-check:

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/RiskDetected-AppReview-31.xcarchive \
  -exportOptionsPlist /tmp/RiskDetectedExportOptions.plist \
  -exportPath /tmp/RiskDetectedExport31 \
  -allowProvisioningUpdates
```

Result:

- `EXPORT SUCCEEDED`
- Exported IPA: `/tmp/RiskDetectedExport31/RiskDetected.ipa`
- Exported IPA size: `26M`
- Version: `1.0`
- Build: `31`
- Certificate: `Cloud Managed Apple Distribution`
- Profile: `iOS Team Store Provisioning Profile: com.riskdetected.app`
- Entitlements:
  - `aps-environment = production`
  - `get-task-allow = false`
  - `com.apple.developer.applesignin = Default`
- File hygiene: no matches for `Marketing`, `mockup`, `screenshot`, `AppStoreScreenshots`, `RiskDetectedUITests`, `QA`, `Temporary`, `.p8`, `.env`, or `AuthKey` inside the exported `.app`.
- Narrow binary marker scan: no matches for `RD_UI_TEST`, `AuthKey_*.p8`, `SERVICE_ROLE`, QA secrets, RevenueCat webhook secret name, APNS private key, Supabase secret markers, or `.p8`.
- Note: build `31` supersedes build `30` after the release UI-test hardening below.
- Latest ASC build re-check: build ID `fca919e5-b12a-4129-8d82-cf46ce1736c8`, pre-release version `1.0`, uploaded `2026-06-01T09:54:20-07:00`, processing state `VALID`, min iOS `16.0`, `usesNonExemptEncryption = false`.

### Simulator build and targeted UI smoke

Commands:

```bash
# Via XcodeBuildMCP
build_sim CODE_SIGNING_ALLOWED=NO
test_sim CODE_SIGNING_ALLOWED=NO -only-testing:RiskDetectedUITests/RiskDetectedUITests/testInAppPaywallClaudePlusAndProRenderWithFreeTier

xcodebuild -project RiskDetected.xcodeproj \
  -scheme RiskDetected \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4A71277B-053D-49CF-8414-57840D9B010A' \
  -derivedDataPath /tmp/RiskDetectedPreflightDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:RiskDetectedUITests/RiskDetectedUITests/testInAppPaywallClaudePlusAndProRenderWithFreeTier \
  test-without-building
```

Result:

- Simulator: `iPhone 17 Pro` / iOS `26.5`.
- Latest XcodeBuildMCP `build_sim`: succeeded in `4797ms`.
- Latest build diagnostics: `0` warnings, `0` errors.
- Latest XcodeBuildMCP targeted UI test: `RiskDetectedUITests.testInAppPaywallClaudePlusAndProRenderWithFreeTier()` passed; 1 passed, 0 failed, 0 skipped.
- Full UI suite note: an earlier all-tests MCP run exceeded the 120s MCP tool timeout and was terminated; use targeted smoke or a longer CI timeout for full UI regression.

### ASC build upload and attachment

Commands:

```bash
asc builds next-build-number --app 6769498181 --version 1.0 --platform IOS --output json --pretty
asc builds upload --app 6769498181 --ipa /tmp/RiskDetectedExport31/RiskDetected.ipa --version 1.0 --build-number 31 --wait --poll-interval 30s --output json --pretty
asc builds wait --app 6769498181 --build-number 31 --version 1.0 --platform IOS --poll-interval 30s --output json --pretty
asc versions attach-build --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --build fca919e5-b12a-4129-8d82-cf46ce1736c8 --output json --pretty
```

Result:

- Next build number for `1.0`: `31`.
- Uploaded build ID: `fca919e5-b12a-4129-8d82-cf46ce1736c8`.
- Pre-release version: `1.0`.
- Processing state: `VALID`.
- `usesNonExemptEncryption = false`.
- Attached to ASC version `1.0`: `true`.
- Re-run validation now reports 4 blocking errors instead of 5; the previous `build.required.missing` error is resolved.

### Binary/package hygiene

Checks:

```bash
find /tmp/RiskDetectedIPA31/Payload/RiskDetected.app -maxdepth 4 -print \
  | rg 'Marketing|mockup|screenshot|AppStoreScreenshots|RiskDetectedUITests|QA|Temporary|\.p8|\.env|AuthKey|paywall-device-matrix|paywall-screenshots' -i

/usr/bin/strings /tmp/RiskDetectedIPA31/Payload/RiskDetected.app/RiskDetected \
  | rg 'demo@riskdetected\.app|plus@riskdetected\.app|free@riskdetected\.app|demo123456|plus123456|free123456|Pro demo|Plus demo|Free demo|RD_UI_TEST|AuthKey_|SERVICE_ROLE|GROQ_QA_SECRET|AI_QA_SECRET|REVENUECAT_WEBHOOK_AUTHORIZATION|APNS_PRIVATE_KEY|SUPABASE_SERVICE_ROLE|SUPABASE_SECRET|\.p8|localhost|127\.0\.0\.1' -i
```

Result:

- No matches for QA/test/screenshot tooling folders.
- No `.p8`, `.env`, AuthKey, or service-role secrets in the IPA.
- No `RD_UI_TEST` launch flags in the exported IPA binary.
- No demo account emails, demo passwords, or demo labels in the exported IPA binary.
- Marketing App Icon concept/mockup images no longer ship in the app bundle.
- The app source contains no `localhost`, `127.0.0.1`, or `allowLocalhostRequest` references.
- Note: the current `1.0 (31)` narrow binary marker scan completed with no secret/test marker matches. The only localhost-related strings found by the expanded scan are from linked auth library support (`allowLocalhostRequest`, `http://localhost:9999`, `localhost.local`, `127.0.0.1`), not app backend configuration.

### Privacy manifest and entitlements

Evidence:

- `App/PrivacyInfo.xcprivacy`
- `App/RiskDetected.entitlements`
- Exported IPA entitlements
- Exported IPA `Info.plist`
- Exported IPA embedded third-party `PrivacyInfo.xcprivacy` files

Result:

- `NSPrivacyTracking = false`
- Required reason API category present: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`
- Exported IPA contains `12` privacy manifests, including app, Google Sign-In/Auth, RevenueCat, GoogleUtilities, Promises, and swift-crypto bundles.
- All exported privacy manifests report `NSPrivacyTracking = false`.
- All exported privacy manifests report zero tracking domains.
- Third-party privacy manifests disclose the expected non-tracking data surfaces:
  - Google Sign-In: name, email address, phone number, other data types, coarse location, user ID, device ID, and other usage data for app functionality/analytics.
  - RevenueCat: purchase history for app functionality.
  - App/Google utility bundles: UserDefaults required-reason API usage.
- Local source scan found no app code using `ATTrackingManager`, `AppTrackingTransparency`, `ASIdentifierManager`, `advertisingIdentifier`, AdSupport, IDFA, SKAdNetwork, Firebase Analytics, Adjust, AppsFlyer, Branch, Mixpanel, Amplitude, PostHog, or Crashlytics.
- Exported IPA `Info.plist` does not contain `NSUserTrackingUsageDescription`, ad network IDs, Google Ads IDs, Facebook IDs, or SKAdNetwork items.
- Binary strings include dormant RevenueCat attribution support symbols such as IDFA/network attribution keys, but local app code does not call RevenueCat attribution APIs and the binary does not link `AdSupport.framework`.
- Exported app entitlements from the embedded App Store provisioning profile:
  - `application-identifier = 68CU98HAY3.com.riskdetected.app`
  - `aps-environment = production`
  - `get-task-allow = false`
  - `com.apple.developer.applesignin = Default`
- Exported IPA `Info.plist` includes Turkish, purpose-specific permission strings:
  - `NSCameraUsageDescription`: saha fotoğrafı çekerek iş güvenliği analizi.
  - `NSPhotoLibraryUsageDescription`: saha fotoğraflarını analiz etmek için galeri erişimi.
- `ITSAppUsesNonExemptEncryption = false`
- Exported IPA version/build: `1.0 (31)`
- Legal documents are bundled in the exported app:
  - `Gizlilik-Politikasi.md`
  - `Kullanim-Kosullari.md`
  - `KVKK-Aydinlatma-ve-Acik-Riza-Metni.md`
  - `Acik-Riza-Beyani.md`
- Sign in with Apple entitlement present.
- Production APNs entitlement present in exported IPA.

### Account deletion and legal access

Evidence:

- `App/Views/Profile/ProfileView.swift`
- `App/Services/AnalysisService.swift`
- `supabase/functions/request-account-deletion/index.ts`
- `supabase/functions/account-deletion-complete/index.ts`
- `App/Views/Legal/LegalInfoSheet.swift`
- `App/Views/Components/LegalAcceptanceNotice.swift`
- `App/Views/Paywall/PaywallView.swift`
- `App/Views/Paywall/InAppPaywallView.swift`

Result:

- Profile data section exposes:
  - `Verilerimi dışa aktar`
  - `Tüm raporlarımı sil`
  - `Tüm analizlerimi sil`
  - `Hesabımı ve verilerimi sil`
- Account deletion confirmation text states profile, analyses, reports, and stored files are permanently deleted, and active App Store subscriptions are managed through Apple.
- The mobile app calls the user-callable `request-account-deletion` Edge Function with the signed-in user's JWT; the app never receives the service-role key.
- `request-account-deletion` verifies the JWT with Supabase Auth, creates/reuses an `account_deletion_requests` row, then invokes the privileged `account-deletion-complete` worker server-side.
- Legal access exists in auth/onboarding/profile/paywall surfaces:
  - Auth/onboarding legal notice links to Privacy, KVKK, and Explicit Consent.
  - Profile opens the bundled legal document sheet.
  - In-app and onboarding paywalls link to Terms, Privacy, and Apple subscription management.

### Review notes readiness

Evidence:

- `.agents/skills/app-store-preflight-skills/references/rules/metadata/review_notes_new_submission.md`
- `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`
- `QA/App_Store_Submission_Preparation_2026-05-16.md`
- `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md`

Result:

- The review notes template now covers all six new-submission sections:
  - Physical-device demo video.
  - App purpose and value.
  - Access instructions and test credentials.
  - External services.
  - Regional differences.
  - Regulated-industry documentation / not-applicable explanation.
- Remaining manual replacements:
  - Real Fastmail mailbox password must be pasted only into App Store Connect Notes.
  - Physical-device demo video URL must be replaced before submission.

### Supabase backend readiness

Commands:

```bash
supabase projects list
supabase functions list --project-ref ppcrzemgiztzcgddbins
deno check $(find supabase/functions -maxdepth 2 -name index.ts | sort)
supabase db lint --linked --level warning --fail-on none
supabase db advisors --linked --type all --level warn --fail-on none --output json
```

Results:

- Project linked: `riskdetected` / `ppcrzemgiztzcgddbins`.
- Supabase production secret enumeration is intentionally skipped by request; source gating verifies test-simulation code is not active by default.
- All listed Edge Functions are `ACTIVE`.
- Required remote secret names are present, including:
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `GEMINI_API_KEY`
  - `GEMINI_API_KEY_PAID`
  - `GROQ_API_KEY_FREE`
  - `GROQ_API_KEY_PLUS_PRO`
  - `REVENUECAT_WEBHOOK_AUTHORIZATION`
  - `APNS_KEY_ID`
  - `APNS_TEAM_ID`
  - `APNS_BUNDLE_ID`
  - `APNS_PRIVATE_KEY`
  - `APNS_ENV`
  - `PROCESS_ANALYSIS_JOBS_SECRET`
  - `RETENTION_CLEANUP_SECRET`
  - `AI_QA_SECRET`
  - `GROQ_QA_SECRET`
- Latest `deno check` passed for all Edge Function `index.ts` files.
- Previous `supabase db lint --linked --level warning --fail-on none` run passed with no schema errors after the migrations were applied.
- Latest 2026-06-02 re-check: `supabase db lint --linked --level warning --fail-on none` completed through the linked CLI profile and reported `No schema errors found`; no database password was recorded.
- `supabase db advisors --linked --type all --level warn --fail-on none --output json` completed after the migrations were applied and returned only the remaining warnings summarized above.
- Latest `supabase db advisors` re-check completed and still reports the same post-hardening summary:
  - `auth_leaked_password_protection: 1`
  - `multiple_permissive_policies: 2`

## Local Fixes Applied In This Pass

### Version alignment

File:

- `RiskDetected.xcodeproj/project.pbxproj`

Change:

- App target `MARKETING_VERSION` changed from `0.1.0` to `1.0`.
- App target `CURRENT_PROJECT_VERSION` changed from `27` to `28` for the first upload, then from `28` to `29`, then from `29` to `30`, then from `30` to `31` after the release UI-test hardening was applied and uploaded.

Reason:

- ASC version is `1.0`; uploaded build must match the App Store version and final attached build number.

### Marketing assets removed from app bundle

Moved:

- `App/Marketing/AppIconConcepts/` -> `Marketing/AppIconConcepts/`

Reason:

- `App` is a synchronized Xcode root. Marketing-only concept/mockup PNG files were being copied into the archive/IPA. They are not runtime app assets and should not ship.

### Supabase security migrations applied

Files:

- `supabase/migrations/20260601064449_deep_security_remediation.sql`
- `supabase/migrations/20260601154641_app_review_preflight_function_hardening.sql`

Change:

- Makes analysis quota reservation idempotent for queued worker retries.
- Adds durable support request rate limiting.
- Narrows client-writable table policies to the intended app surface.
- Revokes direct `anon` / `authenticated` execute access from trigger-style `SECURITY DEFINER` functions:
  - `public.enforce_report_plan_limits()`
  - `public.set_photo_retention_fields()`
- Pins `search_path` for:
  - `public.set_updated_at()`
  - `private.pp_title_key_for_mdp(integer)`
  - `private.pp_title_label(text)`
  - `private.pp_competency_label(text)`
  - `private.pp_risk_rank(text)`
  - `private.pp_highest_risk_level(text, text)`
  - `private.pp_contains_any(text, text[])`

Apply status:

- Applied to remote with `supabase db push`.
- Post-hardening advisor summary:
  - `auth_leaked_password_protection: 1`
  - `multiple_permissive_policies: 2`
- Follow-up `supabase migration list --linked` remains unreliable in the local CLI session: one attempt hit a Supabase CLI JSON parse error, and later exploratory DB metadata queries hit pooler `ECIRCUITBREAKER`/SASL failures. The latest full `db lint` re-check completed successfully at 2026-06-02 02:08 +03 with `No schema errors found`; do not keep retrying DB-query loops rapidly without the correct env if the pooler reports temporary auth failures. The successful `supabase db push`, clean lint run, `deno check`, deployed Edge Function list, Auth baseline restore verification, and repeated post-hardening advisor summaries are the current backend evidence.

### Swift warning cleanup

File:

- `App/Services/SubscriptionManager.swift`

Change:

- Made the intentionally ignored `FileHandle.seekToEnd()` return value explicit in DEBUG RevenueCat diagnostics logging.

Verification:

- Re-ran simulator build; diagnostics now report `0` warnings and `0` errors.

### Release UI-test hardening

Files:

- `App/RootView.swift`
- `App/Services/NetworkMonitor.swift`
- `App/Services/NotificationService.swift`
- `App/Views/Home/MainTabView.swift`
- `App/Views/Onboarding/V2/OnboardingViewV2.swift`

Change:

- Wrapped generic `RD_UI_TEST_` launch flag checks in `#if DEBUG`, returning `false` in Release builds.
- Wrapped demo sign-in state, demo account credentials, and demo sign-in helpers in `#if DEBUG`.

Reason:

- UI test hooks and demo sign-in helpers remain available for Debug simulator tests, but cannot alter Release/App Store behavior or leave demo credentials in the App Store binary.

Verification:

- XcodeBuildMCP simulator build passed with `0` warnings and `0` errors after the change.
- Targeted UI test `RiskDetectedUITests.testInAppPaywallClaudePlusAndProRenderWithFreeTier()` still passed in Debug on iPhone 17 Pro.
- Exported IPA binary marker scan found no demo account emails, demo passwords, demo labels, or `RD_UI_TEST` strings.
- Release archive/export produced IPA `1.0 (31)`, which was uploaded, processed as `VALID`, and attached to ASC version `1.0`.

## Final Before-Submission Checklist

- Fill App Review contact first name, last name, email, and phone in ASC.
- Done: upload and attach build `1.0 (31)` to ASC version `1.0`.
- Use `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md` as the final ordered checklist before tapping `Add for Review`.
- Use `QA/APP_REVIEW_GATE_MATRIX_2026-06-01.md` as the one-page pass/hold/blocker status view.
- Fill `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` with non-secret manual evidence from ASC, Supabase, and physical-device smoke testing.
- Run `node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md` for a fresh read-only evidence snapshot.
- Use `QA/RELEASE_HYGIENE_2026-06-01.md` for final release staging; do not bulk-stage `output/`, `.DS_Store`, or raw generated QA screenshots.
- Attach all four `READY_TO_SUBMIT` subscriptions to the app review submission.
- Confirm App Privacy is completed/published in ASC.
- Confirm Turkey storefront subscription price points in ASC UI and one final sandbox-device paywall price display.
- Re-run:
  - `asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown`
  - `asc validate subscriptions --app 6769498181 --output markdown`
- Supabase leaked-password protection is accepted known risk for this submission path; enablement remains optional post-release hardening if plan support and release timing allow it.
- Dashboard path for post-release hardening: Supabase project `riskdetected` -> Authentication -> Settings -> Password Security -> Prevent use of leaked passwords.
- Official Supabase note: leaked password protection is available on Pro plan and above.
- Re-run Supabase `migration list`, `db lint`, and `db advisors` through the linked CLI profile, mainly to archive clean final evidence.
- Do final TestFlight physical-device smoke:
  - email OTP login
  - Apple login
  - Google login
  - paywall product load
  - purchase sandbox flow
  - restore purchases
  - one Free analysis
  - one Plus/Pro entitlement sync
  - account deletion request flow
- Curate release commit contents and keep `output/`, temporary screenshots, raw QA captures, and local CLI keys out of the release commit.
