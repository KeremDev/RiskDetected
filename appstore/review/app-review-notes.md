RiskDetected 1.3.2 (build 82) is a maintenance and reliability update.

Changes in this build:
- Sign-in, localization, analysis/report flows, and general stability were improved.
- Trial and notification explanations were clarified; users can continue without purchasing.
- StoreKit/RevenueCat prices come from the user's App Store storefront.
- Best-effort platform analytics are isolated from auth, subscriptions, quotas, analyses, and reports; telemetry failure cannot block app use.

Reviewer login and mailbox:
Use the demo account in App Review Information. Request a fresh email OTP and use the latest code delivered to the supplied review mailbox. Credentials are intentionally excluded from these notes and the repository.

Physical-device demo video:
No separate video is required. The candidate was tested on a physical iPhone and the complete flow is available in the submitted build.

External services:
Supabase provides authentication, database, storage, and Edge Functions. RevenueCat/StoreKit manages subscriptions. Transactional email uses Resend/Supabase hooks. AI-assisted workplace-safety analysis uses Google Gemini/Google AI with possible Groq-compatible fallback.

Regional differences:
English users explicitly select International, UK, US, Australian WHS, or Canadian OHS terminology. Storefront, IP address, and analytics do not select or change the user's safety profile.

China mainland availability decision:
China mainland remains excluded because the app includes AI-assisted workplace-safety analysis and external AI processing.

Regulated industry documentation:
AI output is advisory decision support. It does not certify compliance or replace a qualified occupational safety professional, workplace inspection, or legal review.

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
