# RiskDetected Subscription QA Master Runbook

Date: 2026-06-03

## Goal

This runbook makes subscription testing repeatable without weakening the real production rules.

Policy under test:

- Active Apple/RevenueCat subscriptions stay with the original RiskDetected account.
- Another RiskDetected account using the same store receipt must remain free and show owner conflict.
- Expired or inactive subscriptions may be used by a new RiskDetected account according to RevenueCat restore behavior: `Transfer if there are no active subscriptions`.
- App UI may show Plus/Pro only after backend validation.
- No test may manually write paid state to Supabase, hardcode entitlement, disable owner guards, or loosen purchase preflight.

## Test Lanes

### A. Apple Sandbox E2E

Use this lane to test the full real path:

- App Store sandbox sheet
- Apple subscription group behavior
- RevenueCat App Store provider
- RevenueCat webhook
- Production Supabase sync
- App paid/free UI after backend validation

This is the closest to a real user, but it can be blocked by device-level sandbox receipt/cache state. When that happens, classify as `APPLE_SANDBOX_DEVICE_BLOCKED`, not app/backend success.

### B. RevenueCat Test Store QA

Use this lane to test RevenueCat/backend/account ownership behavior deterministically, without Apple sandbox accounts.

Requirements:

- Separate QA RevenueCat project or app/provider.
- RevenueCat Test Store API key beginning with `test_`.
- Separate QA Supabase project.
- QA iOS build config using QA Supabase URL/key and QA RevenueCat API key.
- This build must not be submitted to App Store/TestFlight release as production.

### C. Xcode StoreKit Local

Use this lane to test local StoreKit product loading, purchase result handling, subscription group behavior, downgrade/upgrade UI, and “backend must verify before paid” rules.

Requirements:

- `RiskDetectedQA.storekit` in Xcode.
- Product IDs exactly match production product IDs.
- Plus and Pro are in one subscription group.
- Pro has a higher subscription level than Plus.
- QA Supabase only.
- Do not expect local StoreKit transactions to appear in RevenueCat dashboard like App Store sandbox transactions.

## Shared Evidence Command

Run this after each test step:

```bash
node scripts/subscription_qa_evidence.mjs \
  --email "test@example.com" \
  --environment apple_sandbox \
  --scenario A1 \
  --output "QA/tmp/subscription-A1-test@example.com.md"
```

For QA Supabase/RevenueCat:

```bash
SUPABASE_DB_URL="postgresql://..." \
REVENUECAT_REST_API_KEY="..." \
node scripts/subscription_qa_evidence.mjs \
  --email "qa@example.com" \
  --environment revenuecat_test_store \
  --scenario B1 \
  --output "QA/tmp/subscription-B1-qa@example.com.md"
```

The evidence script is read-only. It does not modify Supabase or RevenueCat.

## Apple Sandbox E2E Preparation

1. RevenueCat:
   - Confirm App Store provider, products, entitlements, and offerings are production/current.
   - Confirm production restore behavior is `Transfer if there are no active subscriptions`.
   - Confirm sandbox override is also `Transfer if there are no active subscriptions`.
   - Enable Sandbox data view in the dashboard.
   - Note the most recent sandbox transaction timestamp before testing.

2. Supabase:
   - Use production project only for this lane.
   - Confirm `revenuecat-webhook` and `sync-revenuecat-subscription` are deployed.
   - If a test email exists, clean it with approved cleanup flow only.
   - Do not manually set `profiles.tier`, `user_subscriptions.status`, or entitlement state.

3. iPhone:
   - Create a fresh Apple sandbox tester when possible.
   - In iOS: `Settings > Developer > Sandbox Apple Account > Manage > Clear Purchase History`.
   - Sign out/in from Sandbox Apple Account.
   - Delete RiskDetected and install fresh.
   - Manually write down the sandbox Apple ID shown on the App Store sheet.

## Apple Sandbox E2E Matrix

### A1 Fresh Plus Yearly Purchase

Steps:

1. Create a new RiskDetected account.
2. Complete onboarding until Plus yearly trial paywall.
3. Tap purchase and complete Apple sandbox sheet.
4. Open app home.
5. Collect evidence for the same email.

Expected:

- Apple sheet opens and completes.
- RevenueCat shows a new customer transaction for Plus yearly.
- Supabase `profiles.tier = plus`.
- Supabase `user_subscriptions` shows Plus active from RevenueCat.
- App shows Plus, not Pro.

Fail if:

