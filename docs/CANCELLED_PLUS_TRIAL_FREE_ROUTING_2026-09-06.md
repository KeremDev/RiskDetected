# Cancelled PLUS trial provider routing — 2026-09-06

## Live behavior

- Still-active, cancelled seven-day PLUS yearly trial: product remains PLUS;
  provider uses Free API gemini-3.5-flash-lite / Standard.
- Renewing trial, normal paid PLUS and PRO: existing paid route unchanged.
- UNCANCELLATION: existing subscription sync sets will_renew=true; subsequent
  enqueue decisions return to paid_plan. Trial expiration uses existing
  entitlement lifecycle; no trial extension or premature entitlement removal.
- PLUS quotas, three-photo allowance, reports and result access are not changed.
- Old queued snapshots are immutable. The change applies to new compatible V5
  analyses after server subscription synchronization, not instantaneously at an
  unobserved store cancellation. Existing app build gates are preserved.

The subscription-lifecycle review kept entitlement and provider billing
independent. Existing enqueue eligibility requires PLUS yearly product, active
status, will_renew=false, approximately seven-day trial, matching trial/current
period end and a current time inside the trial. Existing Play store checks are
preserved too. There is no client-side permission downgrade.

## Implementation

- Migration 20260905233537 preserves cancellation candidate/enabled evidence
  in the server snapshot and pins free_standard only for the verified cohort.
- Runtime requires trusted source/version, product_plan=plus, cancelled trial
  route, both boolean attestations, pinned free pool and enabled engine flag.
- Actual analysis plan must match the pinned product plan. The API credential
  changes, not the entitlement. One attempt per photo; no paid fallback.
- analyze-v4 v97 deployed before enabling v5_cancelled_plus_trial_free_enabled.
  Existing cancelled_plus_trial_free_routing mode=on was retained. Repeat-Free
  remains enabled; paid retry remains disabled. No auth setting changes.

## Verification

- 67 isolated tests passed (53 lifecycle/routing + 14 billing/worker).
- Seven database routing assertions passed and were rolled back, covering
  valid and incomplete cancelled-trial attestations and preserved cohorts.
- Anonymous and authenticated callers cannot execute the routing RPC.
- Hosted canary analysis: 1129cace-5eba-4737-b6d8-a7ca02896809.
- Synthetic QA user: a0c8ccb2-2db5-4918-bcd4-abe45e2028dd.
- Real queue and model request completed: gemini-3.5-flash-lite, free_standard,
  HTTP 200, 13,667 ms, one persisted provider attempt, one completed quota record,
  worker attempt count one, one finding.
- Server record stayed plan_at_creation=plus and subscription tier=plus,
  max_photos_allowed_at_creation=3, with original trial end preserved.
- Canary subscription was an explicit QA synthetic fixture (SANDBOX), not an
  actual Apple purchase/cancellation. No real App Store cancellation was induced.
  QA trace rows and synthetic image are retained for inspection.

Manual reproduction: RD_CONFIRM_HOSTED_CANARY=ppcrzemgiztzcgddbins and
RD_CANARY_COHORT=cancelled_plus_trial with scripts/hosted_free_repeat_canary.mjs.
Requires the synthetic image at /tmp/rd-free-synthetic-scene.png. Creates only
a new QA user/fixture/analysis; credentials are held in memory.

Rollback for new snapshots: set v5_cancelled_plus_trial_free_enabled=false in
the active private.analysis_v4_configs config; keep the compatible engine.
Do not rewrite running snapshots or alter subscription dates/tiers to rollback.

No app build, commit or push was performed.

References reviewed: [RevenueCat trial cancellation flows](https://www.revenuecat.com/docs/integrations/webhooks/event-flows),
[uncancellation events](https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields).
