# Android Profile + Analysis Sector Picker — Design QA

## Evidence

- iOS profile runtime reference: `/tmp/ios-profile-reference.png`
- iOS sector reference: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/analysis-sector-picker-screenshot/analysis_sector_picker_unselected.png`
- Android profile golden: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.profile_ios_parity_light.png`
- Android sector golden: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.analysis_sector_picker_three_column_light.png`
- Combined comparison: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected/output/android-ios-profile-sector-parity/comparison.png`
- Android viewport: `393 × 852 dp`, `xxhdpi`, Turkish, light theme.
- iOS profile reference was captured from the existing UI-test fixture on an iPhone 16 Pro simulator; no `App/` source was changed.

## Findings and resolutions

1. P1 — Android profile used a plain centered identity card and a large “Profil” header; iOS uses a cover-led hero without a tab-page title. Resolved with the 148-point sky cover, 96-point overlapping avatar, tier/camera badges, left-aligned identity, professional-title capsule and four stat cells.
2. P1 — Android collapsed all professional progress content into one oversized card. Resolved by matching the iOS sequence: MDP showcase, weekly tracking, competency preview, then tier status.
3. P1 — Android profile actions were separate oversized cards and the floating tab bar obscured content. Resolved with iOS-style HESAP/AYARLAR grouped rows, inset dividers, 32-point icon tiles and 112 dp bottom content clearance.
4. P1 — Account rows were missing Geçmiş analizler/Raporlarım navigation. Resolved; both rows now show live progress counts and switch to their corresponding tabs.
5. P1 — Analysis sector choices were a one-column descriptive list and selection immediately advanced. Resolved with the iOS 74 dp card geometry, 3 columns on phones/4 on tablets, sector colors, badge priority, selected onyx state and explicit “Devam et”.
6. P2 — Android sector title/copy and close-button treatment differed. Resolved with “Analiz kapsamını seç”, the live iOS explanatory copy and platform back/swipe dismissal instead of an extra close control.
7. P2 — Plus/Pro identity was visually neutral. Resolved with Plus yellow and Pro green across avatar badge and subscription status card.

## Fidelity review

- Typography uses the existing iOS-derived Android optical scale and platform sans metrics; SF Pro is not redistributed.
- Profile cover proportions, 30 dp hero radius, 96 dp avatar, 54 dp stat strip, 14/16 dp card radii, menu inset and content rhythm follow the Swift source.
- The iOS runtime fixture has no professional-progress summary, while the Android golden intentionally includes one to validate the live-data branch. The MDP, weekly and competency components were checked against their corresponding Swift sources.
- Sector cards match the iOS three-column phone grid and selected-card behavior. Android system sheet motion/back handling remains platform-native.
- No actionable P0/P1/P2 finding remains.

## Interaction and regression checks

- Sector tap only selects; “Devam et” invokes the callback with the selected sector.
- Geçmiş analizler and Raporlarım switch tabs through `MainShell` callbacks.
- Profile bottom clearance prevents the floating navigation bar from covering rows.
- Roborazzi exact-pixel goldens recorded for both surfaces.
- `testDebugUnitTest`, `lintDebug`, and `assembleDebug` pass.
- Debug APK installed on API 36 emulator; cold launch succeeds and filtered crash buffer is clean.
- `git diff --check` passes and `App/` source diff is empty.

final result: passed