- App opens paid before backend validation.
- RevenueCat has no new transaction but app becomes paid.
- Supabase writes paid to a different user.

### A2 Same Account Restore

Steps:

1. Stay logged in as the original paid RiskDetected account.
2. Tap restore.
3. Collect evidence.

Expected:

- Paid state remains on the same RiskDetected user.
- Owner does not change.
- No conflict is shown for the correct account.

### A3 Different RiskDetected Account, Same Sandbox Apple ID, Restore

Steps:

1. Log out or reinstall.
2. Create/login as a different RiskDetected account.
3. Use the same sandbox Apple ID.
4. Tap restore.
5. Collect evidence for both A and B accounts.

Expected:

- B remains free.
- B sees conflict message.
- A remains paid.
- Supabase does not write active paid state for B.

This is `EXPECTED_CONFLICT`, not a failure.

### A4 Different RiskDetected Account, Same Sandbox Apple ID, Purchase

Steps:

1. Stay as B.
2. Attempt Plus or Pro purchase.
3. Collect evidence for A and B.

Expected:

- Apple/RevenueCat returns existing subscription, upgrade/downgrade, or owner conflict behavior.
- B remains free.
- A remains paid.
- RevenueCat active owner does not silently move to B.

This is `EXPECTED_CONFLICT` if B stays free.

### A5 Renewal and Expiration Observation

Steps:

1. Keep A installed or periodically reopen.
2. Observe RevenueCat renewal/expiration.
3. Collect evidence after renewal and after expiration.

Expected:

- Renewal webhook updates Supabase without owner mismatch.
- After expiration, Supabase becomes free/inactive.
- App heals to free after backend sync.

## RevenueCat Test Store QA Preparation

1. RevenueCat QA:
   - Create separate QA project or QA app/provider.
   - Create Test Store.
   - Use a Test Store API key beginning with `test_`.
   - Create products:
     - `riskdetected_plus_monthly`
     - `riskdetected_plus_yearly`
     - `riskdetected_pro_monthly`
     - `riskdetected_pro_yearly`
   - Map Plus products to `plus` entitlement.
   - Map Pro products to `pro` entitlement.
   - Configure offerings to match production package structure.
   - Point webhook to QA Supabase `revenuecat-webhook`.

2. Supabase QA:
   - Separate project: `riskdetected-qa`.
   - Project ref: `iidhnqvuszjcoyncqzkg`.
   - URL: `https://iidhnqvuszjcoyncqzkg.supabase.co`.
   - Same migrations/functions as production.
   - Current verified state:
     - 64 migrations applied.
     - 28 public tables.
     - `profiles`, `user_subscriptions`, `subscription_events`, and `paywall_events` start empty.
     - `revenuecat-webhook` and `sync-revenuecat-subscription` deployed.
   - Separate secrets:
     - `REVENUECAT_REST_API_KEY`
     - `REVENUECAT_WEBHOOK_AUTHORIZATION`
     - Supabase URL/key used by QA iOS build.
  - QA `REVENUECAT_REST_API_KEY` depends on the lane:
    - RevenueCat Test Store QA uses the `test_...` key.
    - Apple Sandbox/TestFlight QA for bundle id `com.riskdetected.app` uses the matching App Store `appl_...` key.
   - Auth callback setup required before simulator onboarding auth:
     - `site_url` must be `io.supabase.riskdetected://login-callback`.
     - `uri_allow_list` must include `io.supabase.riskdetected://login-callback`.
     - Hosted QA currently uses 8-digit email OTP. The QA iOS build supports this via `RDConfig.Auth.emailOTPLength`; production remains 6.
     - Supabase hosted email has a low built-in send rate unless custom SMTP is configured. For repeated QA auth runs, prefer magic-link/admin generated links or configure QA SMTP; do not use subscription bypasses.

3. iOS QA build:
   - Separate scheme/build config.
   - Uses QA Supabase URL/key.
   - Uses the RevenueCat key for the active lane.
   - Do not ship as production.
   - Local scheme name: `RiskDetected QA`.
   - Local build configuration: `QA`.
   - Physical-device Apple Sandbox/TestFlight bundle id: `com.riskdetected.app`.
   - Local display name: `RiskDetected QA`.
   - Apple Sandbox/TestFlight RevenueCat key: the App Store `appl_...` key tied to `com.riskdetected.app`.

Build/run with real QA values by overriding build settings, not by committing secrets:

