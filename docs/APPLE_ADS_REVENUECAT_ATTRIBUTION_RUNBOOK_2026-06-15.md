# Apple Ads RevenueCat Attribution Runbook - 2026-06-15

Scope: RiskDetected iOS Apple Ads attribution and subscription revenue measurement.

## Current Decision

P0 uses RevenueCat-managed Apple AdServices attribution. The app collects the AdServices attribution token through RevenueCat and RevenueCat resolves Apple Ads attribution within its backend. This is the source of truth for the first Apple Ads campaign.

P1 raw backend attribution is intentionally deferred. Do not add a custom Supabase `AAAttribution.attributionToken()` resolver until RevenueCat Charts are proven insufficient for keyword/ad group revenue decisions.

## Implemented

- `App/Services/SubscriptionManager.swift` enables `Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()` after RevenueCat configure.
- The same RevenueCat AdServices helper is re-triggered after `Purchases.shared.logIn(appUserID)` so anonymous-to-Supabase UUID transitions do not depend only on the first anonymous RevenueCat user.
- RevenueCat dashboard was checked on 2026-06-15: `Apple AdServices` is active, and both Basic and Advanced sections show `Done`.
- No ATT prompt, IDFA flow, AdSupport framework, or legacy iAd attribution path is part of P0.

## Preflight

Run this before the next TestFlight/App Review candidate:

```bash
node scripts/apple_ads_attribution_preflight.mjs
```

Expected result:

- All static checks pass.
- Manual gates remain manual: RevenueCat dashboard status and live Apple Ads cohort validation.

The script checks:

- RevenueCat AdServices token collection is still enabled.
- Legacy iAd markers are absent.
- ATT/IDFA/AdSupport markers are absent from the app source/config/project.
- `NSPrivacyTracking` remains false in the app privacy manifest.
- Supabase has the existing join surface for `paywall_events`, `subscription_events`, `user_subscriptions`, and `user_onboarding_answers`.
- RevenueCat webhook still stores `app_user_id`, `raw_event`, and treats processed `event_id` as duplicate.
- P1 custom backend token resolver is not accidentally enabled.

## Supabase Join Check

P0 does not add Apple Ads attribution tables. The useful join for the first campaign is:

- RevenueCat Charts: Apple Ads source/campaign/ad group/keyword -> trials, purchases, revenue.
- Supabase: `paywall_events.user_id` -> `subscription_events.user_id` -> `user_subscriptions.user_id`.

Use this read-only SQL after live events exist:

```sql
select
  pe.user_id,
  min(pe.created_at) filter (where pe.event_name = 'view') as first_paywall_view_at,
  min(pe.created_at) filter (where pe.event_name = 'purchase_started') as first_purchase_started_at,
  min(pe.created_at) filter (where pe.event_name = 'purchase_succeeded') as first_purchase_succeeded_at,
  min(se.received_at) filter (where se.event_type in ('INITIAL_PURCHASE', 'RENEWAL', 'PRODUCT_CHANGE')) as first_revenuecat_paid_event_at,
  us.tier,
  us.status,
  us.product_id,
  us.revenuecat_app_user_id
from public.paywall_events pe
left join public.subscription_events se on se.user_id = pe.user_id
left join public.user_subscriptions us on us.user_id = pe.user_id
group by pe.user_id, us.tier, us.status, us.product_id, us.revenuecat_app_user_id
order by first_paywall_view_at desc
limit 50;
```

If this join does not show the same user through paywall and subscription events, do not scale Apple Ads spend.

## App Review Note

Use this short note in the next submission when relevant:

```text
RiskDetected uses RevenueCat for App Store subscription entitlement management and Apple Ads measurement. The app enables RevenueCat's Apple AdServices attribution token collection for Apple Ads campaign measurement. It does not request App Tracking Transparency permission, does not access IDFA, and does not link or use AdSupport.framework.
```

## Live Campaign Gate

After the new App Store build is live:

1. Run a low-budget Apple Ads Advanced Search Results campaign.
2. Wait for RevenueCat attribution and purchase data to populate. RevenueCat notes that attribution data can take time to appear for new campaigns.
3. In RevenueCat Charts, verify these filters/segments before increasing spend:
   - Attribution source = Apple Search Ads
   - Apple search ads campaign
   - Apple search ads group
   - Apple search ads keyword
   - Apple search ads claim type
4. Confirm at least one downstream monetization signal: paywall view, trial, initial purchase, renewal, or refund/cancellation event.

## P1 Trigger

Start P1 only if at least one of these is true:

- RevenueCat keyword/ad group breakdown is not enough to make budget decisions.
- Supabase admin/dashboard must show independent keyword-level ROAS.
- Apple Ads spend/taps/impressions need to be joined with RevenueCat revenue in Supabase.
- A second source of truth is required before meaningful budget scale.

P1 requires a new app/backend implementation: install-scoped `install_id`, app-to-Supabase token submit, Apple AdServices Attribution API resolve within 24 hours, 404 retry, attribution payload storage, and user/install mapping after login.
