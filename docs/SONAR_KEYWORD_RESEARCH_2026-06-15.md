# RiskDetected Sonar Keyword Research - 2026-06-15

Scope: Turkey App Store, iOS, RiskDetected `6769498181`.

Source: Sonar keyword search, keyword metrics, app search, app ASO score. Sonar returns `popularity`, not absolute monthly search volume, so this report uses relative opportunity scoring rather than traffic forecasts.

## Snapshot

- App: `RiskDetected: İSG Risk Analizi`
- Store ID: `6769498181`
- Sonar ASO score: `72/100`
- Strong signals: title length, title keywords, description quality, rating, recent update, release notes.
- Weak signals: review count, screenshot detection in Sonar.
- Current metadata keyword concentration: `risk`, `risk analizi`, `iş güvenliği`, `yapay zeka`, `rapor`.

## Main Takeaways

1. The best near-term organic opportunity is not broad `iş güvenliği`; it is the professional long-tail cluster around `risk değerlendirme`, `5x5 matris`, `fine kinney`, `iş güvenliği raporu`, and `isg rapor`.
2. RiskDetected already ranks well on method terms: `5x5 matris` rank `1`, `risk değerlendirme` rank `2`, and `fine kinney` rank `2` in sampled Sonar app search.
3. Broad `isg` and `iş güvenliği` are noisy. `isg` currently returns Sabiha Gökçen airport and multiple exam/training apps; RiskDetected was not in the sampled top 10.
4. `risk analizi` is relevant but mixed. RiskDetected ranked `6`; the SERP includes ISG competitors, earthquake/building risk, insurance, finance, and unrelated AI analysis apps.
5. Competitor terms have selective paid-search value, but should not be used in App Store metadata.

## Opportunity Table

Opportunity formula:

`(Popularity * 0.4) + ((100 - Difficulty) * 0.3) + (Relevance * 0.3)`

| Keyword | Popularity | Difficulty | Relevance | Opportunity | Sampled Rank | Action |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| iş güvenliği raporu | 5 | 13 | 96 | 56.9 | 7 | Primary / CPP |
| 5x5 matris | 5 | 13 | 93 | 56.0 | 1 | Secondary |
| risk matrisi | 5 | 13 | 93 | 56.0 | not sampled | Secondary |
| isg rapor | 5 | 14 | 92 | 55.4 | not sampled | Primary |
| risk analizi | 5 | 17 | 95 | 55.4 | 6 | Primary |
| fine kinney | 5 | 17 | 94 | 55.1 | 2 | Secondary |
| risk değerlendirme | 5 | 19 | 95 | 54.8 | 2 | Primary |
| tehlike tespiti | 5 | 12 | 88 | 54.8 | not sampled | Long-tail |
| saha denetim | 5 | 13 | 85 | 53.6 | not sampled | Secondary |
| iş güvenliği uzmanı | 5 | 16 | 86 | 53.0 | not sampled | Long-tail |
| iş güvenliği | 5 | 18 | 80 | 50.6 | >10 | Aspirational |
| osgb | 6 | 15 | 72 | 49.5 | not sampled | Discovery |
| isg | 5 | 17 | 75 | 49.4 | >10 | Aspirational / negative split |
| ramak kala form | 7 | 0 | 55 | 49.3 | not sampled | Discovery long-tail |
| dijital rapor isg | 5 | 14 | 70 | 48.8 | not sampled | Discovery / competitor-adjacent |
| findrisk | 23 | 28 | 45 | 44.3 | not sampled | Competitor ads only |
| riskai: i̇sg risk analizi | 54 | 92 | 55 | 40.5 | not sampled | Competitor ads only |
| i̇sg aı pro | 16 | 52 | 40 | 32.8 | not sampled | Competitor ads only |

## Recommended App Store Metadata

Keep the current title. It uses the full 30-character budget and carries the core phrase.

```text
Title (30): RiskDetected: İSG Risk Analizi
```

Add a subtitle that covers report and method intent without repeating the title terms.

```text
Subtitle (23): Rapor, 5x5, Fine Kinney
```

Use the keyword field for non-repeated components that combine with title/subtitle terms.

```text
Keyword Field (100):
değerlendirme,matris,saha,denetim,tehlike,tespiti,uzmanı,osgb,uygunsuzluk,pdf,excel,fotoğraf,kontrol
```

Expected combinations supported by this structure:

- `risk değerlendirme`
- `risk matrisi`
- `5x5 matris`
- `fine kinney`
- `iş güvenliği raporu`
- `isg rapor`
- `saha denetim`
- `tehlike tespiti`
- `iş güvenliği uzmanı`
- `uygunsuzluk tespiti`
- `pdf rapor`
- `excel rapor`

## Apple Search Ads Priority

Use exact match first:

- `risk değerlendirme`
- `risk analizi`
- `iş güvenliği raporu`
- `isg rapor`
- `5x5 matris`
- `fine kinney`
- `risk matrisi`
- `tehlike tespiti`
- `saha denetim`
- `iş güvenliği uzmanı`

Use discovery or low-bid broad only:

- `iş güvenliği`
- `isg`
- `osgb`
- `ramak kala form`
- `dijital rapor isg`

Use competitor exact only with small caps:

- `findrisk`
- `riskai`
- `isg ai pro`
- `first isg`
- `dijital rapor isg`

Do not put competitor names in App Store title, subtitle, keyword field, screenshots, or custom product page copy.

## Negative Keyword Themes

Keep these negative themes from the Apple Ads plan because Sonar confirmed broad-query drift:

- finance: `kredi`, `banka`, `sigorta`, `borsa`, `yatırım`
- earthquake/building risk: `deprem`, `konut`, `bina`
- education/exam traffic: `sınav`, `test`, `sertifika`, `eğitim`, `çıkmış sorular`, `hazırlık`
- airport false positive: `sabiha`, `gökçen`, `airport`
- jobs/salary: `iş ilanı`, `maaş`

## Tracking Plan

Track these weekly in Sonar or Apple Ads Search Terms after the next metadata update:

- `risk değerlendirme`
- `risk analizi`
- `iş güvenliği raporu`
- `isg rapor`
- `5x5 matris`
- `fine kinney`
- `risk matrisi`
- `saha denetim`
- `tehlike tespiti`
- `iş güvenliği uzmanı`
- `iş güvenliği`
- `isg`

Prioritize movement from rank `6-10` into top `3` before expanding budget. For terms where RiskDetected is already rank `1-2`, protect them with exact-match ads only if competitors start buying the same terms.
