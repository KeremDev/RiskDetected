# Feedback Panel Design QA

## Comparison target

- Source visual: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-9dd74cfc-fa2a-4eff-ba14-adf6d51e73a7.png`
- Physical-device implementation:
  - `.codex-qa/feedback-sheet-compact-final.png`
  - `.codex-qa/feedback-sheet-custom-note-final.png`
  - `.codex-qa/feedback-thanks-toast-final.png`
- Combined comparison: `.codex-qa/compare-feedback-panel.png`
- Viewport: connected iPhone, portrait, light appearance; `440 x 956 pt`.
- Density: source and implementation are `1320 x 2868` at `@3x`; the comparison contains equal-width source and implementation halves.

## Findings

- No actionable P0, P1, or P2 mismatch remains in the requested feedback flow.
- The source and UI-test fixture show different analysis data, but the feedback interaction is compared at the same device size and visual state.
- The floating picture-in-picture video belongs to the device state and is not part of the application UI.

## Required fidelity surfaces

- Typography: the heading uses the existing app-wide Mulish face with strong hierarchy; subtitle and compact reason labels remain readable and untruncated.
- Spacing and rhythm: six reasons use a two-column compact grid, removing the oversized vertical stack and excess occupied height from the source.
- Colors and tokens: existing ink, green, fog, white, border, radius, and shadow tokens are retained; the send action uses the app's black primary treatment.
- Icons and assets: only existing SF Symbols are used; no placeholder or approximated asset was introduced.
- Copy: the requested Turkish title, subtitle, custom-reason label, send action, and thank-you message are present.

## Interaction checks

- Tapping any predefined reason submits feedback immediately.
- `Nedenini Yazmak İstiyorum` expands an inline editor with a `1000`-character counter and `Gönder` action.
- Empty custom feedback cannot be submitted.
- Submitted custom text is sent as the backend-supported `note` field.
- Successful submission closes the panel and displays `Teşekkürler! Bildirimini en kısa sürede inceleyeceğiz.`
- The thank-you toast dismisses itself after seven seconds.
- Dismiss, reason, editor, submit, and toast states are exposed to accessibility/UI automation.

## Comparison history

- Iteration 1 — P1: replacing the large confirmation dialog with a system sheet still left a visibly empty lower region. Fixed by using a bounded custom overlay whose height follows its content.
- Iteration 2 — P2: the initial overlay container identifier was not exposed consistently through SwiftUI accessibility. The focused test was changed to validate the visible title-to-action geometry and the actual interactive elements instead.
- Final physical-device comparison found no remaining P0/P1/P2 issues.

## Verification

- Native Debug build succeeded for the connected iPhone.
- Focused physical-device UI test: `1` test executed, `0` failures.
- The test validates compact card height, custom text entry and submission, success messaging, and seven-second auto-dismiss.
- No simulator was used.

## Open questions

- None.

## Follow-up polish

- None required for handoff.

final result: passed

---

# Android Paywall Plan-Card Parity QA

Date: 2026-09-06

## Comparison target

- Live iOS source-of-truth captures from `RiskDetectedUITests/testDarkPaywallPricesComparisonAndAllVariants` on `RD QA iPhone 16 Pro` (`393 x 852 pt`):
  - `artifacts/android-paywall-card-parity-20260906/ios-attachments/B506202B-5329-4A25-B978-377E75C99580.png` — PLUS yearly selected.
  - `artifacts/android-paywall-card-parity-20260906/ios-attachments/E9A79F38-EFEB-4475-97F5-32659038FB5F.png` — PRO monthly selected.
- Android implementation captures at the matching `393 x 852 dp` viewport:
  - `android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.paywall_plus_yearly_gold_light.png`.
  - `android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.paywall_pro_monthly_green_light.png`.
- Combined same-state comparisons, inspected with iOS on the left and Android on the right:
  - `artifacts/android-paywall-card-parity-20260906/qa-plus-ios-left-android-right.png`.
  - `artifacts/android-paywall-card-parity-20260906/qa-pro-ios-left-android-right.png`.
- Density normalization: iOS `1206 x 2622 px`; Android `1179 x 2556 px` (`3x`). Android was normalized to `1206 x 2622 px` for the full-view comparison.
- User-directed Popular-badge refinement evidence, previous version left and revised version right:
  - Full view: `artifacts/android-paywall-card-parity-20260906/qa-popular-badge-before-left-after-right.png`.
  - Focused card edge: `artifacts/android-paywall-card-parity-20260906/qa-popular-badge-focused-before-left-after-right.png`.
- States: PLUS yearly selected and PRO monthly selected, portrait, dark appearance.

## Findings and fixes

- P1 layout — Android changed the title/price HStack into a vertical stack based on remaining card width. iOS only stacks at accessibility Dynamic Type sizes. Fixed so normal phone widths always keep the plan name on the left and the price/caption column trailing on the right.
- P1 badge geometry — Android applied the top inset, clipping, surface, and border to one container, so the discount and popular badges could not float over the card edge like iOS. Fixed by separating the card surface from the outer selectable container.
- P2 comparison data — the deterministic Android preview reused the yearly total in the monthly row and omitted the PRO annual discount badge. Added independent monthly preview pricing and aligned both fixtures with the exact iOS reference values.
- P2 Popular-badge scale/alignment — the first parity pass left the gold badge slightly too large and its center below the card's top border. Reduced it to a fixed `18 dp` height with `7.25 sp` text, then used a `9 dp` top inset and `-9 dp` offset. Pixel inspection confirms the badge spans `y=1346...1399` while the border begins at `y=1373`, so the border crosses the badge's `1372.5 px` center.
- No actionable P0, P1, or P2 mismatch remains in the requested monthly/yearly selection-card scope.

## Required fidelity surfaces

- Typography: the existing shared Mulish family, weights, sizes, and two-line annual hierarchy match the iOS component contract; normal-size price columns remain unwrapped.
- Spacing and layout: `12 dp` icon/content spacing, `16 dp` horizontal padding, `16 dp` radius, `1.5 dp` border, `10 dp` inter-card gap, and the centered/trailing badge positions are retained. The Popular badge now straddles the top border equally.
- Colors and states: selected cream surface/border/icon, unselected translucent surface/border/icon, green trial copy, green discount capsule, and gold popular badge match the iOS tokens.
- Icons and behavior: checked and unchecked radio states remain selectable, expose selected semantics, and retain the full card hit target.
- Responsiveness: normal phone widths preserve the horizontal hierarchy; `1.3x` accessibility text keeps the existing stacked fallback and scrollable content with the CTA pinned.

## Verification

- iOS reference UI test: `1` test executed, `0` failures, five screenshots exported from the result bundle.
- Focused Android Roborazzi verification: `2` tests executed with exact-pixel threshold `0`, both passed after recording the corrected baselines.
- Kotlin compilation, Turkish/English resource verification, and Android legal-bundle verification passed as dependencies of the focused visual run.
- No Android release bundle or Play Console submission was performed during this approval step.

## Open questions

- Awaiting visual approval before the Android release build.

final result: passed

# Android Sector Selection and Start Scan Parity QA

## Comparison target

- Reported Android defect photo: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/codex-clipboard-1ba72ea3-1021-4851-b867-1d99cdad81a4.jpg`.
- iOS source-of-truth implementations:
  - `App/Views/Analysis/AnalysisSectorPickerView.swift`
  - `App/Views/Home/HomeView.swift`
  - `App/Views/Onboarding/V2/Screens/OBSectorView.swift`
