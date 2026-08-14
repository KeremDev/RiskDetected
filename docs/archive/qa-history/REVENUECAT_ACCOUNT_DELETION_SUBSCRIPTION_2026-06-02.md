# RevenueCat / Account Deletion Subscription Note - 2026-06-02

## Decision

Supabase Auth user deletion removes RiskDetected account data, but it does not cancel or delete the user's Apple App Store sandbox/TestFlight subscription and does not remove RevenueCat customer purchase history.

## Expected Behavior

- A deleted Supabase user can be recreated with the same email as a new Supabase UUID.
- The same Apple sandbox account may still own an active Plus/Pro App Store subscription.
- StoreKit can show "Bu ogeye abonesiniz" for the same Apple ID even when the Supabase user was deleted.
- RiskDetected must grant only the tier proven by the active App Store product ID.
- A Plus product must never upgrade the app or backend to Pro, even if stale/mixed RevenueCat entitlement data includes `pro`.

## Clean Test Rule

For a truly fresh purchase test, use a new sandbox Apple ID with no active RiskDetected subscription. If reusing an existing tester, cancel the active subscription, clear purchase history in App Store Connect when available, and sign out/sign back in on the device.

Deleting a Supabase test user alone is not a full subscription reset.

The dirty sandbox account is still useful, but only for recovery testing: StoreKit already-owned responses should not lock the paywall, and RiskDetected should only restore/sync the subscription if RevenueCat ties it to the same Supabase UUID or an anonymous RevenueCat original ID alias.

## Fix Coverage

- iOS purchase flow validates the returned RevenueCat product tier against the selected package tier.
- iOS purchase/restore flow accepts anonymous RevenueCat original IDs and rejects active subscriptions owned by a different identified RevenueCat App User ID.
- App UI does not use stale `profiles.tier` as a paid fallback when RevenueCat SDK state is free/unknown.
- Backend sync keeps product ID as the strongest tier source and refuses expected-tier mismatches.
- Successful membership push notifications remain disabled; critical billing/cancellation/expiration notifications remain allowed.
