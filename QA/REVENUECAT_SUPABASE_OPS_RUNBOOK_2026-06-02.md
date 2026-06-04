# RevenueCat / Supabase Ops Runbook - 2026-06-02

> 2026-06-03 update: End-to-end subscription QA now has a dedicated master runbook and read-only evidence collector:
> - `QA/SUBSCRIPTION_QA_MASTER_RUNBOOK_2026-06-03.md`
> - `QA/SUBSCRIPTION_QA_EVIDENCE_TEMPLATE_2026-06-03.md`
> - `scripts/subscription_qa_evidence.mjs`
>
> Use those files for Apple Sandbox E2E, RevenueCat Test Store QA, and Xcode StoreKit Local evidence. This ops runbook remains the cleanup/config reference.

## Keychain Services

Store long-lived local ops secrets in macOS Keychain. Do not commit secrets.

```bash
scripts/rd_store_secret.sh riskdetected_supabase_access_token
scripts/rd_store_secret.sh riskdetected_supabase_db_password
scripts/rd_store_secret.sh riskdetected_revenuecat_rest_api_key
node scripts/rd_ops_env.mjs status
```

## Supabase Commands

Run Supabase CLI through the wrapper so Codex shells receive the token and DB password automatically.

```bash
node scripts/rd_ops_env.mjs supabase secrets list --project-ref ppcrzemgiztzcgddbins
node scripts/rd_ops_env.mjs supabase db query --linked --output json "select now();"
```

## QA Apple Sandbox RevenueCat Key Alignment

Apple Sandbox/TestFlight E2E for the current physical-device bundle must keep these values aligned:

- Bundle id: `com.riskdetected.app`
- RevenueCat App Store SDK key: `appl_mckFFxUrvtNqzjShezjMIrFmItA`
- QA Supabase `REVENUECAT_REST_API_KEY`: same `appl_...` key
- Offering: `default`, because it contains the App Store products for this bundle

Configure the QA Supabase secrets for this lane with:

```bash
scripts/configure_qa_supabase_apple_sandbox_subscription_secrets.sh
```

Do not use the RevenueCat Test Store `test_...` key for Apple Sandbox/TestFlight purchases. The Test Store key remains valid only for the separate RevenueCat Test Store QA lane.

## RevenueCat Test Customer Cleanup

Default dry-run emails:

- `isgadasi@gmail.com`
- `kayalar.kerem.game@gmail.com`
- `keremkayalar@icloud.com`
- `keremtiguan@gmail.com`

```bash
node scripts/cleanup_revenuecat_test_users.mjs
node scripts/cleanup_revenuecat_test_users.mjs --confirm-delete
```

The script finds RevenueCat App User IDs from current Supabase Auth users and completed account deletion request audit rows, then deletes matching RevenueCat customer profiles.

## Apple Sandbox Subscription Cleanup

RevenueCat customer deletion does not cancel Apple sandbox subscriptions.

Use two sandbox tracks when validating subscription fixes:

- Clean sandbox tester: main acceptance path for fresh purchases.
- Dirty sandbox tester: intentional recovery path for "Bu ogeye abonesiniz" / already-owned receipt behavior.

For a truly fresh purchase test, use a newly created sandbox tester with no RiskDetected purchase history, or clear purchase history for the existing tester:

1. On the iPhone, open Settings.
2. Go to Developer.
3. Open Sandbox Apple Account.
4. Open Manage.
5. Cancel the active RiskDetected sandbox subscription.
6. Sign out and sign back in with the sandbox tester.
7. If needed, use App Store Connect > Users and Access > Sandbox Testers to clear purchase history for that tester.

If the Apple sandbox subscription remains active, StoreKit can still show "Bu ogeye abonesiniz" even after Supabase and RevenueCat cleanup.

## RevenueCat Restore Behavior Check

Before release QA, confirm RevenueCat Dashboard restore behavior is compatible with account recovery:

- Required production and sandbox setting: `Transfer if there are no active subscriptions`.
- Do not treat `$RCAnonymousID...` as a different user by itself; RevenueCat can preserve anonymous original IDs after `logIn()` aliases them to the identified Supabase UUID.
- Treat another identified Supabase UUID with an active subscription as an owner conflict.

Record the dashboard setting in the QA handoff before the final TestFlight pass.

## Acceptance Matrix

- Clean sandbox + fresh Supabase user + Plus annual trial: app and backend stay Plus, never Pro.
- Dirty sandbox + already-owned Plus: app does not lock; same/anonymous owner can restore/sync.
- Dirty sandbox + other identified owner: app stays free and shows account-conflict copy.
- Supabase/Auth/Profile cleanup and RevenueCat customer delete are not considered a full reset unless Apple sandbox purchase history is also clean.
