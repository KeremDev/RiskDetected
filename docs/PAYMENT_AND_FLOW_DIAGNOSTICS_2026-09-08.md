# Payment and first-analysis diagnostics — 2026-09-08

## Crash finding and limits

- Crashlytics issue `dae7cb84b3499727c650a64570d882a8`: one Android 2.0.0 (12) crash, OnePlus 8 Pro / Android 11, September 5 at 13:50:45 TR.
- `ProxyBillingActivity.onCreate`, Billing 8.3.0: null `PendingIntent.getIntentSender()`.
- RevenueCat documents this exact error and OnePlus 8 Pro as a signature associated with automated testing launching the internal Activity without required arguments. They report no confirmed production-user impact and no supported workaround: https://www.revenuecat.com/docs/known-store-issues/play-billing-library/proxy-billing-activity-crash
- Our merged manifest already marks this SDK Activity `exported=false`.
- This is NOT proof a recent registrant's payment failed. No user linkage or live reproduction is available. Automated-test origin is a strong hypothesis, not a confirmed cause for this individual record.
- No SDK patch, Activity replacement, exception swallowing around SDK lifecycle, billing version override, or crash suppression was introduced. The vendor exception is **not claimed fixed**.

## Implemented safeguards

- Repository-wide atomic checkout guard rejects concurrent launches across paywall instances.
- Activity validity is checked after the asynchronous customer-info lookup and before Play launch. Uses lifecycle RESUMED, not window focus (Compose dialogs legitimately take window focus).
- Coroutine cancellation is rethrown; paywall busy state is cleared in finally.
- API 29+ pre-create Crashlytics diagnostics capture only presence of expected billing arguments and restored-state flag. They do not modify Play's intent or expose its contents.
- First-party billing launch/result events distinguish blocked launch, cancellation, pending purchase and store/network failure. `billing_result/completed` means the SDK purchase returned; backend entitlement success remains governed by existing receipt verification and paywall success events, not this diagnostic.

## First-analysis measurement

Both clients now record authenticated home entry, photo picker/import/ready, analysis CTA/validation, create/upload/submit/result stages and failures. iOS additionally records JPEG preparation; Android records local file-read errors. Android camera permission rejection and camera failures, and iOS already-denied camera access, are observable. iOS gallery cancellation is distinct from a failed image import.

Android gallery stream exceptions now fail gracefully with the existing localized unreadable-photo message. Analysis file-read IOException becomes a recoverable failure with pending-row cleanup. iOS concurrent gallery loads protect the result array with a lock.

Transport: `public.client_flow_events`, separate from quota `usage_events` and Meta.

- Allowlisted stage/outcome/reason, capped photo count, platform/build, random process session/event IDs and timestamps.
- Authenticated account ID is used for first-party diagnostics: this is account-linked, **not anonymous**. No photo, URI, analysis content, raw error text, email, payment details or advertising ID is included.
- RLS enforces owner-only insert/read; clients cannot update/delete. Events are untrusted diagnostics, never purchase or quota authority.
- Stable event IDs make retries idempotent. Local queue is capped at 200, expires after 24 hours, retries up to three times per flush and remains queued for a subsequent event/relaunch. This is best-effort telemetry, not a guaranteed event ledger.
- Server retention: 30 days; dedicated daily cron. No existing rows were deleted or altered.
- Migration `20260908134026_client_flow_diagnostics` deployed and production history verified. Initial transaction test was rolled back; post-deploy tests were also rolled back, leaving zero synthetic events.

## Verification

- Android app debug Kotlin compile passed. Core data: 95 tests; analysis: 30; paywall: 8. All passed, none skipped.
- iOS simulator compilation passed; `RiskDetectedSnapshots` / `ClientFlowEventsTests`: 3 passed. Tests use isolated UserDefaults and a fake sender (no actual purchase/analysis).
- `node --test scripts/client_flow_contract_test.mjs`: 5 passed, including cross-platform/database allowlist parity and dialog-safe billing guard.
- `scripts/client_flow_events_transaction_test.sql`: role grants, owner insert, cross-owner denial/read isolation, invalid stage rejection, retry dedup. Run only inside BEGIN/ROLLBACK with an existing auth user. Tested before and after deployment.
- Supabase advisor produced no finding for the new table. Existing unrelated private-table/policy and auth warnings remain; no broad security-settings changes made.
- `git diff --check` passed.

## Release caveats

- No release archive, store upload, version bump, or review submission in this task. Installed store builds cannot emit these newly added events yet.
- Real Google Play payment and the reported vendor crash have NOT been reproduced end to end. A licensed Play tester checkout is still required before release.
- Android's `verifyAndroidLegalBundle` now passes against the owner-approved
  `LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json` record. The default debug and
  instrumentation compile was rerun without excluding that gate and passed.
- No changes to ATT, Meta event policy, existing release flags, free quota or subscription authority.
