# App Store Review Notes - 2026-06-02

Scope: RiskDetected `1.0 (31)` App Review candidate.

This is a copy-ready App Store Connect Notes draft with placeholders for secrets and private assets. Do not commit the real mailbox password, private contact values, OTP codes, sandbox Apple ID passwords, or private video URLs unless they are explicitly safe to publish.

## App Review Information

| Field | Value |
| --- | --- |
| Sign-in required | Checked |
| User name | `riskdetected.appreview@fastmail.com` |
| Password | `Email OTP login. See Notes for OTP mailbox access.` |

## Notes

Paste the following into App Store Connect `Notes` only after replacing both placeholders.

```text
RiskDetected is a Turkish occupational safety assistant. The app lets users upload or capture field photos, enter text, run AI-assisted risk analysis, prioritize findings, and generate PDF/Excel reports. AI output is advisory and does not replace a qualified occupational safety professional's final field assessment.

Reviewer login:
1. Open the app.
2. Choose email login and enter riskdetected.appreview@fastmail.com.
3. Open https://app.fastmail.com.
4. Sign in with the mailbox credentials below.
5. Use the latest OTP email/code in the app.
6. If the code expires, request a new code from the app and use the newest email.

Review mailbox:
Webmail URL: https://app.fastmail.com
Mailbox username: riskdetected.appreview@fastmail.com
Mailbox password: <PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>

OTP validity:
Email OTP is configured for 3600 seconds / 1 hour in Supabase Auth > Providers > Email > Email OTP Expiration.

Physical-device demo video:
<PHYSICAL_DEVICE_DEMO_VIDEO_URL>

External services:
The app uses Supabase for authentication, database, storage, and Edge Functions; RevenueCat/App Store for subscription entitlement and purchases; Google Gemini/Google AI with possible Groq-compatible fallback for AI analysis; Apple/Google sign-in where selected by the user; and APNs for account/report notifications.

Regional differences:
The first release is Turkish-first. No region-specific test account behavior is required for App Review. Before submission, confirm the China mainland availability decision in App Store Connect: either China mainland is excluded for the first release, or a China-specific compliance decision is recorded because the app uses AI-assisted analysis and Google/Groq providers.

Regulated industry documentation:
RiskDetected is an occupational safety documentation and risk-analysis assistant, not a medical, financial, gambling, insurance, or legal advisory app. No regulated-industry license is required for App Review. AI outputs are advisory and the final professional field assessment remains the user's responsibility.

Subscriptions:
Plus and Pro are auto-renewable subscriptions through App Store in-app purchase. Purchases are processed by Apple, and entitlement state is synced through RevenueCat/Supabase. If purchase testing is needed, please use Apple sandbox purchase flow.
RevenueCat is used only for App Store subscription entitlement management. The app does not request App Tracking Transparency permission, does not access IDFA, does not link AdSupport.framework, and does not use RevenueCat attribution APIs.

Permissions:
Camera and photo library access are used only for field photo capture/selection, logo selection, and report/support attachments. The app does not use IDFA or advertising tracking.

Legal and privacy:
Terms: https://riskdetected.com/kullanim-kosullari
Privacy Policy: https://riskdetected.com/gizlilik
KVKK Notice: https://riskdetected.com/kvkk
Apple Standard EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## Placeholder Checklist

Before tapping `Add for Review`, confirm in App Store Connect only:

- `<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>` is replaced with the real review mailbox password.
- `<PHYSICAL_DEVICE_DEMO_VIDEO_URL>` is replaced with the final physical-device smoke/demo video URL.
- The review mailbox can be opened from a fresh/private browser session.
- The newest email OTP for `riskdetected.appreview@fastmail.com` works on the physical release candidate.
- No private password or OTP value is written into repo files.