```bash
scripts/rd_store_secret.sh riskdetected_qa_supabase_url
scripts/rd_store_secret.sh riskdetected_qa_supabase_publishable_key
scripts/rd_store_secret.sh riskdetected_qa_revenuecat_api_key
scripts/configure_qa_supabase_subscription_secrets.sh
scripts/run_qa_storekit_sim.sh
```

Use `scripts/configure_qa_supabase_subscription_secrets.sh` for the RevenueCat Test Store lane.
Use `scripts/configure_qa_supabase_apple_sandbox_subscription_secrets.sh` for the Apple Sandbox/TestFlight lane.
Never run C2/C3 purchase tests while required values still contain `not_configured` placeholders.

## RevenueCat Test Store QA Matrix

### B1 Plus Success

Expected:

- Test Store success activates Plus in QA RevenueCat.
- QA Supabase shows Plus active.
- App shows Plus only after sync.

### B2 Pro Success

Expected:

- Test Store success activates Pro in QA RevenueCat.
- QA Supabase shows Pro active.
- App shows Pro only after sync.

### B3 Purchase Cancel

Expected:

- Supabase remains unchanged.
- App remains free or current tier.
- Paywall records cancel/failure behavior without paid write.

### B4 Purchase Failure

Expected:

- Supabase remains unchanged.
- App shows understandable failure message.
- `paywall_events` includes `purchase_failed` or equivalent.

### B5 Owner Conflict

Expected:

- A active paid remains paid.
- B using same Test Store restore/purchase chain remains free.
- QA Supabase records conflict evidence.

### B6 Renewal and Expiration

Expected:

- Renewal webhook updates QA Supabase.
- Expiration makes QA Supabase free/inactive.
- App follows backend state.

## Xcode StoreKit Local Preparation

1. Confirm local Xcode tooling:

   ```bash
   xcode-select -p
   xcodebuild -version
   xcodebuild -checkFirstLaunchStatus
   xcrun storekit --help
   ```

   On this machine, Xcode 26.5 includes StoreKit frameworks and the Xcode StoreKit Editor plugin, but no standalone `xcrun storekit` command-line utility. That is acceptable for this lane; create and maintain the file through Xcode UI.

   Additional readiness check on 2026-06-04:
   - `xcrun storekit` is still unavailable on this machine.
   - RevenueCat documents that StoreKit configuration files only work when the app is run directly from Xcode; command-line `xcodebuild` based launches do not use the StoreKit configuration selected in the scheme.
   - Xcode was opened successfully and the shared `RiskDetected QA` scheme exists, but the toolbar was still on the regular `RiskDetected` scheme during the readiness attempt. Before running this lane manually, select `RiskDetected QA` from the scheme picker.
   - The local `.storekit` file is correctly attached to the `RiskDetected QA` scheme `LaunchAction`.
   - Do not use the RevenueCat Test Store `test_...` key for this lane. Test Store produces RevenueCat's Test Store modal, not Xcode's StoreKit transaction sheet/manager.
   - For backend-verified StoreKit-local E2E, the RevenueCat iOS/App Store provider used by the QA build must be able to validate receipts generated by `RiskDetectedQA.storekit`. If that provider/certificate setup is missing, StoreKit-local purchases may be useful for UI/product loading checks but must not be accepted as backend subscription lifecycle proof.

2. Create `RiskDetectedQA.storekit` in Xcode:
   - Xcode > File > New > File.
   - Choose StoreKit Configuration File.
   - Save it in the project.
   - Add it to the RiskDetected project.

3. Add products with production IDs:
   - `riskdetected_plus_monthly`
   - `riskdetected_plus_yearly`
   - `riskdetected_pro_monthly`
   - `riskdetected_pro_yearly`

4. Put Plus and Pro products in the same subscription group.
5. Set Pro above Plus in subscription level.
6. Select the `.storekit` file in the QA scheme Run options.
7. Run against QA Supabase.

Important scope note:

- Xcode StoreKit Transaction Manager can locally control refunds, cancellations, interrupted/failed purchases, and renewal speed.
- RevenueCat notes that cancellation/refund events triggered through Xcode's Manage Transactions window are not stored in the receipt and may not appear in RevenueCat dashboard/webhook events. The SDK should still be able to detect no active subscriptions after app restart and remove entitlements.
- Therefore, StoreKit Local is best for app/SDK healing behavior and transaction UI behavior. Apple Sandbox E2E remains the lane for full store receipt + RevenueCat webhook + Supabase `subscription_events` validation.

## Xcode StoreKit Local Matrix

### C1 Product Loading

