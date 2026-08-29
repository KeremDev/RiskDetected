RiskDetected 2.0.0 (build 87) introduces the V4 analysis engine and redesigned result/report flows. It adds no permissions, external services, or declared data categories.

Changes in this build:
- All new iOS build-87 analyses use V4. The route is pinned at creation and never silently falls back to an older engine.
- Risk Analysis, Expert Guidance, Approved Notebook, and Training Recommendations share a new result hub with explicit empty, single, and multiple-finding states.
- Finding details include evidence, corrective action, preventive action, and regulatory references when available. Like/dislike feedback and optional reasons persist.
- PDF/Excel exports preserve the selected section and full expert content. Single-finding download/share and archive tracking are supported.
- Free/Plus/Pro access, paywall attribution, onboarding, and light/dark presentation were refreshed. Product identifiers and entitlements are unchanged; StoreKit remains the source of prices and offers.

Reviewer login:
Use the demo account in App Review Information. Sign-in uses email OTP; no password is required.

Review mailbox:
The code is sent to the demo-account mailbox recorded in App Review Information.

OTP validity:
The code is single-use and valid for 10 minutes; request a new code if it expires.

Physical-device demo video:
No separate video is required. The full flow is available in the submitted build and was verified on a physical iPhone.

External services:
Supabase provides authentication, database, storage, and Edge Functions. RevenueCat/StoreKit manages subscriptions. Resend/Supabase sends transactional email. AI-assisted workplace-safety analysis uses Google Gemini/Google AI with possible Groq-compatible fallback.

Regional differences:
English users explicitly select International, UK, US, Australian WHS, or Canadian OHS terminology. Storefront, IP address, and analytics do not select or change this profile.

China mainland availability decision:
China mainland is excluded because the app includes AI-assisted safety analysis and external AI processing.

Regulated industry documentation:
AI output is advisory. AI-assisted risk analysis does not certify compliance and does not replace a qualified occupational safety professional, workplace inspection, or legal review.

Subscriptions:
Apple IAP manages subscriptions. Purchases can be restored from Profile; localized metadata is configured for supported English locales.

Permissions:
Camera and photo-library access let users capture or select workplace photos for risk analysis.

Legal and privacy:
- Privacy: https://riskdetected.com/en/privacy
- Terms: https://riskdetected.com/en/terms
- Support: https://riskdetected.com/en/support

Suggested review path:
1. Sign in with the supplied demo account.
2. Select English and review the terminology profiles.
3. Create a photo analysis using the synthetic image available to the account.
4. Review the Risk Analysis, Expert Guidance, Approved Notebook, and Training tabs.
5. Open a finding, submit feedback, and inspect Fine-Kinney / 5x5 scoring.
6. Generate and share PDF and Excel reports, including Expert Guidance.
7. Open Profile to inspect legal documents, restore purchases, and account deletion.

Important product boundaries:
- AI findings may be incomplete or inaccurate and require professional review.
- Non-Turkish profiles provide terminology guidance only; they do not claim regulatory certification.
- Screenshots use synthetic fixtures with no real user or workplace data.
- Historical analyses use a compatibility projection and are not reprocessed.
