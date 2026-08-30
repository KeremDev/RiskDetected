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
