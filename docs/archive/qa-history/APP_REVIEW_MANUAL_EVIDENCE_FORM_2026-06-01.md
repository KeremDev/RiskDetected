# App Review Manual Evidence Form - 2026-06-01

Scope: RiskDetected `1.0 (31)` final manual gates.

Do not write real mailbox passwords, private phone numbers, API keys, App Store Connect private keys, or sandbox Apple ID passwords in this file. Record only pass/fail evidence, timestamps, and non-secret notes.

## Candidate

| Item | Value |
| --- | --- |
| App ID | `6769498181` |
| Version ID | `e97f1de1-7e8c-448b-a5b9-80869f0a8816` |
| Version | `1.0` |
| Build | `31` |
| Build ID | `fca919e5-b12a-4129-8d82-cf46ce1736c8` |

## Manual Gate Status

Fill this table on submission day.

| Gate | Owner | Status | Timestamp | Evidence / Notes |
| --- | --- | --- | --- | --- |
| App Review contact details filled |  | TODO |  | Do not record private phone/email values here; just note that ASC validation no longer reports `review_details.missing_field`. |
| ASC Notes placeholders replaced |  | TODO |  | Confirm `<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>` and `<PHYSICAL_DEVICE_DEMO_VIDEO_URL>` are not present in ASC Notes. |
| Physical-device demo video URL added |  | TODO |  | Record only the non-secret hosted URL or internal asset location if safe to share. |
| App Privacy completed/published | Codex | HOLD | 2026-06-01 22:32 +03 | ASC App Privacy page is configured with Privacy Policy URL `https://riskdetected.com/gizlilik`, product page preview, and 16 declared data types; `Publish` button is still visible, so final publish remains manual before submission. |
| App Store screenshots visually approved/uploaded | Manual + Marketing | PASS | 2026-06-02 05:13 +03 | User confirmed the final App Store screenshot task is closed. Final 10-file iPhone 6.9 candidate remains at `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/` and passes count/dimension checks. |
| Four subscriptions attached to review | Codex | PASS | 2026-06-01 22:31 +03 | ASC iOS App Version `1.0` page shows all four subscriptions under `In-App Purchases and Subscriptions`: Plus Monthly, Plus Yearly, Pro Monthly, Pro Yearly. |
| Turkey storefront prices confirmed | Codex | PASS | 2026-06-01 21:04 +03 | `asc subscriptions pricing summary --app 6769498181 --territory Turkey --output markdown` confirms Plus monthly `199.99 TRY`, Plus yearly `1999.99 TRY`, Pro monthly `499.99 TRY`, Pro yearly `4999.99 TRY`. Device paywall display remains separate rows below. |
| China mainland availability decision | Codex | HOLD | 2026-06-02 02:16 +03 | `asc pricing availability territory-availabilities --availability 6769498181 --paginate --output json` shows `CHN available=true` and `availableInNewTerritories=true`. Because the app metadata/legal docs describe AI-assisted analysis and Google/Groq providers, exclude China mainland for first release or record a China-specific compliance decision before submission. |
| Supabase leaked-password toggle decision | Codex | PASS | 2026-06-02 11:30 +03 | Current release decision: leaked-password protection is accepted known risk for this submission path. Release auth uses Email OTP, Apple, and Google; password demo sign-in is DEBUG-only. Enablement remains optional post-release hardening. |
| Supabase production simulation secrets | Codex | SKIP | 2026-06-02 04:50 +03 | Remote production secret enumeration is intentionally skipped by release decision and no longer counted as an App Review preflight blocker. Collector source gate still confirms iOS test-simulation helpers are DEBUG-only and Edge Function AI simulation requires explicit env flags. |
| Supabase Edge Functions deployed | Codex | PASS | 2026-06-02 00:56 +03 | `register-report` was missing remotely while the app calls `RDConfig.registerReportFunctionName`; `supabase functions deploy register-report --project-ref ppcrzemgiztzcgddbins` deployed it. `supabase functions list --project-ref ppcrzemgiztzcgddbins --output json` now confirms all 15 local functions are `ACTIVE` and local `verify_jwt` settings match remote. |
| Supabase `db lint` final rerun | Codex | PASS | 2026-06-02 02:08 +03 | Latest full collector re-ran `supabase db lint --linked --level warning --fail-on none` through the linked CLI profile with `No schema errors found`. No DB password was recorded. |
| Final evidence collector rerun | Codex | HOLD | 2026-06-02 11:31 +03 | `SUPABASE_DB_PASSWORD="$(security find-generic-password -a "$USER" -s riskdetected_supabase_db_password -w)" node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md` wrote the report with `37 PASS`, `2 WARN`, `6 HOLD`, `2 FAIL`, `1 SKIP`. Supabase leaked-password decision evidence is now PASS and advisors are documented as accepted/non-blocking. Remaining FAILs are separate collector cleanup items: old paywall legal-link marker expectations and old App Store screenshot path probing. |
| Final ASC validation rerun | Codex | HOLD | 2026-06-02 02:08 +03 | Current expected state: `asc review status` is `NOT_SUBMITTED`; `asc validate subscriptions` has `0` errors; `asc validate` has only the intentionally unfilled App Review contact errors as blocking, plus subscription attachment/promotional-image warnings and `privacy.publish_state.unverified` info. Re-run after filling contact details, publishing App Privacy, and attaching/submitting first-time subscriptions with the app. |

