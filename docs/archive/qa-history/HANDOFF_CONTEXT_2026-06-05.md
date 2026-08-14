# RiskDetected Handoff Context - 2026-06-05

This document is the compact context handoff for a new Codex/ChatGPT thread.

Important security rule:

- Do not paste Supabase access tokens, DB passwords, RevenueCat REST API keys, service-role keys, Apple credentials, or private reviewer credentials into chat or markdown.
- Secrets are stored in macOS Keychain and accessed through the helper scripts listed below.
- Public client keys already present in Xcode build settings are public SDK/publishable keys, not service-role secrets.

## Repository

- Workspace: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`
- Current branch during this handoff: `codex/worktree-cleanup`
- Latest important commit: `0e105eb Prepare subscription lifecycle for TestFlight`
- Current uncommitted changes at handoff time:
  - `QA/SUBSCRIPTION_PRODUCTION_READINESS_AND_QA_RESET_2026-06-04.md`
  - `QA/HANDOFF_CONTEXT_2026-06-05.md`

## Product And App Lane Decision

The product should be tested and shipped as one visible app:

- App name: `RiskDetected`
- Visible Xcode scheme for the user: `RiskDetected`
- Bundle id: `com.riskdetected.app`
- App Store Connect app: the real RiskDetected app
- RevenueCat offering for TestFlight/App Review lane: `default`
- RevenueCat client SDK key: production App Store `appl_...` key tied to `com.riskdetected.app`
- Supabase for Internal TestFlight/App Review lane: production Supabase

The separate `RiskDetected QA` path can stay only as developer/internal background tooling when useful, but the user should not have to select it for real TestFlight or App Review confidence.

## Build Configurations

Current intended flow:

- Internal TestFlight testing:
  - Scheme: `RiskDetected`
  - Archive configuration: `InternalTestFlight`
  - Bundle/display remain production: `com.riskdetected.app` / `RiskDetected`
  - Production Supabase and RevenueCat App Store lane
  - `INTERNAL_TEST_RESET_TOOLS` enabled
  - Profile shows `Test araçları > Temiz test başlangıcı`

- App Review candidate:
  - Scheme: `RiskDetected`
  - Archive configuration must be changed back to `Release`
  - `INTERNAL_TEST_RESET_TOOLS` absent
  - Reset UI absent
  - QA auto-login absent
  - Local StoreKit config absent from shipped app

Known current state:

- `RiskDetected.xcodeproj/xcshareddata/xcschemes/RiskDetected.xcscheme` currently archives with `InternalTestFlight`.
- Before App Review, switch ArchiveAction back to `Release` and run binary/config scans.

## Subscription Work Completed

Completed and validated in this thread:

- RevenueCat products/offerings aligned around the real app bundle.
- Offering strategy settled on production `default` for real TestFlight/App Review lane.
- QA auto-login/fake user flow removed from the user-visible TestFlight lane.
- Internal reset tool added behind `INTERNAL_TEST_RESET_TOOLS`.
- Profile restore entry added/kept for paid users who cannot otherwise access paywall.
- App paid access remains fail-closed:
  - Apple sheet success alone does not unlock paid state.
  - RevenueCat SDK local paid state alone does not unlock paid state.
  - Backend RevenueCat/Supabase verification must agree before Plus/Pro opens.
- Purchase/restore errors were classified into clearer user-facing messages.
- Purchase verification retry was added for the webhook/backend delay case:
  - Observed issue: Plus -> Pro purchase succeeded, then app initially showed "backend planı Plus".
  - Fix: backend verification retries with short delays before failing.
- Evidence captured for real device/TestFlight sandbox flows:
  - Plus purchase and restore.
  - Plus -> Pro upgrade.
  - Pro gate/canvas access.
  - New account `yakemic820@bncinema.com` reached Pro yearly successfully.
- User marked these latest todo items complete:
  - New Internal TestFlight build.
  - Subscription smoke test.
  - Apple Sandbox operational blocker handled enough to continue.
  - RevenueCat/Supabase evidence captured.

## Important Subscription Learnings

- `com.riskdetected.app.qa` did not work for real App Store product loading.
- Real subscription tests must use `com.riskdetected.app`.
- Old Apple Sandbox purchase history can contaminate new RiskDetected users.
- App-local reset can clear RiskDetected local state and RevenueCat cache, but cannot clear Apple Sandbox purchase history.
- Apple Sandbox purchase history must be managed through Apple-side tooling:
  - iPhone Settings > Developer > Sandbox Account
  - App Store Connect > Users and Access > Sandbox
  - Or a fresh sandbox tester
- TestFlight internal tester Apple ID and Sandbox Apple Account are separate concepts but can interact confusingly on a real device.
- Best real-device test setup:
  - Dedicated second device if possible.
  - Install TestFlight build with developer Apple ID.
  - Then manage Media & Purchases / Developer Sandbox account carefully.
  - Open the installed app directly after switching sandbox state; avoid unnecessarily re-opening TestFlight if it forces account changes.

## Current Code Review Note

Static review found one important risk to revisit:

- `App/Services/SubscriptionManager.swift` restore flow calls `Purchases.shared.syncPurchases()` before `restorePurchases()` and before owner guard validation.
- Depending on RevenueCat restore transfer behavior, this could attach/transfer a receipt before the app has a chance to fail closed.
- Safer follow-up:
  - Remove `syncPurchases()` from the normal restore flow, or
  - Prove and document that RevenueCat restore behavior cannot silently transfer active subscriptions in this project.

## Remaining Work

Immediate technical items:

- Re-verified the production-lane `analyze` Edge Function.
  - Device previously showed: `AI hatası: Requested function was not found` on the legacy QA Supabase lane.
  - 2026-06-05 automated readiness now passes for production App Review/Internal TestFlight lane:
    - `analyze`: `ACTIVE`, `verify_jwt=false`, version `97`.
    - `process-analysis-jobs`: `ACTIVE`, `verify_jwt=false`, version `9`.
    - No production deploy was needed.
    - Manual current TestFlight smoke passed: a normal Free analysis completed and opened successfully.
  - Evidence: `QA/ANALYZE_EDGE_FUNCTION_READINESS_2026-06-05.md`.
- Revisit restore implementation risk around `syncPurchases()`.
- Run final subscription smoke on the latest Internal TestFlight build:
  - Free registration.
  - Plus purchase.
  - Relaunch persistence.
  - Restore.
  - Plus -> Pro upgrade.
  - Negative contaminated Apple state fail-closed behavior.

App Review prep:

- Switch `RiskDetected` archive config from `InternalTestFlight` to `Release`.
- Confirm Release has no reset UI and no internal test compile flag.
- Run Release string scan for:
  - `Temiz test başlangıcı`
  - `Test araçları`
  - `INTERNAL_TEST_RESET_TOOLS`
  - `RD_QA_AUTO_LOGIN`
  - `qa_test_store`
  - `RiskDetectedQA.storekit`
- Fill App Store Connect review contact fields.
- Publish/verify App Privacy.
- Add final Review Notes and demo video URL.
- Attach/submit the four first-time subscriptions with the app version.
- Decide China mainland availability for first release.
- Run final `asc validate`, `asc validate subscriptions`, and physical-device smoke.

## Supabase Projects And CLI Access

Known project refs from scripts/config:

- Production Supabase URL in app config: `https://ppcrzemgiztzcgddbins.supabase.co`
- QA Supabase ref used by older QA lane: `iidhnqvuszjcoyncqzkg`

