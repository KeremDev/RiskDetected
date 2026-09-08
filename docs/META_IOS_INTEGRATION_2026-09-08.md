# Meta iOS App Events — 2026-09-08

App: `com.riskdetected.app`; Meta App ID: `2138752823371873`.
FacebookCore pinned to 18.1.1. Client Token is in the mobile Info.plist;
no App Secret is embedded. No Android or backend deployment is included.

## Implemented

| Business action | Meta events | Success boundary |
| --- | --- | --- |
| Launch/session | SDK install attribution + `fb_mobile_activate_app`, custom `first_launch` | Native app activation |
| Registration | `registration_completed`, `fb_mobile_complete_registration` | Profile ready for a newly created auth account |
| Analysis | `risk_assessment_completed`, `first_risk_analysis` | Completed result fetched; first event requires completed-analysis count of one |
| Report | `report_created` with PDF/XLSX format | Successful report registration / XLSX response |
| Free trial | `trial_started`, `StartTrial` | Validated RevenueCat purchase with trial entitlement |
| Paid subscription | `subscription_started`, `Subscribe` | Validated purchase, not restore/cancel/error |

Custom aliases are supplied as requested; optimize on the corresponding standard
event where available. Do not sum aliases and standard events together. Monetary
value is attached only to the standard event. Actual RevenueCat transaction price
is used only when its transaction ID matches; unknown price is omitted, not replaced
with list price. Trial value is zero.

Event idempotency is local, SHA256-keyed in UserDefaults. Raw account, transaction,
analysis and report IDs are not event parameters. Reinstallation removes this local
deduplication. SDK delivery is best effort, not an exactly-once business audit log.
Registration detection requires account/sign-in timestamps within one minute and
an account younger than ten minutes; delayed verification is not a guaranteed count.
Analysis completion outside the active polling flow is not server-reconciled.
Trial-to-paid conversion while the app is closed and subsequent renewals require a
separate consent-aware RevenueCat/server attribution integration; this SDK hook does
not claim to cover those server-only lifecycle events.

## Privacy and attribution

- No ATT prompt is requested anywhere; the usage-description key and translations
  were removed. Advertiser ID collection is always disabled, regardless of consent.
- `isEventDataUsageLimited=true` limits SDK event use to analytics/conversions;
  the outgoing `application_tracking_enabled` field is zero. User matching data and
  the SDK userID are cleared. This is not a claim that all SDK metadata is anonymous.
- SDK 18 reads ATT directly on iOS 17+ and ignores its tracking setter there. If a
  legacy/test installation is already ATT-authorized, this release skips SDK startup
  and explicit event calls instead of reusing that grant. Ordinary notDetermined,
  denied and restricted installations use the limited path. No prior Meta/ATT build
  was shipped to App Store users.
- SDK events without ATT do not grant permission for cross-company tracking.
- No photos, safety findings, report content, names, email or app user IDs are sent
  by these hooks. Meta still receives SDK-generated app/device metadata and an
  anonymous installation identifier; “no personal data collected” would be false.
- Automatic App Events/IAP logging and codeless AEM auto-setup are disabled to avoid
  automatic UI collection and duplicate purchase events. Explicit AEM event reporting
  remains part of FacebookCore's FBAEMKit dependency.
- SDK owns SKAdNetwork conversion reporting (`FacebookSKAdNetworkReportEnabled`).
  Do not add another conversion-value updater. An advertised-only app is not an
  Audience Network publisher: publisher `SKAdNetworkItems` lists are not added blindly.
- Auth URLs still reach existing Google/Supabase handlers after AEM forwarding.

## Verification

- Debug simulator build passed; dedicated clean iPhone 17 Pro Max / iOS 26.5 simulator.
- Release generic iOS device build passed (`CODE_SIGNING_ALLOWED=NO`); not a signed
  distribution archive. Final targeted XCTest rerun passed after transaction-price changes.
- 15 standalone ledger assertions passed.
- 4 XCTest cases passed: business-event deduplication, standard/custom subscription
  mapping without doubled monetary value, old-account registration exclusion, and
  no-ATT policy/settings verification for all four permission states.
