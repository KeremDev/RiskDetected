RiskDetected 1.3.1 (build 81) is a maintenance and reliability update.

Changes in this build:

- Notification preference restoration and synchronization were improved.
- The legal-document update notice is now shown once per actual document
  revision.
- Sign-in, localization, account settings, and general stability were improved.
- The app records the signed-in account's first observed two-letter device
  locale region (for example, AU or CA) for aggregate product analytics. This
  is not App Store storefront data, is written only once, and is not used to
  select a safety terminology profile.

Reviewer login:
Use the demo account supplied in the App Review Information fields. Demo
credentials are intentionally not included in these notes or in the source
repository.

Review mailbox:
The review mailbox is supplied in the App Review Information fields.

OTP validity:
If the reviewer chooses the email OTP path, request a fresh OTP from the sign-in
screen and use the latest code delivered to the supplied review mailbox.

Physical-device demo video:
No separate video is required for normal review. The candidate build was tested
on a physical iPhone and the app flow is available directly in the submitted
build.

External services:
RiskDetected uses Supabase for authentication, database, storage and Edge
Functions, RevenueCat/StoreKit for subscriptions, Resend/Supabase email hooks
for transactional email, and AI providers for workplace-safety analysis.
AI-assisted risk analysis uses Google Gemini/Google AI with possible Groq-compatible fallback.

Regional differences:
English users explicitly select a safety terminology profile: International,
UK, US, Australian WHS, or Canadian OHS. Storefront and IP address are not used
to infer the user’s safety jurisdiction. The first observed device locale region
described above is analytics-only and never changes the user's selected safety
terminology profile.

China mainland availability decision:
China mainland is excluded for this release because the app contains
AI-assisted workplace-safety analysis and external AI provider processing.

Regulated industry documentation:
AI output is advisory. The app provides decision-support output only. It does not certify workplace compliance and does not replace a qualified occupational safety professional, workplace inspection, or legal review.

Subscriptions:
Subscriptions are managed by Apple IAP. Purchases can be restored in the app
from Profile, and localized subscription metadata is configured for the English
App Store locales.

Permissions:
Camera and photo-library access are requested so the user can capture or select
workplace photos for safety-risk analysis.

Legal and privacy:
English legal URLs:

- Privacy Policy: https://riskdetected.com/en/privacy
- Terms of Use: https://riskdetected.com/en/terms
- Support: https://riskdetected.com/en/support

Suggested review path:

1. Sign in with the supplied demo account.
2. Select English as the app language.
3. Open the safety terminology selector and review International, UK, US,
   Australian WHS, and Canadian OHS choices.
4. Create a photo analysis using the synthetic workplace image available to
   the review account.
5. Review the evidence-linked findings and the Fine-Kinney / 5×5 scoring
   presentation.
6. Open an analysis result and generate PDF and Excel reports.
7. Open Settings/Profile to inspect legal documents, restore purchases, and
   the in-app account-deletion entry point.

Important product boundaries:

- AI-generated findings are decision support and may be incomplete or
  inaccurate.
- Non-Turkish profiles use terminology guidance only. They do not claim
  regulatory certification or compliance, and structured country legislation
  references are not shown in this release.
- The App Store screenshots use synthetic debug fixtures and contain no real
  user or workplace data.
- Existing Turkish App Store metadata and screenshots are unchanged.
