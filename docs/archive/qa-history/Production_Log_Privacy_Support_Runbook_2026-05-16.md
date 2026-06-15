# Production Log Privacy and Support Lookup Runbook

Date: 2026-05-16

## Scope

This pass covers production error/log readiness for:

- iOS DEBUG-only simulation flags.
- Supabase Edge Function test simulation flags.
- Edge Function log privacy.
- Support id lookup flow for user-reported errors.

## Simulation Flags

### iOS

The iOS-only failure simulation helpers are guarded by `#if DEBUG` and return `false` in non-DEBUG builds:

- `ReportFailureSimulation`
  - `RISKDETECTED_ENABLE_REPORT_TEST_SIMULATION`
  - `SIMULATE_REPORT_ERROR`
- `DataActionFailureSimulation`
  - `RISKDETECTED_ENABLE_DATA_TEST_SIMULATION`
  - `SIMULATE_DATA_ERROR`

Production/TestFlight release builds cannot enable these code paths through runtime env alone.

### Edge Functions

The AI simulation path in `analyze` is disabled by default and only runs when:

- `RISKDETECTED_ENABLE_TEST_SIMULATION=true`
- `SIMULATE_AI_ERROR_CODE` is one of `429`, `500`, `502`, `503`, `504`, `invalid_json`

Production secrets must not contain:

- `RISKDETECTED_ENABLE_TEST_SIMULATION`
- `SIMULATE_AI_ERROR_CODE`
- `SIMULATE_AI_ERROR_ONCE`

Verification command:

```bash
supabase secrets list --project-ref ppcrzemgiztzcgddbins
```

If any simulation secret appears in production, unset it immediately:

```bash
supabase secrets unset RISKDETECTED_ENABLE_TEST_SIMULATION SIMULATE_AI_ERROR_CODE SIMULATE_AI_ERROR_ONCE --project-ref ppcrzemgiztzcgddbins
```

## Edge Function Log Privacy

Reviewed and tightened:

- `analyze`
  - User ids in operational logs are hashed.
  - Raw Storage paths are not logged.
  - Gemini errors are logged as status/name summaries, not raw response bodies.
  - DB/storage errors are logged as bounded summaries with `request_id` and `support_id`.
- `generate-excel-report`
  - Upload/metadata/logo errors are logged as bounded summaries.
  - No raw Storage path or user id is logged in function logs.
- `support-contact`
  - Resend failure detail is truncated and email addresses/tokens are redacted before logging.
- `send-push-notification`
  - APNs credential and device-token-like long hex strings are redacted/truncated before storing `last_error`.
  - HTTP error responses no longer include raw provider details.
- `account-deletion-complete`
  - Operator-visible errors are bounded and bearer tokens are redacted.

Allowed in logs:

- `support_id`
- `request_id`
- non-sensitive status/error codes
- model name and API key alias such as `gemini_primary`
- counts, durations and HTTP status codes

Not allowed in logs:

- bearer tokens, service-role key, API keys or APNs private key
- raw photo base64 or raw AI prompt/input
- email body/attachment body
- full push device token
- raw Storage object path containing user id
- unredacted user id in routine function logs

## Support Id Lookup

When a user sends a support code like `RD-58771F8E`, check in this order.

### AI / Analysis

```sql
select created_at, request_id, support_id, user_id, analysis_id, provider, model,
       api_key_alias, http_status, error_code, fallback_source, duration_ms
from public.ai_usage_logs
where support_id = 'RD-XXXXXXXX'
order by created_at desc
limit 20;
```

If needed:

```sql
select id, user_id, status, status_message, created_at, updated_at
from public.analyses
where id in (
  select analysis_id from public.ai_usage_logs where support_id = 'RD-XXXXXXXX'
);
```

### PDF / XLSX Reports

```sql
select created_at, request_id, support_id, user_id, analysis_id, format,
       kind, method, title, file_name, mime_type, size_bytes
from public.reports
where support_id = 'RD-XXXXXXXX'
order by created_at desc
limit 20;
```

### Account Deletion

```sql
select id, status, requested_scope, target_user_hash, completion_support_id,
       completion_error, deleted_photo_objects, deleted_report_objects,
       deleted_logo_objects, auth_user_deleted, created_at, completed_at
from public.account_deletion_requests
where completion_support_id = 'RD-XXXXXXXX'
order by created_at desc
limit 20;
```

### Edge Function Logs

Use Supabase Dashboard > Edge Functions > target function > Logs and search:

- `RD-XXXXXXXX`
- matching `request_id`
- function name, for example `analyze` or `generate-excel-report`

## Verification

- `deno fmt` and `deno check` passed for changed Edge Functions.
- `supabase functions deploy --use-api --no-verify-jwt` completed for changed deployed functions.
- Unauthenticated `account-deletion-complete` call returns `401`.
- `supabase db lint --linked` still reports pre-existing issues in:
  - `private.cleanup_expired_retention`
  - `public.check_and_consume_quota`

Those lint findings are outside this log/privacy pass and should be handled separately.
