# RiskDetected Apple Search Ads First Campaign

Date: 2026-06-15
Market: Turkiye App Store
App: RiskDetected: ISG Risk Analizi
App ID: 6769498181

## Goal

Launch a controlled Apple Ads Advanced test for Search Results only. The first goal is not scale; it is to learn which search terms produce high-intent installs and paid-plan signals without letting broad traffic spend the budget.

## Current App Store Signals

- App is live: version 1.1, released after version 1.0 approval on 2026-06-11.
- App Store categories from Apple lookup: Productivity primary, Business secondary.
- Current rating signal is small but strong: 5.0 average from 3 ratings.
- Core value proposition: AI-supported occupational safety risk analysis from photo/text, Fine-Kinney and 5x5 Matrix outputs, PDF/Excel reporting.
- In-app monetization: Free -> Plus -> Pro subscription funnel, RevenueCat-backed.

## Before Spending

1. Use Apple Ads Advanced, not Basic.
2. Country/region: Turkiye only.
3. Placement: Search Results only.
4. Account currency: choose deliberately before account finalization. Apple Ads supports currencies such as USD and EUR, but not TRY as of the checked Apple billing docs.
5. Verify RevenueCat Apple Search Ads attribution before scale. The app now enables RevenueCat Apple AdServices token collection after RevenueCat configure and after RevenueCat login; RevenueCat dashboard Apple AdServices is active. Keep the first campaign small until RevenueCat Charts shows Apple Ads source/campaign/ad group/keyword subscription signals.
6. Confirm that App Store Connect screenshots and product page assets are final. Search Results default ads use App Store metadata/assets unless a custom product page ad variation is selected.

## Launch Budget

Use a 14-day learning budget.

Recommended starting cap: USD 10/day total.

| Campaign | Daily budget | Max CPT starting point | Purpose |
| --- | ---: | ---: | --- |
| RD_TR_Brand_SearchResults_Exact | USD 1 | USD 1.00-1.50 | Protect app/developer name searches |
| RD_TR_Category_SearchResults_Exact | USD 5 | USD 0.50-1.20 | Main high-intent acquisition |
| RD_TR_Competitor_SearchResults_Exact | USD 2 | USD 0.30-0.70 | Controlled competitor conquesting |
| RD_TR_Discovery_SearchResults | USD 2 | USD 0.20-0.45 | Mine new terms via broad/Search Match |

If eligible for Apple's new account credit, use it as the first test budget, but keep the same daily caps.

## Campaign Structure

### 1. Brand Exact

Search Match: off
Match type: exact

Keywords:

- `[riskdetected]`
- `[risk detected]`
- `[riskdetected isg]`
- `[riskdetected iş güvenliği]`
- `[riskdetected risk analizi]`
- `[ibrahim kerem kayalar]`

Why: Brand volume will likely be low because the app is new, but exact brand coverage prevents cheap leakage later.

### 2. Category Exact

Search Match: off
Match type: exact

Create two ad groups so bids can differ.

Ad group: `Risk_Method_Report_Exact`

- `[risk değerlendirme]`
- `[risk analizi]`
- `[isg risk]`
- `[iş güvenliği raporu]`
- `[isg rapor]`
- `[risk matrisi]`
- `[5x5 matris]`
- `[fine kinney]`
- `[saha risk]`

Ad group: `Workplace_Safety_Exact`

- `[iş güvenliği]`
- `[iş sağlığı güvenliği]`
- `[iş güvenliği denetim]`
- `[saha denetim]`
- `[tehlike tespiti]`
- `[osgb]`
- `[iş güvenliği uzmanı]`

Bid the first ad group higher. The second group is broader and can mix students, job seekers, OSGB service buyers, and general research traffic.

### 3. Competitor Exact

Search Match: off
Match type: exact
Do not use competitor names in ad copy or CPP promotional text.

Keywords to test:

- `[findrisk]`
- `[riskbul]`
- `[first isg]`
- `[first iş güvenliği]`
- `[riskai]`
- `[isg ai pro]`
- `[dijital rapor isg]`
- `[isg gozcu]`
- `[safetyculture]`
- `[hse reporter pro]`
- `[ramak kala form]`

Keep this capped. Competitor terms can have lower install and purchase conversion even when taps look strong.

### 4. Discovery

Campaign budget: small and fixed.

Ad group A: `Discovery_Search_Match`

- No keywords.
- Search Match: on.
- Max CPT: USD 0.20-0.35.