- 25/25 localization gates passed; ATT text removed and original snapshot restored.
- Real SDK network smoke test: `first_launch` and `fb_mobile_activate_app`,
  `Flush Result: Success`; advertiser tracking, advertiser ID collection and
  application tracking all `0` in the final no-ATT runtime test,
  user-data matching dictionary empty. No synthetic purchases were sent to production.
- Events Manager Test Events still requires Facebook login on the test phone.
  Network acceptance is verified; dashboard appearance and an actual paid-install
  SKAN/AEM attribution have not been verified. Permission-state coverage is a unit
  test; real-device behavior has not been tested in this turn.

## Release status / external configuration

1. App Privacy published: Device ID, Purchase History and Product Interaction have
   Analytics and Developer Advertising purposes, linked to identity, not tracking.
   Existing other purposes and data types are retained. Final web preview shows only
   Data Linked to You; the new-purpose linkage defaults were explicitly corrected.
   Signed archive manifests were inspected: app tracking is false; vendor SDK
   capability manifest remains untouched and declares tracking capability. Runtime
   settings and network smoke test, not that capability alone, define this integration.
2. Existing TR/EN policies updated with explicit user approval on 8 September 2026.
   New approval record: docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json.
   Production web policies published and exact hashes verified. Live legal release
   gates passed; 13/13 phase-5 tests passed. Prior approval record remains untouched.
3. Meta app is unpublished. Bundle ID, App Store ID `6769498181` and manual event
   logging were saved in Meta basic settings. Verify policy/terms/deletion URLs and
   complete the Meta publish requirements before claiming campaign eligibility.
4. Validate physical-device Test Events and Meta's campaign-side iOS attribution
   configuration. Do not equate an HTTP/SDK success with attributed campaign installs.
5. Signed archive/export 2.0.3 (91) succeeded; codesign verification passed. Apple
   accepted build b26fcacc-eea9-465e-86ec-8d6aa20fab07 as VALID. Release type is
   AFTER_APPROVAL. All five locales retain live metadata except approved Whats New;
   43 ordered screenshots match the live source. See release evidence for submission.
   Do not raise the live minimum/latest-build gate before actual public release.

## Disclosure reference — approved and published in iOS-scoped wording

TR: RiskDetected, uygulama reklamlarının performansını ve uygulama içi dönüşümleri
ölçmek için Meta App Events SDK kullanır. Uygulama açılışı, kayıt, analiz tamamlama,
rapor oluşturma, deneme ve abonelik başlangıcı olayları; uygulama/cihaz bilgileri,
SDK kurulum tanımlayıcısı ve ilgili ürün, para birimi ve doğrulanmış işlem tutarı
Meta'ya iletilebilir. Saha fotoğrafları, analiz/rapor içerikleri, adınız ve e-posta
adresiniz bu entegrasyonla gönderilmez. Bu sürüm reklam kimliğini (IDFA) toplamaz ve
uygulamalar arası takip izni istemez. Meta SDK olay kullanımı analiz ve dönüşüm
ölçümüyle sınırlandırılır. Reklam kurulumu ölçümünde Apple'ın gizlilik korumalı
SKAdNetwork mekanizmasından yararlanılır; kişi bazında reklam eşleştirmesi hedeflenmez.

EN: RiskDetected uses Meta App Events to measure app advertising and in-app
conversions. Launch, registration, completed analysis, report creation, trial and
subscription events may be shared with Meta together with app/device metadata,
an SDK installation identifier, product, currency and verified transaction amount.
This integration does not send site photographs, analysis/report content, your
name or email address. This version does not collect IDFA or request cross-app
tracking permission. SDK event use is limited to analytics and conversion measurement.
Apple's privacy-preserving SKAdNetwork mechanism supports install measurement;
individual cross-app advertising matching is not the intended use.

Review must also cover applicable legal basis, recipient/transfers, retention,
withdrawal/deletion and jurisdiction-specific consent requirements. ATT alone is
not a substitute for that legal review.

References: https://github.com/facebook/facebook-ios-sdk/tree/v18.1.1
and https://developer.apple.com/app-store/user-privacy-and-data-use/
