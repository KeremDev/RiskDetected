# App Store Preflight Report - 2026-05-30

Scope: RiskDetected iOS app pre-submission pass using `.agents/skills/app-store-preflight-skills`.

Applicable checklists:

- `all_apps.md`
- `subscription_iap.md`
- `ai_apps.md`

Official references checked:

- Apple App Review Guidelines: https://developer.apple.com/appstore/resources/approval/guidelines.html
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple AI data sharing guideline update: https://developer.apple.com/news/?id=ey6d8onl

## Executive Summary

Code-side App Store blockers from the earlier security QA pass are closed: onboarding paywall now has real restore and legal links, account deletion is user-initiated through a JWT-protected Edge Function, privacy manifest exists, and required entitlements match app functionality.

Remaining preflight risk is mostly outside the repo: App Store Connect metadata, review notes, app privacy answers, IAP metadata, and final archive/TestFlight smoke need to be verified from ASC before submission.

## Rejections Found

None confirmed in the local code/binary preflight.

## Warnings

### [2.1] App Store Connect metadata not pulled yet

- Severity: Warning / submission blocker until verified
- Evidence: `asc` CLI is not installed on this machine, so live ASC metadata could not be inspected.
- Impact: We cannot yet verify live description, keywords, review notes, subscription metadata, privacy URL, support URL, screenshots, or IAP review state.
- Fix:
  - Install/authenticate `asc`.
  - Pull metadata for the target app/version.
  - Re-run metadata rules against the pulled canonical JSON.

Commands:

```bash
brew install asc
asc auth doctor
asc metadata pull --app "<APP_ID>" --version "<VERSION>" --dir ./metadata
```

### [2.1] Review notes need external production values

- Severity: Warning / common Information Needed risk
- Evidence: The email OTP review path is now documented in `QA/App_Review_Webmail_OTP_Access_2026-06-01.md` and referenced from `QA/App_Store_Submission_Preparation_2026-05-16.md`, but the real mailbox password and physical-device demo video URL must be pasted directly into App Store Connect Notes before submission.
- Required before submission in App Store Connect:
  - `Sign-in required` checked.
  - User name `riskdetected_appreview@fastmail.com`.
  - Password text `Email OTP login. See Notes for OTP mailbox access.`
  - Webmail URL `https://app.fastmail.com` and real mailbox password in Notes only, not committed to the repo.
  - Physical-device screen recording URL.
  - Supabase email OTP expiration confirmed as `3600` seconds / 1 hour.
- Fix: Verify the Fastmail review mailbox, verify TestFlight OTP login on a physical iPhone, then replace the password and demo video placeholders in App Store Connect Notes.

### [China Storefront / AI] Decide China mainland availability before metadata final

- Severity: Warning
- Evidence: Legal/privacy docs disclose Google Gemini/Google AI and Groq processing. The app also uses AI image/text analysis as core functionality.
- Impact: If China mainland storefront is enabled, Apple may apply China DST scrutiny to AI service references and functionality.
- Fix: Either exclude China mainland for the first release, or prepare China-specific compliance/suppression plan and remove AI provider brand references from all visible metadata/locales.

### [1.5] Support URL should be reviewed as a support destination

- Severity: Warning
- Evidence: `RDConfig.Web.supportURL` and the draft support URL point to `https://riskdetected.com`.
- Impact: If the homepage does not expose a clear support/contact path, App Review may ask for better support access.
- Fix: Prefer a dedicated support page such as `https://riskdetected.com/destek`, or ensure the homepage clearly shows support email/contact.

### [3.1.2] Confirm live App Store subscription metadata and localized prices

- Severity: Warning
- Evidence: In-app paywalls include title, period, price, restore, terms and privacy links. However, ASC subscription products/packages could not be verified without `asc`/ASC access.
- Fix:
  - Confirm Plus/Pro monthly/yearly products are approved or submitted with this app version.
  - Confirm RevenueCat package IDs map to ASC product IDs.
  - Confirm App Store Connect subscription display names, durations, trial terms, and review screenshots are complete.
  - Confirm live localized prices match in-app fallback copy.

## Passed

### [3.1.2 / 3.1.1] Subscription paywalls

- `OnboardingViewV2` wires restore to `onRestorePurchases`, not purchase.
- `OBTimelinePaywallView` exposes restore, Terms, and Privacy actions and disables controls while working.
- `InAppPaywallView` and `PaywallView` expose restore and legal links.
- Restore failure/no active subscription produces a visible message.

Relevant files:

