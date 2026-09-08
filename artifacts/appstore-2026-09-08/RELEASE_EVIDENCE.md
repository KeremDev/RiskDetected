# iOS 2.0.3 (91) — Meta limited measurement release

Submitted 2026-09-08T10:34:35.357Z. Independent version readback confirmed
**WAITING_FOR_REVIEW**, with build **91** attached.

- App: 6769498181 / com.riskdetected.app
- Version: 2de5fcc1-6909-4eab-8fa2-be7512599c9a
- Build: b26fcacc-eea9-465e-86ec-8d6aa20fab07, Apple processing VALID
- Review submission: 1ee6ecaa-8090-4077-b43c-543d2f3c5128
- Automatic release: AFTER_APPROVAL
- Source live version: 2.0.2 (90)

## Verification

- Signed Release archive and App Store export succeeded; deep strict codesign passed.
- Archive Info.plist verified 2.0.3 / 91, no ATT purpose string, advertiser ID
  collection false, automatic event logging false, SKAdNetwork reporting true.
- App and vendor privacy manifests inspected; vendor signed capabilities untouched.
- Earlier targeted verification: 4 XCTest cases, 15 ledger assertions and 25
  localization gates passed. SDK activation flush succeeded with all three
  advertising/tracking flags zero. No synthetic production purchase events sent.
- Updated legal release live gate passed; 13 phase-5 tests passed.
- ASC review doctor: zero errors, zero blockers. Four existing optional subscription
  promotional-image warnings left untouched to preserve listing assets.
- ASC web Regulations & Permits inspected; existing trader declaration retained.
- Five locales: exact live app-info and version metadata match, excluding approved
  short stability Whats New. Existing review credentials/contact copied without
  logging credentials; review notes updated.
- 43 screenshots: live/draft set type, ordering, hashes and asset states match.

## Privacy publication

User explicitly approved the new TR/EN disclosure. It was appended to existing
policies, not a separate agreement. New approval record and hash manifest recorded.
Production riskdetected.com deployment dpl_CrDmmoN83mbonM7CaDAFfVKZDzof contains only
approved legal changes over the exact former production source inventory. Public
TR/EN markdown hashes match the approved files.

ASC App Privacy published: Device ID, Purchase History, Product Interaction include
Analytics and Developer Advertising, linked to identity, no tracking. Other
existing declarations retained. Final preview: Data Linked to You only.

## Deliberately unchanged / remaining external checks

No Android build, backend deployment or premature live version-policy bump.
Meta campaign eligibility/publication and physical-device paid install attribution
remain external checks; successful SDK delivery is not proof of campaign attribution.