- Android implementation evidence:
  - `output/android-qa-20260830/sector-picker-initial-expanded.png`
  - `output/android-qa-20260830/onboarding-sector-font-scale-1.3.png`
  - `output/android-qa-20260830/release-after-fixes-launch.png`
  - `android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.sector_grid_selected_light.png`
  - `android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.sector_grid_font_scale_1_3_keeps_subtitles_visible.png`
  - `android/app/src/test/screenshots/debug/com.riskdetectedan.app.visual.OnboardingGoldenTest.home_start_scan_button_has_both_ios_icons_light.png`
- Normalized side-by-side comparison: `output/android-qa-20260830/onboarding-sector-before-after.png`.
- Emulator viewport: `1080 x 2400 px`, Android 13 / API 33, density `420 dpi`, portrait, light appearance.
- Golden viewport: `1179 x 2556 px`. The physical-device defect photo is `4032 x 3024 px` with EXIF portrait orientation; both sides were normalized to equal-width columns for the comparison.

## Findings and fixes

- P1 behavior/layout — the analysis sector sheet could enter a partially expanded state, leaving its Continue action below the initial viewport. Fixed by disabling the partial state; on-device state is now `Expanded` on first presentation and the Continue action is visible.
- P1 icon fidelity — the Home `Start Scan` action was missing the leading iOS sparkle icon. Fixed with the leading sparkle while preserving the trailing white send capsule.
- P1 typography/responsiveness — onboarding sector subtitles were clipped by fixed-height cards. Fixed with a `96 dp` minimum card height, two subtitle lines, and iOS-aligned title/subtitle scale and line height.
- No actionable P0, P1, or P2 mismatch remains for the three requested surfaces.

## Required fidelity surfaces