Expected:

- Plus/Pro monthly/yearly appear on paywall.
- Product IDs map to correct tier/package.

Observed on 2026-06-03:

- QA auth callback/session works; the QA app lands on the home screen as a free user.
- RevenueCat Test Store key is accepted by the QA build; the previous Test Store release-protection alert is gone.
- Initial product loading was blocked by RevenueCat dashboard configuration:
  - SDK diagnostic: Test Store API key was configured, but no Test Store products were registered in the RevenueCat dashboard offerings.
  - App stayed free and showed the package-unavailable message.
  - QA Supabase remained safe: `profiles.tier=free`, `user_subscriptions.tier=free`, `user_subscriptions.status=inactive` for `qac1780516350@gmail.com`.
- Fixed by creating the `qa_test_store` RevenueCat offering with the four Test Store products and mapping the QA build to that offering.
- Verified diagnostics:
  - Selected offering: `qa_test_store`.
  - Mapped packages: `riskdetected_plus_monthly`, `riskdetected_plus_yearly`, `riskdetected_pro_monthly`, `riskdetected_pro_yearly`.

Observed on 2026-06-04 for StoreKit Local/App Store SDK key:

- Earlier local StoreKit QA used a dedicated RevenueCat App Store provider:
  - App name: `RiskDetected QA StoreKit`
  - Bundle id: `com.riskdetected.app.qa`
  - Public SDK key stored locally in Keychain as `riskdetected_qa_storekit_revenuecat_api_key`.
- Removed the RevenueCat Test Store release-check compile flag from the QA build and updated `scripts/run_qa_storekit_sim.sh` to require the QA App Store `appl_...` key instead of the Test Store `test_...` key.
- Built and launched `RiskDetected QA` on the iPhone 17 Pro Simulator with:
  - QA Supabase URL: `https://iidhnqvuszjcoyncqzkg.supabase.co`
  - QA RevenueCat App Store SDK key from `riskdetected_qa_storekit_revenuecat_api_key`
  - Offering identifier: `default`
- App landed safely on the free home screen.
- Paywall opened but product loading was blocked by RevenueCat catalog configuration:
  - SDK diagnostic: `You have configured the SDK with an App Store API key, but there are no App Store products registered in the RevenueCat dashboard for your offerings.`
  - App stayed free and showed the package-unavailable message.
  - No paid state was granted locally.
- Classification: `REVENUECAT_CONFIG_FAIL`.
- Required fix before C1 can pass in this lane:
  - Under RevenueCat Product catalog > Products > `RiskDetected QA StoreKit`, add the four App Store products with ids matching `RiskDetectedQA.storekit`:
    - `riskdetected_plus_monthly`
    - `riskdetected_plus_yearly`
    - `riskdetected_pro_monthly`
    - `riskdetected_pro_yearly`
  - Attach Plus products to `plus` entitlement and Pro products to `pro` entitlement.
  - Add those QA App Store products to the active offering packages used by the QA app, or create a dedicated StoreKit-local offering and set `RISKDETECTED_REVENUECAT_OFFERING_IDENTIFIER` to that identifier.

Observed on 2026-06-04 for physical-device Apple Sandbox/TestFlight QA:

- The QA app now runs against the production bundle id `com.riskdetected.app` while still using QA Supabase.
- RevenueCat sync must use the App Store `appl_...` key tied to `com.riskdetected.app`, not the old dedicated QA StoreKit provider key.
- QA Supabase Apple Sandbox secrets are configured with `scripts/configure_qa_supabase_apple_sandbox_subscription_secrets.sh`.
- Active offering identifier for this lane: `default`.

### D9 Physical Apple Sandbox Plus Sync and Restore

Observed on 2026-06-04:

- Evidence: `QA/tmp/subscription-D9-apple-sandbox-plus-sync-restore-free-negative-pass.md`
- Device/build lane:
  - Physical iPhone `iPhone Kerem`.
  - `RiskDetected QA` 1.0 (49).
  - Bundle id `com.riskdetected.app`.
  - RevenueCat App Store key lane `appl_mck...`.
  - Offering `default`.
  - QA Supabase project `iidhnqvuszjcoyncqzkg`.
- Clean Plus test user:
  - email: `kosixol673@brixozu.com`
  - Supabase user id / RevenueCat customer id: `fce0f956-a0aa-4306-9041-31272428c2fe`
