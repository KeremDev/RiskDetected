#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const REPORT_PATH = process.argv.includes("--output")
  ? process.argv[process.argv.indexOf("--output") + 1]
  : `QA/ProfessionalProgress_QA_Run_${new Date().toISOString().slice(0, 10)}.md`;

const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const A1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";
const R1 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1";
const R2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2";
const INSTANCE = "00000000-0000-0000-0000-000000000000";

function runLocalSql(name, sql, { expectFailure = false } = {}) {
  const startedAt = Date.now();
  const result = spawnSync("docker", [
    "exec",
    "-i",
    "supabase_db_RiskDetected",
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
    "-X",
    "-q",
    "-t",
    "-A",
    "-F",
    "\t",
  ], {
    cwd: process.cwd(),
    encoding: "utf8",
    input: sql,
    maxBuffer: 30 * 1024 * 1024,
  });
  const durationMs = Date.now() - startedAt;
  const rows = parsePsqlRows(result.stdout ?? "");
  const passed = expectFailure ? result.status !== 0 : result.status === 0;

  return {
    name,
    status: passed ? "PASS" : "FAIL",
    note: expectFailure
      ? passed ? "rejected as expected" : "unexpectedly succeeded"
      : passed ? "completed" : `exit ${result.status}`,
    durationMs,
    command: `docker exec -i supabase_db_RiskDetected psql <sql:${sql.length} chars>`,
    rows,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

function parsePsqlRows(stdout) {
  return stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const parts = line.split("\t");
      if (parts.length >= 3) {
        return { name: parts[0], status: parts[1], details: parts.slice(2).join("\t") };
      }
      if (parts.length === 1) {
        return { value: parseInt(parts[0], 10), raw: parts[0] };
      }
      return { raw: line };
    });
}

function psqlValue(rows) {
  if (!rows.length) return null;
  if (Number.isFinite(rows[0].value)) return rows[0].value;
  const parsed = Number(rows[0].raw);
  return Number.isFinite(parsed) ? parsed : rows[0].raw;
}

