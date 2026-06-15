# App Review Remaining Actions - 2026-06-02

Scope: RiskDetected `1.0 (31)` App Review candidate.

This file tracks only the remaining submission blockers and manual smoke checks. Do not store real passwords, private phone numbers, OTP codes, API keys, App Store Connect keys, sandbox Apple ID passwords, or user identifiers here.

## Current Automated Gate

Latest read-only collector:

- Report: `QA/App_Review_Preflight_Evidence_2026-06-02.md`
- Command: `node scripts/app_review_preflight_collect.mjs`
- Result at 2026-06-02 11:31 +03: `37 PASS`, `2 WARN`, `6 HOLD`, `2 FAIL`, `1 SKIP`

Expected non-pass items:

- `HOLD`: App Review contact fields are intentionally empty.
- `HOLD`: ASC validation reports only the intentionally missing contact fields.
- `HOLD`: App Privacy publish evidence is still manual/pending; ASC validation reports `privacy.publish_state.unverified`.
- `FAIL`: Subscription paywall disclosure collector check expects old `legalLink(... RDConfig.Web...)` markers; current legal links now open the in-app legal sheet and should be reconciled in the collector separately.
- `FAIL`: App Store screenshot local set collector check still probes the old `AppStoreScreenshots/public/screenshots/apple/iphone/tr` path; final approved candidate path is already tracked separately.
- `PASS`: App Store screenshot task is closed per user confirmation.
- `HOLD`: China mainland is currently available in ASC while the app discloses AI-assisted analysis; exclude China mainland for first release or record a China-specific compliance decision.
- `PASS`: Supabase leaked-password item is not being treated as an App Review blocker for this release decision.
- `SKIP`: Supabase remote production secret enumeration is intentionally skipped by release decision. Source gating passes and this is no longer counted as an App Review preflight blocker.
- `HOLD`: Manual evidence form still contains TODO/placeholders until final device and ASC checks are recorded.
- `PASS`: Physical-device smoke is treated as complete per user confirmation, including onboarding TL display, auth, sandbox purchase/restore, and fresh analysis/report generation.
- `HOLD`: Review Notes draft still contains ASC-only placeholders for the mailbox password and physical-device demo video URL.
- `WARN`: Supabase advisors still report accepted leaked-password risk plus `profiles` permissive-policy performance cleanup; these are not App Review blockers for this submission path.
- `PASS`: All locally configured Supabase Edge Functions are deployed, ACTIVE, and match local `verify_jwt` settings; `register-report` was deployed at 2026-06-02 00:55 +03.
- `PASS`: Supabase local and public Auth baselines are restored and verified: Email/Apple/Google enabled, phone disabled, email autoconfirm disabled.
- `PASS`: Physical-device readiness evidence is recorded: candidate `1.0 (31)` installed on `iPhone Kerem`, display evidence is `1320 x 2868`, and the 2026-06-02 04:30 refresh confirms lock-state/app-info/details through CoreDevice with the tunnel connected; foreground launch still needs an unlocked, awake, interactive iPhone.
- `PASS`: Release local-evidence hygiene is guarded: raw physical-device smoke output is ignored and forbidden by the staging guard.
- `PASS`: Submission-day runbook coverage is guarded: final build, ASC contact/privacy/subscription gates, Turkey pricing, China availability decision, Supabase leaked-password gate, physical smoke, final validation, and release staging are all present.
- `PASS`: AI-assisted analysis disclosure is now a dedicated collector gate across Review Notes, bundled Terms, Privacy Policy, and KVKK text.
- `PASS`: Subscription paywall disclosure is now a dedicated collector gate across onboarding/in-app paywalls and AppState purchase/restore sync markers.
- `PASS`: Release simulation source gating is now a dedicated collector gate: iOS simulation helpers are DEBUG-only, Edge Function AI simulation requires explicit env flags, and the production runbook documents remote secret cleanup.
- `PASS`: Review Notes helper coverage is guarded: all copy/paste helper notes now include the China mainland availability decision reminder.
- `PASS`: App Store screenshot count/dimensions now pass through the final iPhone TR 6.9 upload candidate folder.
- `PASS`: Release staging guard and dirty worktree guard report no forbidden staged/dirty files; only expected marketing/tooling warnings remain.

