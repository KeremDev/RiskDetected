# Google Play Production — RiskDetected 2.0.1 (13)

- Package: `com.riskdetectedan.app`
- Track: Production
- Country: Turkey only
- Release mode: automatic after Google review
- Artifact: new minified AAB signed with the approved upload key
- Evidence: AAB SHA-256, CI URL, commit SHA, mapping and native symbols

## Before Play submission

- [ ] CI release-candidate workflow is fully green.
- [ ] Play App Bundle Explorer and Pre-launch Report contain no blocker.
- [ ] Data Safety, App Access, content rating and legal URLs are verified.
- [ ] RevenueCat Plus/Pro products, entitlements and restore flow are verified.
- [ ] Turkish and English release notes are approved.
- [ ] Final screenshots are approved.

Do not select **Send for review** until every item is complete.

## After Play goes live

1. Verify clean install and upgrade to build 13 from the previous production build.
2. Smoke-test Google sign-in, camera, analysis, results hub, PDF/XLSX, notifications and purchases.
3. Publish build 13 in `android_release_policy` with a separate forward-only migration; keep soft/hard update disabled.
4. Monitor crash/ANR, API, analysis, report and RevenueCat signals at 2, 24 and 72 hours.
