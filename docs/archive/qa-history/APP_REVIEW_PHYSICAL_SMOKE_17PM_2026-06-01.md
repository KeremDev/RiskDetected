# App Review Physical Smoke - iPhone 17 Pro Max - 2026-06-01

Scope: RiskDetected `1.0 (31)` on physical device `iPhone Kerem`.

Do not record OTP codes, sandbox passwords, mailbox passwords, private phone numbers, API keys, or Apple ID passwords in this file.

## Device

| Item | Value |
| --- | --- |
| Device | `iPhone Kerem` |
| Model | `iPhone 17 Pro Max` |
| OS | `iOS 26.5` |
| Device ID | `F8EB649B-8963-59F6-90D0-CE4176B7D1DE` |
| Screen | `1320 x 2868` |
| App | `com.riskdetected.app` |
| Candidate | `1.0 (31)` |
| Screen viewer | `devices://device/open?id=F8EB649B-8963-59F6-90D0-CE4176B7D1DE` |
| Mac mirror app | `/System/Applications/iPhone Mirroring.app` (`com.apple.ScreenContinuity`) |
| Latest device refresh | 2026-06-02 04:30 +03 |

## Already Verified

| Check | Status | Evidence |
| --- | --- | --- |
| Candidate installed | PASS | `devicectl` reported `RiskDetected com.riskdetected.app 1.0 31`; refreshed on 2026-06-02 01:52 +03. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02.json`. |
| Device details refresh | PASS | 2026-06-02 03:46 +03: `devicectl device info details` reports `iPhone Kerem`, iOS `26.5`, booted, developer mode enabled, paired over local network, and `tunnelState=connected`. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/details-2026-06-02-latest.json`. |
| Display/lock readiness | PASS | 2026-06-02 01:52 +03: `devicectl` display info reports primary LCD `1320 x 2868`, portrait, `backlightState=off`; lock-state info reports `passcodeRequired=true` and `unlockedSinceBoot=true`. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/display-2026-06-02.json`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02.json`. |
| Fresh foreground launch | PASS | `devicectl device process launch --terminate-existing com.riskdetected.app` succeeded again on 2026-06-01 21:50 +03. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-01-rerun.json`. |
| Locked launch retry | EXPECTED BLOCKED | 2026-06-02 03:46 +03: a fresh `devicectl device process launch --terminate-existing com.riskdetected.app` retry acquired the device tunnel but failed because SpringBoard denied foreground launch while the physical device was locked. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-latest.json`. Unlock the iPhone before the next functional smoke run. |
| Later device retry | EXPECTED BLOCKED | 2026-06-02 03:51 +03: another foreground launch retry acquired the tunnel but failed with CoreDevice connection error `4000`; a lock-state retry timed out with CoreDevice error `1010`. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-retry-2.json`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-retry-2.json`. Keep the iPhone unlocked and awake before the next functional smoke run. |
| Current launch retry | EXPECTED BLOCKED | 2026-06-02 03:57 +03: lock-state retry succeeded and reports `passcodeRequired=true`, `unlockedSinceBoot=true`; foreground launch again acquired the tunnel but failed with CoreDevice error `10002` / SpringBoard `Locked`. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-current.json`, `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-current.json`. Unlock and keep the iPhone awake before functional smoke. |
| Current tunnel retry | EXPECTED BLOCKED | 2026-06-02 04:07 +03: `devicectl list devices` still shows `iPhone Kerem` as `available (paired)`, but lock-state and app-info retries both timed out while establishing the CoreDevice tunnel. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/devices-2026-06-02-current.txt`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-current-2.json`, `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02-current-2.json`. Keep the iPhone unlocked, awake, and on the same network before functional smoke. |
| 04:30 device refresh | EXPECTED BLOCKED | 2026-06-02 04:30 +03: `devicectl` lock-state, app-info, and details refreshed successfully; device is `iPhone Kerem` iOS `26.5`, developer mode enabled, tunnel connected, and `RiskDetected 1.0 (31)` installed. Foreground launch then failed with CoreDevice error `4000` / immediate disconnect. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/details-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-refresh-1.json`. Keep the iPhone unlocked, awake, and interactive before functional smoke. |
| ASC Turkey storefront prices | PASS | `asc subscriptions pricing summary --app 6769498181 --territory Turkey --output markdown` reported Plus monthly `199.99 TRY`, Plus yearly `1999.99 TRY`, Pro monthly `499.99 TRY`, Pro yearly `4999.99 TRY`. |
| iPhone Mirroring availability | PASS | `iPhone Mirroring` opens on the Mac. Current blocker to visual QA: the iPhone must be locked before mirroring connects. |
| In-app Plus yearly price | PASS | 2026-06-01 21:57 +03 via iPhone Mirroring: `₺1.999,99`; no USD/fallback observed. |
| In-app Plus monthly price | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring: `₺199,99`; no USD/fallback observed. |
| In-app Pro yearly price | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring: `₺4.999,99`; no USD/fallback observed. |
| In-app Pro monthly price | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring: `₺499,99`; no USD/fallback observed. |
| Purchase-sheet attempt | NOT TESTED | Current mirrored account already appears to have Pro entitlement, so Pro CTA did not provide clean free-user purchase-sheet evidence. Re-test with a non-entitled sandbox user. |
| In-app legal sheet | PASS | 2026-06-01 22:04 +03 via iPhone Mirroring: legal sheet opened with KVKK, Rıza, Koşullar, and Gizlilik tabs. |
| Support form | PASS | 2026-06-01 22:05 +03 via iPhone Mirroring: support form opened with sender info, subject, message, photo/file attachment controls. No request submitted. |
| Account deletion entry point | PASS | 2026-06-01 22:05 +03 via iPhone Mirroring: `Verilerim` screen showed `Hesabımı ve verilerimi sil` with clear warning copy. No destructive action completed. |
| Notification permission copy | PASS | 2026-06-01 22:08 +03 via iPhone Mirroring: Profile > Bildirimler explains notifications cover analysis results, report-ready updates, and important account security. System permission prompt was not triggered. |
| Report tab load | PASS | 2026-06-01 22:14 +03 via iPhone Mirroring: Report tab loaded from spinner to `9` analyses, `11` risk tables, and `14` archived files. |
| Existing PDF/risk report preview | PASS | 2026-06-01 22:14 +03 via iPhone Mirroring: archived report opened to preview with report pages visible. |
| Existing Excel report preview | PASS | 2026-06-01 22:15 +03 via iPhone Mirroring: Excel filter showed `2` files and an Excel table opened to preview. |
| Backend subscription aggregate | PARTIAL PASS | 2026-06-01 22:18 +03: Supabase linked aggregate query showed active `plus`/`pro` rows with `riskdetected_plus_monthly`, `riskdetected_pro_monthly`, and `riskdetected_pro_yearly` product IDs. This proves backend subscription sync data exists, not a user-specific assertion. |
| Supabase leaked-password advisor context | HOLD | 2026-06-01 22:25 +03: advisor still reports leaked-password protection disabled; release auth surface uses OTP/Apple/Google and password demo sign-in is DEBUG-only. Dashboard decision remains manual. |
| ASC subscription attachment | PASS | 2026-06-01 22:31 +03 read-only ASC UI check: iOS App Version `1.0` page lists Plus Monthly, Plus Yearly, Pro Monthly, and Pro Yearly under `In-App Purchases and Subscriptions`. |
| ASC App Privacy state | HOLD | 2026-06-01 22:32 +03 read-only ASC UI check: App Privacy data is configured with 16 data types and privacy URL, but `Publish` is still visible. |