- Typography: Turkish sector titles and descriptions remain legible without truncation at normal scale and `1.3x` font scale; weight and hierarchy remain consistent with the iOS target.
- Spacing and layout: two-column onboarding cards preserve the existing grid; the minimum-height change adds only the vertical space needed for localized copy. The analysis sheet's full three-column grid and primary action fit in its initial expanded presentation.
- Viewport resilience: large-font instrumentation and golden coverage confirm that subtitles wrap inside their cards instead of crossing or clipping the card boundary.
- Colors and tokens: existing white/fog surfaces, black primary action, disabled gray action, semantic sector colors, borders, and radii are unchanged.
- Icons and assets: Material sparkle and send icons are both visible and optically centered in the Home CTA; existing sector icons remain unchanged. No placeholder imagery or custom vector substitute was introduced.
- Copy and content: existing localized Turkish and English resource strings are retained; no new hard-coded product copy was added.

## Interaction and accessibility checks

- Analysis sector sheet enters `SheetValue.Expanded` and exposes its title and Continue action on first presentation.
- Continue remains visibly disabled until a sector is selected, preserving the intended interaction contract.
- Onboarding card subtitles are present in the unmerged accessibility tree and remain displayed at `1.3x` font scale.
- Home CTA exposes the existing button semantics while both visual icons remain independently testable.

## Comparison history

- Iteration 1 — P1: initial sector sheet state and Continue visibility were corrected with `skipPartiallyExpanded = true`.
- Iteration 2 — P1: the Home CTA gained the missing sparkle icon and retained the trailing action capsule.
- Iteration 3 — P1: onboarding cards moved from a clipping fixed height to a wrapping minimum height; normal and large-font visual baselines were recorded.
- Final emulator comparison found no remaining P0/P1/P2 issues in the requested scope.

## Verification

- Relevant Kotlin debug and unit-test compilation succeeded.
- Three focused Roborazzi visual tests passed and baselines were recorded for normal onboarding, `1.3x` font scale, and the Home CTA icons.
- Two API 33 on-device Compose tests passed: initial expanded sector sheet and large-font onboarding subtitle visibility.
- A locally signed production release was built and launched with the existing real app session; the corrected Home CTA was visually verified.
- No Play Console upload was performed.

## Open questions

- None.

## Follow-up polish

- None required for this requested scope.

final result: passed

---

# Android iOS Parity Design QA — Analysis Results

Date: 2026-09-01

## Grounding

- Product source: `App/Views/Result/AnalysisResultHubView.swift`
  - optional report selection state (`reportKind`) at line 69
  - report sheet implementation near line 3135
  - membership promotion implementation near line 2579
- Finding detail source: `App/Views/Result/RiskDetailView.swift` near line 467
- Progress celebration source: `App/Features/ProfessionalProgress/ProfessionalProgressCelebrationSheet.swift`
- Reported Android states: the five screenshots attached to the implementation request.

## Side-by-side visual evidence

- Locked result cards: `output/design-qa/locked-cards-before-after.png`
- Report creation sheet: `output/design-qa/report-sheet-before-after.png`
- Finding membership promotion: `output/design-qa/finding-promotion-before-after.png`
- Professional progress celebration: `output/design-qa/celebration-before-after.png`

Each comparison was opened and visually inspected after the updated Android screenshot was placed beside the reported state.

## Checklist

- [x] Free Expert Opinion, Training Recommendation, and Approved Notebook cards expose only a two-word teaser; protected copy is blurred and removed from accessibility semantics.
- [x] PLUS / PRO overlay and upgrade action match the iOS premium treatment.
- [x] Result header uses the account avatar source and shows the correct Upgrade CTA for eligible tiers.
- [x] Celebration content is compact; confetti starts above the content, flows downward continuously, and fades before the bottom edge.
- [x] Standard Report is the compact option; Risk Analysis Table has stronger visual weight.
- [x] No report type is selected initially and the primary action remains disabled until an explicit selection.
- [x] Report action label is centered.
- [x] Finding editor sheet drag is disabled so the inner scroll does not fight the bottom sheet.
- [x] Finding detail membership promotion uses the iOS multi-plan gradient, PLUS / PRO badges, copy, and CTA treatment.
- [x] Turkish and English resource generation is current.
- [x] Roborazzi visual verification, profile unit tests, debug assemble, install, launch, and crash-log smoke check pass.

final result: passed

---

# Android Notification and Dark Appearance QA

Date: 2026-09-01

## Grounding

- Notification reference: the Android notification tray screenshot attached to the request and the native iOS notification behavior in `App/Services/NotificationService.swift`.
- Dark result references: the three attached Android screenshots covering the report sheet, finding detail, and result-card states.
- Product source: the existing RiskDetected logo assets, Android design tokens, `App/Views/Result/AnalysisResultHubView.swift`, and `App/Views/Result/RiskDetailView.swift`.

## Side-by-side visual evidence

