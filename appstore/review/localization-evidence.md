# RiskDetected 2.0.0 Localization Review Evidence

Target: iOS 2.0.0 build 88
Release mode: After approval
Mutable App Store locales: `en-GB`, `en-US`, `en-AU`, `en-CA`
Protected App Store locale: `tr`

## Product evidence

- English UI strings are compiled into build 88 with
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

- 43 final screenshots copied from the live 1.3.4 listing: nine for each
  mutable English locale and seven for Turkish.
- Format: portrait 1320×2868, legacy 1.3.4 presentation.
- Source: synthetic debug fixtures; no production user or workplace data.
- QA manifest: `appstore/screenshots/qa/manifest.json`.
- QA contact sheet: `appstore/screenshots/qa/contact-sheet.png`.
- App Store read-after-write verification confirms the four mutable English
  sets match the local source checksums. Turkish was migrated explicitly from
  1.3.4 and then re-protected with a refreshed baseline.

## Approval evidence

- Safety profile source SHA-256:
  `ae72ae29ac4ed47d6ffbd7aa37dba426e44647066fe70d93d1021e8eefa54ad3`
- Safety/language/product review: approved by Kerem, qualified to evaluate
  English workplace-safety copy.
- Notification copy: approved by Kerem, qualified to evaluate English
  workplace-safety copy.
- Legal documents: approved by Kerem, qualified to review and approve the
  legal documents.

## Release safety

- Build 86 / version 1.3.4 remains the live App Store release.
- Build 88 is attached only to candidate 2.0.0.
- Candidate release type is `AFTER_APPROVAL`.
- App Review submission was performed by automation; the version remains
  `AFTER_APPROVAL` and cannot go live before Apple approval.
- App Store metadata for `tr`, `en-US`, `en-GB`, `en-AU`, and `en-CA` was copied
  from 1.3.4, with 2.0.0-specific What's New notes added to every locale.
- Build 88 uses the approved V4 analysis and new result-hub release policy.
- Turkish App Store metadata, screenshots, and subscription localizations are
  protected by the post-migration baseline and are not automation mutation
  targets.
