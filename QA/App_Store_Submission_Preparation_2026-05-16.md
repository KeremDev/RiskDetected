# App Store Submission Preparation - 2026-05-16

This is the working App Store Connect entry pack for RiskDetected.

Official references checked:

- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Age ratings: https://developer.apple.com/help/app-store-connect/reference/age-ratings
- App metadata reference: https://developer.apple.com/help/app-store-connect/reference/app-information

## 1. Capability / Binary Check

### Current Bundle

| Field | Value |
| --- | --- |
| Bundle ID | `com.riskdetected.app` |
| Display name | `RiskDetected` |
| Version | `0.1.0` |
| Build | `2` |
| Deployment target | iOS 16.0 |
| Category | Productivity |
| Device family | iPhone-only |

Decision: first release is iPhone-only. The Xcode target previously included iPad (`1,2`), which would require iPad screenshots and iPad UI review. It has been changed to `TARGETED_DEVICE_FAMILY = 1`. Add iPad later only after iPad-specific QA/screenshots.

### Capabilities

| Capability | Status | App Store Connect / Apple Developer Action |
| --- | --- | --- |
| Sign in with Apple | Enabled in entitlements | Keep enabled for `com.riskdetected.app`; verify App ID capability in Apple Developer. |
| Push Notifications / APNs | Enabled in entitlements | Keep enabled only if APNs production key/secrets are configured before release. Archive embedded entitlement should show production APNs for App Store distribution. |
| In-App Purchase | Enabled in project system capabilities | Products/subscriptions must be created and approved in App Store Connect; RevenueCat products must match. |
| Associated Domains | Not enabled | No action unless universal links are added later. |
| Background Modes | Not enabled | No action. Push delivery does not require background mode for the current notification design. |
| Camera | Permission string present | OK. Used for field photo capture. |
| Photo Library | Permission string present | OK. Used for selecting analysis photos/logo/support attachments. |
| ATT / Tracking | Not present | OK. Tracking answer should be No. |

### Current Permission Copy

- Camera: `RiskDetected, saha fotoğrafları çekerek iş güvenliği analizi yapabilmek için kamerana ihtiyaç duyar.`
- Photo Library: `Saha fotoğraflarını analiz edebilmek için galerine erişim izni gerekiyor.`

These are acceptable for review because they explain the concrete feature need.

### Privacy Manifest

`App/PrivacyInfo.xcprivacy` exists:

- `NSPrivacyTracking = false`
- Required Reason API:
  - `NSPrivacyAccessedAPICategoryUserDefaults`
  - Reason: `CA92.1`

Final archive check: in Xcode Organizer, inspect Privacy Report and embedded entitlements. Third-party SDK manifests for GoogleSignIn and RevenueCat should be visible in the archive report.

## 2. App Store Metadata Draft

### App Information

| Field | Entry |
| --- | --- |
| Name | `RiskDetected` |
| Subtitle | `Yapay zeka destekli İSG asistanı` |
| Category | Productivity |
| Secondary category | Business |
| Content rights | No third-party copyrighted content unless screenshots include user-provided/demo images. |
| Sign-in requirement note | App offers Apple, Google and email OTP sign-in. |

### Promotional Text

Saha fotoğrafı veya metniyle iş güvenliği risklerini analiz et, bulguları önceliklendir ve PDF/Excel raporlarını hızlıca hazırla.

### Description

RiskDetected, sahada iş güvenliği uygunsuzluklarını daha hızlı fark etmeye ve raporlamaya yardımcı olan yapay zeka destekli bir İSG asistanıdır.

Fotoğraf veya metin üzerinden analiz başlatabilir, tespit edilen bulguları Fine-Kinney ve 5x5 Matris yaklaşımıyla değerlendirebilir, raporlarınızı PDF veya Excel olarak oluşturabilirsiniz.

Öne çıkanlar:

- Fotoğraf ve metin ile risk analizi
- Odaklı analiz seçenekleri
- Fine-Kinney ve 5x5 risk değerlendirme çıktıları
- PDF ve Excel rapor oluşturma
- Rapor arşivi, indirme ve paylaşım
- Profil bilgileriyle hazırlayan, belge no, firma bilgisi ve logo varsayılanları
- KVKK ve gizlilik odaklı veri yönetimi

RiskDetected, İSG uzmanları ve saha ekipleri için destekleyici bir araçtır. AI analizleri profesyonel değerlendirme yerine geçmez; nihai karar ve saha kontrolü yetkili uzman tarafından yapılmalıdır.

### Keywords

`İSG, iş güvenliği, risk analizi, Fine Kinney, 5x5 matris, saha denetimi, rapor, PDF, Excel, KKD, yapay zeka`

### Support / Legal URLs

| Field | URL |
| --- | --- |
| Marketing URL | `https://riskdetected.com` |
| Support URL | `https://riskdetected.com` or `mailto:info@riskdetected.com` if App Store Connect accepts mailto for the field; website URL is safer. |
| Privacy Policy URL | `https://riskdetected.com/gizlilik` |
| Terms URL | `https://riskdetected.com/kullanim-kosullari` |
| KVKK URL | `https://riskdetected.com/kvkk` |

Important: public website legal pages are live and ready for App Store Connect entry.

### Review Notes

Use this in App Review notes:

RiskDetected is a Turkish occupational safety assistant. The app lets users upload or capture field photos, enter text, run AI-assisted risk analysis, and generate PDF/Excel reports. AI output is advisory and the app includes legal/privacy notices in the profile/legal center.

Test account:

- Email: `<provide review test email>`
- OTP: `<explain OTP mailbox access or provide a pre-authenticated TestFlight account path>`

Purchases:

- Plus and Pro are auto-renewable subscriptions through App Store / RevenueCat.
- If sandbox purchase needs testing, use App Store sandbox tester.

Notes:

- Camera/photo access is used only for analysis image capture/selection.
- No advertising tracking or IDFA use.
- If push is enabled, notifications are account/report events only.

## 3. Screenshot / App Preview Plan

Because the app is now iPhone-only, prepare iPhone screenshots only. App preview video is optional; screenshots are required.

Recommended screenshot sizes to prepare:

- 6.9-inch iPhone display set for current large devices.
- If App Store Connect asks for additional fallback sizes, also prepare 6.5-inch and 5.5-inch sets.

Recommended screenshot sequence:

1. Home / scan start: photo + text analysis entry, quota card, recent findings.
2. Odaklı Analiz: focus selection with Pro/Plus locked states visible.
3. Analysis result: risk score, findings, Fine-Kinney/5x5 summary.
4. Report creation: Standard / Risk Analysis / PDF / Excel settings.
5. Reports archive: saved PDF/XLSX rows, search/filter and share/download affordance.
6. Paywall: Plus/Pro plan comparison and trial CTA.

Screenshot rules:

- Use demo data, not real workplace/customer photos.
- Do not show personal email, phone, real names, tokens, support IDs, or production company data.
- Avoid showing violent injury/gore. Use neutral workplace safety scenes.
- Keep Turkish UI text consistent with the release language.
- If adding captions on top of screenshots, keep them truthful and do not imply guaranteed legal compliance or guaranteed AI accuracy.

Suggested app preview video, optional:

- 15-30 seconds.
- Flow: upload/select photo -> AI result -> report creation -> share/export.
- No mention of guaranteed compliance; use "destek olur", "hızlandırır", "önceliklendirir".

## 4. Privacy Nutrition Form

Use `QA/App_Store_Privacy_Nutrition_2026-05-16.md` as the detailed source of truth.

Summary answer:

- Tracking: No
- Data linked to user: Yes
- Data not linked to user: No separate anonymous analytics pipeline currently

Select these collected data types:

- Contact Info: Name, Email Address, Phone Number, Other User Contact Info
- Sensitive Info: Sensitive Info
- User Content: Photos or Videos, Customer Support, Other User Content
- Identifiers: User ID, Device ID
- Purchases: Purchase History
- Usage Data: Product Interaction, Other Usage Data
- Diagnostics: Performance Data, Other Diagnostic Data
- Location: Coarse Location, conservatively, because server/security logs may include IP-derived coarse location even though the app does not request device location permission

