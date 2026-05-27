# Professional Progress Test Plan - 2026-05-26

## Scope

This plan covers the new `ProfessionalProgress` module end to end:

- Supabase migration `20260526093512_professional_progress_module.sql`
- iOS module under `App/Features/ProfessionalProgress/`
- Home/Profile integration and `RDConfig.Features.professionalProgressEnabled`
- Progress notification preferences in `NotificationService`
- `send-push-notification` progress preference handling
- Hybrid QA static checks in `scripts/qa_hybrid_runner.mjs`

The module must stay removable. Analysis, report, onboarding, paywall, company, auth, and notification core flows must keep working when progress UI or backend processing fails.

## Release Gates

Do not ship unless all P0/P1 gates pass:

| Priority | Gate | Expected |
| --- | --- | --- |
| P0 | Local migration reset | `supabase db reset --local --yes` exits 0 |
| P0 | Remote migration state | `supabase db push --dry-run` returns `Remote database is up to date` |
| P0 | iOS build/run | XcodeBuildMCP `build_run_sim` succeeds |
| P0 | Edge function check | `deno check supabase/functions/send-push-notification/index.ts` exits 0 |
| P0 | Client cannot write MDP/events | Authenticated client insert/update to event/profile MDP is rejected |
| P0 | Core flow isolation | Analysis/report creation still succeeds if progress trigger raises warning |
| P1 | Idempotency | Reprocessing same analysis/report does not duplicate MDP, badges, weekly bonus, or classifications |
| P1 | Feature flag off | Home/Profile progress UI is fully hidden and app remains usable |
| P1 | Classification accuracy smoke | Known category samples map to the fixed taxonomy; unknown stays `unclassified` |
| P1 | Notification preferences | Progress toggles update only progress columns and push respects them |

## Test Data Matrix

Use at least 3 test users:

| User | Setup | Purpose |
| --- | --- | --- |
| `pp_empty_user` | New account, no onboarding, no analyses | Empty state, feature flag, no crash |
| `pp_onboarding_user` | Onboarding sectors: `mining`, `construction` | Onboarding seed, declared area chip |
| `pp_power_user` | Multiple analyses/reports across risk levels and categories | MDP, titles, badges, weekly summary, aggregation |

Use at least these finding samples:

| Category | Title/Description Signal | Expected Competency |
| --- | --- | --- |
| `KKD uyumsuzluğu` | `Maske yok`, `kimyasal buhar` | `ppe` because category wins |
| `Kimyasal risk` | `SDS yok`, `solvent` | `chemical` |
| `Yangın güvenliği` | `acil çıkış kapalı` | `fire` |
| `Elektrik` | `pano kapağı açık` | `electrical` |
| `Mekanik risk` | `forklift`, `sıkışma` | `mechanical` |
| `Ergonomi` | `manuel taşıma`, `duruş` | `ergonomics` |
| `Psikososyal` | `vardiya`, `stres` | `psychosocial` |
| `Yüksekte çalışma` | `iskele`, `ankraj`, `düşme` | `working_at_height` |
| `Maden` | `ocak`, `galeri`, `havalandırma` | `mining` |
| `İnşaat` | `şantiye`, `kalıp`, `hafriyat` | `construction` |
| `Fabrika` | `üretim hattı`, `konveyör`, `pres` | `factory` |
| `Genel` | `Belirsiz bulgu`, no taxonomy keyword | `unclassified` |

## Database And Migration Tests

### DB-01 Local Reset

Command:

```bash
supabase db reset --local --yes
```

Expected:

- Exit code 0.
- Migration `20260526093512_professional_progress_module.sql` applies.
- No blocking errors.
- Warnings from `drop policy if exists` are acceptable.

### DB-02 Remote State

Command:

```bash
supabase db push --dry-run
```

Expected:

- `Remote database is up to date`.
- If Supabase pooler circuit breaker appears, wait and retry one command at a time. Do not parallelize remote DB queries.

### DB-03 Table Count

