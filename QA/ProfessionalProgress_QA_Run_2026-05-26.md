# Professional Progress QA Run - 2026-05-26T10:45:11.030Z

- Overall: PASS
- Checks: 35
- Failures: 0

## Results

| status | check | details |
| --- | --- | --- |
| PASS | cleanup before QA | completed |
| PASS | setup synthetic progress data and assertions | completed |
| PASS | RLS own select | completed |
| PASS | RLS other user hidden | completed |
| PASS | RLS client event insert rejected | rejected as expected |
| PASS | RLS client MDP mutation blocked | rejected as expected |
| PASS | RLS client MDP unchanged | completed |
| PASS | RLS seen_at update allowed | completed |
| PASS | RLS badge title mutation blocked | rejected as expected |
| PASS | RLS badge title unchanged | completed |
| PASS | cleanup after QA | completed |
| PASS | BADGE report/risk/onboarding/risk-report/title badges | competency:3, onboarding_area:first_report:mining, report_kind:first_risk_analysis, reports:1, risk:first_high, title:field_observer |
| PASS | CLS-01 category priority KKD -> ppe | expected ppe/finding_category/0.96 |
| PASS | CLS-02 unclassified excluded from stats | expected no stat row |
| PASS | CLS-02 unknown classifier returns no row | expected 0 |
| PASS | CLS-03 highest risk wins | critical |
| PASS | CLS-04 four classifications including unclassified | chemical:high, mining:medium, ppe:critical, unclassified:low |
| PASS | DB-03 progress table count | 7 |
| PASS | DB-04 RLS enabled table count | 7 |
| PASS | DRIFT event/profile MDP match | profile=925, events=925 |
| PASS | DRIFT no duplicate events | expected no duplicate event_key |
| PASS | MDP idempotent duplicate report event rejected | expected false |
| PASS | MDP weekly bonus once | 1 |
| PASS | MDP-01/02/03 total MDP exact | 925 |
| PASS | MDP-05 title threshold field_observer | field_observer |
| PASS | MSG human readable competency label | Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. |
| PASS | MSG safe language scan | İlk yüksek/kritik riskli analizini tamamladın. Zor olanı görünür kıldın. \| 3 farklı yetkinlik alanında risk dokümante ettin. \| Tebrikler. Saha Gözlemcisi ünvanına ulaştınız. Bu, 500 MDP'lik mesleki birikim demek. \| İlk detaylı risk analizi raporunu arşivledin. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. \| Onboardingde belirttiğin çalışma alanında ilk gerçek raporunu oluşturdun. \| İlk raporunu oluşturdun. Mesleki takip izin başladı. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. |
| PASS | MSG weekly summary one row | 2/1/4/chemical |
| PASS | NOTIF columns exist | expected 3 columns |
| PASS | ONB-01 mining/construction onboarding seeds | construction, mining |
| PASS | DB-05 own progress rows readable | 1 |
| PASS | DB-05 other user rows hidden | 0 |
| PASS | DB-05 client MDP cannot mutate | 925 |
| PASS | DB-05 seen_at update allowed | 1 |
| PASS | DB-05 badge title cannot mutate | İlk Adım |

## Failed Command Output
