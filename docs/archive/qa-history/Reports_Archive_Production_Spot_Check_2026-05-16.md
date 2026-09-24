# Reports Archive Production Telemetry / Performance Spot-Check

Date: 2026-05-16

## Scope

- Reports archive DB index and row distribution check on linked Supabase project.
- iOS archive query payload review.
- Client-side telemetry hook for archive initial load and load-more behavior.
- Build verification after code and migration changes.

## Production Snapshot

- `public.reports` live tuple estimate: 34 live rows, 36 dead rows.
- Top report-heavy user currently has 26 archived reports:
  - 21 PDF
  - 5 XLSX
- Overall format/method distribution observed:
  - 14 standard PDF / Fine-Kinney
  - 10 riskAnalysis PDF / Fine-Kinney
  - 6 XLSX risk analysis / Fine-Kinney
  - 3 riskAnalysis PDF / 5x5
  - 1 XLSX risk analysis / 5x5

## Findings

- Required access indexes are present:
  - `reports_user_created` for `user_id + created_at desc`
  - `reports_user_format_created` for format-filtered report archive access
  - request/support id indexes for support lookup
- Duplicate legacy index found:
  - `reports_user_id_idx` duplicated `reports_user_created`.
- iOS list query was using `select()` and pulling all columns, although the archive UI only needs a bounded report row projection.

## Changes

- Added migration `20260516163356_drop_duplicate_reports_user_id_idx.sql`.
- Applied migration to linked Supabase project.
- Verified `reports_user_id_idx` is gone and canonical indexes remain.
- Narrowed `AnalysisService.listReports` projection to only the columns used by `ReportRow`.
- Added PII-free OSLog telemetry in `ReportView`:
  - `initial_load`
  - `load_more`
  - duration in ms
  - fetched count
  - cached count
  - offset
  - remote-more flag
  - active filter/search state

## Verification

- `supabase db push --linked --yes` completed.
- `supabase migration list --linked` shows local/remote aligned through `20260516163356`.
- Index verification query confirms only `reports_user_created` and `reports_user_format_created` remain from the user archive path.
- XcodeBuildMCP simulator build + launch succeeded with no diagnostics.
- `supabase db lint --linked` still reports two pre-existing unrelated function lint issues:
  - `private.cleanup_expired_retention`: temp table static lint false-positive / existing issue.
  - `public.check_and_consume_quota`: legacy ambiguous `tier` reference.

## Result

Reports archive production telemetry/performance spot-check is complete. No release-blocking archive performance issue was found at current production volume; one duplicate index was removed and client archive reads now transfer a smaller payload.
