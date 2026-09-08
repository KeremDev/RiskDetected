# Google Play Production — RiskDetected 2.0.2 (14)

- Package: `com.riskdetectedan.app`
- Track: Production
- Country: Turkey only
- Release mode: automatic after Google review
- Artifact: new minified AAB signed with the approved upload key
- Evidence: AAB SHA-256, commit SHA, mapping and native symbols

## Before Play submission

- [ ] Release tests, lint and artifact verification pass.
- [ ] Play App Bundle Explorer and pre-launch checks contain no blocker.
- [ ] Data Safety, App Access, content rating and legal URLs remain valid.
- [ ] RevenueCat Plus/Pro products and entitlements remain active.
- [ ] Turkish and English release notes are attached.
- [ ] Existing screenshots and store metadata remain unchanged.

## After Play goes live

1. Verify clean install and upgrade from build 13 to build 14.
2. Smoke-test Google sign-in, camera, analysis, results hub, PDF/XLSX, notifications and purchases.
3. Publish build 14 in `android_release_policy` with a separate forward-only migration; keep soft/hard update disabled.
4. Monitor crash/ANR, API, analysis, report and RevenueCat signals at 2, 24 and 72 hours.