- Apple Sandbox purchase:
  - Product: `riskdetected_plus_yearly`.
  - Apple purchase succeeded in Sandbox.
  - RevenueCat SDK diagnostic showed `activeProducts=[riskdetected_plus_yearly]` and `activeEntitlements=[plus]`.
  - RevenueCat REST also returned active `plus` / `riskdetected_plus_yearly` with sandbox transaction id `2000001182669889`.
- QA Supabase:
  - Backend sync repair returned `tier=plus`, `status=active`, `product_id=riskdetected_plus_yearly`.
  - `profiles.tier=plus`.
  - `user_subscriptions.tier=plus`.
  - `user_subscriptions.status=active`.
  - `user_subscriptions.entitlement_id=plus`.
- App behavior:
  - After app close/open, the user entered Plus automatically.
  - `Geri yukle` returned home and Plus stayed active.
  - User verified paid gates by adding a company and seeing no lock/upgrade warning.
- Negative Free control:
  - email: `vocosa2292@bncinema.com`
  - Supabase user id: `4290c94d-3734-408b-b8bf-7e8f1fa3959b`
  - RevenueCat subscriber snapshot empty.
  - QA Supabase remained `free/inactive`.
  - App remained Free and locked.
- Dirty account note:
  - `free-demo@riskdetected.qa` is contaminated for clean first-purchase testing because RevenueCat SDK sees active `pro` / `riskdetected_pro_yearly`.
  - The `Pro aktif gorunuyor` message for that account is classified as expected dirty-account conflict, not a current Plus sync failure.
- Result: PASS for Apple Sandbox/TestFlight Plus sync after RevenueCat key/bundle/offering alignment. Use a fresh sandbox tester or cleared purchase history plus a fresh QA app user for future first-purchase tests.

### D10 Physical Apple Sandbox Plus-to-Pro Upgrade

Observed on 2026-06-04:

- Evidence: `QA/tmp/subscription-D10-apple-sandbox-plus-to-pro-upgrade-pass.md`
- Post-upgrade REST snapshot: `QA/tmp/subscription-D10-plus-to-pro-upgrade-post.json`
- Device/build lane:
  - Physical iPhone `iPhone Kerem`.
  - `RiskDetected QA` 1.0 (49).
  - Bundle id `com.riskdetected.app`.
  - RevenueCat App Store key lane `appl_mck...`.
  - Offering `default`.
  - QA Supabase project `iidhnqvuszjcoyncqzkg`.
- Upgrade user:
  - email: `kosixol673@brixozu.com`
  - Supabase user id / RevenueCat customer id: `fce0f956-a0aa-4306-9041-31272428c2fe`
- Pre-upgrade baseline:
  - QA Supabase and RevenueCat both showed active Plus yearly.
  - `profiles.tier=plus`.
  - `user_subscriptions.tier=plus`.
  - RevenueCat active entitlement `plus`.
  - RevenueCat active product `riskdetected_plus_yearly`.
- Upgrade action:
  - User opened Pro paywall from active Plus state.
  - User selected Pro yearly and confirmed the Apple Sandbox purchase sheet.
  - User reported the app moved to Pro.
- RevenueCat post-upgrade:
  - Active entitlement: `pro`.
  - Active product: `riskdetected_pro_yearly`.
  - Sandbox transaction id: `2000001182697120`.
  - Expiration: `2026-06-04T13:46:26Z`.
- QA Supabase post-upgrade:
  - `profiles.tier=pro`.
  - `user_subscriptions.tier=pro`.
  - `user_subscriptions.status=active`.
  - `user_subscriptions.product_id=riskdetected_pro_yearly`.
  - `user_subscriptions.entitlement_id=pro`.
- Paywall telemetry:
  - `purchase_started` for `pro_yearly::riskdetected_pro_yearly` with `current_tier=plus`.
  - `purchase_succeeded` for `pro_yearly::riskdetected_pro_yearly` with `current_tier=pro`.
- Result: PASS for physical-device Apple Sandbox Plus-to-Pro upgrade. The app, RevenueCat, Supabase, and paywall telemetry all converged on Pro.
- Production/TestFlight QA method note: the same Apple Sandbox tester can be reused for sequential lifecycle coverage when state is known. In this run, one sandbox tester completed Plus yearly first-purchase and then Plus-to-Pro yearly upgrade against the real bundle id `com.riskdetected.app`, real App Store sandbox receipt validation, RevenueCat App Store backend, and QA Supabase sync. This is preferred for upgrade-path testing before App Review; use a fresh tester or clear purchase history only when a clean first-purchase baseline is required.

