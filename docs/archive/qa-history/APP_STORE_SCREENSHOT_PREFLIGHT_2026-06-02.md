# App Store Screenshot Preflight - 2026-06-02

Scope: RiskDetected App Store listing screenshot assets.

This is a QA/preflight note only. It does not delete, resize, reorder, or upload screenshots.

## Apple Spec Check

Official Apple reference checked on 2026-06-02:

- `https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications`

Relevant current constraints:

- App Store Connect accepts `.jpeg`, `.jpg`, and `.png`.
- Each screenshot set must contain 1 to 10 screenshots.
- For iPhone 6.9" displays, accepted portrait sizes include:
  - `1260 x 2736`
  - `1290 x 2796`
  - `1320 x 2868`
- For iPhone 6.1" displays, accepted portrait sizes include:
  - `1170 x 2532`
  - `1125 x 2436`
  - `1080 x 2340`

## Local Asset Inventory

Current local TR iPhone export folder:

- `AppStoreScreenshots/public/screenshots/apple/iphone/tr/`

Final iPhone TR 6.9 upload candidate folder:

- `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/`

Findings:

- Found 13 PNG files: `01.png` through `13.png`.
- All 13 files are `1125 x 2436`.
- This size is an accepted iPhone 6.1" portrait size, not a 6.9" portrait size.
- `AppStoreScreenshots/app-store-screenshots.json` also defines 13 iPhone slides.
- A final 10-file iPhone 6.9 candidate set was created from slides `01.png` through `10.png`.
- The final candidate files are all `1320 x 2868`, which is an accepted iPhone 6.9" portrait size.

Current slide list:

| # | ID | Label | Headline |
| ---: | --- | --- | --- |
| 1 | `rd-ios-01` | AI SAHA TARAMA | Saha riskini / fotoğraftan gör |
| 2 | `rd-ios-02` | İŞARETLE | Tehlikeyi işaretle / AI analiz etsin |
| 3 | `rd-ios-03` | ODAKLI ANALİZ | Analizi doğru / alana odakla |
| 4 | `rd-ios-04` | PRO ODAK | Yüksekte çalışmayı / ayrı değerlendir |
| 5 | `rd-ios-05` | RİSK SKORU | Risk puanını / anında gör |
| 6 | `rd-ios-06` | ÖNLEM PLANI | Her bulguya / net önlem |
| 7 | `rd-ios-07` | RAPOR | Raporu tek / dokunuşla oluştur |
| 8 | `rd-ios-08` | ÇIKTI SEÇ | PDF veya Excel / hazırla |
| 9 | `rd-ios-09` | HAZIRLANIYOR | Raporun saniyeler / içinde hazır |
| 10 | `rd-ios-10` | STANDART RAPOR | Saha raporunu / düzenli çıkar |
| 11 | `rd-ios-11` | FINE-KINNEY | Fine-Kinney / hesabı otomatik |
| 12 | `rd-ios-12` | 5x5 MATRİS | 5x5 matris / hazır gelsin |
| 13 | `rd-ios-13` | PROFİL | Uzmanlığını / ilerledikçe göster |

## Gate Status

| Gate | Status | Notes |
| --- | --- | --- |
| Screenshot count | PASS | Final upload candidate has 10 screenshots: `01.png` through `10.png`. The original 13-file source set remains available separately. |
| Screenshot dimensions | PASS | Final candidate files are all `1320 x 2868`, accepted for iPhone 6.9" portrait. |
| Secret/privacy scan | PASS WITH OWNER APPROVAL REQUIRED | Codex visual QA found no obvious private emails, phone numbers, tokens, support IDs, private identifiers, localhost/debug/beta labels, or USD/fallback subscription price at contact-sheet scale. Final owner/marketing approval should still confirm the demo field photo/profile avatar/report imagery are approved non-private assets and that claims are not misleading. See `QA/APP_STORE_SCREENSHOT_VISUAL_QA_2026-06-02.md`. |
| Final selection | PASS | Final candidate sequence is `01.png` through `10.png`; slides `11.png` through `13.png` are not part of the upload candidate. |

## Submission Recommendation

- Use `AppStoreScreenshots/public/screenshots/apple/iphone/tr-6-9-final/` as the current final iPhone 6.9 upload candidate after visual approval.
- Do not upload all 13 source TR iPhone screenshots as one App Store Connect set.
- Keep `1125 x 2436` assets as 6.1" support/fallback assets if App Store Connect requests or accepts an additional display-specific set.
- Keep screenshot tooling and raw/generated assets in a separate marketing commit from runtime/backend release changes unless the release commit intentionally includes final store assets.
