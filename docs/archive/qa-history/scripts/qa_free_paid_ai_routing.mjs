#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const PROJECT_REF = "ppcrzemgiztzcgddbins";
const SUPABASE_URL = "https://ppcrzemgiztzcgddbins.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt";
const RUN_LIVE_E2E = process.argv.includes("--live-e2e");
const REPORT_DIR = path.join(ROOT, "QA");
const REPORT_PATH = path.join(
  REPORT_DIR,
  `FreePaidAIRouting_QA_${new Date().toISOString().slice(0, 10)}.md`,
);

const checks = [];
const notes = [];

function addCheck(name, status, detail = "") {
  checks.push({ name, status, detail });
  const marker = status === "PASS" ? "✓" : status === "WARN" ? "!" : "✗";
  console.log(`${marker} [${status}] ${name}${detail ? ` - ${detail}` : ""}`);
}

function runCommand(name, command, args, { warnOnly = false, maxOutput = 12000 } = {}) {
  try {
    const stdout = execFileSync(command, args, {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 20 * 1024 * 1024,
    });
    const trimmed = stdout.trim();
    addCheck(name, "PASS", trimmed.length > maxOutput ? `${trimmed.slice(0, maxOutput)}...` : "");
    return { ok: true, stdout };
  } catch (error) {
    const output = `${error.stdout ?? ""}${error.stderr ?? ""}`.trim();
    addCheck(name, warnOnly ? "WARN" : "FAIL", output.slice(0, maxOutput));
    return { ok: false, stdout: error.stdout ?? "", stderr: error.stderr ?? "", output };
  }
}

function extractJsonObject(output) {
  const start = output.indexOf("{");
  if (start < 0) throw new Error("No JSON object in output");
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < output.length; i += 1) {
    const char = output[i];
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
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) return JSON.parse(output.slice(start, i + 1));
    }
  }
  throw new Error("Unclosed JSON object in output");
}

function queryLinked(name, sql, validate, { warnOnly = false } = {}) {
  try {
    const stdout = execFileSync("supabase", ["db", "query", "--linked", "--output", "json", sql], {
      cwd: ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 20 * 1024 * 1024,
    });
    const parsed = extractJsonObject(stdout);
    const rows = parsed.rows ?? [];
    const result = validate(rows);
    if (result === true) {
      addCheck(name, "PASS", `${rows.length} row`);
    } else {
      addCheck(name, warnOnly ? "WARN" : "FAIL", result || `${rows.length} row`);
    }
    return rows;
  } catch (error) {
    addCheck(name, warnOnly ? "WARN" : "FAIL", `${error.message}\n${error.stdout ?? ""}${error.stderr ?? ""}`);
    return [];
  }
}