Do not select:

- Precise Location
- Contacts
- Browsing History
- Search History
- Advertising Data
- Payment Info / Credit Info
- Health & Fitness
- Audio Data

Purposes:

- App Functionality
- Product Personalization where profile/report defaults or user-entered content customize output
- Analytics for usage/performance/diagnostic logs

Do not select:

- Third-Party Advertising
- Developer's Advertising or Marketing
- Other Purposes

## 5. Age Rating

Recommended target rating: 4+ if the questionnaire accepts the current answers.

Suggested questionnaire answers:

| Category | Answer |
| --- | --- |
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Contests | No |
| Gambling | No |
| Unrestricted Web Access | No |
| User-generated content | Yes, if Apple asks whether users can submit/upload content; mitigation: content is private to the account and used for analysis/reporting, not publicly shared. |

Important nuance: workplace photos can theoretically contain injuries or sensitive scenes, but the app does not present a public feed and does not intentionally provide medical/treatment content. If App Store Connect asks about "User Generated Content", answer honestly and document moderation/privacy controls in review notes if needed.

## 6. Current Blockers Before Submit

1. Done: Public website legal URLs are live:
   - `https://riskdetected.com/gizlilik`
   - `https://riskdetected.com/kullanim-kosullari`
   - `https://riskdetected.com/kvkk`
2. Archive / Organizer signing check:
   - Done: local control archive created at `/tmp/RiskDetectedCheck.xcarchive`.
   - Done: bundle id is `com.riskdetected.app`, version `0.1.0`, build `2`.
   - Done: `TARGETED_DEVICE_FAMILY = 1` and the control archive app `UIDeviceFamily` is iPhone-only.
   - Done: app root `PrivacyInfo.xcprivacy` is included in the new control archive.
   - Done: GoogleSignIn and RevenueCat privacy manifests are included in the archive bundles.
   - Done: Debug build setting keeps `APS_ENVIRONMENT = development`; Release build setting now uses `APS_ENVIRONMENT = production`.
   - Done: manual `CODE_SIGN_IDENTITY` overrides were removed so Xcode automatic signing can choose the correct certificate/profile pair. Forcing `Apple Distribution` while Xcode only had a development managed profile caused the "conflicting provisioning settings" Archive error.
   - Done: post-fix local archive succeeded at `/tmp/RiskDetectedArchiveAfterSigningFix.xcarchive`.
   - Done: final Archive / Xcode Organizer check completed by owner.
   - Done: final archive verification covered embedded entitlements, APNs production, distribution signing, privacy report, and GoogleSignIn / RevenueCat privacy manifests.
3. Done: App Store Connect subscription products match RevenueCat:
   - Plus monthly/yearly
   - Pro monthly/yearly
4. Done: Subscription validation checks completed:
   - product IDs match between App Store Connect and RevenueCat.
   - Plus monthly/yearly products are linked to the Plus entitlement.
   - Pro monthly/yearly products are linked to the Pro entitlement.
   - active offering includes the expected packages.
   - TestFlight purchase, restore, expiration and downgrade checks are complete.
5. Done: TestFlight paywall USD display was handled in-app; when StoreKit/RevenueCat returns USD in a Turkish context, the paywall falls back to the configured TL display prices while purchases still use the real App Store package.
6. Enter/confirm the App Store privacy nutrition form in App Store Connect from the prepared draft.
7. APNs production secrets/device test should be done if notifications remain enabled for release.
8. Create final App Store screenshots from clean demo data.
9. Provide App Review test account and OTP access plan.
10. Optional: prepare a 15-30 second App Preview video.

## 7. Local Verification Completed

- Entitlements inspected.
- Info.plist inspected.
- App icon set inspected; required iOS marketing 1024 icon exists.
- Privacy manifest inspected.
- Xcode target changed to iPhone-only for first release.