Latest simulator smoke:

- 2026-06-02 00:23 +03: XcodeBuildMCP `build_sim` passed on `iPhone 17 Pro` / iOS 26.5 with 0 warnings/errors.
- 2026-06-02 00:25 +03: targeted paywall UI tests passed, `2 passed`, `0 failed`.
- Tests: `testInAppPaywallClaudePlusAndProRenderWithFreeTier`, `testPaywallYearlyMonthlyToggleForPlusAndPro`.
- Latest xcresult: `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-06-01T21-24-28-824Z_pid65279_2d78585a.xcresult`

Latest ASC read-only check:

- 2026-06-02 02:08 +03: `asc review status --app 6769498181 --output markdown` still reports `NOT_SUBMITTED`, `PREPARE_FOR_SUBMISSION`, and `reviewDetail = not configured`.
- 2026-06-02 02:08 +03: `asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown` reports only the intentionally missing App Review contact fields as blocking errors, plus subscription readiness/promotional-image warnings and `privacy.publish_state.unverified` info.
- 2026-06-02 02:08 +03: `asc validate subscriptions --app 6769498181 --output markdown` reports 4 subscriptions, 0 errors, 8 warnings, 0 blocking.
- 2026-06-02 00:26 +03: `asc subscriptions pricing summary --app 6769498181 --territory Turkey --output markdown` confirms Plus monthly `199.99 TRY`, Plus yearly `1999.99 TRY`, Pro monthly `499.99 TRY`, Pro yearly `4999.99 TRY`.
- 2026-06-02 02:16 +03: `asc pricing availability territory-availabilities --availability 6769498181 --paginate --output json` shows `CHN available=true` and `availableInNewTerritories=true`; this is now tracked as an explicit HOLD in the collector for the AI-assisted app.

Latest Supabase read-only check:

- 2026-06-02 00:55 +03: `supabase functions deploy register-report --project-ref ppcrzemgiztzcgddbins` deployed the previously local-only report metadata function.
- 2026-06-02 02:08 +03: `supabase projects list` verified the CLI is linked to project `riskdetected` / `ppcrzemgiztzcgddbins` without requiring an additional password prompt.
- 2026-06-02 02:08 +03: `supabase functions list --project-ref ppcrzemgiztzcgddbins` verified all 15 remote functions are `ACTIVE`, including `register-report`.
- 2026-06-02 02:08 +03: `supabase db lint --linked --level warning --fail-on none` connected to the remote database and returned `No schema errors found`.
- 2026-06-02 04:50 +03: latest full collector re-ran `supabase functions list --project-ref ppcrzemgiztzcgddbins --output json`; all 15 locally configured functions are remote `ACTIVE`; `register-report` is `verify_jwt=true`.
- 2026-06-02 04:50 +03: latest full collector re-ran public Auth settings; Email/Apple/Google are enabled, phone is disabled, signup is enabled, and `mailer_autoconfirm=false`.
- 2026-06-02 04:50 +03: latest full collector re-ran `supabase db lint --linked --level warning --fail-on none`; result remains `No schema errors found`.
- 2026-06-02 11:30 +03: latest live advisor re-check shows the current known set: `auth_leaked_password_protection: 1`, `multiple_permissive_policies: 2`. The earlier RLS init-plan performance warning is no longer present in the current advisor summary.
- 2026-06-02 04:50 +03: latest full collector skips remote Supabase secret enumeration by release decision. Source gating still verifies iOS simulation helpers are DEBUG-only and Edge Function AI simulation requires explicit env flags.
- 2026-06-02 11:30 +03: leaked-password automation investigation is recorded in `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md`. A broad Auth config drift was restored and verified; leaked-password protection is accepted as known risk for this submission and remains optional post-release hardening. DB query retries should not continue without the correct DB credential/env after a temporary pooler auth failure.

## Submission Blockers