Ad group B: `Discovery_Broad`

- Add the strongest category and competitor seeds as broad match.
- Search Match: off.
- Max CPT: USD 0.25-0.45.

Add all exact keywords from Brand, Category, and Competitor as exact-match negatives in Discovery so the discovery campaign does not compete with the performance campaigns.

## Starting Negatives

Add these as account or campaign negatives before launch, then expand weekly from Search Terms.

Broad negative themes:

- `kredi`
- `kredi notu`
- `banka`
- `sigorta`
- `borsa`
- `yatırım`
- `deprem`
- `konut`
- `bina`
- `oyun`
- `sınav`
- `test`
- `iş ilanı`
- `maaş`
- `sertifika`
- `eğitim`
- `sabiha`
- `gökçen`
- `airport`

Reason: App Store searches for `risk raporu`, `risk analizi`, and `isg` can drift into finance, earthquake/building risk, education/tests, or unrelated abbreviation traffic.

## Custom Product Pages

Start with default product page if CPP assets are not ready, but prepare these before increasing spend:

1. `CPP_Rapor_Excel`
   - Use for: `iş güvenliği raporu`, `isg rapor`, `risk analizi`, `saha denetim`
   - Screenshot story: photo/text input -> AI finding list -> PDF/Excel report -> share/archive.

2. `CPP_FineKinney_5x5`
   - Use for: `fine kinney`, `5x5 matris`, `risk matrisi`, `risk değerlendirme`
   - Screenshot story: risk score -> Fine-Kinney -> 5x5 matrix -> action plan.

3. `CPP_Saha_Denetim`
   - Use for: `iş güvenliği denetim`, `tehlike tespiti`, `iş güvenliği uzmanı`
   - Screenshot story: field photo -> hazard detection -> prioritized measures -> report.

## First 14 Days Optimization

Review Search Terms every 2-3 days at launch.

Move to exact:

- Search term has installs and relevant intent.
- Search term has high TTR and at least one downstream paywall/trial/purchase signal.
- Search term is highly relevant even with low volume, such as `fine kinney` or `5x5 matris`.

Add negatives:

- High impressions, low TTR.
- Taps from unrelated finance, earthquake, job, exam, education, or general dictionary intent.
- Any broad/Search Match term with 10+ taps and no install, unless the product page clearly mismatched the intent and a CPP test is planned.

Bid rules:

- Exact keyword has installs below target CPI: raise CPT 10-20%.
- Exact keyword gets no impressions but is strategically important: raise CPT gradually toward Apple recommendation.
- Keyword gets taps but weak installs: lower bid or pause.
- Discovery term performs: add it to Category Exact, then add it as an exact negative in Discovery.

Do not raise total budget until:

- RevenueCat or another attribution view shows Apple Ads cohort revenue/purchase data.
- Category Exact has stable install conversion.
- At least 2 CPPs are live or the default product page has strong TTR and install conversion.

## Core Metrics

- TTR = taps / impressions. Above 5% is strong; below 3% means keyword/creative mismatch.
- CVR = installs / taps. Above 50% is strong; below 30% needs product page or intent review.
- CPT = spend / taps.
- CPI = spend / installs.
- Revenue ROAS = subscription revenue / spend.

For RiskDetected, the first paid scaling decision should be based on CPI plus trial/purchase rate, not installs alone.

## Source Notes

- Apple Ads campaign structure recommends separating brand, category, competitor, and discovery campaigns, and using Search Match/broad primarily for discovery: https://ads.apple.com/app-store/best-practices/campaign-structure
- Apple Ads Search Match uses App Store metadata, similar apps, and search data: https://ads.apple.com/app-store/help/campaigns/0006-understand-search-match
- Apple Ads match type docs distinguish broad and exact match and recommend negatives for control: https://ads.apple.com/app-store/help/keywords/0059-understand-keyword-match-types
- Apple Ads custom product page ad variations can be created from App Store Connect CPPs without submitting a new app version: https://ads.apple.com/app-store/help/ads/0077-create-ad-variations
- Apple Ads account currency support was checked here: https://ads.apple.com/app-store/help/get-started/0030-set-your-payment-method
- RevenueCat Apple Search Ads attribution notes were checked here: https://www.revenuecat.com/docs/integrations/attribution/apple-search-ads
- RiskDetected App Store lookup was checked via Apple's iTunes Search API and App Store link: https://apps.apple.com/tr/app/riskdetected-i-sg-risk-analizi/id6769498181
