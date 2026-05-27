# Professional Progress QA Run - 2026-05-26T17:23:09.177Z

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
| PASS | BADGE report/risk/onboarding/risk-report/diversity badges | competency:3, onboarding_area:first_report:mining, report_kind:first_risk_analysis, reports:1, risk:first_high |
| PASS | CLS-01 category priority KKD -> ppe | expected ppe/finding_category/0.96 |
| PASS | CLS-02 unclassified excluded from stats | expected no stat row |
| PASS | CLS-02 unknown classifier returns no row | expected 0 |
| PASS | CLS-03 highest risk wins | critical |
| PASS | CLS-04 four classifications including unclassified | chemical:high, mining:medium, ppe:critical, unclassified:low |
| PASS | DB-03 progress table count | 7 |
| PASS | DB-04 RLS enabled table count | 7 |
| PASS | DRIFT event/profile MDP match | profile=425, events=425 |
| PASS | DRIFT no duplicate events | expected no duplicate event_key |
| PASS | MDP idempotent duplicate report event rejected | expected false |
| PASS | MDP weekly bonus once | 1 |
| PASS | MDP-01/02/03 total MDP exact | 425 |
| PASS | MDP-05 title threshold candidate | candidate |
| PASS | MSG human readable competency label | Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. |
| PASS | MSG safe language scan | İlk yüksek/kritik riskli analizini tamamladın. Zor olanı görünür kıldın. \| 3 farklı yetkinlik alanında risk dokümante ettin. \| İlk detaylı risk analizi raporunu arşivledin. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. \| Onboardingde belirttiğin çalışma alanında ilk gerçek raporunu oluşturdun. \| İlk raporunu oluşturdun. Mesleki takip izin başladı. \| Bu raporda KKD alanında yüksek/kritik riskleri görünür kıldın. |
| PASS | MSG weekly summary one row | 2/1/4/chemical |
| PASS | NOTIF columns exist | expected 3 columns |
| PASS | ONB-01 mining/construction onboarding seeds | construction, mining |
| PASS | DB-05 own progress rows readable | 1 |
| PASS | DB-05 other user rows hidden | 0 |
| PASS | DB-05 client MDP cannot mutate | 425 |
| PASS | DB-05 seen_at update allowed | 1 |
| PASS | DB-05 badge title cannot mutate | İlk Adım |

## Failed Command Output

## Manual Visual QA - 2026-05-27

- PASS: Profil sayfası hero, istatistik satırı, mesleki ilerleme kartı, haftalık takip kartı, yetkinlik haritası ve Plus/Pro kartı iPhone 17 Pro light mode üzerinde kontrol edildi.
- PASS: Ana sayfa haftalık takip kartı ve compact progress şeridi iPhone 17 Pro light/dark mode üzerinde kontrol edildi.
- PASS: Compact progress şeridinin dark mode zemin/kontrastı iyileştirildi; MDP, hedef, yüzde ve "Kıdemini yükselt" metinleri okunur durumda.
- PASS: Mesleki Ünvanlar sheet'i iPhone 17 Pro ve iPhone 17e üzerinde açıldı; kazanılmış/kilitli rütbe ikonları, aktif rozet çerçevesi ve xmark kapatma kontrolü çalışıyor.
- PASS: Başarılarım sheet'i iPhone 17 Pro ve iPhone 17e üzerinde açıldı; kazanılmış başarılar renkli, kilitli başarılar gri/kilitli görünüyor ve xmark kapatma kontrolü çalışıyor.
- PASS: Rütbe Puanlama sheet'i iPhone 17 Pro ve iPhone 17e üzerinde açıldı; kullanıcı dili güncellendi ve "Tek akışta 400 MDP" teknik ifadesi kaldırıldı.
- PASS: Bildirimler, Profil Bilgileri, Destek, Yasal Bilgilendirme, Firmalarım ve Rapor ayarları sheet'lerinde xmark kapatma kontrolleri denendi.
- PASS: Firmalarım free/locked sheet'i içerik yüksekliğine göre açılıyor; paid firma düzenleme akışı mevcut demo hesabında erişilemediği için görsel olarak açılmadı.
- PASS: Final Debug build iPhone 17 Pro ve iPhone 17e simulator üzerinde başarılı.