## Manual Smoke Order

Use the physical device screen or the device screen viewer. Mark the matching rows in `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`.

1. Start from a clean app launch.
2. If using Mac visual QA, lock the iPhone and wait for `iPhone Mirroring` to connect. For `devicectl` foreground launch, unlock the iPhone first and keep it awake; the 2026-06-02 retries proved the device tunnel can connect but SpringBoard/CoreDevice still denies or times out while the phone is locked or not interactive.
3. Complete onboarding until the Plus paywall.
4. Confirm onboarding Plus yearly:
   - Expected ASC storefront price: `1999.99 TRY`.
   - Expected app display: `₺1.999,99`.
   - Expected monthly equivalent/copy must not show USD or fallback.
5. Toggle onboarding Plus monthly:
   - Expected ASC storefront price: `199.99 TRY`.
   - Expected app display: `₺199,99`.
   - No USD price.
6. Enter the app and open in-app Plus paywall:
   - Plus yearly expected: `₺1.999,99`.
   - Plus monthly expected: `₺199,99`.
7. Switch to Pro paywall:
   - Pro yearly expected: `₺4.999,99`.
   - Pro monthly expected: `₺499,99`.
8. Tap purchase CTA once:
   - Apple sandbox purchase sheet opens.
   - Do not complete a real charge outside sandbox.
9. Complete one sandbox purchase if appropriate:
   - Entitlement updates in the app.
   - No stuck loader or blank screen.
10. Run Restore Purchases:
   - Restore completes or shows a clear no-active-subscription message.
11. Validate authentication paths:
   - Email OTP delivery for `riskdetected_appreview@fastmail.com`.
   - Apple login.
   - Google login.
12. Run one Free analysis flow.
13. Confirm Plus/Pro entitlement sync reaches backend-visible state.
14. Generate one PDF report and one Excel report.
15. Open account deletion request path and confirm copy is clear.
16. Open support/contact and legal links from paywall/profile/auth surfaces.

## Red Flags

Do not submit until resolved if any of these appear:

- Any paywall price shows USD.
- Any paywall price falls back to static/non-store price unexpectedly.
- Product package fails to load or CTA stays disabled.
- Purchase sheet does not open.
- Restore is stuck or crashes.
- OTP login cannot be completed by reviewer account.
- Apple or Google login blocks entry.
- Analysis/report generation crashes or hangs.
- Account deletion path is missing or unclear.
- Legal links are broken.
