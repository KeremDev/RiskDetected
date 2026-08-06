# RiskDetected 1.3.0 Localization Review Evidence

Target: iOS 1.3.0 build 80  
Release mode: Manual  
Mutable App Store locales: `en-GB`, `en-US`, `en-AU`, `en-CA`  
Protected App Store locale: `tr`

## Product evidence

- English UI strings are compiled into build 80 with
  `RD_GLOBAL_LOCALIZATION_WAVE1`.
- The profile selector contains International, UK, US, Australian WHS, and
  Canadian OHS terminology choices.
- Non-Turkish safety profiles disable structured legislation and compliance
  claims.
- Single-photo and up-to-three-photo English analysis contracts are covered by
  schema, language, terminology, prompt-injection, cross-country leakage, and
  12-layer multi-photo audit tests.
- English PDF and XLSX output is generated from the immutable analysis
  localization snapshot.
- English push, transactional email, permission prompt, support, legal, and
  subscription copy has reviewer approval and checksum-backed production
  records.
- Restore purchases and in-app account deletion remain available from Profile.
- Decision-support disclaimers appear in product copy, reports, legal
  documents, and App Store metadata.

## Screenshot evidence

- 20 final screenshots: five for each mutable English locale.
- Format: portrait 1290×2796, light theme.
- Source: synthetic debug fixtures; no production user or workplace data.
- QA manifest: `appstore/screenshots/qa/manifest.json`.
- QA contact sheet: `appstore/screenshots/qa/contact-sheet.png`.
- No protected Turkish final screenshot directory exists and the upload
  automation refuses protected locales.

## Approval evidence

- Safety profile source SHA-256:
  `3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc8b9c6932`
- Safety/language/product review: approved by Kerem, qualified to evaluate
  English workplace-safety copy.
- Notification copy: approved by Kerem, qualified to evaluate English
  workplace-safety copy.
- Legal documents: approved by Kerem, qualified to review and approve the
  legal documents.

## Release safety

- Build 77 / version 1.2.4 remains the live App Store release.
- Build 80 is attached only to candidate 1.3.0.
- Candidate release type is `MANUAL`.
- Automation cannot submit App Review or release the version.
- Production localization rollout flags remain off until Apple approval and
  the owner's explicit activation instruction.
- Build 80 and later builds are eligible for the 12-layer multi-photo audit and
  6144 thinking budget; current live Build 77 is excluded by the release gate.
- Turkish App Store metadata, screenshots, and subscription localizations are
  protected by a before/after hash and are not mutation targets.
