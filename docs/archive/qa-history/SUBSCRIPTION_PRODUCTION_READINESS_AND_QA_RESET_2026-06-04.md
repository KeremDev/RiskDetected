# RiskDetected Subscription Production Readiness and Internal Test Reset

Date: 2026-06-04

## Executive Summary

The D1-D12 subscription run proved the production subscription chain only works reliably when the visible app, bundle id, RevenueCat App Store key, offering, and Supabase project all point to the same real product lane.

The user-facing development workflow is now:

- One visible app: `RiskDetected`.
- One visible Xcode scheme: `RiskDetected`.
- Bundle id: `com.riskdetected.app`.
- Display name: `RiskDetected`.
- App Store Connect app: the real RiskDetected app.
- RevenueCat key: production App Store `appl_...` key.
- RevenueCat offering: `default`.
- Supabase: production Supabase.

Production safety rule to preserve:

- Apple purchase sheet success alone must never unlock Plus or Pro.
- Local RevenueCat SDK state alone must never unlock Plus or Pro.
- Paid access opens only after backend verification through RevenueCat and Supabase agrees on the paid tier.

Internal TestFlight convenience:

- During internal TestFlight only, the same `RiskDetected` app can show a manual `Temiz test başlangıcı` tool under Profile settings.
- This tool clears local app/session/subscription cache so repeated real-device sandbox tests are less polluted by old app state.
- It does not clear Apple Sandbox purchase history or active Apple subscription state. That still requires Apple Developer settings, App Store Connect, or a new sandbox tester.

## Current Todo Status - 2026-06-05

User-reported completed items from the latest TestFlight readiness list:

- [x] New Internal TestFlight build produced/uploaded/installed for the single visible `RiskDetected` app lane.
- [x] Subscription smoke test completed for the current TestFlight flow.
- [x] Apple Sandbox operational blocker handled enough to continue testing.
- [x] RevenueCat/Supabase subscription evidence captured for the completed purchase/upgrade flow.

Remaining active items:

- [x] Re-verify the `analyze` backend function so the app no longer returns `Requested function was not found` in the production App Review/Internal TestFlight lane.
  - 2026-06-05: Production `analyze` is `ACTIVE`, `verify_jwt=false`, version `97`; `process-analysis-jobs` is `ACTIVE`, `verify_jwt=false`, version `9`.
  - No production deploy was needed. The earlier function-not-found evidence came from the legacy QA Supabase lane, where `analyze` and `process-analysis-jobs` are missing.
  - Manual current TestFlight smoke passed: a normal Free analysis completed and opened successfully.
  - Evidence: `QA/ANALYZE_EDGE_FUNCTION_READINESS_2026-06-05.md`.
- [ ] Prepare App Review cleanup by switching `RiskDetected` archive configuration from `InternalTestFlight` back to `Release`.
- [ ] Run Release binary/config scan and confirm internal reset tools are absent.
- [ ] Complete App Store Connect manual submission items: contact fields, App Privacy publish/verify, review notes, demo video URL, subscription attachment, and China mainland availability decision.
- [ ] Run final production smoke tests before App Review submission.

## D1-D12 Findings

| Scenario | Result | Learning |
| --- | --- | --- |
| D1 | Blocked | Simulator was not enough for real App Store subscription receipt testing. Real tests should use physical device or TestFlight. |
| D2 | Blocked | A separate QA bundle did not match the App Store product chain. Real subscription tests must use `com.riskdetected.app`. |
| D3 | Pass | `com.riskdetected.app` plus the matching App Store RevenueCat key loaded the four production products. |
| D4 | Blocked | Physical XCUITest runner trust blocked automation, but manual device testing stayed valid. |
| D5 | Pass | Attempting Plus while Pro was active stayed safe; downgrade/conflict was not counted as purchase success. |
| D6 | Pass | Restore saw device Pro but backend Free; app failed closed and did not unlock paid. |
| D7 | Pass | SDK and backend mismatch stayed safe. Backend verification remained authoritative. |
| D8 | Incomplete | Evidence before Supabase user/customer id exists is not useful. Capture after user id is known. |
| D9 | Pass | Clean sandbox state completed Plus yearly purchase, restore, and Free negative control. |
| D10 | Pass | The same sandbox tester can cover Plus-to-Pro upgrade when state is known and managed. |
| D11 | Pass | Paid users may not have a paywall route, so Profile restore entry must remain in production. |
| D12 | Pass | Pro backend gate and Pro canvas selection passed. Analyze function-not-found is a separate backend deploy issue. |

## Final Workflow Decision

There will not be a second visible app for the user to choose.

Internal TestFlight:

- Xcode scheme picker: `RiskDetected`.
- Archive configuration: `InternalTestFlight`.
- Bundle id and display name remain production.
- Production Supabase, production RevenueCat App Store key, and production offering are used.
- The only extra behavior is the manual internal reset tool.

App Review:

- Xcode scheme picker: `RiskDetected`.
- Archive configuration: `Release`.
- The reset tool is not compiled.
- Normal restore and subscription management stay available.
- New build number is produced after the reset tool is removed from the archive config.

## RevenueCat Decisions

- Production/App Review/Internal TestFlight builds use only the App Store `appl_...` key tied to `com.riskdetected.app`.
- Test Store keys are not part of the user-visible TestFlight/App Review lane.
- `default` remains the production offering.
- Products remain:
  - `riskdetected_plus_monthly`
  - `riskdetected_plus_yearly`
  - `riskdetected_pro_monthly`
  - `riskdetected_pro_yearly`
