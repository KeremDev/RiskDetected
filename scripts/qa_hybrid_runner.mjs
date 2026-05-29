#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const PROJECT_REF = "ppcrzemgiztzcgddbins";
const PROJECT_NAME = "riskdetected";
const REQUIRED_EDGE_FUNCTIONS = [
  "analyze",
  "process-analysis-jobs",
  "generate-excel-report",
  "send-push-notification",
  "send-report-ready-notification",
  "send-welcome-email",
  "revenuecat-webhook",
  "sync-revenuecat-subscription",
  "account-deletion-complete",
];
const DENO_CHECK_FUNCTIONS = REQUIRED_EDGE_FUNCTIONS;
const REPORT_DATE = new Date().toISOString().slice(0, 10);

function parseArgs(argv) {
  const args = {
    output: `QA/Hybrid_QA_${REPORT_DATE}.md`,
    skipXcode: false,
    skipDeno: false,
    skipDb: false,
    xcodeStatus: null,
    xcodeBuildLog: null,
    xcodeRuntimeLog: null,
    xcodeScreenshot: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--output") args.output = argv[++index];
    else if (value === "--skip-xcode") args.skipXcode = true;
    else if (value === "--skip-deno") args.skipDeno = true;
    else if (value === "--skip-db") args.skipDb = true;
    else if (value === "--xcode-status") args.xcodeStatus = argv[++index];
    else if (value === "--xcode-build-log") args.xcodeBuildLog = argv[++index];
    else if (value === "--xcode-runtime-log") args.xcodeRuntimeLog = argv[++index];
    else if (value === "--xcode-screenshot") args.xcodeScreenshot = argv[++index];
    else if (value === "--help") {
      printHelp();
      process.exit(0);
    }
  }

  return args;
}

function printHelp() {
  console.log(`Usage: node scripts/qa_hybrid_runner.mjs [options]

Options:
  --output <path>          Markdown report path. Defaults to QA/Hybrid_QA_${REPORT_DATE}.md
  --skip-xcode            Skip local xcodebuild fallback check.
  --skip-deno             Skip Edge Function deno check commands.
  --skip-db               Skip production read-only Supabase DB queries.
  --xcode-status <value>  Add externally captured XcodeBuildMCP status.
  --xcode-build-log <p>   Add externally captured XcodeBuildMCP build log path.
  --xcode-runtime-log <p> Add externally captured XcodeBuildMCP runtime log path.
  --xcode-screenshot <p>  Add externally captured simulator screenshot path.
`);
}

function runCommand(name, command, args, options = {}) {
  const startedAt = Date.now();
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? process.cwd(),
    encoding: "utf8",
    maxBuffer: options.maxBuffer ?? 20 * 1024 * 1024,
    env: { ...process.env, ...(options.env ?? {}) },
  });

  return {
    name,
    command: [command, ...args].join(" "),
    status: result.status ?? 1,
    signal: result.signal,
    durationMs: Date.now() - startedAt,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    error: result.error?.message ?? null,
  };
}

function checkFromCommand(name, result, passNote = "command completed") {
  return {
    name,
    status: result.status === 0 ? "PASS" : "FAIL",
    note: result.status === 0
      ? passNote
      : `exit ${result.status}${result.error ? `: ${result.error}` : ""}`,
    command: result,
  };
}

function extractJsonObject(raw) {
  const first = raw.indexOf("{");
  if (first === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = first; index < raw.length; index += 1) {
    const char = raw[index];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") inString = true;
    else if (char === "{") depth += 1;
    else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        try {
          return JSON.parse(raw.slice(first, index + 1));
        } catch {
          return null;
        }
      }
    }
  }

  return null;
}

