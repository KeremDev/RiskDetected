# Reports Defaults and Archive Dense QA - 2026-05-15

## Scope

- Pro/Plus PDF and XLSX report defaults.
- Report archive search, filters, status labels, empty/error handling and load-more behavior.
- Dense archive pagination beyond the first Supabase page.

## Code QA

- PDF defaults now resolve from profile before report generation:
  - profile logo -> report logo;
  - preparer name;
  - title;
  - document number;
  - company name/details;
  - default risk method.
- Standard PDF, detailed risk-analysis PDF and XLSX metadata use the same profile-backed defaults.
- PDF preview/share is no longer blocked by a non-quota archive save failure. The user still gets the generated PDF and sees an archive warning.
- Archive fetch uses paged Supabase range queries:
  - initial archive fetch: 100 rows;
  - local reveal: 5 rows per tap;
  - remote continuation: next 100 rows when local matches are exhausted;
  - duplicate rows are dropped by `id` and `storage_path`.

## Dense Data QA

Command:

```bash
node scripts/qa_report_archive_heavy.mjs
```

Result:

```text
Report archive dense QA passed
syntheticRows: 247
initialFetchSize: 100
localPageSize: 5
counts:
  all: 247
  pdf: 211
  excel: 36
  standard: 140
  riskAnalysis: 107
  thisWeek: 14
```

Covered scenarios:

- First page loads 100 reports.
- Load-more reveals local rows in +5 increments.
- When the first 100 local rows are exhausted, the archive fetches the next 100 rows.
- Final short page stops remote pagination.
- Filtered load-more still fetches remote continuation after local matching Excel rows are exhausted.
- Duplicate merge by report id and storage path is rejected.
- Turkish diacritic-insensitive search matches `İş Güvenliği` with `is guvenligi`.

## Simulator Smoke

Environment:

- XcodeBuildMCP simulator: iPhone 17 Pro.
- Scheme: `RiskDetected`.
- Account state: Pro demo session.

Observed:

- Reports tab opens with `Kayıtlı Rapor Dosyaları`.
- Archive shows 21 saved report files.
- Filter chips render with counts:
  - `Tümü`;
  - `PDF`;
  - `Excel`;
  - `Standart`;
  - `Risk analizi`;
  - `Bu hafta`.
- Archive rows show file type labels such as `Excel tablo`, `Standart rapor`, `Risk analizi`.
- Method/status labels render in rows, including `FK` and `Hazır`.
- Excel filter shows only Excel rows.
- Load-more control is visible with the current visible/total count.

## Verification Commands

```bash
deno check supabase/functions/generate-excel-report/index.ts
node scripts/qa_report_archive_heavy.mjs
git diff --check
```

XcodeBuildMCP:

```text
build_run_sim: SUCCEEDED
```

## Remaining Release Spot Checks

- TestFlight real-device share sheet for newly generated PDF and XLSX.
- Very long company/preparer/title values in real customer profile data.
- Production-scale archive telemetry after launch.