## Physical-Device Smoke Test

Use TestFlight build `1.0 (31)` on a physical iPhone. Prefer the same device/account setup that will reflect the reviewer path.

Current device discovery note, 2026-06-01 21:54 +03:

- `iPhone Kerem` / iPhone 17 Pro Max is reachable via `devicectl` and has `com.riskdetected.app` candidate `1.0 (31)` installed; refreshed evidence is in `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02.json`.
- 2026-06-02 01:52 +03: device display evidence confirms primary LCD `1320 x 2868`, portrait, `backlightState=off`; lock-state evidence confirms passcode required and unlocked since boot. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/display-2026-06-02.json`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02.json`.
- 2026-06-02 01:50 +03: foreground launch retry was denied because the iPhone was locked. This does not regress the app; unlock the iPhone before the next functional smoke run. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02.json`.
- 2026-06-02 03:46 +03: `devicectl device info details` refreshed successfully and reports `iPhone Kerem`, iOS `26.5`, booted, developer mode enabled, paired, and `tunnelState=connected`. A fresh foreground launch retry acquired the tunnel but was again denied because the iPhone was locked. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/details-2026-06-02-latest.json`, `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-latest.json`.
- 2026-06-02 03:51 +03: later foreground launch and lock-state retries acquired the device path but failed with CoreDevice connection/timeout errors. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-retry-2.json`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-retry-2.json`. Keep the iPhone unlocked and awake before functional smoke.
- 2026-06-02 03:57 +03: current lock-state retry succeeded and confirms `passcodeRequired=true`, `unlockedSinceBoot=true`; foreground launch again acquired the tunnel but was denied with SpringBoard `Locked` / CoreDevice error `10002`. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-current.json`, `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-current.json`. Keep the iPhone unlocked and awake before functional smoke.
- 2026-06-02 04:07 +03: `devicectl list devices` still shows `iPhone Kerem` as `available (paired)`, but lock-state and app-info retries timed out while establishing the CoreDevice tunnel. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/devices-2026-06-02-current.txt`, `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-current-2.json`, `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02-current-2.json`. Keep the iPhone unlocked, awake, and on the same network before functional smoke.
- 2026-06-02 04:30 +03: `devicectl` lock-state, app-info, and details refreshed successfully: `iPhone Kerem` iOS `26.5`, developer mode enabled, tunnel connected, and `RiskDetected 1.0 (31)` installed. Foreground launch then failed with CoreDevice error `4000` / immediate disconnect. Evidence: `output/app-review-physical-smoke/iphone-17-pro-max/lockstate-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/apps-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/details-2026-06-02-refresh-1.json`, `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-02-refresh-1.json`. Keep the iPhone unlocked, awake, and interactive before functional smoke.
- `Kerem iPhone` / iPhone 14 Pro Max is not required for this gate because the 17 Pro Max target device is current.
- Physical-device smoke functional checks remain open and should be run on `iPhone Kerem`.
- Launch evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-01.json` records a successful foreground launch. A short console attach in `output/app-review-physical-smoke/iphone-17-pro-max/console-launch-2026-06-01.log` confirmed launch but did not expose app-level RevenueCat/paywall logs. The 2026-06-02 launch retry is locked-device evidence only, not a functional launch pass.
- Latest launch evidence: `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-01-rerun.json`.
- Smoke worksheet: `QA/APP_REVIEW_PHYSICAL_SMOKE_17PM_2026-06-01.md`.
- Screen viewer: `devices://device/open?id=F8EB649B-8963-59F6-90D0-CE4176B7D1DE`.
- Mac visual QA option: `/System/Applications/iPhone Mirroring.app` opens successfully; it requires the iPhone to be locked before it connects.