function asNumber(value) {
  if (typeof value === "number") return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function assertReadOnlySql(sql) {
  const normalized = sql.trim().toLowerCase();
  if (!normalized.startsWith("select") && !normalized.startsWith("with")) {
    throw new Error(`Refusing non-read-only SQL: ${sql.slice(0, 80)}`);
  }
}

function runSupabaseQuery(name, sql, assess) {
  assertReadOnlySql(sql);
  const command = runCommand(name, "supabase", [
    "db",
    "query",
    "--linked",
    "--output",
    "json",
    sql,
  ]);

  if (command.status !== 0) {
    return {
      name,
      status: "FAIL",
      note: `query failed with exit ${command.status}`,
      rows: [],
      command,
    };
  }

  const parsed = extractJsonObject(command.stdout + "\n" + command.stderr);
  const rows = Array.isArray(parsed?.rows) ? parsed.rows : [];
  const assessed = assess(rows);

  return {
    name,
    rows,
    command,
    ...assessed,
  };
}

function markdownTable(rows, headers) {
  if (!rows.length) return "_No rows._";
  const keys = headers ?? Object.keys(rows[0]);
  const header = `| ${keys.join(" | ")} |`;
  const divider = `| ${keys.map(() => "---").join(" | ")} |`;
  const body = rows.map((row) =>
    `| ${keys.map((key) => String(row[key] ?? "").replace(/\n/g, " ")).join(" | ")} |`
  );
  return [header, divider, ...body].join("\n");
}

function truncate(value, maxLength = 5000) {
  const text = String(value ?? "").trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength)}\n... truncated ${text.length - maxLength} chars`;
}

function summarizeStatus(checks) {
  return checks.reduce((acc, check) => {
    acc[check.status] = (acc[check.status] ?? 0) + 1;
    return acc;
  }, { PASS: 0, WARN: 0, FAIL: 0 });
}

function statusEmoji(status) {
  switch (status) {
    case "PASS": return "PASS";
    case "WARN": return "WARN";
    case "FAIL": return "FAIL";
    default: return status;
  }
}

function linkedProjectCheck() {
  const refPath = "supabase/.temp/project-ref";
  const linkedPath = "supabase/.temp/linked-project.json";
  const ref = existsSync(refPath) ? readFileSync(refPath, "utf8").trim() : null;
  let linked = null;
  if (existsSync(linkedPath)) {
    try {
      linked = JSON.parse(readFileSync(linkedPath, "utf8"));
    } catch {
      linked = null;
    }
  }

  const ok = ref === PROJECT_REF && linked?.name === PROJECT_NAME;
  return {
    name: "Supabase linked project",
    status: ok ? "PASS" : "FAIL",
    note: ok
      ? `${PROJECT_NAME} / ${PROJECT_REF}`
      : `expected ${PROJECT_NAME}/${PROJECT_REF}, got ${linked?.name ?? "-"} / ${ref ?? "-"}`,
    rows: [{ expected_ref: PROJECT_REF, actual_ref: ref ?? "-", expected_name: PROJECT_NAME, actual_name: linked?.name ?? "-" }],
  };
}

function edgeFunctionCheck(command) {
  if (command.status !== 0) {
    return checkFromCommand("Edge Function list", command);
  }
  const output = command.stdout + "\n" + command.stderr;
  const missing = REQUIRED_EDGE_FUNCTIONS.filter((slug) => !output.includes(slug));
  return {
    name: "Edge Function list",
    status: missing.length === 0 ? "PASS" : "FAIL",
    note: missing.length === 0
      ? `${REQUIRED_EDGE_FUNCTIONS.length} required functions active/listed`
      : `missing: ${missing.join(", ")}`,
    command,
  };
}

function fileContains(path, terms) {
  if (!existsSync(path)) {
    return { exists: false, missing: terms };
  }
  const content = readFileSync(path, "utf8");
  return {
    exists: true,
    missing: terms.filter((term) => !content.includes(term)),
  };
}

function staticProfessionalProgressChecks() {
  const migrationPath = "supabase/migrations/20260526093512_professional_progress_module.sql";
  const migrationTerms = [
    "professional_progress_profiles",
    "professional_progress_events",
    "unique (user_id, event_key)",
    "professional_progress_finding_classifications",
    "classifier_version",
    "pp_competency_for_finding",
    "unclassified",
    "enable row level security",
    "grant update (seen_at)",
    "progress_weekly_summary",
  ];
  const migration = fileContains(migrationPath, migrationTerms);
  const moduleFiles = [
    "App/Features/ProfessionalProgress/ProfessionalProgressService.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressModels.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressHomeCard.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressProfileSection.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressBadgesView.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressCompetencyMapView.swift",
    "App/Features/ProfessionalProgress/ProfessionalProgressCelebrationSheet.swift",
  ];
  const missingModuleFiles = moduleFiles.filter((path) => !existsSync(path));
  const config = fileContains("App/Services/RDConfig.swift", ["professionalProgressEnabled"]);
  const models = fileContains("App/Features/ProfessionalProgress/ProfessionalProgressModels.swift", [
    "case fire",
    "case chemical",
    "case electrical",
    "case mechanical",
    "case ergonomics",
    "case psychosocial",
    "case workingAtHeight",
    "case ppe",
    "case mining",
    "case construction",
    "case factory",
  ]);

  return [
    {
      name: "Professional Progress migration static contract",
      status: migration.exists && migration.missing.length === 0 ? "PASS" : "FAIL",
      note: migration.exists
        ? migration.missing.length === 0
          ? "ledger, classifier, RLS/preference hooks present"
          : `missing terms: ${migration.missing.join(", ")}`
        : `${migrationPath} missing`,
    },
    {
      name: "Professional Progress iOS module files",
      status: missingModuleFiles.length === 0 ? "PASS" : "FAIL",
      note: missingModuleFiles.length === 0
        ? `${moduleFiles.length} module files present`
        : `missing files: ${missingModuleFiles.join(", ")}`,
    },
    {
      name: "Professional Progress feature flag",
      status: config.exists && config.missing.length === 0 ? "PASS" : "FAIL",
      note: config.exists && config.missing.length === 0
        ? "RDConfig.Features.professionalProgressEnabled present"
        : "feature flag missing",
    },
    {
      name: "Professional Progress competency taxonomy",
      status: models.exists && models.missing.length === 0 ? "PASS" : "FAIL",
      note: models.exists && models.missing.length === 0
        ? "11 fixed competency cases present"
        : `missing taxonomy terms: ${models.missing.join(", ")}`,
    },
  ];
}

function buildReport({ checks, commands, dbChecks, args, startedAt, finishedAt }) {
  const counts = summarizeStatus(checks);
  const failed = checks.filter((check) => check.status === "FAIL");
  const warnings = checks.filter((check) => check.status === "WARN");

  const lines = [];
  lines.push(`# Hybrid QA Report - ${REPORT_DATE}`);
  lines.push("");
  lines.push(`Generated: ${finishedAt.toISOString()}`);
  lines.push(`Mode: production read-only DB checks + local build/static checks`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- PASS: ${counts.PASS ?? 0}`);
  lines.push(`- WARN: ${counts.WARN ?? 0}`);
  lines.push(`- FAIL: ${counts.FAIL ?? 0}`);
  lines.push(`- Overall: ${failed.length > 0 ? "FAIL" : warnings.length > 0 ? "WARN" : "PASS"}`);
  lines.push("");
  lines.push(markdownTable(checks.map((check) => ({
    status: statusEmoji(check.status),
    check: check.name,
    note: check.note,
  })), ["status", "check", "note"]));
  lines.push("");

  if (args.xcodeStatus || args.xcodeBuildLog || args.xcodeRuntimeLog || args.xcodeScreenshot) {
    lines.push("## XcodeBuildMCP Artifacts");
    lines.push("");
    lines.push(`- Status: ${args.xcodeStatus ?? "not provided"}`);
    lines.push(`- Build log: ${args.xcodeBuildLog ?? "not provided"}`);
    lines.push(`- Runtime log: ${args.xcodeRuntimeLog ?? "not provided"}`);
    lines.push(`- Screenshot: ${args.xcodeScreenshot ?? "not provided"}`);
    lines.push("");
  }

  lines.push("## Production DB Read-Only Results");
  lines.push("");
  for (const check of dbChecks) {
    lines.push(`### ${statusEmoji(check.status)} ${check.name}`);
    lines.push("");
    lines.push(check.note);
    lines.push("");
    lines.push(markdownTable(check.rows ?? []));
    lines.push("");
  }

  lines.push("## Command Details");
  lines.push("");
  for (const command of commands) {
    lines.push(`### ${command.name}`);
    lines.push("");
    lines.push(`- Command: \`${command.command}\``);
    lines.push(`- Exit: ${command.status}`);
    lines.push(`- Duration: ${command.durationMs} ms`);
    if (command.error) lines.push(`- Error: ${command.error}`);
    lines.push("");
    if (command.stdout.trim()) {
      lines.push("stdout:");
      lines.push("```text");
      lines.push(truncate(command.stdout));
      lines.push("```");
    }
    if (command.stderr.trim()) {
      lines.push("stderr:");
      lines.push("```text");
      lines.push(truncate(command.stderr));
      lines.push("```");
    }
    lines.push("");
  }

  lines.push("## Manual Remaining");
  lines.push("");
  lines.push("- APNs real-device delivery and tap routing.");
  lines.push("- App Store/TestFlight purchase sheet and sandbox purchase confirmation.");
  lines.push("- Apple/Google live provider login prompts.");
  lines.push("- Real-device share sheet behavior for freshly generated PDF/XLSX.");
  lines.push("");
  lines.push("## Next Actions");
  lines.push("");
  if (failed.length > 0) {
    lines.push("- Fix FAIL rows first, then rerun this runner.");
  } else if (warnings.length > 0) {
    lines.push("- Review WARN rows and decide whether they are expected for current test volume.");
  } else {
    lines.push("- Hybrid QA is clean. Continue with real-device spot checks.");
  }
  lines.push("");
  lines.push(`Run duration: ${finishedAt.getTime() - startedAt.getTime()} ms`);
  lines.push("");

  return lines.join("\n");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const startedAt = new Date();
  const checks = [];
  const commands = [];
  const dbChecks = [];

  checks.push(linkedProjectCheck());

  const gitStatus = runCommand("Git status", "git", ["status", "--short"]);
  commands.push(gitStatus);
  checks.push(checkFromCommand("Git status", gitStatus, gitStatus.stdout.trim() ? "dirty worktree captured" : "clean worktree"));

  const migrationList = runCommand("Supabase migration list", "supabase", ["migration", "list"]);
  commands.push(migrationList);
  checks.push(checkFromCommand("Supabase migration list", migrationList));

  const functionsList = runCommand("Edge Function list", "supabase", ["functions", "list", "--project-ref", PROJECT_REF]);
  commands.push(functionsList);
  checks.push(edgeFunctionCheck(functionsList));

  for (const check of staticProfessionalProgressChecks()) {
    checks.push(check);
  }

  if (!args.skipDeno) {
    for (const functionName of DENO_CHECK_FUNCTIONS) {
      const path = `supabase/functions/${functionName}/index.ts`;
      const deno = runCommand(`deno check ${functionName}`, "deno", ["check", path]);
      commands.push(deno);
      checks.push(checkFromCommand(`deno check ${functionName}`, deno));
    }
  }

  const archiveQa = runCommand("Report archive dense QA", "node", ["scripts/qa_report_archive_heavy.mjs"]);
  commands.push(archiveQa);
  checks.push(checkFromCommand("Report archive dense QA", archiveQa));

  if (!args.skipXcode && !args.xcodeStatus) {
    const xcode = runCommand("iOS Debug build", "xcodebuild", [
      "-project",
      "RiskDetected.xcodeproj",
      "-scheme",
      "RiskDetected",
      "-configuration",
      "Debug",
      "-destination",
      "platform=iOS Simulator,name=iPhone 17 Pro",
      "build",
    ], { maxBuffer: 60 * 1024 * 1024 });
    commands.push(xcode);
    checks.push(checkFromCommand("iOS Debug build", xcode));
  } else if (args.xcodeStatus) {
    checks.push({
      name: "XcodeBuildMCP build/run",
      status: args.xcodeStatus === "SUCCEEDED" ? "PASS" : "FAIL",
      note: `external XcodeBuildMCP status: ${args.xcodeStatus}`,
    });
  }

  if (!args.skipDb) {
    const queries = [
      runSupabaseQuery(
        "Stale queued/analyzing analyses",
        `select status::text as status, count(*)::int as count, min(created_at) as oldest_created_at
         from public.analyses
         where status::text in ('queued','analyzing')
           and coalesce(worker_started_at, queued_at, updated_at, created_at) < now() - interval '20 minutes'
         group by status::text
         order by status::text`,
        (rows) => {
          const total = rows.reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: total > 0 ? "FAIL" : "PASS",
            note: total > 0 ? `${total} stale async analysis job(s)` : "no stale async jobs",
          };
        },
      ),
      runSupabaseQuery(
        "Recent analysis status distribution",
        `select status::text as status, count(*)::int as count
         from public.analyses
         where created_at >= now() - interval '24 hours'
         group by status::text
         order by status::text`,
        (rows) => {
          const failed = rows.filter((row) => row.status === "failed").reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: failed > 0 ? "WARN" : "PASS",
            note: failed > 0 ? `${failed} failed analysis row(s) in last 24h` : "no failed analyses in last 24h",
          };
        },
      ),
      runSupabaseQuery(
        "Recent AI usage distribution",
        `select user_plan,
                coalesce(quality_tier, user_plan) as quality_tier,
                coalesce(ai_execution_route, '-') as ai_execution_route,
                provider,
                model,
                coalesce(api_key_alias, '-') as api_key_alias,
                coalesce(fallback_source, '-') as fallback_source,
                count(*)::int as calls,
                coalesce(sum(total_tokens), 0)::int as total_tokens,
                coalesce(round(avg(total_tokens))::int, 0) as avg_total_tokens,
                coalesce(sum(thoughts_tokens), 0)::int as thoughts_tokens,
                coalesce(round(avg(duration_ms))::int, 0) as avg_duration_ms
         from public.ai_usage_logs
         where created_at >= now() - interval '24 hours'
         group by user_plan, quality_tier, ai_execution_route, provider, model, api_key_alias, fallback_source
         order by calls desc, total_tokens desc
         limit 20`,
        (rows) => ({
          status: "PASS",
          note: rows.length ? `${rows.length} AI usage bucket(s)` : "no AI calls in last 24h",
        }),
      ),
      runSupabaseQuery(
        "Recent AI errors",
        `select coalesce(http_status::text, '-') as http_status,
                coalesce(error_code, '-') as error_code,
                coalesce(api_key_alias, '-') as api_key_alias,
                count(*)::int as count
         from public.ai_usage_logs
         where created_at >= now() - interval '24 hours'
           and (error is not null or coalesce(http_status, 200) >= 400)
         group by http_status, error_code, api_key_alias
         order by count desc
         limit 20`,
        (rows) => {
          const total = rows.reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: total > 0 ? "WARN" : "PASS",
            note: total > 0 ? `${total} AI error log(s) in last 24h` : "no AI errors in last 24h",
          };
        },
      ),
      runSupabaseQuery(
        "Notification event distribution",
        `select kind, status, count(*)::int as count
         from public.notification_events
         where created_at >= now() - interval '24 hours'
         group by kind, status
         order by kind, status`,
        (rows) => {
          const failed = rows.filter((row) => row.status === "failed").reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: failed > 0 ? "WARN" : "PASS",
            note: failed > 0 ? `${failed} failed notification event(s)` : "no failed notification events in last 24h",
          };
        },
      ),
      runSupabaseQuery(
        "Recent report exports",
        `select format, kind, count(*)::int as count, coalesce(sum(size_bytes), 0)::int as bytes
         from public.reports
         where created_at >= now() - interval '7 days'
         group by format, kind
         order by format, kind`,
        (rows) => ({
          status: rows.length ? "PASS" : "WARN",
          note: rows.length ? `${rows.length} report export bucket(s) in last 7d` : "no report exports in last 7d",
        }),
      ),
      runSupabaseQuery(
        "Welcome email failures",
        `select welcome_email_status, count(*)::int as count
         from public.profiles
         where welcome_email_status = 'email_failed'
         group by welcome_email_status`,
        (rows) => {
          const total = rows.reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: total > 0 ? "WARN" : "PASS",
            note: total > 0 ? `${total} profile(s) with failed welcome email` : "no failed welcome email rows",
          };
        },
      ),
      runSupabaseQuery(
        "RevenueCat event processing",
        `select case when processed_at is null then 'unprocessed' else 'processed' end as processing_state,
                event_type,
                count(*)::int as count
         from public.subscription_events
         where received_at >= now() - interval '7 days'
         group by processing_state, event_type
         order by processing_state, event_type`,
        (rows) => {
          const unprocessed = rows.filter((row) => row.processing_state === "unprocessed").reduce((sum, row) => sum + asNumber(row.count), 0);
          return {
            status: unprocessed > 0 ? "WARN" : "PASS",
            note: unprocessed > 0 ? `${unprocessed} unprocessed RevenueCat event(s)` : "no unprocessed RevenueCat events in last 7d",
          };
        },
      ),
      runSupabaseQuery(
        "Paywall event flow",
        `select source, variant_id, event_name, count(*)::int as count
         from public.paywall_events
         where created_at >= now() - interval '7 days'
         group by source, variant_id, event_name
         order by source, variant_id, event_name`,
        (rows) => ({
          status: rows.length ? "PASS" : "WARN",
          note: rows.length ? `${rows.length} paywall event bucket(s) in last 7d` : "no paywall events in last 7d",
        }),
      ),
      runSupabaseQuery(
        "Company active duplicate guard",
        `select md5(user_id::text) as user_hash, lower(btrim(name)) as normalized_name, count(*)::int as count
         from public.companies
         where is_archived = false
         group by user_id, lower(btrim(name))
         having count(*) > 1
         order by count desc
         limit 20`,
        (rows) => ({
          status: rows.length ? "FAIL" : "PASS",
          note: rows.length ? `${rows.length} active duplicate company name group(s)` : "no active duplicate company names per user",
        }),
      ),
    ];

    for (const query of queries) {
      dbChecks.push(query);
      checks.push({
        name: query.name,
        status: query.status,
        note: query.note,
      });
      commands.push(query.command);
    }
  }

  const finishedAt = new Date();
  const outputPath = resolve(args.output);
  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, buildReport({ checks, commands, dbChecks, args, startedAt, finishedAt }));

  const counts = summarizeStatus(checks);
  console.log(`Hybrid QA report written: ${outputPath}`);
  console.log(`PASS=${counts.PASS ?? 0} WARN=${counts.WARN ?? 0} FAIL=${counts.FAIL ?? 0}`);
  if ((counts.FAIL ?? 0) > 0) process.exitCode = 1;
}

main();