- `App/Views/Onboarding/V2/OnboardingViewV2.swift`
- `App/Views/Onboarding/V2/Screens/OBTimelinePaywallView.swift`
- `App/Views/Paywall/InAppPaywallView.swift`
- `App/Views/Paywall/PaywallView.swift`
- `App/Services/SubscriptionManager.swift`

### [5.1.1(v)] Account deletion

- Profile UI offers "Hesabımı ve verilerimi sil".
- iOS calls `request-account-deletion`.
- `request-account-deletion` is `verify_jwt = true`.
- Privileged completion worker deletes storage/auth user via service-role path.
- UI text explains App Store subscription cancellation remains managed by Apple.

Relevant files:

- `App/Views/Profile/ProfileView.swift`
- `App/Services/AnalysisService.swift`
- `supabase/functions/request-account-deletion/index.ts`
- `supabase/functions/account-deletion-complete/index.ts`
- `supabase/config.toml`

### [5.1.1 / Privacy Manifest] Privacy manifest

- `App/PrivacyInfo.xcprivacy` exists.
- Declares `NSPrivacyTracking = false`.
- Declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.
- Static scan found UserDefaults usage; no direct required-reason disk-space/system-boot-time/file-timestamp API usage requiring additional manifest entries was found in app code.

### [4.8 / 4.0] Sign in with Apple

- Apple Sign In entitlement exists.
- App also offers Google and email OTP; Apple sign-in is present in onboarding/auth.
- Apple credential email/fullName are passed as fallbacks and app does not force a post-SIWA name/email form.

Relevant files:

- `App/RiskDetected.entitlements`
- `App/Services/AppleSignInService.swift`
- `App/Services/AuthService.swift`
- `App/Views/Auth/AuthView.swift`
- `App/Views/Onboarding/V2/Screens/OBAuthView.swift`

### [2.4.5(i)] Entitlements

Declared entitlements:

- `aps-environment`: justified by APNs/report notifications.
- `com.apple.developer.applesignin`: justified by Apple Sign In.

No unused high-risk entitlement was found.

### [5.1.1 / AI data disclosure]

- Privacy policy discloses third-party AI processing for uploaded photo/text content.
- Terms describe AI output limitations and professional-review disclaimers.
- App does not claim to replace official workplace safety inspection or professional judgment.

Relevant files:

- `App/LegalDocuments/Gizlilik-Politikasi.md`
- `App/LegalDocuments/Kullanim-Kosullari.md`
- `Legal/Gizlilik-Politikasi.md`
- `Legal/Kullanim-Kosullari.md`

### [2.5.1 / Build] Local build

Latest local simulator build passed:

```bash
xcodebuild -project RiskDetected.xcodeproj -scheme RiskDetected -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

Result: `BUILD SUCCEEDED`.

Current build settings checked:

- Bundle ID: `com.riskdetected.app`
- Version: `0.1.0`
- Build: `25`
- Device family: `1` (iPhone-only)
- App icon name: `AppIcon`
- Entitlements: `App/RiskDetected.entitlements`

## Manual App Store Connect Checklist

Before submission:

- Run the full App Review preflight gate captured in `IMPLEMENTATION_PLAN.md` before tapping `Add for Review`.
- Include repo hygiene, archive/binary, App Store Connect metadata, IAP/RevenueCat, Supabase backend, legal/privacy, physical-device TestFlight smoke and final review notes checks.
- Pull ASC metadata with `asc` and re-run metadata checks.
- Fill only the App Store Connect review notes placeholders from `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`; do not commit the real mailbox password.
- Add physical-device demo video URL.
- Confirm `riskdetected_appreview@fastmail.com` mailbox remains active for at least 2 weeks.
- Confirm Supabase email OTP expiration is `3600` seconds / 1 hour.
- Confirm ASC privacy nutrition matches `QA/App_Store_Privacy_Nutrition_2026-05-16.md`.
- Confirm privacy policy URL field is `https://riskdetected.com/gizlilik`.
- Done: App Store Connect Description includes subscription note plus Terms URL `https://riskdetected.com/kullanim-kosullari`, Privacy URL `https://riskdetected.com/gizlilik`, and Apple Standard EULA URL. Confirmed by owner on 2026-05-31.
- Confirm support URL exposes contact path.
- Confirm IAP/subscription products are attached to the app version and visible to reviewers.
- Confirm final archive privacy report includes app manifest plus third-party SDK manifests.
- Confirm App Store/TestFlight production APNs smoke with production token.
- Decide China mainland availability.

## Local Working Tree Note

At the time of this preflight, unrelated local changes are present:

- SwiftUI onboarding preview helper changes.
- Newly installed `.agents/skills/app-store-preflight-skills` files and `skills-lock.json`.

These were not treated as App Store app-code findings.
