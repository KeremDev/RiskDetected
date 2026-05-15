# RevenueCat TestFlight Sandbox Verification - 2026-05-15

## Scope

RevenueCat App Store integration was verified end to end through a TestFlight build and an Apple sandbox subscription purchase.

## Build

- App: RiskDetected
- Bundle ID: `com.riskdetected.app`
- TestFlight version/build: `0.1.0 (1)`
- RevenueCat SDK key path: Release/TestFlight uses App Store public SDK key from `RDConfig.Subscription.revenueCatAPIKey`.

## Purchase Result

- Purchase flow: TestFlight sandbox purchase
- Purchased product: `riskdetected_plus_monthly`
- RevenueCat event type: `INITIAL_PURCHASE`
- RevenueCat environment: `SANDBOX`
- Entitlement IDs: `[plus]`
- Event ID: `1F1E31F7-2650-44DC-8E2D-013751BFFDA3`
- App/User ID: `9af4b09f-8835-46f0-86db-70a1c0b09eb8`

## Supabase Verification

`subscription_events` received and processed the RevenueCat webhook event:

- `product_id`: `riskdetected_plus_monthly`
- `entitlement_ids`: `[plus]`
- `processed_at`: populated

`user_subscriptions` was updated:

- `tier`: `plus`
- `status`: `active`
- `product_id`: `riskdetected_plus_monthly`
- `entitlement_id`: `plus`
- `current_period_ends_at`: `2026-05-16 06:35:55+00`

`profiles` was updated:

- `email`: `kayalar.kerem21@gmail.com`
- `tier`: `plus`

## Notes

- RevenueCat dashboard test events were also verified earlier; they are logged with `user_id = NULL` when RevenueCat sends fake test users.
- The first TestFlight upload required App Store icon slots. Temporary upload-safe app icons were generated from the existing RiskDetected logo. These should be replaced with final production-grade app icon artwork before App Store release.
