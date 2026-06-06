# Analyze Edge Function Readiness - 2026-06-05

Scope: App Review / Internal TestFlight production lane for `RiskDetected`.

This check was run without printing secret values and without deploying or changing
production Supabase state.

## Result

PASS for automated readiness.

No production deploy was required.

The earlier `AI hatası: Requested function was not found` evidence came from the
legacy QA Supabase lane. The App Review/Internal TestFlight lane uses production
Supabase, where `analyze` and `process-analysis-jobs` are deployed and active.

Manual TestFlight acceptance also passed. The current `RiskDetected` TestFlight
build was opened, a normal RiskDetected account was used, and a Free analysis
completed with the result opening successfully.

## Commands Run

```bash
node --check scripts/analyze_readiness_check.mjs
node --check scripts/app_review_preflight_collect.mjs
deno check supabase/functions/analyze/index.ts
deno check supabase/functions/process-analysis-jobs/index.ts
node scripts/analyze_readiness_check.mjs
node scripts/app_review_preflight_collect.mjs --skip-asc --skip-devices --output QA/tmp/App_Review_Preflight_Evidence_analyze_readiness_probe_2026-06-05.md
```

## Automated Readiness Evidence

`node scripts/analyze_readiness_check.mjs` returned:

- `PASS: 23`
- `INFO: 1`
- `FAIL: 0`
- `HOLD: 0`

Key checks:

- Production project `ppcrzemgiztzcgddbins`:
  - `analyze`: `ACTIVE`, `verify_jwt=false`, version `97`.
  - `process-analysis-jobs`: `ACTIVE`, `verify_jwt=false`, version `9`.
- Legacy QA project `iidhnqvuszjcoyncqzkg`:
  - `analyze`: missing.
  - `process-analysis-jobs`: missing.
  - This is not an App Review blocker because the current submission lane uses production Supabase.
- `InternalTestFlight` and `Release` Xcode build settings point to production Supabase URL/key.
- Main `RiskDetected` scheme has no QA Supabase runtime override and no local StoreKit override.
- Remote `analyze` bundle contains expected markers:
  - prompt version marker
  - `reserve_analysis_quota`
  - `enqueue_analysis_job_message`
  - `GEMINI_API_KEY_PAID`
  - `GROQ_API_KEY_PLUS_PRO`
- Required production secret names are present:
  - Free Gemini key path.
  - Paid Gemini key path.
  - `PROCESS_ANALYSIS_JOBS_SECRET`.
  - Free/Paid AI fallback secret path.
- Production test-simulation secret names are absent:
  - `RISKDETECTED_ENABLE_TEST_SIMULATION`
  - `SIMULATE_AI_ERROR_CODE`
  - `SIMULATE_AI_ERROR_ONCE`
- Database readiness is present:
  - `pgmq`
  - `pg_cron`
  - `pg_net`
  - `supabase_vault`
  - queue RPCs
  - `reserve_analysis_quota`
  - active `riskdetected-analysis-jobs-every-minute` cron job
  - DB Vault `project_url`
  - DB Vault `analysis_worker_secret`
- Recent stuck analyses:
  - `0` `queued/analyzing` analyses in the last 24 hours.
- No-bypass gateway smoke:
  - Invalid JWT reached `analyze` and returned `401 auth_invalid`.
  - It did not return `Requested function was not found`.

## App Review Collector Integration

`scripts/app_review_preflight_collect.mjs` now falls back to
`scripts/analyze_readiness_check.mjs --functions-json` when the local Supabase CLI
cannot parse `supabase functions list --output json`.

Probe report:

- `QA/tmp/App_Review_Preflight_Evidence_analyze_readiness_probe_2026-06-05.md`

Relevant result from that report:

- `PASS`: Supabase Edge Functions deno check.
- `PASS`: Supabase deployed Edge Functions.
- Evidence source: Supabase Management API fallback.

The probe report still has unrelated App Review preflight failures/HOLDs, including
manual ASC items, old collector marker expectations, missing unpacked IPA path, and
Supabase CLI failures for advisors/db lint. Those are not `analyze` function-not-found
readiness failures.

## Deployment Decision

Do not deploy for this item right now.

Deploy only if a future production-lane check shows one of these:

- production `analyze` or `process-analysis-jobs` missing/inactive;
- remote function `verify_jwt` differs from `supabase/config.toml`;
- remote `analyze` bundle markers are missing;
- no-bypass gateway smoke returns function-not-found;
- current TestFlight production-lane app returns `Requested function was not found`.

If deployment becomes necessary, deploy only:

```bash
supabase functions deploy analyze --project-ref ppcrzemgiztzcgddbins --no-verify-jwt
supabase functions deploy process-analysis-jobs --project-ref ppcrzemgiztzcgddbins --no-verify-jwt
```

Do not deploy to the legacy QA project for App Review readiness.

## Manual TestFlight Acceptance

PASS.

User-reported final smoke:

1. Opened the current `RiskDetected` TestFlight build.
2. Signed in with a normal RiskDetected account.
3. Ran a Free analysis through the app UI.
4. The analysis completed and the result opened successfully.

Read-only database follow-up for `pokipi1451@bncinema.com` confirmed:

- analysis status: `completed`;
- `last_worker_error`: `null`;
- `worker_attempt_count`: `1`;
- `ai_usage_logs`: `1` row;
- model: `gemini-2.5-flash`;
- provider: `gemini`;
- route: `free_paid_trial`;
- HTTP status: `200`;
- error: `null`.

No temp-user DB manipulation or email-confirm bypass was used as final App Review evidence.
