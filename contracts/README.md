# contracts/

Shared source of truth between backend, iOS, and Android — not generated code, not a client
library. If a backend field, capability flag, or error code changes here, both `App/` (iOS) and
`android/` must be updated in the **same PR/epic** before merge. See the Android execution plan's
Bölüm D (`docs/android/RISKDETECTED_ANDROID_PLAN_INCELEME_VE_FINAL_KARAR_2026-08-06.md` and the
committed master plan) for the full rule set — summary:

1. Backend is designed platform-aware from the start (`platform` param required, unknown
   platform fails closed — see review doc finding F3).
2. New capability/feature flags get both an iOS allowlist entry and an Android allowlist entry
   together; neither ships alone.
3. This directory is updated **before** either client implementation, not after.
4. A task isn't "Done" without: iOS fixture regression green, Android fixture test present,
   unknown-platform/old-build behavior tested, both platforms' flags independently killable.

## Layout

- `mobile/api/` — request/response shapes for backend endpoints as consumed by mobile clients
  (`analyze`, `app-release-policy`, `register-report`, etc.).
- `mobile/models/` — shared domain shapes (finding, plan/tier, safety profile, canvas/sector).
- `mobile/errors/` — the common error contract (master plan §10.4) — code → meaning, both
  platforms must map 1:1, no client-invented error codes.
- `mobile/fixtures/` — one fixture set per platform per contract, used by both the Deno backend
  tests and each client's own tests (F5/F6 pattern: `client_capabilities`, OTP metadata).
- `design/riskdetected-tokens.json` — placeholder for the day design tokens (color/spacing/type)
  become a single generated source for both `App/DesignSystem/` and
  `android/core/designsystem/` instead of two hand-maintained copies. Not wired up yet — Faz 1
  ported the Android tokens by hand from the iOS Swift source; see that module's file header.

## Status (2026-08-06, Faz 1)

Empty skeleton. First real content lands in Faz 2 with the `client_capabilities` contract (review
doc finding F5) — that's also the first real test of whether this process actually gets followed.
