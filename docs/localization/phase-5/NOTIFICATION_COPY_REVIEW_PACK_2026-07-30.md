# RiskDetected Faz 5 — Notification Copy Review Pack

Tarih: 2026-07-30  
Durum: **review required**  
Kapsam: `en-001`, `en-GB`, `en-US`, `en-AU`, `en-CA`

Bu paketteki İngilizce metinler bütün Wave 1 locale'lerinde aynıdır. Runtime
çözümleme yine tam locale ile yapılır; bir locale eksikse başka İngilizce
locale'e veya Türkçeye fallback yapılmaz.

## Operations Center automation

| Event/template | Title | Body |
| --- | --- | --- |
| `first_analysis_reminder_v1` | Your first analysis is waiting | Add a site photo and review the risks in a few minutes. |
| `inactivity_reminder_v1` | Do not postpone site risks | Add a new site photo, update the risk assessment and review the controls. |

Bu iki template migration'da `draft` olarak seed edilir. İnsan onayı
verilmeden `approved` yapılmaz ve İngilizce otomasyon job'ı fail closed olur.

## Transactional push

| Stable event key | Title | Body |
| --- | --- | --- |
| `analysis_complete` | Analysis ready | Your risk assessment is ready to review. |
| `report_ready` | Report ready | Your risk report is ready in the Reports section. |
| `trial_reminder` | Your detailed-analysis trial ends soon | There are 2 days left in your Plus trial. |
| `progress_weekly_summary` | Your weekly progress summary is ready | Review your professional progress for this week. |
| `progress_monthly_summary` | Your monthly progress summary is ready | Review your professional progress for this month. |
| `progress_milestones` | You reached a new progress milestone | Review the details of your professional progress in Profile. |
| `account_update.cancellation` | Subscription cancellation received | Your plan will remain active until the end of the billing period. |
| `account_update.expiration` | Your subscription has ended | Your RiskDetected account has moved to the free plan. |
| `account_update.billing_issue` | Payment details need attention | Check your App Store payment details to keep your subscription active. |
| `account_update.subscription_paused` | Subscription paused | Your RiskDetected account has temporarily moved to the free plan. |

## Review kaydı

- Reviewer: pending
- Reviewer role/qualification: pending
- Decision: pending
- Reviewed at: pending
- Notes: pending