function psqlRowsPass(run, expectedValue) {
  const value = psqlValue(run.rows);
  if (expectedValue === undefined) {
    return run.status === "PASS";
  }
  return run.status === "PASS" && value === expectedValue;
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

const cleanupSql = `
delete from auth.users
where id in (${sqlString(U1)}::uuid, ${sqlString(U2)}::uuid);
`;

const setupAndAssertSql = `
delete from auth.users
where id in (${sqlString(U1)}::uuid, ${sqlString(U2)}::uuid);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (${sqlString(INSTANCE)}::uuid, ${sqlString(U1)}::uuid, 'authenticated', 'authenticated',
   'pp-power-user@example.test', 'qa', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  (${sqlString(INSTANCE)}::uuid, ${sqlString(U2)}::uuid, 'authenticated', 'authenticated',
   'pp-other-user@example.test', 'qa', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.profiles (id, email, full_name)
values
  (${sqlString(U1)}::uuid, 'pp-power-user@example.test', 'PP Power User'),
  (${sqlString(U2)}::uuid, 'pp-other-user@example.test', 'PP Other User')
on conflict (id) do update
set email = excluded.email,
    full_name = excluded.full_name;

insert into public.user_onboarding_answers (
  user_id,
  onboarding_version,
  sectors,
  hazard_classes,
  raw_answers
) values (
  ${sqlString(U1)}::uuid,
  'v2',
  array['mining','construction']::text[],
  '{}'::text[],
  '{}'::jsonb
)
on conflict (user_id) do update
set sectors = excluded.sectors,
    updated_at = now();

insert into public.analyses (
  id,
  user_id,
  title,
  kind,
  canvas,
  status,
  started_at,
  primary_method,
  highest_band_fk,
  highest_band_m5,
  analysis_mode,
  created_at
) values (
  ${sqlString(A1)}::uuid,
  ${sqlString(U1)}::uuid,
  'PP QA Analizi',
  'text',
  'general',
  'pending',
  now() - interval '15 minutes',
  'fine_kinney',
  'high',
  'critical',
  'detailed',
  now() - interval '15 minutes'
);

insert into public.findings (
  analysis_id, user_id, ordinal, title, category, description, recommended_action, confidence,
  fk_probability, fk_frequency, fk_severity, fk_band,
  m5_probability, m5_severity, m5_band
) values
  (${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid, 1, 'Maske yok', 'KKD uyumsuzluğu', 'Kimyasal buhar maruziyeti var', 'Uygun maske ve eğitim', 0.90, 3, 3, 15, 'high', 5, 5, 'critical'),
  (${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid, 2, 'SDS eksik', 'Kimyasal risk', 'Solvent etiketsiz kapta tutuluyor', 'SDS ve etiketleme', 0.88, 3, 2, 15, 'high', 3, 3, 'medium'),
  (${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid, 3, 'Galeri havalandırması', 'Maden', 'Ocak galerisinde havalandırma zayıf', 'Havalandırmayı iyileştir', 0.86, 1, 2, 15, 'medium', 2, 2, 'low'),
  (${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid, 4, 'Belirsiz gözlem', 'Genel', 'Açıklama', 'Öneri', 0.50, 1, 1, 3, 'low', 1, 1, 'low');

update public.analyses
set status = 'completed',
    completed_at = now() - interval '10 minutes',
    highest_band_fk = 'high',
    highest_band_m5 = 'critical',
    analysis_mode = 'detailed'
where id = ${sqlString(A1)}::uuid;

insert into public.reports (
  id, analysis_id, user_id, document_no, format, storage_path, method,
  kind, title, file_name, mime_type, size_bytes, file_size, page_count, created_at
) values (
  ${sqlString(R1)}::uuid, ${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid,
  'PP-QA-0001', 'pdf', '${U1}/${A1}/pp-qa-0001.pdf', 'fine_kinney',
  'standard', 'PP QA Standard Report', 'pp-qa-0001.pdf', 'application/pdf', 1024, 1024, 2, now() - interval '5 minutes'
), (
  ${sqlString(R2)}::uuid, ${sqlString(A1)}::uuid, ${sqlString(U1)}::uuid,
  'PP-QA-0002', 'xlsx', '${U1}/${A1}/pp-qa-0002.xlsx', 'fine_kinney',
  'risk_analysis', 'PP QA Risk Report', 'pp-qa-0002.xlsx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 2048, 2048, 1, now() - interval '4 minutes'
);

with qa as (
  select 'DB-03 progress table count' as name,
         (select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'professional_progress_%') = 7 as ok,
         (select count(*)::text from information_schema.tables where table_schema = 'public' and table_name like 'professional_progress_%') as details
  union all
  select 'DB-04 RLS enabled table count',
         (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'professional_progress_%' and c.relrowsecurity) = 7,
         (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'professional_progress_%' and c.relrowsecurity)
  union all
  select 'CLS-01 category priority KKD -> ppe',
         exists (
           select 1 from private.pp_competency_for_finding('KKD uyumsuzluğu','Maske yok','Kimyasal buhar maruziyeti var','SDS','general', array['mining']::text[])
           where competency_key = 'ppe' and matched_by = 'finding_category' and confidence = 0.96
         ),
         'expected ppe/finding_category/0.96'
  union all
  select 'CLS-02 unknown classifier returns no row',
         (select count(*) from private.pp_competency_for_finding('Genel','Belirsiz bulgu','Açıklama','Öneri','general','{}'::text[])) = 0,
         'expected 0'
  union all
  select 'ONB-01 mining/construction onboarding seeds',
         (select count(*) from public.professional_progress_competency_stats where user_id = ${sqlString(U1)}::uuid and onboarding_seed and competency_key in ('mining','construction')) = 2,
         (select string_agg(competency_key, ', ' order by competency_key) from public.professional_progress_competency_stats where user_id = ${sqlString(U1)}::uuid and onboarding_seed)
  union all
  select 'CLS-04 four classifications including unclassified',
         (select count(*) from public.professional_progress_finding_classifications where analysis_id = ${sqlString(A1)}::uuid) = 4
           and exists (select 1 from public.professional_progress_finding_classifications where analysis_id = ${sqlString(A1)}::uuid and competency_key = 'unclassified'),
         (select string_agg(competency_key || ':' || risk_level, ', ' order by competency_key) from public.professional_progress_finding_classifications where analysis_id = ${sqlString(A1)}::uuid)
  union all
  select 'CLS-03 highest risk wins',
         exists (select 1 from public.professional_progress_finding_classifications where analysis_id = ${sqlString(A1)}::uuid and competency_key = 'ppe' and risk_level = 'critical'),
         (select risk_level from public.professional_progress_finding_classifications where analysis_id = ${sqlString(A1)}::uuid and competency_key = 'ppe' limit 1)
  union all
  select 'CLS-02 unclassified excluded from stats',
         not exists (select 1 from public.professional_progress_competency_stats where user_id = ${sqlString(U1)}::uuid and competency_key = 'unclassified'),
         'expected no stat row'
  union all
  select 'MDP-01/02/03 total MDP exact',
         (select total_mdp from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid) = 425,
         (select total_mdp::text from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'MDP-05 title threshold candidate',
         (select current_title_key from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid) = 'candidate',
         (select current_title_key from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'MDP idempotent duplicate report event rejected',
         private.pp_record_event(${sqlString(U1)}::uuid, 'report_created:${R1}', 'report_created', 100, ${sqlString(A1)}::uuid, ${sqlString(R1)}::uuid, null, '{}'::jsonb, now()) = false,
         'expected false'
  union all
  select 'MDP weekly bonus once',
         (select count(*) from public.professional_progress_events where user_id = ${sqlString(U1)}::uuid and event_type = 'weekly_report_bonus') = 1,
         (select count(*)::text from public.professional_progress_events where user_id = ${sqlString(U1)}::uuid and event_type = 'weekly_report_bonus')
  union all
  select 'BADGE report/risk/onboarding/risk-report/diversity badges',
         (select count(*) from public.professional_progress_badges where user_id = ${sqlString(U1)}::uuid and badge_key in ('reports:1','risk:first_high','onboarding_area:first_report:mining','report_kind:first_risk_analysis','competency:3')) = 5,
         (select string_agg(badge_key, ', ' order by badge_key) from public.professional_progress_badges where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'MSG safe language scan',
         not exists (
           select 1 from public.professional_progress_messages
           where user_id = ${sqlString(U1)}::uuid
             and (body ~* 'Yasal olarak|Kesin olarak|üst %|güvendesin|çalışanları korudun')
         ),
         (select coalesce(string_agg(body, ' | ' order by created_at), '-') from public.professional_progress_messages where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'MSG human readable competency label',
         exists (select 1 from public.professional_progress_messages where user_id = ${sqlString(U1)}::uuid and body like '%KKD alanında%'),
         (select coalesce(string_agg(body, ' | ' order by created_at), '-') from public.professional_progress_messages where user_id = ${sqlString(U1)}::uuid and message_type = 'instant')
  union all
  select 'MSG weekly summary one row',
         exists (
           select 1 from public.professional_progress_weekly_summaries
           where user_id = ${sqlString(U1)}::uuid and reports_count = 2 and analyses_count = 1 and findings_count = 4 and top_competency_key <> 'unclassified'
         ),
         (select coalesce(string_agg(reports_count || '/' || analyses_count || '/' || findings_count || '/' || coalesce(top_competency_key, '-'), ', '), '-') from public.professional_progress_weekly_summaries where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'DRIFT event/profile MDP match',
         (select total_mdp from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid) =
           (select coalesce(sum(mdp_delta), 0) from public.professional_progress_events where user_id = ${sqlString(U1)}::uuid),
         (select 'profile=' || total_mdp::text from public.professional_progress_profiles where user_id = ${sqlString(U1)}::uuid) ||
           (select ', events=' || coalesce(sum(mdp_delta), 0)::text from public.professional_progress_events where user_id = ${sqlString(U1)}::uuid)
  union all
  select 'DRIFT no duplicate events',
         not exists (
           select 1 from public.professional_progress_events
           where user_id = ${sqlString(U1)}::uuid
           group by event_key
           having count(*) > 1
         ),
         'expected no duplicate event_key'
  union all
  select 'NOTIF columns exist',
         (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'notification_preferences' and column_name in ('progress_weekly_summary','progress_monthly_summary','progress_milestones')) = 3,
         'expected 3 columns'
)
select name,
       case when ok then 'PASS' else 'FAIL' end as status,
       coalesce(details, '-') as details
from qa
order by name;
`;

const ownSelectSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
with q as (
  select count(*)::int as c
  from public.professional_progress_profiles
)
select 'DB-05 own progress rows readable',
       case when c = 1 then 'PASS' else 'FAIL' end,
       c::text
from q;
rollback;
`;

const otherUserHiddenSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
with q as (
  select count(*)::int as c
  from public.professional_progress_profiles
  where user_id = ${sqlString(U2)}::uuid
)
select 'DB-05 other user rows hidden',
       case when c = 0 then 'PASS' else 'FAIL' end,
       c::text
from q;
rollback;
`;

const forbiddenEventInsertSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
insert into public.professional_progress_events (user_id, event_key, event_type)
values (${sqlString(U1)}::uuid, 'qa_forbidden_client_insert', 'backfill_seed');
rollback;
`;

const forbiddenMdpUpdateSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
update public.professional_progress_profiles
set total_mdp = 999999
where user_id = ${sqlString(U1)}::uuid;
rollback;
`;

const verifyMdpUnchangedSql = `
select 'DB-05 client MDP cannot mutate',
       case when total_mdp = 425 then 'PASS' else 'FAIL' end,
       total_mdp::text
from public.professional_progress_profiles
where user_id = ${sqlString(U1)}::uuid;
`;

const allowedSeenUpdateSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
update public.professional_progress_badges
set seen_at = now()
where user_id = ${sqlString(U1)}::uuid
  and badge_key = 'reports:1';
with q as (
  select count(*)::int as c
  from public.professional_progress_badges
  where user_id = ${sqlString(U1)}::uuid
    and badge_key = 'reports:1'
    and seen_at is not null
)
select 'DB-05 seen_at update allowed',
       case when c = 1 then 'PASS' else 'FAIL' end,
       c::text
from q;
rollback;
`;

const forbiddenBadgeTitleUpdateSql = `
begin;
set local role authenticated;
set local request.jwt.claim.sub = ${sqlString(U1)};
update public.professional_progress_badges
set title = 'Client changed'
where user_id = ${sqlString(U1)}::uuid
  and badge_key = 'reports:1';
rollback;
`;

const verifyBadgeTitleUnchangedSql = `
select 'DB-05 badge title cannot mutate',
       case when title <> 'Client changed' then 'PASS' else 'FAIL' end,
       title
from public.professional_progress_badges
where user_id = ${sqlString(U1)}::uuid
  and badge_key = 'reports:1';
`;

const runs = [];
runs.push(runLocalSql("cleanup before QA", cleanupSql));
runs.push(runLocalSql("setup synthetic progress data and assertions", setupAndAssertSql));
runs.push(runLocalSql("RLS own select", ownSelectSql));
runs.push(runLocalSql("RLS other user hidden", otherUserHiddenSql));
runs.push(runLocalSql("RLS client event insert rejected", forbiddenEventInsertSql, { expectFailure: true }));
runs.push(runLocalSql("RLS client MDP mutation blocked", forbiddenMdpUpdateSql, { expectFailure: true }));
runs.push(runLocalSql("RLS client MDP unchanged", verifyMdpUnchangedSql));
runs.push(runLocalSql("RLS seen_at update allowed", allowedSeenUpdateSql));
runs.push(runLocalSql("RLS badge title mutation blocked", forbiddenBadgeTitleUpdateSql, { expectFailure: true }));
runs.push(runLocalSql("RLS badge title unchanged", verifyBadgeTitleUnchangedSql));
runs.push(runLocalSql("cleanup after QA", cleanupSql));

const assertionRows = runs.flatMap((run) =>
  run.rows
    .filter((row) => row.name && row.status)
    .map((row) => ({
      group: run.name,
      name: row.name,
      status: row.status,
      details: row.details ?? "",
    }))
);

const commandChecks = runs.map((run) => ({
  name: run.name,
  status: run.status,
  details: run.note,
}));

const allChecks = [...commandChecks, ...assertionRows];
const failures = allChecks.filter((check) => check.status !== "PASS");

function table(rows) {
  if (!rows.length) return "_No rows._";
  return [
    "| status | check | details |",
    "| --- | --- | --- |",
    ...rows.map((row) => `| ${row.status} | ${String(row.name).replaceAll("|", "\\|")} | ${String(row.details ?? "").replaceAll("\n", " ").replaceAll("|", "\\|")} |`),
  ].join("\n");
}

const report = [
  `# Professional Progress QA Run - ${new Date().toISOString()}`,
  "",
  `- Overall: ${failures.length ? "FAIL" : "PASS"}`,
  `- Checks: ${allChecks.length}`,
  `- Failures: ${failures.length}`,
  "",
  "## Results",
  "",
  table(allChecks),
  "",
  "## Failed Command Output",
  "",
  ...runs
    .filter((run) => run.status === "FAIL")
    .flatMap((run) => [
      `### ${run.name}`,
      "",
      "```text",
      `${run.stdout}\n${run.stderr}`.trim(),
      "```",
      "",
    ]),
].join("\n");

const outputPath = resolve(REPORT_PATH);
mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, report);

console.log(`Professional Progress QA report written: ${outputPath}`);
console.log(`Checks=${allChecks.length} Failures=${failures.length}`);
if (failures.length) process.exitCode = 1;
