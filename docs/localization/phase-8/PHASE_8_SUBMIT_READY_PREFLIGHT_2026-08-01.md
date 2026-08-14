# Phase 8 Submit-Ready Preflight

Date: 2026-08-01  
App: RiskDetected  
Candidate: iOS 1.3.0 (78)  
Current live release: iOS 1.2.4 (77)

## Decision

The implementation, production isolation, security remediation, English legal
site, App Store Connect metadata, subscriptions, screenshots, review details,
and automated test package are complete.

App Store Connect reports zero submission blockers. Version 1.3.0 is
`PREPARE_FOR_SUBMISSION`, build 78 is attached, release type is `MANUAL`, and
the review state is `NOT_SUBMITTED`. No review submission or release was
performed.

The completion audit now classifies the candidate as functionally
submit-ready. The reviewer-only localization allowlist is active for exactly
one authorized account across all 13 flags, while every build and public cohort
remains disabled. Build 77 and all current non-reviewer users remain outside
the localization cohort.

The owner authorized an accelerated device/simulator policy for stages 2–9:
delayed App Store Connect usage metrics are neither collected nor used as gate
inputs, and repeated production AI/report/notification operations are not
required. Strict stage order, runtime flag-drift protection and every
zero-tolerance language/crash/ambiguous-dispatch rule remain enforced.

Stage 2 passed using the existing three Turkish Build 78 analyses, one report,
four linked notification attempts, three queue jobs and three physical cold
launches. There were no failures, wrong-language outcomes, repairs, retries,
ambiguous dispatches or crashes. A Pipeline v2 aggregate-telemetry persistence
gap was repaired from the analyses' authoritative AI audit records; all three
language validations report `passed` in one attempt.

One focused simulator run then passed 6/6 tests and covered all six safety
profiles, English report isolation, onboarding, jurisdiction isolation,
accessibility and pseudo-localization. The backend contract suite passed Node
35/35, Deno 73/73 and pgTAP 45/45. Stages 3–9 passed sequentially from this
digest-bound evidence. The final manifest reports `9/9`, `status=passed` and
`issues=[]`.

The physical English International path was then run once with a real
electrical-installation photo. The analysis completed with two findings,
language validation passed in one attempt with no repair, a two-page English
standard PDF opened successfully, and two exact-locale notification attempts
had zero template misses. The temporary physical-tester hash was removed after
the test, restoring exactly one Apple reviewer hash across all 13 flags.

No Beta App Review, App Review or release submission was performed. App Privacy
publish state was independently read back from an authenticated App Store
Connect browser session: the page reports
`Published 2 months ago by Kerem Kayalar`, and no pending publish control is
visible.

The authoritative requirement-by-requirement result is
`docs/localization/phase-8/WAVE1_COMPLETION_MATRIX_2026-08-01.json`.

## Turkish protection

- Protected App Store locale: `tr`.
- Mutable App Store locales: `en-GB`, `en-US`, `en-AU`, `en-CA`.
- `appstore/versions/1.3.0/tr.json` was not edited or uploaded.
- Protected local draft SHA-256:
  `e49f652e9ed8c15552a2764d04f0834a133bedc5e77899c91441aa7c2eb9dd22`.
- No final Turkish screenshot directory exists.
- App Store automation refuses protected locales before making a mutation.
- Server read-back reports `protected_locale_mutations_detected: false`.
- Apple created draft copies of the already approved Turkish subscription
  localizations when English subscription locales were added. The approved
  Turkish resources remain present, and the copied Turkish name/description
  values are byte-for-byte identical. Only Apple-managed resource IDs and
  workflow state differ.
- The Turkish candidate `what's new` field remains empty. Apple reports this as
  a non-blocking warning; it was not changed because the owner explicitly
  protected all Turkish metadata.

## App Store Connect

- App ID: `6769498181`.
- Candidate version ID: `9a2f5061-8992-4957-a9e8-7b8a96747323`.
- Candidate build ID: `6710ace3-c967-43fc-9186-b005b1a4a83c`.
- Candidate state: `PREPARE_FOR_SUBMISSION`.
- Review state: `NOT_SUBMITTED`.
- Review details: configured.
- Release type: `MANUAL`.
- Guarded apply operations: 35.
- Independent server read-back: 102/102 checks passed.
- Screenshots: 20 total; five 1290×2796 light-theme screenshots for each
  mutable English locale.
