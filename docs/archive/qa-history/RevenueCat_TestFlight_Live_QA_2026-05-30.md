# RevenueCat / TestFlight Live QA - 2026-05-30

## Scope

- TestFlight sandbox purchase / restore
- RevenueCat package and paywall visibility
- Supabase subscription sync
- Pro account E2E readiness

## Results

- PASS: TestFlight sandbox Plus yearly purchase completed on device.
- PASS: Paywall package telemetry shows Plus monthly, Plus yearly, Pro monthly, and Pro yearly package IDs loaded/selected from the app.
- PASS: Paywall purchase telemetry recorded `purchase_started` and `purchase_succeeded` for `riskdetected_plus_yearly`.
- PASS: RevenueCat subscriber lookup for `kayalar.kerem@gmail.com` shows active Plus entitlement.
- PASS: Supabase `user_subscriptions` is synced to Plus for the same user.
- PASS: RevenueCat webhook events for the Plus purchase were received and processed.
- PASS: Free paid AI routing live E2E passed in `QA/FreePaidAIRouting_QA_2026-05-30.md`.
- PASS: TestFlight Restore tap was recorded and backend subscription stayed Plus active.
- PASS: TestFlight Pro purchase/upgrade E2E passed with live analysis, report, AI telemetry, and push events.

## Evidence

### Plus Purchase User

- Email: `kayalar.kerem@gmail.com`
- User id: `1600e01c-3395-43f2-8f28-66db3306ec4c`
- Supabase profile tier: `plus`
- Supabase subscription:
  - `tier=plus`
  - `status=active`
  - `source=revenuecat_sync`
  - `product_id=riskdetected_plus_yearly`
  - `entitlement_id=plus`
  - `environment=SANDBOX`
  - `current_period_ends_at=2026-05-30T23:40:51Z`

### Paywall Telemetry

- `view` recorded for in-app Plus paywall.
- `billing_select` recorded for:
  - `plus_monthly::riskdetected_plus_monthly`
  - `plus_yearly::riskdetected_plus_yearly`
  - `pro_monthly::riskdetected_pro_monthly`
  - `pro_yearly::riskdetected_pro_yearly`
- `cta_tap`, `purchase_started`, and `purchase_succeeded` recorded for:
  - `plus_yearly::riskdetected_plus_yearly`
- Restore telemetry:
  - Event: `restore_tap`
  - User: `kayalar.kerem@gmail.com`
  - Created at: `2026-05-30T00:20:21.272181Z`
  - Selected package at tap time: `pro_yearly::riskdetected_pro_yearly`
  - Current tier in metadata: `plus`
- Restore post-check:
  - Supabase `profiles.tier=plus`
  - Supabase `user_subscriptions.tier=plus`
  - `status=active`
  - `product_id=riskdetected_plus_yearly`
  - `updated_at=2026-05-30T00:20:22.198Z`

### RevenueCat Webhook / Sync

- Processed subscription events for user `1600e01c-3395-43f2-8f28-66db3306ec4c`:
  - `TRANSFER`
  - `PRODUCT_CHANGE`
  - `RENEWAL`
- Latest Plus event:
  - Event id: `95BD042F-EB86-4104-BAAF-B5D1024483A3`
  - Event type: `RENEWAL`
  - Product: `riskdetected_plus_yearly`
  - Entitlements: `plus`
  - Processed at: `2026-05-29T23:40:58.348Z`

## Pro Account Finding

Existing Pro profile rows are not enough to close real Pro E2E:

- `keremkayalar@icloud.com` appears as Pro in Supabase, but RevenueCat subscriber lookup has no active entitlements/subscriptions for that app user id.
- `kayalar.kerem.game@gmail.com` appears as Pro in Supabase, but RevenueCat subscriber lookup has no active entitlements/subscriptions for that app user id.
- Some Supabase Pro subscription rows have `current_period_ends_at` dates in the past, so they should not be treated as a fresh real Pro purchase smoke.

## Pro Purchase / E2E Re-Test

- User purchased Pro from TestFlight after the Plus/restore checks.
- Supabase subscription state after purchase:
  - Email: `kayalar.kerem@gmail.com`
  - User id: `1600e01c-3395-43f2-8f28-66db3306ec4c`
  - `profiles.tier=pro`
  - `user_subscriptions.tier=pro`
  - `status=active`
  - `source=revenuecat_sync`
  - `product_id=riskdetected_pro_monthly`
  - `entitlement_id=pro`
  - `environment=SANDBOX`
  - `current_period_ends_at=2026-05-31T00:22:26Z`
- Processed RevenueCat events:
  - `PRODUCT_CHANGE`, event id `8884ECCC-69C4-4263-9A38-BFADB0F8AA99`, entitlements `pro`
  - `RENEWAL`, event id `EC3CD901-6DC5-4F4C-B9D2-836D9A3AD201`, product `riskdetected_pro_monthly`, entitlements `pro`
- Live Pro analysis:
  - Analysis id: `2824dd0c-7d6a-4029-84fd-7f1c26a0a341`
  - Mode: `standard`
  - Status: `completed`
  - Findings: `11`
  - Model: `gemini-2.5-flash`
- Live Pro standard PDF report:
  - Report id: `07ce2cf4-316f-4c86-b180-ed689192d012`
  - Kind: `standard`
  - Format: `pdf`
  - File size: `1064661`
  - `report_ready_push_sent_at=2026-05-30T00:24:40.69Z`
- AI usage telemetry:
  - `user_plan=pro`
  - `quality_tier=pro`
  - `ai_execution_route=paid_plan`
  - `provider=gemini`
  - `model=gemini-2.5-flash`
  - `api_key_alias=gemini_paid_primary`
  - `total_tokens=7124`
  - `http_status=200`
- Push events:
  - Pro account update events: `sent`
  - Pro `analysis_complete`: `sent`
  - Pro `report_ready`: `sent`

## Remaining Manual Device Steps

- None for this QA group.