### D11 Profile Restore for Active Pro

Observed on 2026-06-04:

- Evidence: `QA/tmp/subscription-D11-profile-pro-restore-pass.md`
- Post-restore REST snapshot: `QA/tmp/subscription-D11-pro-profile-restore-post.json`
- Product gap found:
  - Active Pro users had no natural route to the paywall, so the paywall-only `Geri yukle` control was unreachable.
- Product fix:
  - Added Profile > Ayarlar > `Satın alımları geri yükle`.
  - The row calls `app.restoreSubscriptions()` directly.
  - The entry is available to Free, Plus, and Pro users.
  - Restore telemetry uses variant `profile_subscription_restore_v1`.
- Test user:
  - email: `kosixol673@brixozu.com`
  - Supabase user id / RevenueCat customer id: `fce0f956-a0aa-4306-9041-31272428c2fe`
- User action/result:
  - User tapped the new Profile restore row.
  - App showed `Pro aboneliğin doğrulandı.`
- RevenueCat post-restore:
  - Active entitlement: `pro`.
  - Active product: `riskdetected_pro_yearly`.
  - Sandbox transaction id: `2000001182697120`.
- QA Supabase post-restore:
  - `profiles.tier=pro`.
  - `user_subscriptions.tier=pro`.
  - `user_subscriptions.status=active`.
  - `user_subscriptions.product_id=riskdetected_pro_yearly`.
  - `user_subscriptions.entitlement_id=pro`.
- Telemetry:
  - `paywall_events.event_name=restore_tap`.
  - `variant_id=profile_subscription_restore_v1`.
  - `metadata.layout=profile_restore`.
  - `metadata.current_tier=pro`.
- Result: PASS. Keep Profile restore entry for production/TestFlight because it gives paid users a restore path without reopening the paywall.

### C2 Plus Local Purchase

Expected:

- App receives local purchase result.
- App does not grant paid unless backend validation succeeds.
- QA Supabase is not incorrectly marked paid.

Observed on 2026-06-03:

- RevenueCat Test Store modal opened for `riskdetected_plus_yearly`; no Apple sheet was used.
- `Test valid purchase` succeeded.
- `paywall_events` recorded `purchase_started` and `purchase_succeeded` with selected package `$rc_annual::riskdetected_plus_yearly`.
- RevenueCat subscriber snapshot:
  - `plus` entitlement active.
  - `riskdetected_plus_yearly` subscription active.
  - store: `test_store`.
- QA Supabase:
  - `profiles.tier=plus`.
  - `user_subscriptions.tier=plus`.
  - `user_subscriptions.status=active`.
  - `user_subscriptions.product_id=riskdetected_plus_yearly`.
  - `user_subscriptions.entitlement_id=plus`.
- `subscription_events` stayed empty for this Test Store run; this path updated QA Supabase through app-triggered backend sync, not an Apple/RevenueCat webhook event.

### C3 Pro Local Purchase or Upgrade

Expected:

- Pro is resolved as higher tier than Plus.
- UI does not show Pro without backend-verified Pro state.

Observed on 2026-06-03:

- Initial Plus -> Pro Test Store purchase exposed a backend sync guard issue:
  - RevenueCat resolved `pro`, but authenticated sync returned previous backend `plus`.
  - App showed `Abonelik doğrulanamadı. Seçilen plan Pro, backend planı Plus.`
  - This was a safe failure: Pro was not opened without backend confirmation.
- Fix applied to QA function path:
  - Explicit Pro purchase sync is allowed only when previous tier is Plus, RevenueCat resolved tier is Pro, and client assertion is `expected_tier=pro`.
  - Implicit subscriber snapshots/restores still cannot silently upgrade Plus to Pro.
- Unit tests:
  - `deno test supabase/functions/_shared/subscription-tier_test.ts supabase/functions/_shared/revenuecat-owner-guard_test.ts`
  - Result: 11 passed, 0 failed.
- QA Edge Function deployed:
  - `sync-revenuecat-subscription` on QA project `iidhnqvuszjcoyncqzkg`.
- Retest result:
  - RevenueCat subscriber has active `pro` entitlement and `riskdetected_pro_yearly` subscription.
  - QA Supabase `profiles.tier=pro`.
  - QA Supabase `user_subscriptions.tier=pro`.
  - QA Supabase `user_subscriptions.status=active`.
  - QA Supabase `user_subscriptions.product_id=riskdetected_pro_yearly`.
  - Paywall events include `purchase_succeeded` with `current_tier=pro`.