function expectSource(file, name, predicate, detail = "") {
  const source = readFileSync(path.join(ROOT, file), "utf8");
  const ok = predicate(source);
  addCheck(name, ok ? "PASS" : "FAIL", ok ? detail : `${file} beklenen kontratı karşılamıyor.`);
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function includeAll(source, fragments) {
  return fragments.every((fragment) => source.includes(fragment));
}

async function httpJson(url, options) {
  const response = await fetch(url, {
    ...options,
    headers: {
      apikey: PUBLISHABLE_KEY,
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { response, body, text };
}

async function tryLiveE2E() {
  if (!RUN_LIVE_E2E) {
    addCheck("Canlı free kullanıcı E2E", "WARN", "--live-e2e verilmedi; prod mutasyonu yapılmadı.");
    return;
  }

  const suffix = Date.now();
  const email = `qa-free-paid-routing-${suffix}@example.com`;
  const password = `Qa!${randomUUID()}a1`;
  let userID = null;
  let accessToken = null;
  let analysisID = randomUUID();
  let secondAnalysisID = randomUUID();

  try {
    const signup = await httpJson(`${SUPABASE_URL}/auth/v1/signup`, {
      method: "POST",
      body: JSON.stringify({
        email,
        password,
        data: { full_name: "QA Free Paid Routing" },
      }),
    });

    if (!signup.response.ok) {
      addCheck("Canlı E2E temp kullanıcı oluşturma", "WARN", `${signup.response.status}: ${signup.text.slice(0, 500)}`);
      return;
    }

    userID = signup.body?.user?.id ?? signup.body?.id ?? null;
    accessToken = signup.body?.access_token ?? signup.body?.session?.access_token ?? null;
    if (!accessToken) {
      queryLinked(
        "Canlı E2E temp kullanıcı email doğrulama",
        `update auth.users
            set email_confirmed_at = coalesce(email_confirmed_at, now())
          where email = '${email.replaceAll("'", "''")}';`,
        () => true,
        { warnOnly: true },
      );
      const token = await httpJson(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });
      accessToken = token.body?.access_token ?? null;
      userID = userID ?? token.body?.user?.id ?? null;
    }

    if (!userID || !accessToken) {
      addCheck(
        "Canlı E2E auth session",
        "WARN",
        "Temp kullanıcı için JWT alınamadı. Gerçek E2E için QA JWT/service role gerekli.",
      );
      return;
    }

    addCheck("Canlı E2E auth session", "PASS", `temp user ${userID.slice(0, 8)}...`);

    const createAnalysis = await httpJson(`${SUPABASE_URL}/rest/v1/analyses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        id: analysisID,
        user_id: userID,
        title: "QA Free Paid Routing İlk Analiz",
        kind: "text",
        canvas: "general",
        text_input:
          "Şantiye girişinde elektrik panosu açık, kablolar yerde dağınık, yangın tüpü erişimi kısmen kapanmış.",
        status: "pending",
      }),
    });
    if (!createAnalysis.response.ok) {
      addCheck("Canlı E2E analiz kaydı", "FAIL", `${createAnalysis.response.status}: ${createAnalysis.text.slice(0, 700)}`);
      return;
    }
    addCheck("Canlı E2E analiz kaydı", "PASS", analysisID);

    const invoke = await httpJson(`${SUPABASE_URL}/functions/v1/analyze`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        analysis_id: analysisID,
        canvas: "general",
        canvases: ["general"],
        analysis_mode: "standard",
        text_input:
          "Şantiye girişinde elektrik panosu açık, kablolar yerde dağınık, yangın tüpü erişimi kısmen kapanmış.",
        request_id: `qa-free-paid-routing-${suffix}`,
        support_id: `QA-FREE-PAID-${suffix}`,
      }),
    });
    if (invoke.response.status !== 202) {
      addCheck("Canlı E2E analyze invoke", "FAIL", `${invoke.response.status}: ${invoke.text.slice(0, 700)}`);
      return;
    }
    addCheck("Canlı E2E analyze invoke", "PASS", "queued");

    queryLinked(
      "Canlı E2E worker manuel tetikleme",
      `select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/process-analysis-jobs',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-analysis-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'analysis_worker_secret')
          ),
          body := jsonb_build_object(
            'source', 'qa_free_paid_ai_routing',
            'limit', 3,
            'requested_at', now()
          ),
          timeout_milliseconds := 30000
        ) as request_id;`,
      (rows) => rows.length === 1 && rows[0]?.request_id != null || JSON.stringify(rows),
      { warnOnly: true },
    );

    let finalAnalysis = null;
    let usageRows = [];
    for (let i = 0; i < 90; i += 1) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const analysisPoll = await httpJson(
        `${SUPABASE_URL}/rest/v1/analyses?id=eq.${analysisID}&select=status,status_message,finding_count,raw_ai_response`,
        { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
      );
      finalAnalysis = Array.isArray(analysisPoll.body) ? analysisPoll.body[0] : null;
      const usagePoll = await httpJson(
        `${SUPABASE_URL}/rest/v1/ai_usage_logs?analysis_id=eq.${analysisID}&select=user_plan,quality_tier,ai_execution_route,provider,model,api_key_alias,fallback_source,total_tokens,http_status,error,error_code`,
        { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
      );
      usageRows = Array.isArray(usagePoll.body) ? usagePoll.body : [];
      if (finalAnalysis?.status === "completed" && usageRows.length > 0) break;
      if (finalAnalysis?.status === "failed") break;
    }

    if (finalAnalysis?.status !== "completed") {
      addCheck(
        "Canlı E2E client queue auto-drain",
        "WARN",
        `Normal enqueue 180 saniye içinde tamamlanmadı: ${JSON.stringify(finalAnalysis ?? {}).slice(0, 700)}`,
      );
      queryLinked(
        "Canlı E2E direct worker queue enqueue",
        `with marked as (
            update public.analyses
               set status = 'queued',
                   queued_at = now(),
                   status_message = 'QA direct worker queue',
                   last_worker_error = null
             where id = ${sqlLiteral(analysisID)}
               and user_id = ${sqlLiteral(userID)}
             returning id
          ),
          enqueued as (
            select public.enqueue_analysis_job_message(
              jsonb_build_object(
                'analysis_id', ${sqlLiteral(analysisID)},
                'user_id', ${sqlLiteral(userID)},
                '__worker', true,
                'canvas', 'general',
                'canvases', jsonb_build_array('general'),
                'analysis_mode', 'standard',
                'text_input', ${sqlLiteral("Şantiye girişinde elektrik panosu açık, kablolar yerde dağınık, yangın tüpü erişimi kısmen kapanmış.")},
                'request_id', ${sqlLiteral(`qa-free-paid-routing-direct-${suffix}`)},
                'support_id', ${sqlLiteral(`QA-FREE-PAID-DIRECT-${suffix}`)},
                'photo_paths', jsonb_build_array(),
                'photo_base64_parts', jsonb_build_array()
              )
            ) as msg_id
            from marked
          )
          select msg_id from enqueued;`,
        (rows) => rows.length === 1 && rows[0]?.msg_id != null || JSON.stringify(rows),
        { warnOnly: true },
      );
      queryLinked(
        "Canlı E2E direct worker manuel tetikleme",
        `select net.http_post(
            url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/process-analysis-jobs',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'x-analysis-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'analysis_worker_secret')
            ),
            body := jsonb_build_object(
              'source', 'qa_free_paid_ai_routing_direct',
              'limit', 3,
              'requested_at', now()
            ),
            timeout_milliseconds := 30000
          ) as request_id;`,
        (rows) => rows.length === 1 && rows[0]?.request_id != null || JSON.stringify(rows),
        { warnOnly: true },
      );
      for (let i = 0; i < 90; i += 1) {
        await new Promise((resolve) => setTimeout(resolve, 2000));
        const analysisPoll = await httpJson(
          `${SUPABASE_URL}/rest/v1/analyses?id=eq.${analysisID}&select=status,status_message,finding_count,raw_ai_response,last_worker_error,worker_attempt_count`,
          { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
        );
        finalAnalysis = Array.isArray(analysisPoll.body) ? analysisPoll.body[0] : null;
        const usagePoll = await httpJson(
          `${SUPABASE_URL}/rest/v1/ai_usage_logs?analysis_id=eq.${analysisID}&select=user_plan,quality_tier,ai_execution_route,provider,model,api_key_alias,fallback_source,total_tokens,http_status,error,error_code`,
          { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
        );
        usageRows = Array.isArray(usagePoll.body) ? usagePoll.body : [];
        if (finalAnalysis?.status === "completed" && usageRows.length > 0) break;
        if (finalAnalysis?.status === "failed") break;
      }
      if (finalAnalysis?.status !== "completed") {
        addCheck("Canlı E2E analiz tamamlanma", "FAIL", JSON.stringify(finalAnalysis ?? {}).slice(0, 900));
        return;
      }
    }
    addCheck("Canlı E2E analiz tamamlanma", "PASS", `${finalAnalysis.finding_count ?? 0} bulgu`);

    const usage = usageRows[usageRows.length - 1] ?? null;
    if (!usage) {
      addCheck("Canlı E2E telemetry log", "FAIL", "ai_usage_logs satırı bulunamadı.");
      return;
    }
    addCheck(
      "Canlı E2E free paid trial telemetry",
      usage.user_plan === "free" && usage.quality_tier === "plus" && usage.ai_execution_route === "free_paid_trial"
        ? "PASS"
        : "FAIL",
      JSON.stringify(usage),
    );
    addCheck(
      "Canlı E2E free paid trial Pro model kullanmadı",
      usage.model !== "gemini-2.5-pro" ? "PASS" : "FAIL",
      JSON.stringify({ model: usage.model, api_key_alias: usage.api_key_alias }),
    );

    const audit = finalAnalysis.raw_ai_response?._input_audit ?? {};
    addCheck(
      "Canlı E2E Plus tadı audit",
      audit.quality_tier === "plus" &&
          audit.ai_execution_route === "free_paid_trial" &&
          audit.references_requested === true &&
          audit.root_cause_requested === true
        ? "PASS"
        : "FAIL",
      JSON.stringify(audit).slice(0, 900),
    );

    const secondCreate = await httpJson(`${SUPABASE_URL}/rest/v1/analyses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        id: secondAnalysisID,
        user_id: userID,
        title: "QA Free Paid Routing İkinci Analiz",
        kind: "text",
        canvas: "general",
        text_input: "Depoda geçiş yolunda kutular birikmiş ve uyarı levhası görünmüyor.",
        status: "pending",
      }),
    });
    if (!secondCreate.response.ok) {
      addCheck("Canlı E2E ikinci analiz kaydı", "WARN", `${secondCreate.response.status}: ${secondCreate.text.slice(0, 500)}`);
      return;
    }
    const secondInvoke = await httpJson(`${SUPABASE_URL}/functions/v1/analyze`, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        analysis_id: secondAnalysisID,
        canvas: "general",
        canvases: ["general"],
        analysis_mode: "standard",
        text_input: "Depoda geçiş yolunda kutular birikmiş ve uyarı levhası görünmüyor.",
        request_id: `qa-free-paid-routing-second-${suffix}`,
        support_id: `QA-FREE-PAID-SECOND-${suffix}`,
      }),
    });
    addCheck(
      "Canlı E2E ikinci free analiz kuyruğu",
      secondInvoke.response.status === 202 ? "PASS" : "FAIL",
      `${secondInvoke.response.status}: ${secondInvoke.text.slice(0, 500)}`,
    );

    let secondFinal = null;
    let secondUsageRows = [];
    for (let i = 0; i < 20; i += 1) {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      const secondPoll = await httpJson(
        `${SUPABASE_URL}/rest/v1/analyses?id=eq.${secondAnalysisID}&select=status,status_message`,
        { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
      );
      secondFinal = Array.isArray(secondPoll.body) ? secondPoll.body[0] : null;
      const secondUsagePoll = await httpJson(
        `${SUPABASE_URL}/rest/v1/ai_usage_logs?analysis_id=eq.${secondAnalysisID}&select=id`,
        { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } },
      );
      secondUsageRows = Array.isArray(secondUsagePoll.body) ? secondUsagePoll.body : [];
      if (secondFinal?.status === "failed") break;
    }
    addCheck(
      "Canlı E2E ikinci analiz kota koruması",
      secondFinal?.status === "failed" && secondUsageRows.length === 0 ? "PASS" : "FAIL",
      JSON.stringify({ secondFinal, secondUsageRows }),
    );
  } finally {
    queryLinked(
      "Canlı E2E temp queue cleanup",
      `delete from pgmq.q_analysis_jobs
        where message->>'analysis_id' in ('${analysisID}', '${secondAnalysisID}');`,
      () => true,
      { warnOnly: true },
    );
    if (email) {
      const cleanup = queryLinked(
        "Canlı E2E temp kullanıcı cleanup",
        `delete from auth.users where email = '${email.replaceAll("'", "''")}';`,
        () => true,
        { warnOnly: true },
      );
      notes.push(`Temp cleanup email: ${email}; cleanup rows payload: ${JSON.stringify(cleanup)}`);
    }
  }
}