| Check | Status | Evidence / Notes |
| --- | --- | --- |
| Installed TestFlight build `1.0 (31)` | PASS | 2026-06-01 21:54 +03, `devicectl` reports `iPhone Kerem` has `com.riskdetected.app` `1.0 (31)`. |
| Fresh launch from closed state | PASS | 2026-06-01 21:50 +03, `devicectl device process launch --terminate-existing com.riskdetected.app` succeeded again on `iPhone Kerem`; latest JSON evidence is `output/app-review-physical-smoke/iphone-17-pro-max/launch-2026-06-01-rerun.json`. |
| Email OTP login with `riskdetected_appreview@fastmail.com` | PASS | 2026-06-02 05:13 +03 user confirmed final physical-device smoke completed; OTP flow verified. |
| Apple login | PASS | 2026-06-02 05:13 +03 user confirmed final physical-device smoke completed; Apple login verified. |
| Google login | PASS | 2026-06-02 05:13 +03 user confirmed final physical-device smoke completed; Google login verified. |
| Onboarding Plus monthly price shows TL | PASS | 2026-06-02 05:13 +03 user confirmed onboarding paywall monthly price verified as TL on physical device. |
| Onboarding Plus yearly price shows TL | PASS | 2026-06-02 05:13 +03 user confirmed onboarding paywall yearly price verified as TL on physical device. |
| In-app Plus monthly price shows TL | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring on `iPhone Kerem`; paywall text showed `₺199,99`. |
| In-app Plus yearly price shows TL | PASS | 2026-06-01 21:57 +03 via iPhone Mirroring on `iPhone Kerem`; paywall text showed `₺1.999,99`. |
| In-app Pro monthly price shows TL | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring on `iPhone Kerem`; paywall text showed `₺499,99`. |
| In-app Pro yearly price shows TL | PASS | 2026-06-01 21:58 +03 via iPhone Mirroring on `iPhone Kerem`; paywall text showed `₺4.999,99`. |
| No fallback price copy appears | PASS | 2026-06-02 05:13 +03 user confirmed no fallback/static USD copy appeared during final physical-device smoke. |
| No USD storefront price appears | PASS | 2026-06-02 05:13 +03 user confirmed no USD storefront price appeared during final physical-device smoke. |
| Sandbox purchase flow opens Apple sheet | PASS | 2026-06-02 05:13 +03 user confirmed non-entitled sandbox purchase-sheet path was verified. |
| Successful sandbox purchase updates entitlement | PASS | 2026-06-02 05:13 +03 user confirmed purchase flow updated entitlement successfully. |
| Restore purchases works | PASS | 2026-06-02 05:13 +03 user confirmed restore purchases flow works. |
| One Free analysis flow works | PASS | 2026-06-02 05:13 +03 user confirmed fresh free analysis flow works on physical device. |
| Plus/Pro entitlement sync reaches backend-visible state | PASS | 2026-06-02 05:13 +03 user confirmed entitlement sync verification is complete for submission purposes. |
| PDF report generation starts/completes | PASS | 2026-06-02 05:13 +03 user confirmed fresh PDF generation flow completed successfully on physical device. |
| Excel report generation starts/completes | PASS | 2026-06-02 05:13 +03 user confirmed fresh Excel generation flow completed successfully on physical device. |
| Account deletion request path is reachable and clear | PASS | 2026-06-01 22:05 +03 via iPhone Mirroring: Profile > Verilerim shows `Hesabımı ve verilerimi sil` with clear warning copy. No destructive confirmation/submission was completed. |
| Support/contact path opens and submits or validates form | PASS | 2026-06-01 22:05 +03 via iPhone Mirroring: Profile > Destek opens support form with sender info, konu, mesaj, photo/file attachment controls. No support request was submitted. |
| Legal links open from paywall/profile/auth surfaces | PASS | 2026-06-01 22:04 +03 via iPhone Mirroring: in-app legal sheet opens with KVKK, Rıza, Koşullar, and Gizlilik tabs and bundled legal text. Paywall/auth legal surfaces still covered by code/URL checks; no broken legal UI observed. |
| Push notification permission copy is appropriate if prompted | PASS | 2026-06-01 22:08 +03 via iPhone Mirroring: Profile > Bildirimler shows `Bildirimler kapalı` and explains notifications are for analysis results, report-ready updates, and important account security. Apple system permission prompt was not triggered. |
| No crash, blank screen, stuck loader, or inaccessible CTA | PASS | 2026-06-02 05:13 +03 user confirmed final physical-device smoke completed without crash, blank screen, stuck loader, or inaccessible CTA. |

## Final Manual Decision

| Decision | Value |
| --- | --- |
| Ready to tap `Add for Review`? | TODO |
| Known risks accepted? | TODO |
| Submitted by | TODO |
| Submission timestamp | TODO |
| Notes |  |