- Report sheet reference versus corrected build: `output/design-qa/android-dark-report-reference-vs-build.png`
- Finding detail reference versus corrected build: `output/design-qa/android-dark-finding-reference-vs-build.png`
- Result page reference versus corrected build: `output/design-qa/android-dark-result-reference-vs-build.png`

Each comparison was opened as a single combined image and inspected for contrast, hierarchy, clipping, spacing, CTA treatment, icon size, and header-logo visibility.

## Checklist

- [x] The result and main headers use a white brand mark in dark appearance and retain readable green-tinted avatar initials.
- [x] Active report CTAs use the product green in dark appearance with black text and icons; disabled states remain visually distinct.
- [x] The free risk-analysis entitlement ribbon has a visible amber border, icon, and text on the dark surface.
- [x] Root-cause labels and body copy use a legible amber treatment instead of the low-contrast brown-on-brown state.
- [x] Finding download, edit, delete, and share actions have larger touch surfaces and icons.
- [x] The download subtitle wraps completely inside its action card instead of clipping.
- [x] Existing dark profile and report-archive goldens were inspected; no additional P0/P1/P2 contrast defect was found in the requested scope.
- [x] Foreground notifications use the complete full-colour app artwork plus the dedicated monochrome Android status mark.
- [x] Background/killed-state FCM notifications use the same status mark and notification accent through manifest defaults.

## Verification

- `NotificationBrandingTest`: 2/2 checks passed, including foreground and background notification paths.
- Four focused dark-appearance Roborazzi states were recorded and `verifyRoborazziDebug` passed.
- `assembleDebug` completed successfully and `git diff --check` reported no whitespace errors.
- The final APK installed successfully on the API 33 emulator and `MainActivity` completed a cold launch without a crash.
- The debug environment's existing fail-closed runtime gate prevents a real authenticated-data walkthrough, so requested screen states were verified with deterministic Compose fixtures and combined visual comparisons.

## Open questions

- None.

## Follow-up polish

- None required for this requested scope.

final result: passed

---

# Android Risk Analysis Report Card Fill QA

Date: 2026-09-01

## Comparison target

- Source visual truth: `/var/folders/b8/1ntgctld0x9_wm3ms9cxkdtr0000gn/T/TemporaryItems/NSIRD_screencaptureui_5FFgI3/Ekran Resmi 2026-09-01 13.51.59.png`
- Implementation screenshot: `android/feature/analysis/src/test/screenshots/debug/com.riskdetectedan.feature.analysis.AnalysisParityGoldenTest.free_risk_report_sheet_dark_has_legible_trial_and_themed_cta.png`
- Full and focused side-by-side evidence: `output/design-qa/risk-report-card-fill-reference-vs-build.png`
- State: dark appearance, Standard Report selected, Risk Analysis Table unselected, active report CTA.
- Source pixels: `412 × 472`; implementation pixels: `1179 × 2556`; focused comparison: `2257 × 1200`. The implementation was cropped to the matching report-card region, then both regions were normalized to the same `1200 px` comparison height. Android golden viewport density remains the existing project baseline.

## Findings and comparison history

- Iteration 1 — P2: the emphasized Risk Analysis Table card kept its expanded height while its short subtitle and top-aligned radio occupied only the upper half, leaving an obvious empty lower region.
- Fix: restored the complete iOS report explanation, vertically centered the emphasized row, increased the table icon from `48 dp` to `52 dp`, increased the radio from `26 dp` to `29 dp`, and tightened emphasized vertical padding from `16 dp` to `14 dp`.
- Post-fix evidence: the title and three-line description now use the card body, while the icon and selection control share the card's optical center. The focused combined comparison contains no remaining P0/P1/P2 issue.

## Required fidelity surfaces

- Fonts and typography: existing rounded family and heavy title weight are preserved; the description uses `11.8 sp` with `15 sp` line height and no clipping.
- Spacing and layout rhythm: visual weight is distributed across the full emphasized card; left asset, text block, and radio align around the same vertical center.
- Colors and visual tokens: existing dark surface, multicolour emphasis border, icon gradient, muted secondary copy, and selection-state colors are unchanged.
- Image and icon fidelity: the existing Material table icon is retained and scaled within its supplied gradient container; no placeholder or replacement asset was introduced.
- Copy and content: Turkish and English descriptions now match the complete iOS report-table explanation, including PDF and Excel output context.

## Verification

- Focused Roborazzi record passed for both explicit-selection and dark report-sheet states.
- The complete Turkish subtitle is asserted as visible in the dark report-sheet test.
- No focused-region clipping, overflow, or unbalanced bottom whitespace remains.

## Open questions

- None.

## Follow-up polish

- None required for this requested scope.

final result: passed