Command:

```bash
supabase db query --local --output json "
select count(*)::int as progress_tables
from information_schema.tables
where table_schema = 'public'
  and table_name like 'professional_progress_%';
"
```

Expected: `progress_tables = 7`.

### DB-04 RLS Enabled

Command:

```bash
supabase db query --local --output json "
select count(*)::int as rls_tables
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname like 'professional_progress_%'
  and c.relrowsecurity;
"
```

Expected: `rls_tables = 7`.

### DB-05 Grants And Client Write Protection

Validate as authenticated client:

- `select` own progress rows succeeds.
- `insert` into `professional_progress_events` fails.
- `update total_mdp` on `professional_progress_profiles` fails.
- `update seen_at` on own badges/messages succeeds.
- Updating badge/message fields other than `seen_at` fails.
- Reading another user's progress rows returns 0 rows.

### DB-06 Account Deletion Cascade

Create a disposable test user with progress rows, then delete the auth user.

Expected:

- Rows are removed from all progress tables.
- Core analyses/reports cleanup follows existing account deletion behavior.

## Event Ledger And MDP Tests

### MDP-01 Analysis Completion Event

Create a completed detailed analysis with one high/critical risk.

Expected:

- One `analysis_completed:{analysis_id}` event.
- MDP delta includes detailed analysis `70` and high/critical analysis `120`.
- `total_analyses` increments by 1.
- Re-running trigger or backfill does not create a duplicate event.

### MDP-02 Report Created Event

Create a standard report.

Expected:

- One `report_created:{report_id}` event.
- MDP +60.
- `total_reports` increments by 1.
- Weekly bonus event may appear once for `weekly_bonus:{week_start}` with +25.

### MDP-03 Risk Analysis Export Bonus

Create a risk analysis report with `kind in ('riskAnalysis', 'risk_analysis')` or `format = 'xlsx'`.

Expected:

- Report MDP is `60 + 90`.
- Badge `report_kind:first_risk_analysis` unlocks once.

### MDP-04 First Competency Bonus

First real classified finding in a competency area.

Expected:

- One `first_competency_used:{competency_key}` event.
- MDP +20 once per competency.
- Repeated findings in the same competency do not add this bonus again.
- One analysis/report workflow is capped at `400` MDP.

### MDP-05 Title Thresholds

Seed MDP around boundaries:

- 0
- 999
- 1000
- 4999
- 5000
- 14999
- 15000
- 39999
- 40000
- 89999
- 90000
- 179999
- 180000

Expected title keys:

- `candidate`
- `field_observer`
- `risk_hunter`
- `hazard_analyst`
- `senior_risk_specialist`
- `safety_strategist`
- `master_hse_specialist`

Title change should create:

- `title_changed:{title_key}` event
- `title:{title_key}` badge
- `title_change` message

## Classification Tests

### CLS-01 Category Priority

Command:

```bash
supabase db query --local --output json "
select *
from private.pp_competency_for_finding(
  'KKD uyumsuzluğu',
  'Maske yok',
  'Kimyasal buhar maruziyeti var',
  'SDS ve maske kullanımı',
  'general',
  array['mining']::text[]
);
"
```

Expected:

- `competency_key = 'ppe'`
- `matched_by = 'finding_category'`
- `confidence = 0.96`

### CLS-02 Unknown Stays Unclassified

Command:

```bash
supabase db query --local --output json "
select count(*)::int as no_match_rows
from private.pp_competency_for_finding(
  'Genel',
  'Belirsiz bulgu',
  'Açıklama',
  'Öneri',
  'general',
  '{}'::text[]
);
"
```

Expected:

- Function returns 0 rows.
- Trigger/backfill writes `competency_key = 'unclassified'`.
- `unclassified` does not update `professional_progress_competency_stats`.
- `unclassified` does not appear in iOS competency map.

### CLS-03 Risk Level Max Rule

Create findings with:

- Fine-Kinney `high`, 5x5 `critical`
- Fine-Kinney `critical`, 5x5 `medium`
- Fine-Kinney `low`, 5x5 `medium`
- both unknown/null equivalent through source values if possible

Expected:

- Higher severity wins.
- Stored `risk_level` is `critical`, `critical`, `medium`, `unknown`.

### CLS-04 Multiple Findings In One Analysis

One analysis contains:

- one KKD finding
- one chemical finding
- one mining finding

Expected:

- Three rows in `professional_progress_finding_classifications`.
- Three competency stat rows update.
- `analysis_count` increments once per distinct competency, not once per finding.

### CLS-05 Canvas Fallback

Create findings with weak text but canvas values:

- `fire`
- `explosion`
- `electrical`
- `ppe`
- `working_at_height`
- `machine`
- `mobile_equipment`
- `construction_machinery`
- `ergonomics`
- unknown canvas value

Expected:

- Known canvas values map with `matched_by = 'canvas_fallback'`.
- Unknown canvas value does not throw and becomes `unclassified`.

## Onboarding Tests

### ONB-01 Sector Seed Mapping

Insert/update onboarding sectors:

- `mining`
- `construction`
- `manufacturing`
- `energy`
- `office`

Expected seeded competency stats:

- `mining -> mining`
- `construction -> construction`
- `manufacturing -> factory`
- `energy -> chemical, electrical, fire`
- `office -> ergonomics, psychosocial`

Expected:

- `onboarding_seed = true`
- MDP remains unchanged.
- `onboarding_competency_seeded:{competency}` events have `mdp_delta = 0`.

### ONB-02 Declared Area First Real Report

User declares `mining`, then creates first real report with mining classification.

Expected:

- Badge key `onboarding_area:first_report:mining`.
- Message language is professional and non-legal.
- Badge remains after later data changes.

## Badges And Messages Tests

### BADGE-01 Report Count Badges

Test thresholds:

- 1, 10, 25, 50, 100, 250, 500, 1000 reports

Expected:

- Correct badge key and title.
- Unlock once only.
- `seen_at` initially null.
- Marking seen updates only `seen_at`.

### BADGE-02 Competency Diversity Badges

Test real competency coverage:

- 3
- 5
- 8
- 11

Expected:

- `competency:3`, `competency:5`, `competency:8`, `competency:11`.
- `unclassified` does not count.
- Onboarding-only seed does not count unless real finding/report exists.

### BADGE-03 Active Day Badges

Create activity on distinct Istanbul-local dates:

- 30
- 90
- 365

Expected:

- `active_days:30`, `active_days:90`, `active_days:365`.
- Multiple analyses/reports on the same date count as one active day.

### MSG-01 Safe Language Scan

Search progress messages and UI text for banned phrases:

```bash
rg "Yasal olarak|Kesin olarak|üst %|güvendesin|çalışanları korudun" \
  App/Features/ProfessionalProgress \
  supabase/migrations/20260526093512_professional_progress_module.sql
```

Expected:

- No matches.

### MSG-02 Instant Message

Create report with high/critical classified finding.

Expected:

- `professional_progress_messages.message_type = 'instant'`.
- Body uses safe language such as `görünür kıldın`.
- Competency label is human readable, e.g. `KKD`, `Kimyasal`, not raw `ppe`.

### MSG-03 Weekly Summary

Create analysis/report in current week.

Expected:

- One row per user/week in `professional_progress_weekly_summaries`.
- `reports_count`, `analyses_count`, `findings_count` are recomputed.
- `top_competency_key` excludes `unclassified`.
- Re-running refresh updates same row, does not duplicate.

## iOS Service Tests

### IOS-SVC-01 Empty Summary

Authenticated user has no `professional_progress_profiles` row.

Expected:

- `ProfessionalProgressService.fetchSummary()` returns empty profile summary.
- No crash.
- Home/Profile may show empty progress state if feature enabled.

### IOS-SVC-02 Fetch Failure Isolation

Temporarily block one progress table or simulate Supabase query failure.

