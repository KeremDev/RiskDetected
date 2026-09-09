# Meta Android App Events — 2026-09-08

App: `com.riskdetectedan.app`; launcher activity:
`com.riskdetectedan.app.MainActivity`; Meta App ID: `1704205447330558`.
`facebook-core` is pinned to `18.3.0`; the App Secret is not embedded.
Android intentionally uses its own Meta app rather than the iOS Meta App ID
`2138752823371873`; the Android Client Token is checked by a manifest contract test.

## Implemented event contract

| Business action | Meta events | Success boundary |
| --- | --- | --- |
| Launch/session | SDK install attribution + `fb_mobile_activate_app`, custom `first_launch` | Production app activation |
| Registration | `registration_completed`, `fb_mobile_complete_registration` | Fresh Supabase account session (timestamps within one minute; account younger than ten minutes) |
| Analysis | `risk_assessment_completed`, `first_risk_analysis` | Terminal completed result; first event requires exactly one completed analysis |
| Report | `report_created`, parameter `format=pdf\|xlsx` | Successful server report registration / XLSX response |
| Free trial | `trial_started`, `StartTrial` | New RevenueCat purchase, owner/tier validation and backend sync all successful |
| Paid subscription | `subscription_started`, `Subscribe` | Same validated new-purchase boundary; never restore/cancel/error/already-entitled |

Custom aliases are retained for cross-platform reporting. Optimize Meta campaigns on the
corresponding standard event when one exists. Monetary value is attached only to the standard
event, so aliases and standard events must not be summed. Trial value is zero; subscription value
uses the selected Google Play package's actual price/currency and is omitted when unavailable.

Event idempotency is local and SHA-256 keyed in `SharedPreferences`. Raw account, transaction,
analysis and report identifiers are never Meta parameters. Reinstalling clears local dedupe.
SDK delivery is best effort, not an exactly-once audit trail. Renewals and conversions completed
while the app is closed require a separate consent-aware RevenueCat/server attribution path.

## Privacy and variant isolation

- SDK automatic/codeless App Events and automatic IAP logging are disabled. Explicit events are
  the only business-event source.
- Google Advertising ID collection is disabled in SDK settings. The merged manifest removes both
  classic `com.google.android.gms.permission.AD_ID` and Privacy Sandbox `AD_ID` access.
- Topics and Custom Audience permissions contributed by the SDK are removed. Privacy Sandbox
  Attribution Reporting remains because it provides aggregate/no-runtime-prompt install
  attribution analogous to the privacy-preserving iOS SKAN/AEM path.
- Limited Data Use is enabled, Meta user ID and user matching data are cleared, and no photo,
  finding, report content, name, email or Supabase identifier is sent by these hooks.
- `debug` and `qa` set Meta SDK auto-initialization to false and the service is production-only.
  Synthetic development/test activity therefore cannot pollute the production Meta dataset.

## Verification

- Dedicated ledger/event-policy tests pass: relaunch dedupe, no source-ID leakage,
  custom/standard purchase mapping without double revenue, registration age policy.
- Core data, analysis and reports unit suites pass.
- Full debug Kotlin graph compiles with Hilt after all new dependencies are wired.
- Debug manifest test passes. Release merged-manifest inspection confirms `AutoInit=true`,
  `AutoLogAppEvents=false`, advertiser-ID collection false, no advertising-ID/Topics/Custom
  Audience permissions, and aggregate Attribution Reporting retained.
- Release runtime dependency inspection contains only `facebook-core:18.3.0` plus
  `facebook-bolts:18.3.0`; Facebook Login/Share/Gaming modules are not included.
- A signed production-device network/Test Events run has not yet been performed. An SDK event
  accepted by Meta also does not by itself prove paid-campaign attribution.

## Meta dashboard Android platform values

- App status: Published
- Package name: `com.riskdetectedan.app`
- Class name: `com.riskdetectedan.app.MainActivity`
- Debug key hash: `X430ykbNxhq6IScoMtypSUgSvfE=`
- Upload-certificate key hash: `iIovphVdlimbaQgFqUuDPBFCzjE=`
- Play App Signing key hash: `WLJjBLwo5WZYSNd5BFCABU+bVn4=`
- Automatic in-app purchase logging: disabled (purchases are logged only after the
  RevenueCat/backend success boundary)
- Events Manager automatic SDK event logging: disabled
- Automatic Advanced Matching and every customer-information field: disabled
- Linked ad account: configured; Meta Required Actions: none at verification time
- Privacy policy: `https://riskdetected.com/gizlilik`
- Terms: `https://riskdetected.com/kullanim-kosullari`
- Data deletion: `https://riskdetected.com/hesap-silme`

The Play App Signing hash is the production install identity; the upload hash is retained for
directly signed/internal artifacts, and the debug hash is for local diagnostics only.

## Store/legal release gate

Before an Android build containing this SDK is sent to Play review:

1. Publish an approved Android-scoped TR/EN Meta disclosure in both the web policy and the legal
   bundle embedded in the app; regenerate the signed/checksummed legal manifests and backend
   acceptance checksum through the existing legal release process.
2. Update Google Play Data Safety for App interactions, Purchase history, and Device or other IDs
   with Analytics and Advertising or marketing purposes. Whether Meta qualifies for Google's
   service-provider sharing exception must be confirmed against the account's accepted Meta
   Business Tools/Data Processing terms; until confirmed, declaring transfer to Meta as shared is
   the conservative choice.
3. Re-run release preflight, minified bundle, merged-manifest/AAB permission scan, Play SDK Index,
   physical-device Test Events, and paid-install attribution verification.

Proposed disclosure text is intentionally not promoted into the owner-approved legal bundle by
this technical change; doing so would invalidate its approval/checksum chain without a new owner
approval record.

References:

- https://github.com/facebook/facebook-android-sdk/tree/sdk-version-18.3.0
- https://github.com/facebook/facebook-android-sdk/blob/main/facebook-core/src/main/java/com/facebook/appevents/AppEventsLogger.kt
- https://github.com/facebook/facebook-android-sdk/blob/main/facebook-core/src/main/java/com/facebook/FacebookSdk.kt
- https://support.google.com/googleplay/android-developer/answer/10787469
