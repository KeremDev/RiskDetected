RiskDetected 2.0.0 (build 87) introduces the V4 analysis engine and a redesigned results and reporting workflow.
No new permissions, no new external services, and no change to the declared data collection categories.

Changes in this build:
- Every new iOS build-87 analysis uses the V4 engine. The result route is pinned when the analysis is created and never silently falls back to an older engine.
- Risk Analysis, Expert Guidance, Approved Notebook and Training Recommendations are presented in one redesigned results hub. Empty, single-finding and multi-finding results have explicit states.
- Finding details now include evidence, corrective action, preventive action and regulatory references when available. Like/dislike feedback and optional reasons persist with the analysis.
- PDF and Excel exports now preserve the selected result section and full expert-guidance content. Single-finding download/share and archive tracking are supported.
- Free, Plus and Pro access states, paywall entry attribution, onboarding and light/dark presentation were refreshed.
- Subscription products and entitlement names are unchanged. StoreKit remains the source of price, period and offer information.

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
4. Review Risk Analysis, Expert Guidance, Approved Notebook and Training tabs.
5. Open a finding, submit like/dislike feedback, and inspect Fine-Kinney / 5×5 scoring.
6. Generate and share PDF and Excel reports, including an Expert Guidance report.
7. Open Profile to inspect legal documents, restore purchases, and account deletion.

Important product boundaries:
- AI findings may be incomplete or inaccurate and require professional review.
- Non-Turkish profiles provide terminology guidance only; they do not claim regulatory certification.
- Screenshots use synthetic debug fixtures with no real user or workplace data.
- Existing historical analyses are displayed through a compatibility projection and are not reprocessed.
