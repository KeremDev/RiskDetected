RiskDetected 1.3.4 (build 84) is a subscription-screen and localization update.

Changes in this build:
- The subscription screen was redesigned; every paid entry point and the final onboarding step now use the same screen.
- Prices, free-trial length, and the discount badge are read from the user's App Store storefront and are hidden when the store returns no offer.
- Turkish copy for the Fine-Kinney method name was corrected; it is a proper noun and is no longer translated.
- Sign-in, analysis/report flows, and general stability were improved.
- Best-effort platform analytics are isolated from auth, subscriptions, quotas, analyses, and reports; telemetry failure cannot block app use.

Reviewer login:
Use the demo account supplied in App Review Information. Sign-in is email OTP; no password is required. Credentials are intentionally excluded from these notes and from the repository.

Review mailbox:
The one-time code is delivered to the review mailbox recorded in App Review Information, which is the same address as the demo account.

OTP validity:
Each emailed code is valid for 10 minutes and for a single use. Request a fresh code from the sign-in screen if it expires.

Physical-device demo video:
No separate video is required. The candidate was tested on a physical iPhone and the complete flow is available in the submitted build.

External services:
Supabase provides authentication, database, storage, and Edge Functions. RevenueCat/StoreKit manages subscriptions. Transactional email uses Resend/Supabase hooks. AI-assisted workplace-safety analysis uses Google Gemini/Google AI with possible Groq-compatible fallback.

Regional differences:
English users explicitly select International, UK, US, Australian WHS, or Canadian OHS terminology. Storefront, IP address, and analytics do not select or change the user's safety profile.

China mainland availability decision:
China mainland remains excluded because the app includes AI-assisted workplace-safety analysis and external AI processing.

Regulated industry documentation:
The app performs AI-assisted risk analysis of workplace photographs. AI output is advisory decision support: it does not certify compliance, and it does not replace a qualified occupational safety professional, a workplace inspection, or legal review.

Subscriptions:
Apple IAP manages subscriptions. Purchases can be restored from Profile, and localized subscription metadata is configured for supported English locales.

Permissions:
Camera and photo-library access let users capture or select workplace photos for risk analysis.

Legal and privacy:
- Privacy: https://riskdetected.com/en/privacy
- Terms: https://riskdetected.com/en/terms
- Support: https://riskdetected.com/en/support

Suggested review path:
1. Sign in with the supplied demo account.
2. Select English and review the safety terminology profiles.
3. Create a photo analysis using the synthetic image available to the account.
4. Review evidence-linked findings and Fine-Kinney / 5×5 scoring.
5. Generate PDF and Excel reports.
6. Open Profile to inspect legal documents, restore purchases, and account deletion.

Important product boundaries:
- AI findings may be incomplete or inaccurate and require professional review.
- Non-Turkish profiles provide terminology guidance only; they do not claim regulatory certification.
- Screenshots use synthetic debug fixtures with no real user or workplace data.
- Existing App Store metadata and screenshots are unchanged.
