# RiskDetected Codex Security Remediation — 2026-08-01

## Scope and production safety

- Source scan: `c3474e6e-4a78-4d39-be9f-af6d20df9e3c`
- Source snapshot: `740d5513c3d2500820908b52a6957647f12576a5`
- Findings: 2 medium, 4 low, 0 high, 0 critical
- Production project: `ppcrzemgiztzcgddbins`
- No user row, storage object, subscription, release, rollout flag, or Turkish
  App Store content was changed while validating the fixes.
- Global-localization rollout flags remain `off`; build 77 remains the live
  App Store build.

The source scan is sealed and retained unchanged. This document records fixes
made after that snapshot, including issues that were rejected from the final
report but were inexpensive to harden safely.

## Codex Security workbench disposition

- All six source-scan occurrences are closed as `already_fixed`.
- Open finding count: **0**.
- The sealed scan retains its historical working-tree-change notice and
  four-slot-versus-six-slot preflight warning. These are scan provenance and
  runtime-capability records, not unresolved product vulnerabilities.

## Finding remediation

| ID | Finding | Remediation | Verification | Status |
| --- | --- | --- | --- | --- |
| 1 | Authenticated users can forge server-owned analysis state | Restricted `analyses` client grants to an explicit allowlist; added a trigger that rejects changes to server-owned state; moved finding updates/deletes into the service-only `apply_finding_mutation_atomic` RPC. | 31 client-authority pgTAP assertions, atomic-mutation static test, production ACL/trigger/RPC catalog checks. | Fixed |
| 2 | Storage-backed photos bypass the analysis byte budget | Measures downloaded bytes, applies the same per-image and aggregate limits as inline input, and performs bounded base64 conversion before provider calls. | Analyze static tests and Deno checks; production `analyze` v141 is `ACTIVE`. | Fixed |
| 3 | Screenshot upload route allows persistent local disk consumption | Added same-origin and JSON-content guards plus an aggregate upload quota. Applied to both the working editor and its reusable template. | Same-origin request succeeds; cross-origin and `text/plain` requests fail; editor production build succeeds. | Fixed |
| 4 | Authenticated users can overwrite server-owned profile fields | Restricted profile writes to user-editable columns and added an insert/update authority guard that preserves subscription, quota, and delivery fields. | Client-authority pgTAP and production ACL/trigger checks. | Fixed |
| 5 | Cross-origin requests can overwrite screenshot project state | Added same-origin and JSON-content guards, bounded project-state schema validation, and same-directory atomic canonical-state replacement. Applied to working editor and template. | Valid state returns 200; malformed schema, cross-origin, and non-JSON probes return 422/403/415; project hash remains unchanged; no temporary file remains; editor production build succeeds. | Fixed |
| 6 | Photo metadata can steer privileged deletion to another object | Restricted photo grants, validates owner/analysis/path binding, preserves server retention fields, and makes the cleanup worker revalidate the exact `user/analysis/object` prefix before deletion. | Client-authority pgTAP, cleanup static test, production ACL/trigger checks. | Fixed |

## Additional hardening

- Keychain secret storage no longer places the secret in shell arguments.
- RevenueCat authorization is supplied through curl configuration on standard
  input rather than process arguments.
- Account-deletion completion uses an atomic `pending → processing` claim and
  binds completion/failure updates to the claimed support record.
- Finding update/delete concurrency now uses a single database transaction and
  reports version conflicts as HTTP 409.
- The service-only finding RPC revokes default `PUBLIC`, `anon`, and
  `authenticated` execution; only `service_role` may execute it.
- The RPC reads the request JWT context with `current_setting` instead of the
  deprecated `auth.role()` helper.

## Database and function deployment

Applied migrations:

- `20260801170000_client_field_authority_hardening.sql`
- `20260801170100_replace_deprecated_auth_role_in_finding_rpc.sql`

Active production Edge Functions:

- `analyze` v141
- `account-deletion-complete` v42
- `retention-cleanup` v49
- `mutate-analysis-finding` v8

Production catalog verification confirms:

- RLS remains enabled on `analyses`, `photos`, and `profiles`.
- `anon` has no read access to these tables.
- Broad authenticated updates are absent.
- Client update/insert grants match the declared allowlists.
- Server-owned columns cannot be updated by `authenticated`.
- All three authority triggers exist.
- The atomic RPC does not use `auth.role()`.
- The atomic RPC is not executable by `PUBLIC` or `authenticated` and is
  executable by `service_role`.

## Test evidence

- Full local pgTAP: **342/342 passed**.
- Client-authority pgTAP: **31/31 passed**.
- Changed Edge Function Deno/static tests: **35 passed**.
- Focused analyze/retention/finding static rerun: **32/32 passed**.
- Screenshot editor build and route integration probes: passed.
- Screenshot QA: **20/20** English screenshots valid; all are 1290×2796,
  light-theme, and no protected Turkish output exists.

## Supabase advisor disposition

The post-DDL security advisor reports no new warning for the new authority
triggers or service-only RPC. Its remaining warnings are:

- Four authenticated `SECURITY DEFINER` RPCs that are intentionally client
  entry points and enforce caller identity and ownership internally:
  `acknowledge_legal_document_v1`, `record_notification_open_v1`,
  `record_user_engagement_state_v1`, and
  `set_notification_master_preference_v1`. The generic advisor guidance is
  [Supabase lint 0029](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- Supabase leaked-password protection is disabled. Enabling it changes live
  signup/password behavior, so it is deferred from this build under the
  no-live-user-impact rule. Reference:
  [Supabase password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

The performance advisor reports 53 pre-existing informational/warning items
(21 unindexed foreign keys, 30 unused indexes, and 2 multiple-permissive-policy
items). They are not regressions from the security migration and are outside
the release-critical localization path; bulk index/policy changes were avoided
to protect current production behavior.
