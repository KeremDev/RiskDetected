#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";

const ROOT = process.cwd();
const PROJECT_REF = "ppcrzemgiztzcgddbins";
const FORMER_TEST_PROJECT_REF = ["iidhnqvuszj", "coyncqzkg"].join("");
const SUPABASE_URL = "https://ppcrzemgiztzcgddbins.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt";
const SUPABASE_CONFIG_FILE = "supabase/config.toml";
const KEYCHAIN_SUPABASE_ACCESS_TOKEN = "riskdetected_supabase_access_token";

const args = new Set(process.argv.slice(2));
const outputFunctionsJson = args.has("--functions-json");

const checks = [];

function addCheck(status, name, detail = "", evidence = "") {
  checks.push({ status, name, detail, evidence });
}

function readKeychain(service) {
  const result = spawnSync(
    "security",
    ["find-generic-password", "-a", process.env.USER ?? "", "-s", service, "-w"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

async function managementFetch(path, token, options = {}) {
  const response = await fetch(`https://api.supabase.com${path}`, {
    ...options,
    headers: {
      "Authorization": `Bearer ${token}`,
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...(options.headers ?? {}),
    },
  });
  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(`Management API ${path} returned ${response.status}: ${bodyText.slice(0, 500)}`);
  }
  return bodyText ? JSON.parse(bodyText) : null;
}

async function managementFetchBytes(path, token) {
  const response = await fetch(`https://api.supabase.com${path}`, {
    headers: { "Authorization": `Bearer ${token}` },
  });
  const bytes = Buffer.from(await response.arrayBuffer());
  if (!response.ok) {
    throw new Error(`Management API ${path} returned ${response.status}: ${bytes.toString("utf8", 0, 500)}`);
  }
  return bytes;
}

function runCommand(name, command, commandArgs, validate, options = {}) {
  const result = spawnSync(command, commandArgs, {
    cwd: ROOT,
    encoding: "utf8",
    maxBuffer: options.maxBuffer ?? 40 * 1024 * 1024,
    timeout: options.timeoutMs ?? 120000,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (result.status !== 0) {
    addCheck("FAIL", name, output.slice(0, 700));
    return null;
  }
  const validation = validate?.(result.stdout ?? "", output) ?? true;
  if (validation === true) {
    addCheck("PASS", name, options.passDetail ?? "ok");
  } else {
    addCheck("FAIL", name, typeof validation === "string" ? validation : "validation failed");
  }
  return result.stdout ?? "";
}

function parseExpectedFunctions() {
  if (!existsSync(SUPABASE_CONFIG_FILE)) {
    addCheck("FAIL", "Local Supabase config", `Missing ${SUPABASE_CONFIG_FILE}.`);
    return [];
  }
  const config = readFileSync(SUPABASE_CONFIG_FILE, "utf8");
  const expected = [...config.matchAll(/\[functions\.([^\]]+)\]\s+verify_jwt\s*=\s*(true|false)/g)]
    .map((match) => ({ slug: match[1], verifyJwt: match[2] === "true" }));
  addCheck(
    "PASS",
    "Local Supabase function config",
    `${expected.length} production-required functions parsed.`,
  );
  return expected;
}

function normalizeFunctionRows(value) {
  if (Array.isArray(value)) return value;
  if (Array.isArray(value?.functions)) return value.functions;
  if (Array.isArray(value?.data)) return value.data;
  return [];
}

function validateRemoteFunctions(remoteRows, expected, sourceLabel) {
  const remoteBySlug = new Map(remoteRows.map((fn) => [fn.slug ?? fn.name, fn]));
  const issues = [];
  const evidence = [];

  for (const fn of expected) {
    const deployed = remoteBySlug.get(fn.slug);
    if (!deployed) {
      issues.push(`${fn.slug}: missing`);
      continue;
    }
    if (deployed.status !== "ACTIVE") {
      issues.push(`${fn.slug}: status=${deployed.status}`);
    }
    if (deployed.verify_jwt !== fn.verifyJwt) {
      issues.push(`${fn.slug}: verify_jwt remote=${deployed.verify_jwt} local=${fn.verifyJwt}`);
    }
    evidence.push(`${fn.slug}: ${deployed.status}, verify_jwt=${deployed.verify_jwt}, version=${deployed.version ?? ""}`);
  }

  addCheck(
    issues.length === 0 ? "PASS" : "FAIL",
    "Production Edge Functions deployed",
    issues.length === 0 ? `${expected.length} functions match ${SUPABASE_CONFIG_FILE}.` : issues.join("; "),
    [`source=${sourceLabel}`, ...evidence.sort()].join("\n"),
  );

  const analyze = remoteBySlug.get("analyze");
  const worker = remoteBySlug.get("process-analysis-jobs");
  addCheck(
    analyze?.status === "ACTIVE" && analyze?.verify_jwt === false ? "PASS" : "FAIL",
    "Production analyze function active",
    analyze ? `status=${analyze.status}, verify_jwt=${analyze.verify_jwt}, version=${analyze.version ?? ""}` : "missing",
  );
  addCheck(
    worker?.status === "ACTIVE" && worker?.verify_jwt === false ? "PASS" : "FAIL",
    "Production process-analysis-jobs active",
    worker ? `status=${worker.status}, verify_jwt=${worker.verify_jwt}, version=${worker.version ?? ""}` : "missing",
  );
}

async function checkManagementFunctions(token) {
  const expected = parseExpectedFunctions();
  const productionRows = normalizeFunctionRows(
    await managementFetch(`/v1/projects/${PROJECT_REF}/functions`, token),
  );
  validateRemoteFunctions(productionRows, expected, "Supabase Management API");
}

async function checkRemoteAnalyzeBody(token) {
  const body = await managementFetchBytes(`/v1/projects/${PROJECT_REF}/functions/analyze/body`, token);
  const text = body.toString("utf8");
  const markers = [
    "isg-photo-personalized-v2026-06-02-twelve-layer-two-measures",
    "reserve_analysis_quota",
    "enqueue_analysis_job_message",
    "GEMINI_API_KEY_PAID",
    "GROQ_API_KEY_PLUS_PRO",
  ];
  const missing = markers.filter((marker) => !text.includes(marker));
  const sha = createHash("sha256").update(body).digest("hex").slice(0, 16);
  addCheck(
    missing.length === 0 ? "PASS" : "FAIL",
    "Remote analyze bundle markers",
    missing.length === 0
      ? `all expected markers present, bytes=${body.length}, sha256_16=${sha}`
      : `missing markers: ${missing.join(", ")}`,
  );
}

async function checkSecrets(token) {
  const rows = await managementFetch(`/v1/projects/${PROJECT_REF}/secrets`, token);
  const names = new Set(normalizeFunctionRows(rows).map((row) => row.name).filter(Boolean));
  const requiredAny = [
    ["Free Gemini secret", ["GEMINI_API_KEY_PRIMARY", "GEMINI_API_KEY"]],
    ["Paid Gemini secret", ["GEMINI_API_KEY_PAID", "GEMINI_PAID_API_KEY"]],
    ["Analysis worker secret", ["PROCESS_ANALYSIS_JOBS_SECRET"]],
  ];
  for (const [name, candidates] of requiredAny) {
    addCheck(
      candidates.some((candidate) => names.has(candidate)) ? "PASS" : "FAIL",
      name,
      candidates.filter((candidate) => names.has(candidate)).join(",") || "missing",
    );
  }

  const hasFreeFallback = names.has("GROQ_API_KEY_FREE") || names.has("GEMINI_API_KEY_SECONDARY");
  const hasPaidFallback = names.has("GROQ_API_KEY_PLUS_PRO") || names.has("GEMINI_API_KEY_PAID_SECONDARY");
  addCheck(hasFreeFallback ? "PASS" : "WARN", "Free AI fallback secret", hasFreeFallback ? "present" : "optional fallback missing");
  addCheck(hasPaidFallback ? "PASS" : "WARN", "Paid AI fallback secret", hasPaidFallback ? "present" : "optional fallback missing");

  const forbidden = [
    "RISKDETECTED_ENABLE_TEST_SIMULATION",
    "SIMULATE_AI_ERROR_CODE",
    "SIMULATE_AI_ERROR_ONCE",
  ].filter((name) => names.has(name));
  addCheck(
    forbidden.length === 0 ? "PASS" : "FAIL",
    "Production simulation secrets absent",
    forbidden.length === 0 ? "absent" : `forbidden present: ${forbidden.join(",")}`,
  );
}

async function checkDatabaseReadiness(token) {
  const query = `
    select 'extensions' as check_name,
      jsonb_build_object(
        'pgmq', exists(select 1 from pg_extension where extname = 'pgmq'),
        'pg_cron', exists(select 1 from pg_extension where extname = 'pg_cron'),
        'pg_net', exists(select 1 from pg_extension where extname = 'pg_net'),
        'supabase_vault', exists(select 1 from pg_extension where extname = 'supabase_vault')
      ) as detail
    union all
    select 'queue_functions' as check_name,
      jsonb_build_object(
        'enqueue', to_regprocedure('public.enqueue_analysis_job_message(jsonb)') is not null,
        'read', to_regprocedure('public.read_analysis_job_messages(integer, integer)') is not null,
        'delete', to_regprocedure('public.delete_analysis_job_message(bigint)') is not null,
        'reserve_quota', to_regprocedure('public.reserve_analysis_quota(uuid, uuid, text)') is not null
      ) as detail
    union all
    select 'cron_job' as check_name,
      jsonb_build_object(
        'exists', exists(select 1 from cron.job where jobname = 'riskdetected-analysis-jobs-every-minute'),
        'active', exists(select 1 from cron.job where jobname = 'riskdetected-analysis-jobs-every-minute' and active = true)
      ) as detail
    union all
    select 'vault_secret_presence' as check_name,
      jsonb_build_object(
        'project_url', exists(select 1 from vault.decrypted_secrets where name = 'project_url'),
        'analysis_worker_secret', exists(select 1 from vault.decrypted_secrets where name = 'analysis_worker_secret')
      ) as detail
    union all
    select 'recent_stuck_analysis_24h' as check_name,
      jsonb_build_object(
        'queued_or_analyzing', count(*)::int
      ) as detail
    from public.analyses
    where created_at >= now() - interval '24 hours'
      and status in ('queued', 'analyzing');
  `;
  const result = await managementFetch(`/v1/projects/${PROJECT_REF}/database/query`, token, {
    method: "POST",
    body: JSON.stringify({ query, read_only: true }),
  });
  const rows = Array.isArray(result?.rows) ? result.rows : Array.isArray(result) ? result : [];
  const byName = new Map(rows.map((row) => [row.check_name, row.detail ?? {}]));
  const requiredAllTrue = ["extensions", "queue_functions", "cron_job", "vault_secret_presence"];
  for (const name of requiredAllTrue) {
    const detail = byName.get(name) ?? {};
    const ok = Object.values(detail).every((value) => value === true);
    addCheck(ok ? "PASS" : "FAIL", `Database readiness: ${name}`, JSON.stringify(detail));
  }
  const stuck = Number(byName.get("recent_stuck_analysis_24h")?.queued_or_analyzing ?? 0);
  addCheck(stuck === 0 ? "PASS" : "WARN", "Recent stuck analyses", `${stuck} queued/analyzing in last 24h`);
}

async function checkGatewaySmoke() {
  const response = await fetch(`${SUPABASE_URL}/functions/v1/analyze`, {
    method: "POST",
    headers: {
      "apikey": PUBLISHABLE_KEY,
      "Authorization": "Bearer not-a-jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ analysis_id: "00000000-0000-0000-0000-000000000000" }),
  });
  const text = await response.text();
  let body = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = {};
  }
  const ok = response.status === 401 &&
    body?.code === "auth_invalid" &&
    !text.includes("Requested function was not found") &&
    !text.includes("UNAUTHORIZED_INVALID_JWT_FORMAT");
  addCheck(
    ok ? "PASS" : "FAIL",
    "No-bypass gateway smoke",
    ok ? "invalid JWT reached analyze and returned auth_invalid" : `status=${response.status}, body=${text.slice(0, 300)}`,
  );
}

function checkXcodeBuildSettings() {
  const configuration = "Release";
  runCommand(
    `Xcode build settings ${configuration}`,
    "xcodebuild",
    [
      "-project",
      "RiskDetected.xcodeproj",
      "-scheme",
      "RiskDetected",
      "-configuration",
      configuration,
      "-showBuildSettings",
    ],
    (stdout) => {
      const expectedURL = `RISKDETECTED_SUPABASE_URL = ${SUPABASE_URL}`;
      const expectedKey = `RISKDETECTED_SUPABASE_PUBLISHABLE_KEY = ${PUBLISHABLE_KEY}`;
      if (!stdout.includes(expectedURL)) return `missing ${expectedURL}`;
      if (!stdout.includes(expectedKey)) return "missing production publishable key marker";
      if (stdout.includes(FORMER_TEST_PROJECT_REF)) return "Former test Supabase ref appears in production lane build settings";
      return true;
    },
    { passDetail: "production Supabase URL/key for Release", timeoutMs: 180000 },
  );
}

function checkMainScheme() {
  const schemePath = "RiskDetected.xcodeproj/xcshareddata/xcschemes/RiskDetected.xcscheme";
  if (!existsSync(schemePath)) {
    addCheck("FAIL", "Main scheme", `Missing ${schemePath}`);
    return;
  }
  const scheme = readFileSync(schemePath, "utf8");
  const forbiddenMarkers = [
    ["Internal", "Test", "Flight"].join(""),
    ["RiskDetected", "Q", "A", ".storekit"].join(""),
    "StoreKitConfigurationFileReference",
    ["RD", "Q" + "A", "AUTO", "LOGIN"].join("_"),
    "RISKDETECTED_SUPABASE_URL",
    FORMER_TEST_PROJECT_REF,
  ].filter((marker) => scheme.includes(marker));
  addCheck(
    forbiddenMarkers.length === 0 ? "PASS" : "FAIL",
    "Main scheme has no retired test runtime override",
    forbiddenMarkers.length === 0 ? "no StoreKit/env override markers" : `found: ${forbiddenMarkers.join(",")}`,
  );
}

function checkRetiredActiveMarkers() {
  const result = spawnSync("git", ["ls-files", "-z"], {
    cwd: ROOT,
    encoding: "buffer",
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.status !== 0) {
    addCheck("FAIL", "Retired lane active marker scan", "Could not list tracked files.");
    return;
  }

  const ignoredPrefixes = ["docs/archive/", "backups/", "output/"];
  const files = result.stdout.toString("utf8").split("\0").filter(Boolean)
    .filter((file) => !ignoredPrefixes.some((prefix) => file.startsWith(prefix)));
  const markers = [
    ["Internal", "Test", "Flight"].join(""),
    FORMER_TEST_PROJECT_REF,
    ["riskdetected", "-", "qa"].join(""),
    ["riskdetected", "_", "qa"].join(""),
    ["RISKDETECTED", "Q", "A"].join("_"),
    ["RiskDetected", " ", "Q", "A"].join(""),
    ["RiskDetected", "Q", "A", ".storekit"].join(""),
    ["INTERNAL", "TEST", "RESET", "TOOLS"].join("_"),
  ];
  const hits = [];
  for (const file of files) {
    if (!existsSync(file)) continue;
    if (!statSync(file).isFile()) continue;
    const body = readFileSync(file, "utf8");
    for (const marker of markers) {
      if (body.includes(marker)) {
        hits.push(`${file}: ${marker}`);
      }
    }
  }

  addCheck(
    hits.length === 0 ? "PASS" : "FAIL",
    "Retired lane active marker scan",
    hits.length === 0 ? "no retired QA/TestFlight markers in active tracked files" : hits.slice(0, 12).join("; "),
  );
}

function checkDeno() {
  runCommand(
    "Deno check analyze",
    "deno",
    ["check", "supabase/functions/analyze/index.ts"],
    () => true,
    { passDetail: "supabase/functions/analyze/index.ts" },
  );
  runCommand(
    "Deno check process-analysis-jobs",
    "deno",
    ["check", "supabase/functions/process-analysis-jobs/index.ts"],
    () => true,
    { passDetail: "supabase/functions/process-analysis-jobs/index.ts" },
  );
}

function printReport() {
  const counts = checks.reduce((acc, check) => {
    acc[check.status] = (acc[check.status] ?? 0) + 1;
    return acc;
  }, {});
  console.log("# Analyze Edge Function Readiness");
  console.log("");
  console.log(`Date: ${new Date().toISOString()}`);
  console.log(`Production project: ${PROJECT_REF}`);
  console.log("");
  console.log("## Summary");
  console.log("");
  console.log(Object.entries(counts).map(([status, count]) => `${status}: ${count}`).join(" · "));
  console.log("");
  console.log("## Checks");
  console.log("");
  console.log("| Status | Check | Detail |");
  console.log("| --- | --- | --- |");
  for (const check of checks) {
    const detail = String(check.detail ?? "").replace(/\n/g, "<br>").replace(/\|/g, "\\|");
    console.log(`| ${check.status} | ${check.name} | ${detail} |`);
  }
  const evidenceRows = checks.filter((check) => check.evidence);
  if (evidenceRows.length > 0) {
    console.log("");
    console.log("## Evidence");
    console.log("");
    for (const check of evidenceRows) {
      console.log(`### ${check.name}`);
      console.log("");
      console.log("```text");
      console.log(check.evidence);
      console.log("```");
      console.log("");
    }
  }
}

async function main() {
  const token = readKeychain(KEYCHAIN_SUPABASE_ACCESS_TOKEN);
  if (!token) {
    if (outputFunctionsJson) {
      console.error("Missing Supabase access token in Keychain.");
      process.exit(1);
    }
    addCheck("FAIL", "Supabase access token", "Missing Keychain token.");
    printReport();
    process.exit(1);
  }

  if (outputFunctionsJson) {
    const rows = normalizeFunctionRows(
      await managementFetch(`/v1/projects/${PROJECT_REF}/functions`, token),
    );
    console.log(JSON.stringify(rows));
    return;
  }

  addCheck("PASS", "Supabase access token", "Keychain token present; value not printed.");
  checkDeno();
  checkXcodeBuildSettings();
  checkMainScheme();
  checkRetiredActiveMarkers();
  await checkManagementFunctions(token);
  await checkRemoteAnalyzeBody(token);
  await checkSecrets(token);
  await checkDatabaseReadiness(token);
  await checkGatewaySmoke();
  printReport();

  const hasFail = checks.some((check) => check.status === "FAIL");
  process.exit(hasFail ? 1 : 0);
}

main().catch((error) => {
  if (outputFunctionsJson) {
    console.error(error.message);
  } else {
    addCheck("FAIL", "Analyze readiness script", error.message);
    printReport();
  }
  process.exit(1);
});