function runStaticAndRemoteChecks() {
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Route enum kontratı",
    (source) => includeAll(source, [
      `type AIExecutionRoute = "free_legacy" | "free_paid_trial" | "paid_plan";`,
      `type GeminiPoolName = "free" | "paid";`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Env flag ve kill switch kontratı",
    (source) => includeAll(source, [
      `FREE_STANDARD_ANALYSIS_AI_ROUTE`,
      `return rawValue === "free_legacy" ? "free_legacy" : "paid_trial";`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Free standard paid route çözümü",
    (source) => includeAll(source, [
      `function resolveAIExecutionRoute`,
      `analysisMode === "standard"`,
      `return "free_paid_trial";`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Free paid trial kalite seviyesi Plus",
    (source) => source.includes(`aiExecutionRoute === "free_paid_trial" ? "plus" : planTier;`),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Yetki kontrolleri planTier ile kalıyor",
    (source) => includeAll(source, [
      `if (analysisMode === "detailed" && planTier === "free")`,
      `if (analysisMode === "emergency" && planTier === "free")`,
      `if (analysisMode === "procedure" && planTier !== "pro")`,
      `p_analysis_mode: analysisMode`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Prompt/schema qualityTier ile çalışıyor",
    (source) => includeAll(source, [
      `tier: qualityTier`,
      `referenceModeForTier(qualityTier)`,
      `PLAN_LIMITS[qualityTier]`,
      `references_text: qualityTier !== "free"`,
      `root_cause_text: qualityTier !== "free"`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Free paid trial fallback sırası",
    (source) => includeAll(source, [
      `async function callFreePaidTrialAIWithFallback`,
      `gemini_paid_pool`,
      `gemini_free_pool`,
      `freeGroqKeyConfig`,
      `groq_free_primary`,
    ]),
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Free paid trial Pro model kullanmıyor",
    (source) => {
      const start = source.indexOf("function freePaidTrialPaidGeminiAttemptSequence");
      const end = source.indexOf("async function callGeminiWithFallback", start);
      const block = source.slice(start, end);
      return start >= 0 &&
        block.includes("MODEL_PAID_FAST") &&
        block.includes("MODEL_FLASH_LITE") &&
        !block.includes("MODEL_PRO");
    },
  );
  expectSource(
    "supabase/functions/analyze/index.ts",
    "Telemetry alanları function içinde loglanıyor",
    (source) => includeAll(source, [
      `quality_tier: qualityTier`,
      `ai_execution_route: aiExecutionRoute`,
      `free_standard_analysis_route_flag`,
      `fallback_source`,
    ]),
  );
  expectSource(
    "supabase/migrations/20260529110948_add_ai_execution_route_telemetry.sql",
    "Telemetry migration kontratı",
    (source) => includeAll(source, [
      `quality_tier text`,
      `ai_execution_route text`,
      `free_paid_trial`,
      `ai_usage_logs_ai_execution_route_created_idx`,
      `ai_usage_logs_quality_tier_created_idx`,
    ]),
  );
  expectSource(
    "scripts/qa_hybrid_runner.mjs",
    "Hybrid QA route dağılımını raporluyor",
    (source) => includeAll(source, [
      `coalesce(quality_tier, user_plan) as quality_tier`,
      `coalesce(ai_execution_route, '-') as ai_execution_route`,
      `quality_tier,`,
      `ai_execution_route,`,
    ]),
  );

  runCommand("Deno check analyze", "deno", ["check", "supabase/functions/analyze/index.ts"]);
  runCommand("Node syntax qa_hybrid_runner", "node", ["--check", "scripts/qa_hybrid_runner.mjs"]);
  runCommand("Git whitespace check", "git", ["diff", "--check"]);

  const migrationList = runCommand(
    "Remote migration list contains AI route migration",
    "supabase",
    ["migration", "list", "--linked"],
    { warnOnly: false, maxOutput: 2000 },
  );
  if (migrationList.ok) {
    addCheck(
      "Remote AI route migration applied",
      migrationList.stdout.includes("20260529110948 | 20260529110948") ? "PASS" : "FAIL",
      "20260529110948_add_ai_execution_route_telemetry.sql",
    );
  }

  const secrets = runCommand(
    "Remote secret list readable",
    "supabase",
    ["secrets", "list", "--project-ref", PROJECT_REF],
    { maxOutput: 1200 },
  );
  if (secrets.ok) {
    for (const required of ["GEMINI_API_KEY_PAID", "GEMINI_API_KEY", "FREE_STANDARD_ANALYSIS_AI_ROUTE"]) {
      addCheck(`Remote secret ${required}`, secrets.stdout.includes(required) ? "PASS" : "FAIL");
    }
    addCheck(
      "Remote fallback key present",
      secrets.stdout.includes("GEMINI_API_KEY_SECONDARY") || secrets.stdout.includes("GROQ_API_KEY_FREE") ? "PASS" : "WARN",
      "Free Gemini secondary veya Groq fallback beklenir.",
    );
  }

  const functions = runCommand(
    "Remote analyze function active",
    "supabase",
    ["functions", "list", "--project-ref", PROJECT_REF],
    { maxOutput: 2000 },
  );
  if (functions.ok) {
    const analyzeLine = functions.stdout.split("\n").find((line) => line.includes("| analyze ") || line.includes("│ analyze "));
    addCheck(
      "Analyze function ACTIVE",
      analyzeLine?.includes("ACTIVE") ? "PASS" : "FAIL",
      analyzeLine?.trim() ?? "analyze satırı bulunamadı",
    );
  }

  queryLinked(
    "Remote ai_usage_logs telemetry columns",
    `select column_name, data_type
       from information_schema.columns
      where table_schema = 'public'
        and table_name = 'ai_usage_logs'
        and column_name in ('quality_tier', 'ai_execution_route')
      order by column_name;`,
    (rows) => rows.length === 2 && rows.every((row) => row.data_type === "text") || JSON.stringify(rows),
  );

  queryLinked(
    "Remote telemetry check constraints",
    `select conname, pg_get_constraintdef(oid) as definition
       from pg_constraint
      where conrelid = 'public.ai_usage_logs'::regclass
        and (pg_get_constraintdef(oid) ilike '%quality_tier%'
          or pg_get_constraintdef(oid) ilike '%ai_execution_route%')
      order by conname;`,
    (rows) => rows.length >= 2 && rows.some((row) => row.definition.includes("free_paid_trial")) || JSON.stringify(rows),
  );

  queryLinked(
    "Recent AI usage route distribution",
    `select user_plan,
            coalesce(quality_tier, '-') as quality_tier,
            coalesce(ai_execution_route, '-') as ai_execution_route,
            provider,
            model,
            coalesce(api_key_alias, '-') as api_key_alias,
            coalesce(fallback_source, '-') as fallback_source,
            count(*)::int as calls
       from public.ai_usage_logs
      where created_at >= now() - interval '24 hours'
      group by user_plan, quality_tier, ai_execution_route, provider, model, api_key_alias, fallback_source
      order by calls desc, user_plan
      limit 20;`,
    (rows) => rows.length > 0 || "Son 24 saatte AI usage yok; canlı trafik doğrulanamadı.",
    { warnOnly: true },
  );

  queryLinked(
    "Recent AI errors",
    `select count(*)::int as errors
       from public.ai_usage_logs
      where created_at >= now() - interval '24 hours'
        and (error is not null or coalesce(http_status, 200) >= 400);`,
    (rows) => Number(rows[0]?.errors ?? 0) === 0 || `Son 24 saatte ${rows[0]?.errors} AI error logu var.`,
    { warnOnly: true },
  );
}

async function runRemoteGatewayChecks() {
  const invalidJwt = await httpJson(`${SUPABASE_URL}/functions/v1/analyze`, {
    method: "POST",
    headers: { Authorization: "Bearer not-a-jwt" },
    body: JSON.stringify({ analysis_id: "00000000-0000-0000-0000-000000000000" }),
  });
  addCheck(
    "Remote analyze no-verify-jwt gateway bypass",
    invalidJwt.response.status === 401 &&
        invalidJwt.body?.code === "auth_invalid" &&
        !invalidJwt.text.includes("UNAUTHORIZED_INVALID_JWT_FORMAT")
      ? "PASS"
      : "FAIL",
    invalidJwt.text.slice(0, 700),
  );
}

function writeReport() {
  mkdirSync(REPORT_DIR, { recursive: true });
  const counts = checks.reduce((acc, check) => {
    acc[check.status] = (acc[check.status] ?? 0) + 1;
    return acc;
  }, {});
  const lines = [
    "# Free Paid AI Routing QA",
    "",
    `Tarih: ${new Date().toISOString()}`,
    `Supabase project: ${PROJECT_REF}`,
    `Live E2E: ${RUN_LIVE_E2E ? "denendi" : "kapalı"}`,
    "",
    "## Özet",
    "",
    `- PASS: ${counts.PASS ?? 0}`,
    `- WARN: ${counts.WARN ?? 0}`,
    `- FAIL: ${counts.FAIL ?? 0}`,
    "",
    "## Kontroller",
    "",
    ...checks.map((check) => `- ${check.status}: ${check.name}${check.detail ? ` — ${check.detail.replace(/\n/g, " ").slice(0, 1200)}` : ""}`),
    "",
    "## Notlar",
    "",
    ...(notes.length > 0 ? notes.map((note) => `- ${note}`) : ["- Ek not yok."]),
    "",
  ];
  writeFileSync(REPORT_PATH, `${lines.join("\n")}\n`, "utf8");
  console.log(`\nReport: ${REPORT_PATH}`);
}

runStaticAndRemoteChecks();
await runRemoteGatewayChecks();
await tryLiveE2E();
writeReport();

const failed = checks.filter((check) => check.status === "FAIL");
if (failed.length > 0) {
  process.exitCode = 1;
}
