# TestFlight Nine-Stage Execution Runbook

Date: 2026-08-01  
Candidate: RiskDetected `1.3.0 (78)`  
ASC build ID: `6710ace3-c967-43fc-9186-b005b1a4a83c`  
Supabase project: `ppcrzemgiztzcgddbins`

## Purpose and safety boundary

This runbook executes the mandatory Phase 6 validation sequence without
changing Turkish App Store metadata, screenshots or subscription copy. The
evidence collector is read-only against Supabase. Stage 1 retains its historical
App Store Connect baseline; stages 2–9 neither collect nor gate on delayed App
Store Connect usage metrics. They require digest-bound physical-device or
simulator evidence under the owner-authorized accelerated policy. The collector
never changes a feature flag, tester group, build assignment, App Review
submission or release state.

Build `77` remains the live production build. Any temporary allowlist
transition for stages 2–9 is a separate production mutation and requires the
project owner's explicit authorization before execution. Public rollout,
`rollout_mode=on`, `build_allowlist` and `min_build` are outside this runbook.

No evidence file may contain an email address, user ID, user hash, prompt,
photo, user-authored text, token or notification body. The collector exports
only counts, bounded flag state and SHA-256 digests.

## Collector contract

Thresholds:

`docs/localization/phase-6/TESTFLIGHT_ROLLOUT_THRESHOLDS_2026-08-01.json`

Collector:

`scripts/localization_testflight_rollout.mjs`

Evidence directory:

`docs/localization/phase-6/testflight-rollout`

For every stage the collector:

1. captures the start time and aggregate state of all 13 localization flags;
   Stage 1 also retains its historical TestFlight metric baseline;
2. reads only build-78 analyses, reports, linked notification events and queue
   state created inside the bounded stage window;
3. for stages 2–9, verifies a SHA-256-bound physical-device or simulator
   evidence file and uses its launch/crash counts; App Store Connect usage is
   not a gate input;
4. requires an attested aggregate report request/failure count and verifies
   the claimed successes against `public.reports`;
5. blocks on pending analyses, null localization telemetry, flag drift,
   personal-data keys, counter inconsistencies, threshold violations or an
   out-of-order stage; stage 1 alone permits the expected legacy
   `not_evaluated` language status while all localization flags are off,
   whereas stages 2–9 require evaluated language telemetry;
6. writes a snapshot and gate result whose SHA-256 link is checked by the
   sequence verifier.

Report request/failure counts are entered manually because unsuccessful report
function calls do not create a durable database row. This avoids deploying new
telemetry to the live system. Never include a tester name or report content in
the counter.

## Stage order and minimum operator actions

The stages cannot be skipped or run in parallel. Finish and pass one stage
before beginning the next.

| Stage | Contract | Runtime cohort before `begin` | Minimum stage actions |
|---:|---|---|---|
| 1 | Internal Turkish regression, flags off | All 13 flags `off`, zero hashes/builds | Historical Stage 1 evidence and bounded owner exception |
| 2 | Turkish contract dogfood | Authorized reviewer allowlist; English safety profiles not selected | Existing 3 Turkish analyses, report, notifications and queue evidence plus 3 physical cold launches |
| 3 | English International | Authorized reviewer allowlist | International profile in the focused simulator matrix |
| 4 | English UK | Authorized reviewer allowlist | UK profile in the focused simulator matrix |
| 5 | English US | Authorized reviewer allowlist | US profile in the focused simulator matrix |
| 6 | English AU | Authorized reviewer allowlist | AU profile in the focused simulator matrix |
| 7 | English CA | Authorized reviewer allowlist | CA profile in the focused simulator matrix |
| 8 | Full internal matrix | Authorized reviewer allowlist | All six profiles, report, onboarding, jurisdiction, accessibility, pseudo-localization and backend contracts |
| 9 | Review-candidate path | Authorized reviewer allowlist | Digest-bound simulator review-path evidence; no Apple submission |

Stage 2's existing analyses must reach a terminal state and retain complete
language telemetry. Stages 3–9 intentionally do not repeat production AI,
report or notification operations. Their profile and output contracts are
covered once by the focused simulator suite and the Node/Deno/pgTAP backend
suite. A missing, mismatched, non-aggregate or failed evidence file blocks the
stage. Delayed App Store Connect installs/sessions/crashes cannot place stages
2–9 on hold.

## Current execution status — complete on 2026-08-01

- Stage 1 passed with its owner-authorized, digest-bound exception for delayed
  App Store Connect session telemetry. The exception applies only to Stage 1
  and does not change its recorded session count from zero.