- Plus products map to entitlement `plus`.
- Pro products map to entitlement `pro`.
- Restore behavior should remain `Transfer if there are no active subscriptions`.
- RevenueCat webhook delivery to Supabase must be verified before App Review.

## Supabase Decisions

- Internal TestFlight uses production Supabase because the goal is to test the real product chain.
- Test users created during internal TestFlight may be cleaned later through an ops script or manual admin process.
- Paid state rule stays unchanged:
  - purchase started is not paid
  - Apple sheet success is not paid
  - SDK temporary state is not paid
  - backend verified RevenueCat/Supabase state is paid
- `sync-revenuecat-subscription` remains the source of truth for app paid access.
- Webhook acceptance must be verified by checking subscription event writes.
- The analyze Edge Function must be deployed in production before App Review readiness is complete.

## Apple / App Store Connect Decisions

- Four subscriptions stay under the production App Store Connect app.
- Plus and Pro stay in one subscription group.
- Pro remains above Plus in the subscription level order.
- Sandbox purchase history cleanup is still an Apple-side operation:
  - iPhone Settings > Developer > Sandbox Account
  - App Store Connect sandbox tester history tools
  - or a fresh sandbox tester
- The app cannot clear Apple receipt history, active Apple subscription state, or App Store server history.

## Internal Test Reset Tool

Compile guard:

- `INTERNAL_TEST_RESET_TOOLS`
- Enabled only for the `InternalTestFlight` build configuration.
- Disabled for `Release`.
- The code is wrapped at compile time, so Release/App Review builds do not include the UI.

UI:

- Location: Profile > Ayarlar.
- Section title: `Test araçları`.
- Button: `Temiz test başlangıcı`.
- Confirmation text: `Bu işlem cihazdaki RiskDetected oturumunu ve yerel satın alma önbelleğini temizler. Apple Sandbox satın alma geçmişini temizlemez.`
- Success state returns the app to normal onboarding/registration flow.

The reset clears:

- Supabase local auth session/sign-out state.
- RevenueCat CustomerInfo cache.
- RevenueCat logged-in app user if present.
- App subscription/backend state cache.
- Onboarding completion and pending onboarding answers.
- Paywall funnel/session local state.
- Local free quota keys.
- Local diagnostics/cache used by subscription tests.

The reset does not clear:

- Production Supabase user records.
- RevenueCat dashboard subscribers.
- Apple Sandbox purchase history.
- Active Apple subscriptions.
- App Store receipt history.
- Any server-side purchase ownership.

The reset does not:

- auto-login a user
- create a fake user
- grant fake Plus/Pro
- bypass backend verification
- make a contaminated Apple sandbox account clean

## Internal TestFlight Test Plan

1. Archive the `RiskDetected` scheme with `InternalTestFlight`.
2. Upload to App Store Connect and distribute through internal TestFlight.
3. Install from TestFlight on the physical device.
4. Confirm the installed app is named `RiskDetected`.
5. Confirm Profile settings shows `Test araçları > Temiz test başlangıcı`.
6. Run onboarding normally.
7. Register/login normally and complete email verification normally.
8. With a Free user, purchase Plus yearly.
9. Confirm Apple sandbox sheet opens.
10. Confirm RevenueCat and Supabase verify Plus.
11. Close/open app and confirm Plus persists.
12. Run restore from Profile and confirm the app remains paid after backend verification.
13. Upgrade Plus to Pro and confirm Pro persists.
14. Run negative contaminated-state tests and confirm the app fails closed when backend verification does not agree.

## Clean First-Purchase Procedure

For the cleanest first-purchase test:

1. Run `Temiz test başlangıcı`.
2. Clear Apple Sandbox purchase history from Apple-side tooling.
3. Sign out/in from the sandbox account if state looks stale.
4. Restart or reinstall RiskDetected.
5. Register a new RiskDetected user normally.
6. Purchase Plus yearly.

Expected:

- No old Pro conflict.
- Apple sheet opens.
- RevenueCat returns Plus.
- Supabase returns `plus/active` or `plus/trialing`.
- App shows Plus only after backend verification.

## App Review Cleanup Plan

When the user says App Review is ready:

1. Change `RiskDetected` scheme archive configuration from `InternalTestFlight` to `Release`.
2. Confirm `Release` has no internal reset compile flag.
3. Confirm Profile settings does not show `Test araçları`.
4. Confirm the reset button is absent.
5. Confirm no auto-login or fake-user path exists.
6. Confirm no local StoreKit config is attached to the main scheme.
7. Confirm bundle id is `com.riskdetected.app`.
8. Confirm display name is `RiskDetected`.
9. Confirm production Supabase URL and production RevenueCat App Store key.
10. Confirm offering is `default`.
11. Run Release binary/string scan for internal reset, old QA, and test-store markers.
12. Produce a new build number and archive the App Review candidate.

## App Review Acceptance Tests

- Reset UI absent.
- Profile restore present.
- Paid users can manage/restore subscriptions.
- Free negative control stays Free.
- Plus purchase succeeds.
- Plus restore succeeds.
- Plus-to-Pro upgrade succeeds.
- Backend verification gates paid access.
- RevenueCat webhook writes subscription events.
- Analyze function does not return function-not-found.

## Remaining Risks

- Internal TestFlight uses production Supabase, so test users and test subscription records will exist in production systems until cleaned.
- Apple Sandbox state can still return old active subscriptions if Apple-side history is not cleared.
- RevenueCat dashboard may contain sandbox data in the production app. This is acceptable for internal TestFlight evidence but should be understood when reading analytics.
- Analyze backend deploy remains a separate App Review readiness item.