Expected:

- Service logs error.
- Returns nil.
- Home/Profile hide progress section.
- Core app remains usable.

### IOS-SVC-03 Mark Seen

Open celebration sheet and tap `Tamam`.

Expected:

- `professional_progress_badges.seen_at` updates.
- Sheet does not reappear after refresh.
- Other badge fields are unchanged.

## iOS UI Tests

### IOS-UI-01 Feature Flag On

With `RDConfig.Features.professionalProgressEnabled = true`:

- Home shows compact progress card after primary scan button when summary exists.
- Profile shows `Mesleki İlerleme` after stats row.
- Badges sheet opens.
- Competency detail sheet opens.
- Celebration sheet opens for unseen badge.

### IOS-UI-02 Feature Flag Off

Temporarily set:

```swift
static let professionalProgressEnabled = false
```

Expected:

- No Home progress card.
- No Profile progress section.
- No progress service fetch attempts.
- Analysis/report/onboarding/paywall/company flows unchanged.

### IOS-UI-03 Light/Dark Mode

Verify:

- Home card
- Profile MDP card
- Quick stats
- Badges grid
- Competency rows
- Celebration sheet
- Notification progress toggles

Expected:

- Uses `rdPaper`, `rdWhite`, `rdBlack`, `rdSlate`, `rdGreen*`, risk colors.
- Text remains readable.
- Border/contrast visible in dark mode.

### IOS-UI-04 Small Screen Layout

Use smallest supported iPhone simulator.

Expected:

- MDP number does not overlap title.
- Long Turkish titles fit or scale.
- `Yüksekte Çalışma` and `Beyan edilen alan` chips do not break layout.
- Badge tiles remain 3-column only if readable; otherwise this is a design bug to address.

### IOS-UI-05 Accessibility

Verify:

- Dynamic Type at larger sizes.
- VoiceOver labels for badge tiles: earned vs locked.
- Toggles have understandable labels in notification sheet.
- Color is not the only indicator for competency/risk; icon + label + count exist.

## Notification Tests

### NOTIF-01 Preference Columns Exist

Validate:

- `progress_weekly_summary`
- `progress_monthly_summary`
- `progress_milestones`

Expected default: `true`.

### NOTIF-02 Toggle Writes Correct Column

In Profile notification settings:

- Toggle weekly off.
- Toggle monthly off.
- Toggle milestones off.

Expected:

- Only corresponding column changes.
- Global `enabled`, `analysis_complete`, `report_ready`, `account_updates` remain unchanged.

### NOTIF-03 Edge Function Honors Preference

Call `send-push-notification` with kind:

- `progress_weekly_summary`
- `progress_monthly_summary`
- `progress_milestones`

Expected:

- If corresponding preference false: notification event status `skipped`, `last_error = user_preference_disabled`.
- If true: event queued/sent depending on device token.
- Lock screen body remains generic for summary pushes.

### NOTIF-04 Tap Routing

Send a test push with `kind = progress_weekly_summary`.

Expected:

- App opens Profile tab.
- No analysis/report deep link is attempted.

## Backfill And Drift Tests

### DRIFT-01 Backfill Consistency

Compare source tables to progress summaries:

- completed analyses count
- reports count
- finding count
- risk level totals
- competency classification count excluding unclassified

Expected:

- Differences are zero or explained by deleted source rows.

### DRIFT-02 Reconciliation Idempotency

Re-run summary/backfill logic in a disposable local DB.

Expected:

- No duplicate `backfill_seed:2026-05-26` event.
- No duplicate classifications because `unique(finding_id)`.
- Summary totals remain stable.

### DRIFT-03 Aggregate Update After New Report

Create analysis first, then report later.

Expected:

- Existing classifications reused.
- `report_count` increments in each distinct competency from that analysis.
- Weekly summary refreshes.

## Core Isolation Regression Tests

### CORE-01 Progress Trigger Failure Does Not Break Analysis

Force a classifier edge case locally by temporarily raising an exception inside `private.pp_process_analysis_completed`.