- Screenshot checksum read-back matches every approved local file.
- Apple validation: 0 errors, 0 blocking checks, 5 warnings.
- TestFlight validation: 0 errors, 0 blocking checks, 0 warnings.
- Beta App Review contact, demo-account and review-note fields are configured.
- No external TestFlight review submission was created.
- The nine-stage validation manifest passed 9/9. Stages 2–9 used digest-bound
  physical-device/simulator evidence and did not collect or gate on delayed
  App Store Connect usage metrics.
- Physical readiness passed: RiskDetected 1.3.0 (78) was found and launched on
  a connected iPhone without recording device or account identifiers.
- Four warnings are optional subscription promotional images; these are not
  required for App Review unless App Store subscription promotion, offer-code
  redemption pages, or win-back promotion is planned.
- The remaining warning is the protected Turkish `what's new` field.
- App Privacy is published. Authenticated browser read-back reports
  `Published 2 months ago by Kerem Kayalar`; no pending publish control is
  visible. No privacy field or Turkish metadata was changed.

Evidence:

- `docs/localization/phase-8/ASC_CLI_READINESS_SNAPSHOT_2026-08-01.json`
- `docs/localization/phase-6/TESTFLIGHT_NINE_STAGE_EXECUTION_RUNBOOK_2026-08-01.md`
- `docs/localization/phase-6/ACCELERATED_DEVICE_SIMULATOR_VALIDATION_POLICY_2026-08-01.json`
- `docs/localization/phase-6/SIMULATOR_VALIDATION_RUN_2026-08-01.json`
- `docs/localization/phase-6/PHYSICAL_ENGLISH_INTERNATIONAL_ANALYSIS_REPORT_2026-08-01.json`
- `docs/localization/phase-6/testflight-rollout/TESTFLIGHT_ROLLOUT_MANIFEST.json`
- `docs/localization/phase-6/TESTFLIGHT_STAGE9_EXTERNAL_READINESS_2026-08-01.json`
- `docs/localization/phase-8/PHYSICAL_BUILD_78_SMOKE_READINESS_2026-08-01.json`
- `docs/localization/phase-8/REVIEWER_COHORT_PREFLIGHT_2026-08-01.json`
- `.asc/evidence/app-privacy-browser-readback-2026-08-01.json`
- `.asc/evidence/app-privacy-published-2026-08-01.jpg`
- `.asc/evidence/apply-1.3.0-result.json`
- `.asc/evidence/verify-1.3.0-result.json`
- `.asc/evidence/protected-locales-before.json`
- `appstore/screenshots/qa/manifest.json`
- `appstore/screenshots/qa/contact-sheet.png`
- `appstore/review/app-review-notes.md`
- `appstore/review/localization-evidence.md`

## English legal and support website

Production deployment:

- Deployment ID: `dpl_Dc2dkQHj2aG7tTPduMUp6N9pdsBj`.
- Production alias: `https://riskdetected.com`.
- `/en`: HTTP 200 and rendered English product page.
- `/en/privacy`: HTTP 200 and approved English Privacy Policy.
- `/en/terms`: HTTP 200 and approved English Terms of Use.
- `/en/ai-notice`: HTTP 200 and approved AI and Data Processing Notice.
- `/en/support`: HTTP 200 and English support/account-deletion guidance.
- Desktop and 390×844 mobile browser QA passed.
- Console QA passed without errors or warnings.
- Nested-route asset loading was corrected by using root-relative Vite assets.
- Turkish route component files were not edited as part of the English route
  work.

## Automated verification