### C4 Pro Active, Plus Downgrade Attempt

Expected:

- App does not count downgrade as Plus purchase success.
- Existing “manage downgrade in App Store” behavior remains.

Observed on 2026-06-04:

- Fresh QA user:
  - email: `c4test+1780534086@riskdetected.qa`
  - Supabase user id / RevenueCat customer id: `f7fdb2df-e012-4b97-84d7-41668126d717`
- A Pro monthly purchase was completed through RevenueCat Test Store.
- Pre-downgrade evidence while Pro was active:
  - RevenueCat active entitlement: `pro`.
  - RevenueCat active product: `riskdetected_pro_monthly`.
  - QA Supabase `profiles.tier=pro`.
  - QA Supabase `user_subscriptions.tier=pro`.
  - QA Supabase `user_subscriptions.status=active`.
  - QA Supabase `user_subscriptions.product_id=riskdetected_pro_monthly`.
- UI behavior:
  - Home screen did not show a `Yükselt` entry point while Pro was active.
  - Profile screen showed `Pro plan aktif` and `Pro plan · App Store aboneliği aktif`.
  - Profile `Firmalarım > Yönet` opened the paid company-management sheet, not a Plus purchase/paywall flow.
  - No natural in-app path was available to initiate a Plus purchase while the user was already Pro.
- Paywall event evidence:
  - `purchase_succeeded` exists only for `pro_monthly::riskdetected_pro_monthly`.
  - No Plus `purchase_started` or Plus `purchase_succeeded` event was written after Pro became active.
- Result: pass with stricter UI gating than the fallback downgrade message path. The app did not count a downgrade as Plus purchase success, Pro stayed intact in RevenueCat and QA Supabase, and no manual paid write or guard bypass was used.

### C5 Interrupted, Refund, Expiration

Expected:

- App does not open paid on interrupted/refunded transaction.
- Free/inactive healing works after expiration.

Observed on 2026-06-04:

- Failure/cancel test user:
  - email: `c5test+1780534558@riskdetected.qa`
  - Supabase user id / RevenueCat customer id: `46fba30d-70b3-461f-8ed3-4408b0f6fbd0`
- Failure path:
  - Paywall opened with Plus yearly selected.
  - RevenueCat Test Store modal opened for `riskdetected_plus_yearly`.
  - `Test failed purchase` was selected.
  - User-facing message: `Purchase failure simulated successfully in Test Store.`
  - App stayed on paywall/free state; it did not open Plus.
  - RevenueCat subscriber snapshot remained empty: no entitlements, no subscriptions.
  - QA Supabase remained free/inactive:
    - `profiles.tier=free`.
    - `user_subscriptions.tier=free`.
    - `user_subscriptions.status=inactive`.
    - `product_id=NULL`.
  - `paywall_events` recorded `purchase_started` followed by `purchase_failed`; no `purchase_succeeded` was written.
- Cancel path:
  - RevenueCat Test Store modal was opened again for `riskdetected_plus_yearly`.
  - `Cancel` was selected.
  - App returned to the normal paywall state and did not open paid access.
  - QA Supabase still remained free/inactive.
  - `paywall_events` recorded the second `purchase_started` / `cta_tap`; no Plus `purchase_succeeded` was written.
- Test Store renewal/expiration observation:
  - C4 Pro test user `c4test+1780534086@riskdetected.qa` was used for renewal/expiration observation.
  - RevenueCat Test Store auto-renewed `riskdetected_pro_monthly`.
  - Poll evidence:
    - 03:59:40 +03: active `pro`, expires `2026-06-04T01:03:54Z`.
    - 04:04:13 +03: renewed active `pro`, expires `2026-06-04T01:08:54Z`.
  - QA Supabase did not receive Test Store renewal webhook events; `subscription_events` stayed empty for both C4 and C5 Test Store users.
  - C4 QA Supabase state stayed at the original app-triggered sync timestamp:
    - `profiles.tier=pro`.
    - `user_subscriptions.tier=pro`.
    - `user_subscriptions.status=active`.
    - `current_period_ends_at=2026-06-04 03:53:54 +0300`.
- Result:
  - Failure path: PASS.
  - Cancel path: PASS.
  - Renewal observation: PASS for RevenueCat Test Store renewal visibility.
  - Expiration/refund healing: BLOCKED in this lane. The Test Store modal used here exposes valid purchase, failed purchase, and cancel. It did not expose refund/interrupted controls, and the Pro monthly subscription auto-renewed instead of expiring during the observation window. Run refund/interruption/forced-expiration through Xcode StoreKit Transaction Manager or Apple Sandbox E2E; do not simulate it by manually editing Supabase paid state.