Expected:

- Analysis remains completed.
- Warning is logged.
- Core result/report flow remains usable.

### CORE-02 Progress Trigger Failure Does Not Break Report

Force a progress report processing exception locally.

Expected:

- Report row is created.
- Report file flow remains usable.
- Warning is logged.

### CORE-03 Module Removal Smoke

Temporarily hide UI with feature flag and do not call progress service.

Expected:

- Home, Profile, Analysis, Result, Report, History work normally.
- No compile error if `App/Features/ProfessionalProgress` is excluded only after removing UI references.

## Performance Tests

### PERF-01 Fetch Summary Latency

Measure Profile load with:

- 0 progress rows
- 100 badges/messages
- 1000 classifications

Expected:

- `fetchSummary()` remains acceptable because it reads summary tables and limits badges/messages.
- No direct full classification fetch from iOS.

### PERF-02 Report/Analysis Trigger Latency

For analysis with:

- 1 finding
- 10 findings
- 50 findings

Expected:

- Trigger overhead is acceptable.
- No lock waits or duplicate event conflicts.

### PERF-03 Backfill Volume

On staging/prod-like copy:

- Run migration/backfill timing.
- Watch table/index creation and classification count.

Expected:

- Migration completes without timeout.
- If volume grows, split future backfill into batch function/job.

## Automation Plan

### Existing Commands

Run before every release candidate:

```bash
node --check scripts/qa_hybrid_runner.mjs
deno check supabase/functions/send-push-notification/index.ts
supabase db reset --local --yes
supabase db push --dry-run
```

Run iOS:

1. XcodeBuildMCP `session_show_defaults`
2. XcodeBuildMCP `build_run_sim`

### Add To Hybrid QA

Extend `scripts/qa_hybrid_runner.mjs` with read-only checks:

- Progress table count = 7
- Progress RLS table count = 7
- Event duplicate groups count = 0
- Classification duplicate finding count = 0
- `unclassified` excluded from competency stats
- Profile MDP drift vs event sum = 0
- Badge duplicate groups count = 0
- Weekly summary duplicate groups count = 0
- Notification progress columns exist

Do not run remote DB checks in parallel. Supabase pooler can temporarily circuit-break after repeated failed/auth-heavy connections.

## Manual QA Checklist

- New user sees no progress crash.
- Onboarding `mining` shows Maden as declared area.
- First real Maden report unlocks declared-area badge.
- Standard report gives MDP and weekly bonus once.
- XLSX/risk analysis report gives extra MDP once.
- Critical/high finding unlocks `Cesur Karar`.
- Unknown finding appears in classification table as `unclassified` and not in UI competency map.
- Home progress card shows title, MDP, progress bar, report count, leading competency.
- Profile section opens badges and competency detail.
- Celebration sheet is calm, dismissible, and does not repeat after seen.
- Notification progress toggles persist.
- Progress push opens Profile.
- Banned legal/guarantee language does not appear.
- Dark mode and small screen layouts are clean.

## Known Risk Areas

- Keyword classifier is deterministic but still heuristic. Add regression samples whenever a false positive appears.
- Existing production data can expose classification edge cases that empty local reset cannot. Keep remote/staging backfill smoke after every classifier change.
- Remote Supabase CLI queries should be sequential. Parallel linked DB queries can trigger pooler auth/circuit breaker.
- Progress service currently fetches four tables concurrently. If PostgREST schema cache is stale immediately after migration, UI should fail closed and hide the module.
- `feature flag off` is compile-time static now; runtime remote flag would need a separate test set later.

## Sign-Off Criteria

Module is ready for release when:

- All P0/P1 gates pass.
- At least one full analysis-to-report flow updates MDP, classification, badge/message, and weekly summary correctly.
- iOS Home/Profile visual QA passes on light/dark and small screen.
- Notification toggles and push routing pass.
- No banned language is found.
- `supabase db push --dry-run` says remote is up to date.