Use Keychain-backed helper for Supabase CLI:

```bash
node scripts/rd_ops_env.mjs status
node scripts/rd_ops_env.mjs supabase projects list
node scripts/rd_ops_env.mjs supabase functions list --project-ref <project-ref>
node scripts/rd_ops_env.mjs supabase db lint --linked
```

Keychain services used by `scripts/rd_ops_env.mjs`:

- `riskdetected_supabase_access_token`
- `riskdetected_supabase_db_password`
- `riskdetected_revenuecat_rest_api_key`

To store/update credentials safely:

```bash
scripts/rd_store_secret.sh riskdetected_supabase_access_token
scripts/rd_store_secret.sh riskdetected_supabase_db_password
scripts/rd_store_secret.sh riskdetected_revenuecat_rest_api_key
```

Additional allowed Keychain services in `scripts/rd_store_secret.sh`:

- `riskdetected_qa_supabase_db_password`
- `riskdetected_qa_supabase_url`
- `riskdetected_qa_supabase_publishable_key`
- `riskdetected_qa_revenuecat_api_key`
- `riskdetected_qa_app_store_revenuecat_api_key`
- `riskdetected_qa_storekit_revenuecat_api_key`
- `riskdetected_qa_revenuecat_webhook_authorization`

Do not print secret values. Use status/presence checks and command wrappers.