- The owner then authorized the accelerated device/simulator policy for stages
  2–9: App Store Connect usage metrics are neither collected nor used as gate
  inputs, repeated production AI operations are not required, strict stage
  order and all zero-tolerance checks remain in force.
- The reviewer-only allowlist is active for exactly one authorized account
  across all 13 localization flags. No build or public cohort is enabled.
- Stage 2 passed with runtime configuration SHA-256
  `81330963d87f110aa32f440cc358dd925f51bfee5edf787922204d4543fda8cb`.
- Three Build 78 Turkish analyses completed on a physical device using only
  the two approved canary photos. The bounded window also contains one
  successful report, four linked notification attempts, three queue jobs,
  zero failures, zero language repairs, zero retries, zero ambiguous
  dispatches and zero crashes.
- Pipeline v2 language-validation aggregates were repaired from their
  authoritative `_input_audit` values by
  `supabase/migrations/20260801191332_sync_pipeline_v2_language_validation_telemetry.sql`.
  All three Stage 2 analyses now report `passed` in one validation attempt.
  The original blocked observation is preserved by
  `testflight-rollout/stage-02-attempt-01-archive.json`.
- Three physical cold launches completed without a crash. Stage 2 passed
  without using the delayed App Store Connect session counter.
- One focused simulator run passed 6/6 tests and covers all six safety
  profiles, English report-language isolation, onboarding, jurisdiction
  isolation, accessibility and pseudo-localization. The backend contract suite
  passed Node 35/35, Deno 73/73 and pgTAP 45/45.
- Stages 3–9 then passed sequentially using the digest-bound simulator package.
  Every stage kept the same runtime configuration SHA-256, and no new
  production analysis/report/notification operation was generated.
- A final bounded physical-device test then completed one real English
  International analysis and its two-page standard report. Backend read-back
  reports one exact `en` / `en-001` / `INTL` analysis, one language-validation
  attempt, zero repairs, one exact report, two exact-locale notification
  attempts and zero template misses. The temporary physical-tester hash was
  removed immediately afterwards, restoring one Apple reviewer hash on all 13
  flags.
- `testflight-rollout/TESTFLIGHT_ROLLOUT_MANIFEST.json` reports `status=passed`,
  `completed_stages=9`, `required_stages=9`, `issues=[]`.
- No Beta App Review, App Review or release submission was performed.

## Commands

Confirm current aggregate state:

```sh
make localization-testflight-status
```

Begin the next required stage:

```sh
node scripts/localization_testflight_rollout.mjs begin --stage=1
```

After the required device or simulator validation, finish it. The following
Stage 2 example represents one report request, zero failures and the approved
physical-device evidence:

```sh
node scripts/localization_testflight_rollout.mjs finish \
  --stage=2 \
  --report-requests=1 \
  --report-failures=0 \
  --attest-report-counters \
  --validation-evidence=docs/localization/phase-6/testflight-rollout/stage-02-device-validation.json
```

The attestation means only: “the two supplied values are complete aggregate
counts for this stage window.” It does not approve a rollout mutation.

Verify the whole chain:

```sh
node scripts/localization_testflight_rollout.mjs verify
```

External TestFlight preparation remains a separate, optional and guarded Apple
submission:

```sh
node scripts/testflight_external_stage9.mjs status
```

It is not part of the accelerated local validation result and was not invoked.
Do not run its mutating command without a new explicit owner authorization.

```sh
node scripts/testflight_external_stage9.mjs prepare \
  --confirm=submit-beta-review-candidate
```

This submits only the TestFlight beta candidate. It cannot submit the App Store
version and cannot release the app. The current read-only evidence is
`docs/localization/phase-6/TESTFLIGHT_STAGE9_EXTERNAL_READINESS_2026-08-01.json`.

Exit codes:

- `0`: passed;
- `3`: hold because required samples are incomplete;
- `2`: blocked by integrity or threshold failure.

## Stop conditions

Stop the stage immediately and do not expand the cohort if any of these occur:

- wrong-language output;
- a physical-device or simulator crash;
- unresolved ambiguous queue dispatch;
- missing exact-locale notification template;
- missing language/locale telemetry;
- localization flag state changes between stage start and finish;
- a threshold breach or counter mismatch.

Keep the affected stage evidence. Do not overwrite it to manufacture a pass.
Investigate, remediate and create a new explicitly versioned observation only
after the failure is understood.

## Completion condition

Phase 6 validation is complete because
`TESTFLIGHT_ROLLOUT_MANIFEST.json` reports:

- `status = passed`;
- `completed_stages = 9`;
- `required_stages = 9`;
- `issues = []`.

This completion does not submit App Review and does not enable public
localization rollout.
