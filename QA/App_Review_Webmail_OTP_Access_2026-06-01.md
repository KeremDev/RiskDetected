# App Review Fastmail OTP Access - 2026-06-01

Purpose: give Apple App Review a stable, real email OTP login path without adding a review-only bypass to the app.

## App Store Connect Fields

Use these values in `App Review Information`.

| Field | Value |
| --- | --- |
| Sign-in required | Checked |
| User name | `riskdetected.appreview@fastmail.com` |
| Password | `Email OTP login. See Notes for OTP mailbox access.` |

Do not store the real mailbox password in the repo. Paste it only into App Store Connect Notes.

## Review Detail CLI Template

After choosing the real review contact person and phone number, this can be created from CLI. Replace the placeholders locally; do not commit private phone/mailbox password values.

```bash
asc review details-create \
  --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 \
  --contact-first-name "<CONTACT_FIRST_NAME>" \
  --contact-last-name "<CONTACT_LAST_NAME>" \
  --contact-email "<CONTACT_EMAIL>" \
  --contact-phone "<CONTACT_PHONE_E164_OR_ASC_FORMAT>" \
  --demo-account-required=true \
  --demo-account-name "riskdetected.appreview@fastmail.com" \
  --demo-account-password "Email OTP login. See Notes for OTP mailbox access." \
  --notes "$(cat /tmp/riskdetected-review-notes.txt)"
```

Then re-run:

```bash
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
asc review status --app 6769498181 --output markdown
```

## Notes Template

Paste the following into the App Store Connect `Notes` field after replacing the placeholders.

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

Permissions:
Camera and photo library access are used only for field photo capture/selection, logo selection, and report/support attachments. The app does not use IDFA or advertising tracking.

Legal and privacy:
Terms: https://riskdetected.com/kullanim-kosullari
Privacy Policy: https://riskdetected.com/gizlilik
KVKK Notice: https://riskdetected.com/kvkk
Apple Standard EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

## External Setup Checklist

- Use the dedicated Fastmail review mailbox `riskdetected.appreview@fastmail.com`.
- Disable 2FA, recovery prompts, device verification friction, and temporary login locks for the review mailbox during review.
- Use the plain Fastmail address for this first submission.
- In Supabase Dashboard, confirm `Auth > Providers > Email > Email OTP Expiration = 3600` seconds.
- Keep the mailbox active and accessible for at least 2 weeks after submission.
- Rotate the mailbox password or close the mailbox after review completes.

## Smoke Test Before Submission

- Sign into webmail from an incognito/private browser session.
- Send a normal test email to `riskdetected.appreview@fastmail.com` and confirm delivery.
- Install the release candidate from TestFlight on a physical iPhone.
- Start email login with `riskdetected.appreview@fastmail.com`, open Fastmail webmail, and verify the newest OTP code in the app.
- Request a second OTP and confirm the newest email/code is the one that works.
- Confirm the Notes placeholders are replaced in App Store Connect before tapping `Add for Review`.