## RevenueCat Access

There is no dedicated RevenueCat CLI in this repo. Current ops are done through helper scripts and REST.

Check Keychain presence:

```bash
node scripts/rd_ops_env.mjs status
```

Delete a RevenueCat test subscriber/customer by App User ID:

```bash
node scripts/rd_ops_env.mjs revenuecat-delete-user <app_user_id>
```

Bulk/test cleanup helper:

```bash
node scripts/cleanup_revenuecat_test_users.mjs --help
```

Evidence helper uses RevenueCat REST API key from Keychain or env:

```bash
node scripts/subscription_qa_evidence.mjs --email <email> --environment apple_sandbox --scenario <scenario-id>
node scripts/subscription_qa_evidence.mjs --user-id <uuid> --environment apple_sandbox --scenario <scenario-id>
```

## Important Code Areas

iOS:

- `App/AppState.swift`
  - App flow, backend subscription truth, purchase/restore retry, internal reset.
- `App/Services/SubscriptionManager.swift`
  - RevenueCat configure/identify/load/purchase/restore.
  - Current review concern: `syncPurchases()` before restore owner guard.
- `App/Services/PurchaseErrorClassifier.swift`
  - User-facing purchase error classification.
- `App/Services/AppErrorMessage.swift`
  - Friendly payment/subscription conflict copy.
- `App/Services/RDConfig.swift`
  - Supabase/RevenueCat config read from Info.plist/env with production defaults.
- `App/Views/Paywall/InAppPaywallView.swift`
  - Paywall, CTA states, legal links, purchase feedback.
- `App/Views/Profile/ProfileView.swift`
  - Restore/manage subscription, internal reset UI behind compile flag.

Supabase Edge Functions:

- `supabase/functions/revenuecat-webhook/index.ts`
  - RevenueCat webhook processing, transfer handling, subscription state writes.
- `supabase/functions/sync-revenuecat-subscription/index.ts`
  - Authenticated fallback sync from RevenueCat subscriber truth.
- `supabase/functions/_shared/subscription-tier.ts`
  - Product id -> plan tier mapping.
- `supabase/functions/_shared/revenuecat-owner-guard.ts`
  - Owner mismatch helpers.
- `supabase/functions/_shared/revenuecat-event.ts`
  - RevenueCat event user/transfer id resolution.
- `supabase/functions/analyze/index.ts`
  - Must be re-verified because device saw `Requested function was not found`.

Scripts:

- `scripts/rd_ops_env.mjs`
  - Keychain-backed Supabase/RevenueCat ops wrapper.
- `scripts/rd_store_secret.sh`
  - Securely store required credentials in macOS Keychain.
- `scripts/subscription_qa_evidence.mjs`
  - Pulls Supabase + RevenueCat evidence by email/user id.
- `scripts/cleanup_revenuecat_test_users.mjs`
  - Cleanup helper for RevenueCat test users.
- `scripts/run_qa_storekit_sim.sh`
  - Older StoreKit/sim helper; not the main real TestFlight lane.
- `scripts/configure_qa_supabase_apple_sandbox_subscription_secrets.sh`
  - Older QA Apple Sandbox secret alignment helper.

## Markdown Docs Created Or Updated

Main docs:

- `QA/HANDOFF_CONTEXT_2026-06-05.md`
  - This file. Start here in the new thread.
