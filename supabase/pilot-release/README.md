# LIVE P05 pilot — separate deployment ledger

Production `ppcrzemgiztzcgddbins` received two reviewed pilot migrations:
`20260913201043_isg_p05_scoped_pilot_bundle` and
`20260913205739_isg_p05_company_profile_overview`.

The second migration adds only private company profiles and checked V2 create/overview RPCs. Its byte-identical remote-ledger mirror has SHA256 `2be9935e04d8982dcbf9750d3dbbb79c77d277810bb14ab478df3ca6ecdfe37f`. The predeployment source under `candidates/20260913203710_...sql` is retained for reproducible tests; **do not apply it again**. Existing companies/personnel/grants/account flags and legacy quota helpers were unchanged. See `docs/isg/P05_UI_REVIEW_BUILD_92_2026-09-13.md` for 1115 synthetic/31 baseline-upgrade checks and device build 92.

`supabase/migrations/20260913201043_isg_p05_scoped_pilot_bundle.sql` in **this directory** is the byte-identical migration SQL stored in the remote ledger. SHA256: `ec13ed26fbc180e44a8b59c39488b80592b45280d6771830361059d8166d9a3d`.

This nested directory is an audit mirror, **not a project to push**. It intentionally has no live project link/config. The migration was generated via CLI, then its filename was aligned with the verified version assigned by the migration service.

Do not run a general `supabase db push` from the repository root. The main `supabase/migrations` directory still contains six original P05 candidate migrations plus undeployed P06+ candidates. Applying those six again would duplicate the deployed schema; the original first candidate also includes a global company backfill that this reviewed pilot release excludes. Never mark unexecuted candidate SQL as applied to hide this mismatch. Before the next production DDL release, explicitly reconcile the pilot baseline into the release migration chain and rehearse from this deployed state.

Generation: `scripts/isg/p05_pilot_release.mjs` pins the reviewed bundle hash, lowers deployment lock timeout to 1s, checks the old migration head and legacy helper hash, asserts 18 RLS tables/empty roster/no company backfill/no new global hook, and delegates the outer transaction to the migration service. The remote ledger SQL hash was checked against this file after deployment.

Activation is separate operational DML, not a migration seed. It enabled only the user-approved account for seven days. No real user UUID/email is embedded in this directory. The `disable_pilot.sql` file is a **manual emergency rollback** that closes access and retains all records; it was prepared but not executed. A database restore, schema drop, or deletion of pilot companies is not authorized by this runbook.

Details: `docs/isg/P05_LIVE_ACTIVATION_2026-09-13.md` at the repository root.
