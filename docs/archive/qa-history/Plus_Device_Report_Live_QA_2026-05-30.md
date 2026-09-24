# Plus Device Report Live QA - 2026-05-30

## Scope

- Physical device: Kerem iPhone, iPhone 14 Pro Max.
- App bundle: `com.riskdetected.app`.
- Live account: `plus@riskdetected.app`.
- User id: `2a2043a2-df8b-410e-8882-4cffe3ed2b94`.

## Result

- PASS: User signed in on the physical device.
- PASS: Live subscription row is active Plus:
  - `tier=plus`
  - `status=active`
  - `product_id=riskdetected_plus_monthly`
  - `entitlement_id=plus`
  - `environment=qa`
  - `source=manual_qa`
- PASS: User created a standard PDF report from the device.
- PASS: New report metadata was written to `public.reports`.
- PASS: Report ready push event was created.
- WARN: Push delivery was skipped with `no_active_device_tokens`.

## New Report

- Report id: `6440bdc4-bcd6-476d-8dfc-3af616731846`
- Analysis id: `f14ba322-40ba-4778-90a6-23f36d5c4ccf`
- Document no: `F14BA322-STD-621C`
- Kind: `standard`
- Format: `pdf`
- File size: `862013`
- Created at: `2026-05-29T23:21:05.783558Z`
- Storage path: `2a2043a2-df8b-410e-8882-4cffe3ed2b94/f14ba322-40ba-4778-90a6-23f36d5c4ccf/riskdetected_genel_27_may_22_46_standard_fine_kinney_f14ba322_20260529T232104Z_621c6683.pdf`
- `report_ready_push_sent_at`: `2026-05-29T23:21:07.08Z`

## Push Event

- Event id: `781c0bf6-0573-45ea-ac81-a955caf155c7`
- Kind: `report_ready`
- Status: `skipped`
- Sent count: `0`
- Failure count: `0`
- Last error: `no_active_device_tokens`
- Created at: `2026-05-29T23:21:07.056458Z`
- Payload included:
  - `destination=reports`
  - `format=pdf`
  - `kind=standard`
  - `report_id=6440bdc4-bcd6-476d-8dfc-3af616731846`
  - `support_id=RD-4DEC5550`

## Device Token State

- Push token exists for the Plus demo user.
- Token environment: `sandbox`
- Platform: `ios`
- App version: `0.1.0`
- Device model: `iPhone`
- Notifications enabled: `true`
- Last registered at: `2026-05-27T22:39:11.773378Z`

## Notes

- The report flow itself is live verified for a real Plus account on a physical device.
- Push trigger creation is verified. Actual APNs delivery did not occur because the push sender found no active token for its selected APNs environment.
- Xcode-installed development builds commonly register sandbox APNs tokens; TestFlight/App Store builds use production APNs. Re-test delivery from a TestFlight build or align `APNS_ENV` with the token environment for a controlled sandbox push QA.

## Follow-up After Environment-aware Push Fix

- PASS: `send-push-notification` was updated and deployed to route tokens by their own environment.
- PASS: User created another standard PDF report from the same physical device session.
- PASS: New report metadata was written to `public.reports`.
- PASS: `report_ready` notification event was delivered through APNs sandbox.
- PASS: The sandbox device token `last_success_at` was updated.

### Delivered Report

- Report id: `e32ac161-378c-49c8-a978-d1a3f44a21ea`
- Analysis id: `e045652b-e834-47e4-a442-1c451d65ded5`
- Document no: `E045652B-STD-4E70`
- Kind: `standard`
- Format: `pdf`
- File size: `852956`
- Created at: `2026-05-29T23:30:36.138162Z`
- `report_ready_push_sent_at`: `2026-05-29T23:30:38.586Z`

### Delivered Push Event

- Event id: `a9a9df68-0459-4c37-bb01-cc096c2116d2`
- Kind: `report_ready`
- Status: `sent`
- Sent count: `1`
- Failure count: `0`
- Last error: `null`
- Sent at: `2026-05-29T23:30:37.66Z`
- Token environment: `sandbox`
- Token `last_success_at`: `2026-05-29T23:30:37.66Z`

## TestFlight Production Purchase / Push Smoke

- PASS: New production user signed in.
- PASS: User purchased annual Plus.
- PASS: User ran an analysis.
- PASS: User created a risk analysis PDF report.
- PASS: User enabled notification permission before creating the standard report.
- PASS: User created a standard PDF report from the same analysis.
- PASS: Production APNs token was registered.
- PASS: Standard report `report_ready` push was accepted by APNs.
- PASS: Foreground notification suppression was fixed in code.
- PASS: New TestFlight build showed the `Rapor Hazır` foreground banner on device and triggered vibration.

### Production User

- Email: `kayalar.kerem@gmail.com`
- User id: `1600e01c-3395-43f2-8f28-66db3306ec4c`

### Production Reports

- Risk analysis report:
  - Report id: `c4049862-2263-45c3-b14f-da752e2d737d`
  - Analysis id: `c242186c-d180-4215-8261-df972cab9c78`
  - Kind: `riskAnalysis`
  - Format: `pdf`
  - Created at: `2026-05-29T23:43:16.974408Z`
  - Push event status: `skipped`
  - Push event last error: `no_active_device_tokens`
  - Note: notification permission/token was not available yet.
- Standard report:
  - Report id: `3410c5c2-dc1a-44e7-93fa-6acd6b8859a6`
  - Analysis id: `c242186c-d180-4215-8261-df972cab9c78`
  - Kind: `standard`
  - Format: `pdf`
  - File size: `1057782`
  - Created at: `2026-05-29T23:43:54.021583Z`
  - `report_ready_push_sent_at`: `2026-05-29T23:43:55.194Z`

### Production Push Event

- Event id: `e4e526de-b350-4e1d-a267-258bdb377439`
- Kind: `report_ready`
- Status: `sent`
- Sent count: `1`
- Failure count: `0`
- Last error: `null`
- Sent at: `2026-05-29T23:43:54.393Z`

### Production Token

- Token id: `8592a94e-6360-4659-b90a-6005aa79fd83`
- Environment: `production`
- Notifications enabled: `true`
- Last registered at: `2026-05-29T23:43:43.736718Z`
- Last success at: `2026-05-29T23:43:54.393Z`

### Root Cause

- Backend delivery was successful for the standard report.
- The app's `UNUserNotificationCenterDelegate.willPresent` returned `[]` for `analysis_complete` and `report_ready`, which suppresses foreground banners while the app is open.
- `NotificationService.swift` now returns `[.banner, .sound, .badge]` for foreground notifications.
- Device build after the fix succeeded.

### TestFlight Visual Re-Smoke

- User created a new TestFlight build with the foreground notification fix.
- Same production user created another standard report from the same analysis.
- Expected notification appeared on device:
  - Title: `Rapor Hazır`
  - Body: `Risk raporun oluşturuldu, raporlar bölümünden inceleyebilirsin.`
- Vibration was observed.
- Sound was not expected/confirmed because the device was muted.
