# iOS 2.0.0 / build 87 release operations

This directory contains the production-only controls for the iOS 2.0.0
release. Android routing is intentionally outside this release.

## Before TestFlight

1. Apply
   `supabase/migrations/20260829205956_ios_build_87_v4_result_hub_release_gate.sql`
   with the linked database query command. The repository and production
   migration ledgers contain historical timestamp aliases, so do not run a
   broad `db push --include-all` for this release.
2. Deploy the compatible Edge Functions.
3. Run `verify_pre_release.sql` read-only. It must return one row whose V4 and
   result-hub checks are all true, while hard update remains false.
4. Run `route_canary_rollback.sql`. It verifies Free, Plus and Pro build-87
   routes while rolling back every canary row; iOS 86 and Android must remain
   outside the new build gate.
5. Install build 87 on a physical iPhone and complete the release matrix.

## App Store availability

`activate_after_app_store_live.sql` is deliberately not a migration. Run it
only after App Store Connect and the public App Store both show 2.0.0 build 87
as available. It enables the mandatory update for older iOS clients. It does
not alter Android policy or delete any historical data.

## Incident response

Legacy/V3 is not a build-87 fallback.

1. A V4 quality/configuration incident: deploy the code that matches the
   known-good checkpoint, then use
   `../v4_known_good_2026-08-26/restore_config.sql`.
2. A build-87 client incident: use `pause_build_87.sql`. New build-87 analyses
   fail closed and retry; they never enter V3/legacy. Prepare build 88.
3. Do not delete route snapshots, V4 runs, findings, report snapshots, or
   allowlist tables. They are audit and recovery data.

## First 24 hours

Run `monitor_first_24_hours.sql` periodically. Review V4 route share, jobs that
failed before pinning, report completion/archive outcomes, RevenueCat webhook
delivery, and Edge Function errors. The query returns aggregates only.
