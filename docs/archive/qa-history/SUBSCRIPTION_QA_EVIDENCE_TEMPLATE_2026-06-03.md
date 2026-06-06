# Subscription QA Evidence Template

## Test Identity

- Scenario:
- Environment:
- Date/time:
- Tester:
- RiskDetected email:
- Supabase user ID:
- RevenueCat customer ID:
- Apple sandbox email, if Apple E2E:
- Selected product:
- Build:
- Device:

## Result

- Status: `pass` / `fail` / `blocked`
- Classification: `APP_FAIL` / `BACKEND_FAIL` / `REVENUECAT_CONFIG_FAIL` / `APPLE_SANDBOX_DEVICE_BLOCKED` / `EXPECTED_CONFLICT`
- Short conclusion:

## App Evidence

- Screenshot path:
- User-facing message:
- Home tier shown:
- Paywall tier selected:
- Support code:
- Notes:

## RevenueCat Evidence

- Customer URL:
- Active entitlements:
- Active subscriptions:
- Recent transaction/event:
- Webhook event ID/type/product:
- Notes:

## Supabase Evidence

- `profiles.tier`:
- `user_subscriptions`:
- Recent `subscription_events`:
- Recent `paywall_events`:
- Generated evidence report path:

## Expected vs Actual

Expected:

Actual:

Decision:

## Follow-up

- Owner:
- Action:
- Link:
