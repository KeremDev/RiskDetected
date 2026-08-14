# Phase 6 Completion Audit

## Decision

Phase 6 implementation and QA exit criteria are complete. Release candidate
`1.3.0 (78)` is `VALID` in App Store Connect. Production rollout remains
deliberately off; current users on `1.2.4 (77)` keep the legacy Turkish path.

## Exact-hash approval

- Safety-profile source:
  `3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932`
- Internal review ID: `RD-SPR-20260801-3A68229B`
- Decisions: language `approved`, safety `approved`, product `approved`
- PII-free record:
  `docs/localization/phase-6/SAFETY_PROFILE_APPROVAL_2026-08-01.json`
- Record SHA-256:
  `64b4a4ffb9ac852926448cb89c51188efcd5d846c236a510d8f35bb71aed5b5d`
- Production Edge Function: `analyze` version `140`, `ACTIVE`
- Remote bundle read-back: source hash, internal review ID and 3/3 approval
  hashes present

Changing any safety-profile source changes the manifest source hash and closes
the runtime gate again.

## Automated gates

- Localization profile contract: 17/17
- Localization catalog/JUR gates: 19/19
- AI localization: 63/63
- Phase 6 Deno: 73/73
- Phase 6 pgTAP: 39/39
- TestFlight rollout evaluator: 4/4
- Full iOS UI regression: 45 executed, one intentional real-provider/cost
  skip, zero failures
- Phase 5 live release gate: passed

## UI matrix

The six safety profiles cover Turkish/English, light/dark,
default/accessibility text and Free/Plus/Pro pairwise scenarios. Fresh
onboarding and existing-user main-app fixtures are both covered.

The focused release matrix was repeated on:

- iPhone 13, 6.1-inch: six-profile pairwise passed; English onboarding passed;
  English accessibility-XXXL passed.
- iPhone 14 Pro Max, 6.7-inch: all three focused tests passed in one run.

Online health/pinning, offline price fallback and retry UI are covered.
Provider retry, language repair, queue retry and ambiguous-dispatch behavior
are covered by Deno and pgTAP layers. P0 onboarding, profile, analysis, result,
report, paywall and legal flows are green.

## TestFlight control

The numeric, fail-closed nine-stage contract is:

`docs/localization/phase-6/TESTFLIGHT_ROLLOUT_THRESHOLDS_2026-08-01.json`

It checks analysis failure, wrong-language, repair, report failure, notification
template miss, crash, queue retry and ambiguous dispatch. Missing samples
produce `hold`; threshold breaches produce `blocked`; only complete bounded
aggregate evidence can produce `passed`.

Candidate build 78 currently has one invitation and zero installs, sessions,
crashes or feedback. Per owner instruction, all TestFlight/production rollout
flags remain off until Apple approves the App Store version. The stage engine
and thresholds are ready, but no public or reviewer activation was performed.

## Production isolation

After deploying `analyze` v140, a read-only production query verified:

- 13/13 localization flags present
- all rollout modes `off`
- enabled user hashes: 0
- enabled iOS builds: 0
- no localization kill switch enabled
- production behavior changed: false

No App Store version, review submission or final release was created in
Phase 6.
