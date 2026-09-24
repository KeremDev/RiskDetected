# App Store Screenshot Visual QA - 2026-06-02

Scope: final iPhone TR 6.9 App Store screenshot upload candidate.

This is a non-secret visual QA note. It does not upload screenshots to App Store Connect and does not replace final owner/marketing approval.

## Candidate Set

Directory:

- `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/`

Contact sheet:

- `QA/tmp/app-store-screenshot-final-contact-sheet.png`

Timestamp:

- 2026-06-02 01:24 +03

## Automated File Checks

| File | Size | SHA-256 |
| --- | --- | --- |
| `01.png` | `1320 x 2868` | `b591e9608fce650f26747b5eed5eba08e28b9974536dfc4ac141b90746cce022` |
| `02.png` | `1320 x 2868` | `fb163c784e955d13c1b165b5a53f2dd59f163df968cbde4b66e4b299d1c62f63` |
| `03.png` | `1320 x 2868` | `73f061a31292d7042b2ad9a6338c3e244c22422ba501f56cc229ba10c94b7288` |
| `04.png` | `1320 x 2868` | `18c99882a169752f2a5fd5624bff0f2de9ac2e0516e97f08877a4fa109f1cfa5` |
| `05.png` | `1320 x 2868` | `bfca82a0469a1fc3dae7c9cc6712bf8735f43e449d2107c8132ff11e24bbca13` |
| `06.png` | `1320 x 2868` | `6f5da07812151e72dbcdb26a3fbd0315733b37eb986df0aacaabf37ec7410e01` |
| `07.png` | `1320 x 2868` | `d143eba304dcf5ac66ca652fb9457ae352d7af3d705a9861837010edf3329bce` |
| `08.png` | `1320 x 2868` | `059d69f53561d1724741fe2451a5c39f7cc15a2f32271c322362d3e0cee30974` |
| `09.png` | `1320 x 2868` | `2b263a81ce5c8aa308306706bce422b92efa1e66eea96631435e0d94343036b8` |
| `10.png` | `1320 x 2868` | `da46030331413e9028ad628a7ad32aca85527c9788ced11f79febe0da99e9635` |

Result:

- `PASS`: 10 files.
- `PASS`: all files are `1320 x 2868`, accepted iPhone 6.9" portrait size.
- `PASS`: final set stays within App Store Connect's 1-10 screenshot limit.

## Visual Content Review

| File | Visible content | QA observation |
| --- | --- | --- |
| `01.png` | Home/photo upload screen with RiskDetected brand, report quota/status, CTA. | No obvious private email, phone, token, support ID, or personal identifier. |
| `02.png` | Photo marking screen over construction-site image. | No obvious private text. Underlying field image contains workers/environment and needs owner confirmation that imagery is approved/licensed/non-private. |
| `03.png` | Focused analysis category sheet over construction-site image. | No obvious private text. Same field-image approval caveat as `02.png`. |
| `04.png` | Focused analysis category sheet with working-at-height options. | No obvious private text. Same field-image approval caveat as `02.png`. |
| `05.png` | Analysis result and Fine-Kinney risk summary. | No obvious private identifier. Risk-score claim appears to be in-app output, not an external certification claim. |
| `06.png` | Analysis result, mitigation/legal/regulation copy, report CTA. | No obvious private identifier. Regulation text should remain accurate and not imply official certification. |
| `07.png` | Report type selection bottom sheet. | No obvious private identifier. |
| `08.png` | Report creation form and file type selection. | No obvious private identifier. |
| `09.png` | PDF generation progress sheet. | No obvious private identifier. |
| `10.png` | PDF report preview. | No obvious private email, phone, token, support ID, or private identifier visible at contact-sheet scale. Report content appears demo/sample-like; owner should confirm it is not a real customer report. |

## Risk Notes

Observed as clean at contact-sheet scale:

- No visible email address.
- No visible phone number.
- No visible API key, token, support ID, JWT-like string, or App Store Connect/Supabase secret.
- No visible localhost/debug/beta/test-only label.
- No visible USD/fallback subscription price.

Needs final owner/marketing approval before ASC upload:

- Construction-site photo/worker imagery in `02.png` through `04.png`.
- Profile/avatar imagery visible in several app chrome areas.
- Demo report content in `10.png`.
- Any claims that could be read as official safety certification, regulatory approval, or guaranteed compliance.

## Gate Recommendation

- Automated count/dimension gates: `PASS`.
- Codex visual/privacy scan: `PASS WITH OWNER APPROVAL REQUIRED`.
- App Review manual evidence row should remain `HOLD` until the final set is visually approved by the owner/marketing and uploaded in App Store Connect.
