# Global Localization Build Flag Runbook

## Current safety state

- The current production app remains on its existing binary.
- `RD_GLOBAL_LOCALIZATION_WAVE1` is not present in the app target's Release
  compilation conditions, so a Release build uses the Turkish legacy path.
- English UI lookup, safety-profile selection, localization preference writes,
  localization request fields and pending English onboarding sync all fail
  closed while the build condition is absent.
- DEBUG UI tests may opt in only with
  `RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED`.
- The production backend remains authoritative. Missing/off global and
  per-profile rollout flags reject international profiles.
- Notification rules and queued observations remain `shadow`; this build flag
  does not activate notification delivery.

## Activation order

1. Complete every Phase 5 external gate and obtain the explicit release
   approval.
2. Bump the iOS build number. Never add the condition to an already-live build.
3. Add `RD_GLOBAL_LOCALIZATION_WAVE1` to the app target's Release
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for the approved candidate.
4. Keep backend localization flags off, then allowlist only the candidate build
   for internal/TestFlight rollout.
5. Run Turkish regression first, then the profile rollout sequence from the
   execution plan.
6. The Release build script must pass
   `verify_phase5_external_gates.mjs --mode=release --live`.
7. After App Review and the owner's explicit production approval, activate only
   the approved build/profile allowlists and verify them read-after-write.

## Rollback

- Remove the candidate build from every backend allowlist or engage the relevant
  backend kill switch.
- Do not edit an applied migration or alter the current live binary.
- A later binary can remove `RD_GLOBAL_LOCALIZATION_WAVE1`; the current
  production build is unaffected by repository-only work.
