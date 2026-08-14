# Build 80 Final Submit Readiness

Candidate: RiskDetected `1.3.0 (80)`  
App Store version ID: `9a2f5061-8992-4957-a9e8-7b8a96747323`  
Build ID: `71cc9591-32b9-4fee-b6c4-8c4d30713b23`  
Decision: submit-ready; owner-only `Add for Review` remains.

## Current App Store Connect state

- Build 80 is `VALID`.
- Candidate version `1.3.0` is `PREPARE_FOR_SUBMISSION`.
- Build 80 is attached to the candidate version.
- Release type is `MANUAL`.
- Review state is `NOT_SUBMITTED`.
- Review details and notes are configured.
- Review submission and final release were not performed by automation.

Evidence:

- `.asc/evidence/apply-1.3.0-result.json`
- `.asc/evidence/verify-1.3.0-result.json`
- `.asc/evidence/validate-1.3.0-build80.json`
- `.asc/evidence/review-status-build80.json`
- `.asc/evidence/review-notes-build80-readback.json`

## Localization/App Store evidence

- English App Store locales `en-GB`, `en-US`, `en-AU`, and `en-CA` are
  configured.
- Each mutable English locale has five light-theme iPhone screenshots uploaded
  and read-after-write verified.
- Turkish App Store metadata, subscription copy, and screenshots remain
  protected and are not mutation targets.
- App Privacy is published per authenticated browser readback.
- China mainland availability is excluded for this AI-assisted release.

Evidence:

- `appstore/review/localization-evidence.md`
- `appstore/review/app-review-notes.md`
- `output/app-review-preflight/App_Review_Preflight_Evidence_2026-08-02-build80.md`
- `.asc/evidence/app-privacy-browser-readback-2026-08-02.json`
- `.asc/evidence/app-privacy-published-2026-08-02.png`

## Build 80 functional evidence

- Physical-device readiness confirms RiskDetected `1.3.0 (80)` is installed on
  a reachable physical iPhone.
- A real two-photo English International analysis completed with four findings.
- Build 80 multi-photo layer audit telemetry used compact schema, no schema
  fallback, and 6144 thinking budget.
- Build 80+ keeps the 12-layer multi-photo audit and 6144 budget through the
  production build gate.
- Current live Build 77 remains excluded from the Build 80+ activation gate.

Evidence:

- `docs/localization/phase-8/PHYSICAL_BUILD_80_SMOKE_READINESS_2026-08-02.json`
- analysis id `0854fa06-4ea5-462d-82e8-ad1e67e8fc2b`
- `docs/localization/phase-8/WAVE1_COMPLETION_MATRIX_2026-08-02_BUILD80.json`

## Final gates run

- `node scripts/app_store_connect/verify.mjs`
  - 102/102 checks green.
- `node scripts/app_review_preflight_collect.mjs --output output/app-review-preflight/App_Review_Preflight_Evidence_2026-08-02-build80.md --ipa-app .asc/artifacts/RiskDetected-1.3.0-80-extracted/Payload/RiskDetected.app`
  - 47 PASS, 0 HOLD, 0 FAIL, 2 WARN, 1 SKIP.
- `make localization-wave1-audit`
  - 37 requirements satisfied.
- `make localization-phase6-test`
  - Node 35/35, Deno 73/73, pgTAP 45/45.
- `make localization-test`
  - profile/catalog/AI/Phase 5 test suites passed.
- `make localization-phase5-release-gate`
  - LEGAL-EN, NOTIFICATION-COPY, and AUTH-EMAIL-HOOK passed.
- `bash scripts/localization_release_build_gate.sh`
  - passed.

## Non-blocking warnings accepted for this submission path

- RevenueCat attribution marker strings appear in the binary scan, but AdSupport
  is not imported and privacy manifests report tracking=false.
- Supabase advisors still report accepted/pre-existing warnings:
  leaked-password protection, four security-definer executable grants, and two
  permissive `profiles` policies. These are documented as non-blocking for this
  App Review path and were not introduced by Build 80 localization work.

## Owner-reserved actions

- Press `Add for Review` in App Store Connect.
- Do not release automatically; candidate release type is manual.
- After Apple approval, explicitly instruct Codex before any production rollout
  flag activation or final release operation.

The App Store version is fully prepared, uses manual release, and has not been released.
