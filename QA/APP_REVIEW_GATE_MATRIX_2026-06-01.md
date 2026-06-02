# App Review Gate Matrix - 2026-06-01

Scope: RiskDetected `1.0 (31)` App Review candidate.

This is the one-page gate view for submission day. It intentionally does not fill App Review contact fields and does not start App Review submission.

Manual evidence form:

- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`
- `QA/APP_REVIEW_PHYSICAL_SMOKE_17PM_2026-06-01.md`

## Current Candidate

| Item | Value |
| --- | --- |
| App ID | `6769498181` |
| Bundle ID | `com.riskdetected.app` |
| Version ID | `e97f1de1-7e8c-448b-a5b9-80869f0a8816` |
| Version | `1.0` |
| Build | `31` |
| Build ID | `fca919e5-b12a-4129-8d82-cf46ce1736c8` |
| Supabase project | `ppcrzemgiztzcgddbins` |

## Gate Matrix

| Gate | Status | Evidence | Submission action |
| --- | --- | --- | --- |
| ASC build attached | Passed | `asc builds info` reports build `31` as `VALID`; build ID `fca919e5-b12a-4129-8d82-cf46ce1736c8`; attached to version `1.0`. | Re-check immediately before submit. |
| ASC review state | Holding | `asc review status` reports `NOT_SUBMITTED`, `PREPARE_FOR_SUBMISSION`, `reviewDetail = not configured`, `blockerCount = 1`. | Expected until contact fields are intentionally filled. |
| App Review contact details | Blocking/manual | `asc validate` reports missing `contactFirstName`, `contactLastName`, `contactEmail`, `contactPhone`. | Fill in ASC only when ready to submit. |
| Review notes completeness | Ready except placeholders | `QA/App_Review_Webmail_OTP_Access_2026-06-01.md` covers physical-device video, purpose, access/test credentials, external services, regional differences, and regulated-industry not-applicable explanation. | Replace mailbox password and physical-device demo video URL in ASC Notes only. |
| App Privacy | Configured, publish pending | ASC App Privacy UI shows Privacy Policy URL, product page preview, and 16 declared data types. ASC CLI still reports `privacy.publish_state.unverified`, and the UI shows a `Publish` button, so final publish remains manual. Local privacy manifests and source scans are clean. | Click `Publish` in ASC App Privacy when ready; re-run validation afterward. |
| Subscription products | Attached to version, not yet submitted | Four products exist and `asc validate subscriptions` has `0` errors; all four are `READY_TO_SUBMIT`. ASC iOS App Version `1.0` page shows Plus Monthly, Plus Yearly, Pro Monthly, and Pro Yearly under `In-App Purchases and Subscriptions`. | Keep all four attached; warnings should clear only when the app/subscriptions are submitted for review. |
| Subscription promo images | Optional warning | ASC reports four `subscriptions.images.recommended` warnings. | Optional; not a blocker unless using promoted subscription surfaces. |
| Turkey pricing/paywall display | Partially passed/manual device gate | Evidence collector verifies ASC Turkey storefront pricing automatically: Plus monthly `199.99 TRY`, Plus yearly `1999.99 TRY`, Pro monthly `499.99 TRY`, Pro yearly `4999.99 TRY`. Physical-device in-app paywalls were also checked via iPhone Mirroring on `iPhone Kerem`: Plus monthly `₺199,99`, Plus yearly `₺1.999,99`, Pro monthly `₺499,99`, Pro yearly `₺4.999,99`; no USD/fallback observed there. Onboarding Plus paywall still needs a separate visual check. | Confirm onboarding Plus monthly/yearly on a fresh/non-onboarded path; verify no USD/fallback copy there. |
| Binary/package hygiene | Passed | Exported IPA has no QA folders, App Store screenshot tooling, `.p8`, `.env`, AuthKey, demo accounts, `RD_UI_TEST`, service-role strings, or marketing mockups. | Re-run if a new IPA is exported. |
| Privacy manifests/tracking | Passed locally | Exported IPA contains 12 privacy manifests; all report `NSPrivacyTracking = false` and zero tracking domains. Local source/exported `Info.plist` show no ATT, IDFA, ad IDs, or SKAdNetwork items. | Match ASC App Privacy labels to bundled Google Sign-In and RevenueCat data disclosures. |
| Entitlements/signing | Passed | Exported IPA uses distribution signing, production APNs, Sign in with Apple, and `get-task-allow = false`. | Re-run if a new IPA is exported. |
| Metadata/public URLs | Passed | Fresh ASC metadata pull has valid Turkish locale, no placeholders, no banned AI brand stuffing, and no localhost/test/beta/debug/staging terms. Evidence collector also verifies public website, privacy, terms, KVKK, explicit consent, cookie policy, and Apple Standard EULA URLs return HTTP `200`. | Re-check if metadata or public URLs change. |
| Legal/account deletion | Passed locally and partially on device | App exposes legal docs, paywall legal links, profile legal center, account data controls, and account deletion request flow. Evidence collector verifies `RDConfig.Web` legal URLs, bundled in-app legal markdown documents, Profile deletion UI, client function invocation, and both Supabase account-deletion Edge Functions. Physical 17 Pro Max smoke also opened the in-app legal sheet and the `Verilerim` account-deletion entry point without submitting a destructive action. | Final full smoke can leave destructive deletion unsubmitted; confirm reviewer-facing copy remains clear. |
| AI disclosure / China mainland | Partial PASS + Hold/manual | Collector now has a dedicated `AI-assisted analysis disclosure` PASS gate: Review Notes, Kullanım Koşulları, Gizlilik Politikası, and KVKK text disclose AI-assisted analysis, provider context, and professional-review limits. `asc pricing availability territory-availabilities --availability 6769498181 --paginate --output json` still shows `CHN available=true` and `availableInNewTerritories=true`. | Exclude China mainland for first release, or record a China-specific compliance decision before submission. |
| Supabase Edge Functions | Passed local and remote | `deno check` passes for all Edge Function `index.ts` files. Remote `supabase functions list` confirms all 15 locally configured functions are `ACTIVE` and match local `verify_jwt`; `register-report` was deployed on 2026-06-02 00:55 +03 after the preflight found it was local-only while the app calls it for PDF report metadata. | Re-run after backend edits; keep `register-report` attached/deployed for fresh PDF generation smoke. |
| Supabase Auth baseline | Passed | A broad Auth config drift was restored at 2026-06-02 01:38 +03. Collector now verifies local `supabase/config.toml` and public `/auth/v1/settings`: Email/Apple/Google enabled, phone disabled, signup enabled, `mailer_autoconfirm=false`, and iOS callback allow-list preserved. | Re-run after any Supabase Auth/dashboard/config change; do not run broad `supabase config push` without reviewing the diff. |
| Supabase advisors | Warning/accepted | Current advisors show `auth_leaked_password_protection: 1` and `multiple_permissive_policies: 2`. Prior security-definer/search-path and RLS init-plan warnings are cleared. Supabase CLI exposes no safe minimal read/toggle command for leaked-password protection in the installed version; source scan shows release auth uses Email OTP, Apple, and Google, while password demo sign-in is `#if DEBUG` only. Latest investigation in `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md` records the Auth config restore and accepted-risk decision. | Leaked-password protection is accepted known risk for this submission and optional post-release hardening; treat `profiles` permissive-policy items as performance cleanup unless new security evidence appears. |
| Supabase production simulation secrets | Skipped by release decision | Collector has a dedicated `Release simulation source gating` PASS gate: iOS test-simulation helpers are DEBUG-only, Edge Function AI simulation requires explicit env flags, and the production runbook documents remote secret cleanup. Remote production secret enumeration is intentionally skipped by release decision. | No App Review blocker counted for this item; keep source gating green. |
| Supabase db lint | Passed | `supabase db lint --linked --level warning --fail-on none` completed again on 2026-06-02 02:08 +03 through the linked CLI profile and reported `No schema errors found`. | Re-run after backend/schema edits and again on submission day. |
| Simulator build/UI smoke | Passed | XcodeBuildMCP `build_sim` passed again on 2026-06-02 00:23 +03 on `iPhone 17 Pro` / iOS 26.5 with 0 warnings/errors. Targeted paywall UI tests passed again on 2026-06-02 00:25 +03: `testInAppPaywallClaudePlusAndProRenderWithFreeTier` and `testPaywallYearlyMonthlyToggleForPlusAndPro` (`2 passed`, `0 failed`). Latest build log: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/logs/build_sim_2026-06-01T21-23-12-413Z_pid65279_69032fd2.log`; latest xcresult: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-06-01T21-24-28-824Z_pid65279_2d78585a.xcresult`. | Re-run after app code edits. |
| App Store screenshots | Prepared, owner approval/upload pending | Final iPhone TR 6.9 upload candidate exists at `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/` with 10 PNG files at `1320 x 2868`; collector count/dimension gates pass. Source deck still has 13 slides and the 6.1 set remains at `1125 x 2436`. Codex visual QA found no obvious private email/phone/token/support ID/private identifier, localhost/debug/beta label, or USD/fallback price at contact-sheet scale; see `QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md`. Demo field photo/profile avatar/report imagery still needs owner/marketing approval as non-private before upload. | Visually approve the 10-file final set, then upload it in ASC. Keep source/raw screenshot tooling out of runtime release commits unless intentionally staging marketing assets. |
| Physical-device candidate install | Passed | Collector/device discovery on 2026-06-01 21:50 +03: `iPhone Kerem` 17 Pro Max has `com.riskdetected.app` candidate `1.0 (31)` installed. `Kerem iPhone` 14 Pro Max is not required for this gate because the 17 Pro Max target device is current. | Use `iPhone Kerem` for physical smoke. |
| Physical-device smoke | Manual gate | Required by runbook for OTP login, Apple/Google login, onboarding paywall display, sandbox purchase/restore, analysis, entitlement sync, report generation, and account deletion request. Candidate install, clean foreground launch, iPhone Mirroring access, active Pro state, in-app Plus/Pro TL prices, report archive PDF/Excel preview, backend subscription aggregate, in-app legal sheet, support form, notification copy, and account-deletion entry point are confirmed on 17 Pro Max; remaining functional smoke is open. Latest launch evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-01-rerun.json`. Worksheet: `QA/APP_REVIEW_PHYSICAL_SMOKE_17PM_2026-06-01.md`. | Run the remaining smoke checklist on `iPhone Kerem` before submit; purchase-sheet test needs a non-entitled sandbox user. |
| Release staging hygiene | Warning | Worktree remains dirty with runtime, backend, QA, marketing, and generated-output changes. `QA/RELEASE_HYGIENE_2026-06-01.md` separates include/exclude classes; `scripts/release_staging_guard.mjs` checks staged files. | Curate staging; run the staging guard before commit/tag; do not bulk-stage generated output or local keys. |

## Evidence Collector

Run this read-only collector on submission day:

```bash
node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-01.md
```

Latest generated report:

- `QA/App_Review_Preflight_Evidence_2026-06-02.md`
- Summary: `37 PASS`, `2 WARN`, `6 HOLD`, `2 FAIL`, `1 SKIP`

Expected non-pass statuses before final manual work:

- `HOLD`: ASC review is intentionally not submitted.
- `HOLD`: ASC validation has only the intentionally missing App Review contact fields.
- `HOLD`: App Privacy publish evidence is still manual/pending; ASC validation reports `privacy.publish_state.unverified`.
- `HOLD`: App Store screenshot visual approval/upload evidence is still manual/pending; count and dimensions pass, but final approval/upload is not recorded yet.
- `HOLD`: China mainland is currently available while the app discloses AI-assisted analysis; exclude China mainland for first release or record a China-specific compliance decision.
- `PASS`: Supabase leaked-password protection is accepted known risk for this submission path.
- `HOLD`: Supabase production secrets could not be listed with the current CLI token state; verify no test simulation secret names are present before submission.
- `HOLD`: Manual evidence form still has TODO/placeholders until final ASC/device checks are recorded.
- `HOLD`: Physical-device smoke still has open TODO/PARTIAL/NOT TESTED rows.
- `HOLD`: Physical-device auth smoke still needs Email OTP, Apple login, and Google login evidence.
- `HOLD`: Physical-device onboarding paywall smoke still needs Plus monthly/yearly TL and no-fallback evidence.
- `HOLD`: Physical-device purchase and restore smoke still needs non-entitled sandbox purchase sheet, successful purchase, restore, and entitlement sync evidence.
- `HOLD`: Physical-device fresh analysis/report smoke still needs one fresh free analysis plus fresh PDF/Excel generation evidence.
- `HOLD`: App Store Review Notes draft still has ASC-only placeholders for the mailbox password and physical-device demo video URL.
- `PASS`: Supabase linked `db lint` reports no schema errors.
- `PASS`: Supabase deployed Edge Functions match local config; `register-report` is remote `ACTIVE` and JWT-protected.
- `PASS`: Release staging guard and dirty worktree guard report no forbidden staged/dirty files.
- `PASS`: Release simulation source gating confirms test-simulation helpers are not active by default in production code.
- `PASS`: App Store screenshot count/dimensions pass against the final 10-file iPhone 6.9 candidate set.
- `WARN`: RevenueCat binary contains dormant attribution support strings; app source does not call attribution APIs.
- `WARN`: Supabase advisors still show accepted leaked-password risk plus `profiles` permissive-policy performance cleanup.

## Final Submit Preconditions

Do not tap `Add for Review` until:

- App Review contact fields are filled.
- ASC Notes placeholders are replaced in App Store Connect only.
- App Privacy is published in ASC UI.
- All four subscriptions remain attached to the app review submission.
- Turkey pricing/paywall physical-device check passes.
- Final App Store screenshot set is visually approved and uploaded.
- Supabase leaked-password toggle decision is made.
- Supabase production secrets are verified to contain no test simulation flags.
- Supabase linked `db lint` remains clean.
- Physical-device smoke test passes.
- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` is filled with non-secret pass/fail evidence.
- Final `asc validate`, `asc validate subscriptions`, and `asc review status` match the runbook pass conditions.