- Localization profile contract: 17/17.
- Localization catalog and jurisdiction gates: 19/19.
- AI localization suite: 63/63.
- Phase 5 implementation gates: 12/12.
- Phase 5 evidence harness: 5/5.
- Phase 5 live release gate: passed.
- Phase 6 rollout collector/gate unit tests: 22/22.
- Physical Build 78 readiness collector: 5/5.
- Phase 6 Deno suite: 73/73.
- Phase 6 pgTAP: 45/45.
- Focused accelerated simulator suite: 6/6.
- Physical English International analysis/report: passed.
- Full post-security local pgTAP: 342/342.
- Xcode simulator build/install/launch: succeeded with no diagnostics.
- Full iOS UI regression: 45 executed, 44 passed, 1 intentional opt-in
  real-provider test skipped, 0 failures.
- Xcode result bundle:
  `/Users/keremkayalar/Library/Developer/XcodeBuildMCP/workspaces/RiskDetected-c2163d1a8d63/result-bundles/test_sim_2026-08-01T15-08-03-063Z_pid4783_b6c533a1.xcresult`.
- Repository whitespace validation: passed.

During final testing, the deterministic inventory was refreshed and one Swift
fallback was corrected to match the existing Turkish catalog value
(`Aktif Test Firması`). This is an internal fallback consistency repair; it is
not App Store metadata, a screenshot, or an uploaded Turkish localization.

## Security and production state

- Codex security scan:
  `c3474e6e-4a78-4d39-be9f-af6d20df9e3c`.
- Findings remediated: 6/6; no high or critical findings.
- Production Supabase project: `ppcrzemgiztzcgddbins`.
- Production Edge Functions are active at the remediated versions documented
  in `docs/security/CODEX_SECURITY_REMEDIATION_2026-08-01.md`.
- Localization production isolation read-back:
  - 13/13 flags present.
  - 13/13 rollout modes `allowlist`.
  - enabled user hashes: exactly one authorized reviewer hash per flag.
  - enabled iOS builds: 0.
  - localization kill switches enabled: 0.
- Public localization rollout remains false; Build 77 and all non-reviewer
  users remain outside the cohort.
- Build 77 remains the live release.
- Build 78 is attached only to candidate 1.3.0.
- No rollout, App Review submission, or App Store release occurred.

## Submission gates

### 1. Reviewer runtime access — completed

All required localization gates are active only for the App Review demo
account through `rollout_mode=allowlist`. Build 77, every build-wide cohort and
every other user remain outside the localization rollout. Public/post-approval
rollout remains a separate owner-controlled action.

Prepared and locally verified enable/verify/rollback operations:

- `docs/localization/phase-8/REVIEWER_COHORT_ACTIVATION_RUNBOOK_2026-08-01.md`
- `supabase/operations/enable_global_localization_reviewer_cohort.sql`
- `supabase/operations/disable_global_localization_reviewer_cohort.sql`

### 2. Nine-stage validation — completed

Stages 1–9 passed in strict order. Stage 2 used the completed physical-device
work; stages 3–9 used the owner-approved digest-bound simulator package.
`TESTFLIGHT_ROLLOUT_MANIFEST.json` reports `status=passed`,
`completed_stages=9`, `required_stages=9` and `issues=[]`.

### 3. Physical English review path — completed

Build 78 installation and cold launches passed on a physical iPhone. One real
electrical-installation photo was analysed using English UI, International
safety terminology, Manufacturing / Factory scope and General focus. The
result contained two English findings, the highest Fine–Kinney score was 1800,
the second was 42, and the two-page English standard report opened
successfully. Backend read-back reports one completed exact `en` / `en-001` /
`INTL` analysis, one language-validation attempt, zero repairs, one exact
English International report, two exact-locale notification attempts and zero
template misses.

The physical account was added only temporarily to the allowlist for this
bounded test. It was removed immediately afterwards. Production is restored to
13/13 `allowlist` flags, one Apple reviewer hash per flag, zero enabled builds,
zero kill switches and no public rollout.

### 4. App Privacy read-back — completed

An authenticated App Store Connect browser session was inspected read-only.
The page reports `Published 2 months ago by Kerem Kayalar`, and the visible
header contains no pending publish control. No privacy field or Turkish
metadata was changed.

Evidence:

- `.asc/evidence/app-privacy-browser-readback-2026-08-01.json`
- `.asc/evidence/app-privacy-published-2026-08-01.jpg`

The CLI helper `scripts/app_store_connect/privacy-readback-login.sh` remains as
a reproducible fallback for future audits.
