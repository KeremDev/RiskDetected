# V5 repeat-Free API routing and identical paid retry

## Status

Deployed on 2026-09-06 (local time), following explicit owner authorization.
Migrations 20260905232257 and 20260905233537, process-analysis-jobs v50 and
analyze-v4 v97 are live.
`v5_free_repeat_enabled=true`; `v5_same_model_retry_enabled=false`.
`v5_cancelled_plus_trial_free_enabled=true`. The existing enqueue flag
`cancelled_plus_trial_free_routing` remains mode=on.
Existing immutable analysis snapshots retain their routing. No API keys are
included in this repository. Hosted repeat-Free canary completed successfully.
Provider data/region restrictions were disclosed; the owner explicitly requested
activation. This records the operational decision, not a waiver by Google.

## Routing contract

| Cohort | Primary | Additional attempt |
| --- | --- | --- |
| Free first analysis | Existing paid primary/settings | Unchanged (one attempt) |
| Free repeat, attested server snapshot and flag enabled | Gemini 3.5 Flash Lite, legacy free API credential, Standard | None; no silent paid fallback |
| PLUS / PRO paid_plan, retry flag enabled | Existing paid primary/settings | One identical-model/settings retry for transient errors |
| Cancelled active seven-day PLUS trial, attested new snapshot | Gemini 3.5 Flash Lite, Free credential, Standard; PLUS rights unchanged | One attempt; no silent paid fallback |
| Old or untrusted snapshot | Existing paid routing | Unchanged |

The repeat-Free route requires plan_at_creation=free, trusted free_legacy route,
first_paid_ai_eligible=false, and a prior completed analysis belonging to the
same user. A failed first analysis does not by itself qualify for the free API.
The resulting pool and first-use evidence are pinned before enqueue execution.

Free credentials: GEMINI_API_KEY_PRIMARY, otherwise GEMINI_API_KEY. Paid
credentials: GEMINI_API_KEY_PAID, otherwise GEMINI_PAID_API_KEY. Empty aliases
are skipped. No secondary-key rotation or cross-pool fallback is performed.

Gemini 3.5 uses thinkingLevel, not the Gemini 2.5 thinkingBudget. V5 HIGH and
32768 output-token configuration remain unchanged. Free API requests must not
send service_tier=flex (or invent service_tier=free). Free provider cost is zero;
tokens and the comparable Standard cost are still recorded separately.

## Durable retry

Each dispatch makes at most one primary-model request per photo, with the same
110-second timeout. Photo checkpoints persist the attempt count before sending,
the prompt/image/settings identity, completed output, usage and retry timing.
After a transient error, the function returns 202/v5_retry_pending; the existing
queue claim-release mechanism defers another dispatch. No second analysis or
quota reservation is created. Completed photos are reused, and at most two
physical calls are allowed for each eligible paid photo, even after redelivery.

Authentication, safety blocks and output-cap truncation do not blindly retry.
Parse errors can retry once. Database telemetry failures are outside the model
retry catch. All photo promises settle/checkpoint before a claim is released or
the analysis is marked failed. Failed billable usage is included in final totals.

The optional split pass stays unchanged for paid calls and is disabled for the
free API route. This work does not turn the legacy engine into the V5 engine or
change app build rollout gates.

## Credential evidence and remaining preflight

- Production secret inventory contains GEMINI_API_KEY, GEMINI_API_KEY_SECONDARY
  and GEMINI_API_KEY_PAID. Inventory presence alone does not verify live access.
- Documented local Keychain service riskdetected_gemini_api_key_canary matches
  the PAID secret digest, not the legacy free secret. No other RiskDetected
  Gemini Keychain service was found. Secrets were never printed.
- Authenticated model-metadata GET requests using that paid canary key succeeded
  for Gemini 3.5 Flash Lite and Flash. This is NOT a free-tier inference test.
- On 2026-09-06 the actual legacy credential was obtained from authenticated
  AI Studio and its SHA-256 digest matched production GEMINI_API_KEY, not the
  paid or secondary credential. RiskDetected Gemini (gen-lang-client-0277913590)
  was explicitly shown as Free tier. No secret value was printed or saved.
- Actual Gemini 3.5 Flash Lite inference succeeded twice: a text smoke request
  (HTTP 200, 1,915 ms) and a synthetic image using the application provider,
  V5 prompt/schema and parser (HTTP 200, 14,821 ms, STOP, 19 layers, one finding).
  AI Studio usage showed two requests. No customer data was submitted.
- AI Studio showed shared project limits of 15 RPM, 250,000 TPM and 500 RPD for
  Flash Lite. These are not per-user allowances and do not establish production
  capacity. See FREE_TIER_VERIFICATION_2026-09-06.md for evidence and limitations.
- Google unpaid-services data restrictions and regional eligibility must be
  resolved before routing production data. In particular, personal/confidential
  workplace data must not be submitted to unpaid services, and EEA/UK/Switzerland
  API clients require paid services. A universal production enable is not
  appropriate unless the admitted traffic meets those conditions. Consent alone
  is not a substitute for those requirements.

Official references:
- https://ai.google.dev/gemini-api/terms
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/billing

## Release order

1. Apply the migration with both flags OFF; check service_role-only RPC grants.
2. Deploy process-analysis-jobs (recognizes v5_retry_pending) BEFORE analyze-v4.
3. Deploy analyze-v4 and run synthetic/staging retry tests, including a 110-second
   timeout, multi-photo partial success and queue redelivery.
4. Enable v5_same_model_retry_enabled in the active analysis_v4_configs config.
5. Complete the actual free credential/quota and data/region preflight above.
   Only then enable v5_free_repeat_enabled for an appropriately scoped rollout.
6. Inspect new snapshots, photo attempt counts, costs and queue terminal state.

Changing flags affects only NEW immutable snapshots. For rollback, turn the
relevant flag off for new analyses; keep the compatible queue worker deployed
until in-flight jobs finish. Never rewrite in-flight snapshots to switch keys.

The migration was exercised against the production function definitions inside
BEGIN/ROLLBACK; no production flags, schema or user records were left changed.
Hosted Free happy-path verification subsequently passed: analysis
9ab6a329-2dbd-4d30-863a-95df2f169b55, free_standard, gemini-3.5-flash-lite,
HTTP 200, one provider attempt (14,311 ms), one completed quota event and a
released worker lease. Repeat eligibility used a clearly labelled QA prior-
completed fixture, not a second genuine historic analysis.
Rollback-only database assertions passed for first-Free, repeat-Free, PLUS and
PRO routes. Hosted paid retry/fault injection remains outstanding and its flag
was deliberately left OFF. Existing app build gates were not widened.

## Cancelled PLUS trial verification

See CANCELLED_PLUS_TRIAL_FREE_ROUTING_2026-09-06.md. The cancellation decision
uses the server subscription, never a client-supplied renewal flag. Existing
seven-day/date/product/status checks remain in place. UNCANCELLATION restores
will_renew=true and the normal PLUS route for new analyses after synchronization.