- `QA/SUBSCRIPTION_PRODUCTION_READINESS_AND_QA_RESET_2026-06-04.md`
  - Most important subscription readiness plan.
  - Explains single visible app decision, Internal TestFlight reset tool, App Review cleanup, and latest todo status.
- `QA/SUBSCRIPTION_QA_MASTER_RUNBOOK_2026-06-03.md`
  - Full D1-D12 subscription QA runbook.
  - Contains Apple Sandbox, StoreKit local, RevenueCat Test Store, physical device evidence.
- `QA/SUBSCRIPTION_QA_EVIDENCE_TEMPLATE_2026-06-03.md`
  - Template for future evidence captures.
- `QA/REVENUECAT_SUPABASE_OPS_RUNBOOK_2026-06-02.md`
  - RevenueCat/Supabase cleanup and config reference.
- `QA/REVENUECAT_ACCOUNT_DELETION_SUBSCRIPTION_2026-06-02.md`
  - Account deletion + subscription ownership notes.

App Review docs:

- `QA/APP_REVIEW_REMAINING_ACTIONS_2026-06-02.md`
  - Current App Review blockers and manual actions.
- `QA/App_Review_Preflight_Evidence_2026-06-02.md`
  - Preflight evidence snapshot, ASC validation, Supabase deployed function state, known warnings.
- `QA/APP_REVIEW_SUBMISSION_DAY_RUNBOOK_2026-06-01.md`
  - Submission-day checklist.
- `QA/APP_REVIEW_GATE_MATRIX_2026-06-01.md`
  - Gates and pass/hold/fail matrix.
- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`
  - Manual evidence fields to fill before submission.
- `QA/APP_STORE_REVIEW_NOTES_2026-06-02.md`
  - Draft Review Notes structure.
- `QA/APP_REVIEW_PHYSICAL_SMOKE_17PM_2026-06-01.md`
  - Physical device smoke checklist.

Supporting docs:

- `QA/APP_STORE_SCREENSHOT_PREFLIGHT_2026-06-02.md`
- `QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md`
- `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md`

Evidence files under `QA/tmp/`:

- D-series subscription evidence and JSON snapshots live under `QA/tmp/`.
- Useful examples:
  - `QA/tmp/subscription-D9-apple-sandbox-plus-sync-restore-free-negative-pass.md`
  - `QA/tmp/subscription-D10-apple-sandbox-plus-to-pro-upgrade-pass.md`
  - `QA/tmp/subscription-D12-pro-gate-quota-verification-pass.md`

## Known App Store Connect State From Prior Evidence

From previous App Review preflight evidence:

- App status was not submitted yet.
- Four subscriptions existed and validation had 0 subscription errors, warnings only.
- Turkey prices were confirmed:
  - Plus monthly: TRY 199.99
  - Plus yearly: TRY 1,999.99
  - Pro monthly: TRY 499.99
  - Pro yearly: TRY 4,999.99
- Manual blockers remained:
  - App Review contact fields.
  - App Privacy publish/verify.
  - Review notes placeholders.
  - Demo video URL.
  - China mainland availability decision.
  - Attach/submit first-time subscriptions through app version page.

## Suggested New Thread Opening Prompt

Paste this into the new thread:

```text
RiskDetected projesinde devam edeceğiz. Önce şu dosyayı oku:
QA/HANDOFF_CONTEXT_2026-06-05.md

Sonra özellikle şu dosyaları sırayla oku:
QA/SUBSCRIPTION_PRODUCTION_READINESS_AND_QA_RESET_2026-06-04.md
QA/SUBSCRIPTION_QA_MASTER_RUNBOOK_2026-06-03.md
QA/APP_REVIEW_REMAINING_ACTIONS_2026-06-02.md
QA/App_Review_Preflight_Evidence_2026-06-02.md

Tokenları chat’e yazma. Supabase/RevenueCat erişimi için scripts/rd_ops_env.mjs ve scripts/rd_store_secret.sh kullan.

İlk hedefimiz: restore akışındaki syncPurchases riskini düzeltmek, analyze Edge Function readiness’ı doğrulamak, sonra App Review Release cleanup’a geçmek.
```