| Priority | Item | Owner | Current state | Done when |
| --- | --- | --- | --- | --- |
| P0 | App Review contact fields | Manual | Not filled by request. | ASC validation no longer reports `review_details.missing_field`; do not record private values in repo. |
| P0 | App Privacy publish | Manual | ASC App Privacy is configured, but `Publish` remained visible in the UI. | App Privacy page is published and final validation is rerun. |
| P0 | ASC review notes placeholders | Manual | Copy-ready notes draft exists at `QA/APP_STORE_REVIEW_NOTES_2026-06-02.md`; placeholders are not safe to fill in repo. | ASC Notes contain the reviewer mailbox password and physical-device demo video URL; placeholders are gone in ASC. |
| P0 | ASC Review Notes RevenueCat/ATT clarification | Manual | Add this note to the final App Store Connect Review Notes before submission: "RevenueCat is used only for App Store subscription entitlement management. The app does not request App Tracking Transparency permission, does not access IDFA, does not link AdSupport.framework, and does not use RevenueCat attribution APIs." | Final ASC Notes include the RevenueCat/ATT clarification, matching the no-tracking privacy posture. |
| P1 | China mainland availability decision | Manual | ASC currently shows `CHN available=true` and `availableInNewTerritories=true`; app metadata/legal docs disclose AI-assisted analysis and Google/Groq providers. | Exclude China mainland for the first release, or record a China-specific compliance decision before submission. |
| P1 | Final ASC validation | Codex | Current validation is expected HOLD because contact fields are blank. | After P0 ASC/manual items, `asc validate`, `asc validate subscriptions`, and `asc review status` match runbook pass conditions. |

## Physical-Device Smoke Order

Run on `iPhone Kerem` / iPhone 17 Pro Max with candidate `1.0 (31)` installed.

| Order | Check | Notes |
| --- | --- | --- |
| 1 | Decide test account state | Current mirrored account is already Pro. Purchase-sheet and non-entitled checks need a free/non-entitled sandbox user or a reset path. |
| 2 | Unlock and prepare `iPhone Kerem` | 2026-06-02 `devicectl` refresh confirms candidate `1.0 (31)` installed and display `1320 x 2868`; the 04:30 lock-state/app-info/details refresh reports iOS `26.5`, booted, developer mode enabled, and tunnel connected. Foreground launch still failed with CoreDevice `4000` immediate disconnect, so unlock the physical iPhone and keep it awake/interactive before functional smoke. |
| 3 | Onboarding Plus monthly/yearly TL prices | Verify `₺199,99` and `₺1.999,99`; confirm no USD/fallback copy. |
| 4 | Email OTP login | Use reviewer mailbox; record delivery success only, never OTP code or password. |
| 5 | Apple login | Confirm sign-in succeeds or fails with a reviewer-acceptable explanation. |
| 6 | Google login | Confirm sign-in succeeds or fails with a reviewer-acceptable explanation. |
| 7 | Sandbox purchase sheet | Must be tested with a non-entitled sandbox user; current Pro state is not enough evidence. |
| 8 | Successful sandbox purchase entitlement | Confirm app plan updates and backend sync evidence exists without writing private identifiers. |
| 9 | Restore purchases | Confirm restore works for the purchased sandbox account. |
| 10 | One Free analysis | Run one fresh free analysis if account state allows it. |
| 11 | Fresh PDF/Excel generation | Existing report previews passed; fresh generation is still separate evidence. |

## Final Submit Sequence

1. Publish App Privacy in ASC UI.
2. Fill App Review contact fields in ASC only.
3. Paste final ASC Notes from `QA/APP_STORE_REVIEW_NOTES_2026-06-02.md` in ASC only, including reviewer mailbox password, demo video URL, and the RevenueCat/ATT clarification.
4. Re-run `node scripts/app_review_preflight_collect.mjs`.
5. Re-run final ASC checks:
   - `asc review status --app 6769498181 --output markdown`
   - `asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown`
   - `asc validate subscriptions --app 6769498181 --output markdown`
6. Confirm all four subscriptions remain attached on the iOS App Version page.
7. Only then tap `Add for Review`.