### D12 Pro Gate And Quota Verification

Expected:

- Active Pro user should have Pro backend state and open Pro quota before a real Pro-only analysis test.
- If a later device run shows a lock or upsell, the failure should be classified as app-side gate wiring unless backend state changed.

Observed on 2026-06-04:

- RiskDetected user: `kosixol673@brixozu.com`.
- Supabase user ID / RevenueCat customer ID: `fce0f956-a0aa-4306-9041-31272428c2fe`.
- Supabase:
  - `profiles.tier=pro`.
  - `profiles.daily_quota_used=0`.
  - `user_subscriptions.tier=pro`.
  - `user_subscriptions.status=active`.
  - `user_subscriptions.product_id=riskdetected_pro_yearly`.
  - `user_subscriptions.entitlement_id=pro`.
  - `user_subscriptions.source=revenuecat_sync`.
- RevenueCat:
  - REST status `200`.
  - Active entitlement `pro`.
  - Active product `riskdetected_pro_yearly`.
  - Store transaction ID `2000001182697120`.
- Quota snapshot:
  - Standard analysis `0/40`.
  - Detailed analysis `0/10`.
  - Reports `0/750` for the month.
  - Companies `0/25`.
  - No recent analyses, reports, or usage events.
- App/code capability model for Pro:
  - detailed risk table enabled.
  - emergency risk enabled.
  - procedure check enabled.
  - automatic delivery enabled.
  - trained AI enabled.
  - advanced canvas full.
  - Pro-only canvases include `ergonomics`, `legislation`, and `general_premium`.
- Evidence:
  - `QA/tmp/subscription-D12-pro-gate-quota-snapshot.json`.
  - `QA/tmp/subscription-D12-pro-gate-quota-verification-pass.md`.

Result:

- Backend Pro gate and quota verification: PASS.
- Device Pro canvas selection: PASS. The Pro user could select a Pro canvas with no lock or upsell.
- Analysis execution: out of subscription scope for this run. The device showed `Analiz Hatası` / `AI hatası: Requested function was not found` with support code `RD-2C95E279`. The app calls Supabase Edge Function `analyze`; the repo contains `supabase/functions/analyze`, so this should be tracked separately as an AI/Supabase function deployment or environment wiring issue.

## Evidence Requirements

For every scenario, save:

- Environment: `apple_sandbox`, `revenuecat_test_store`, or `storekit_local`.
- Date/time.
- RiskDetected email.
- Supabase user ID.
- RevenueCat customer ID.
- Product selected.
- App screenshot.
- User-facing message.
- RevenueCat active entitlements/subscriptions.
- Recent RevenueCat transaction or webhook event.
- Supabase `profiles`, `user_subscriptions`, `subscription_events`, `paywall_events`.

Use `QA/SUBSCRIPTION_QA_EVIDENCE_TEMPLATE_2026-06-03.md` for manual notes and attach the generated evidence report from `scripts/subscription_qa_evidence.mjs`.

## Failure Classification

- `APP_FAIL`: app shows paid without backend verification, wrong tier, or paid on conflict.
- `BACKEND_FAIL`: Supabase writes paid against RevenueCat owner/snapshot, or owner guard fails.
- `REVENUECAT_CONFIG_FAIL`: product/offering/entitlement/webhook config is missing or points to wrong environment.
- `APPLE_SANDBOX_DEVICE_BLOCKED`: Apple sheet does not open, old receipt appears with a fresh sandbox account, or RevenueCat receives no new transaction.
- `EXPECTED_CONFLICT`: active subscription belongs to another RiskDetected account and new account stays free.

## Acceptance Criteria

- Fresh purchase success has the same tier in App, RevenueCat, and Supabase.
- Conflict leaves the new user free.
- Restore grants paid only to the correct owner.
- Old purchase dates do not grant paid to a newly-created RiskDetected account.
- Production Supabase is used only in Apple Sandbox E2E.
- Test Store and StoreKit Local do not touch production data.
- Every scenario ends as `pass`, `fail`, or `blocked` with evidence.

## References

- [Apple sandbox testing and clear purchase history](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)
- [Apple StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode/)
- [RevenueCat Sandbox Testing](https://www.revenuecat.com/docs/test-and-launch/sandbox)
- [RevenueCat Test Store](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store)
