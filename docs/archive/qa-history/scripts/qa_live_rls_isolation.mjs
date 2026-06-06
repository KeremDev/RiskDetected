#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const PROJECT_REF = "ppcrzemgiztzcgddbins";
const SUPABASE_URL = "https://ppcrzemgiztzcgddbins.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_cUQq5Lv-zDF1hXqwnmAj1A_LTdk9FJt";
const RUN_ID = `${Date.now()}-${randomUUID().slice(0, 8)}`;
const REPORT_DIR = path.join(ROOT, "QA");
const REPORT_PATH = path.join(REPORT_DIR, `Live_RLS_Isolation_QA_${new Date().toISOString().slice(0, 10)}.md`);

const checks = [];
const cleanupEmails = [];

function addCheck(name, status, detail = "") {
  checks.push({ name, status, detail });
  const marker = status === "PASS" ? "✓" : status === "WARN" ? "!" : "✗";
  console.log(`${marker} [${status}] ${name}${detail ? ` - ${detail}` : ""}`);
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
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

function runLinkedQuery(sql, { retries = 3 } = {}) {
  let lastError = null;
  for (let attempt = 1; attempt <= retries; attempt += 1) {
    try {
      const stdout = execFileSync("supabase", [
        "db",
        "query",
        "--linked",
        "--output",
        "json",
        sql,
      ], {
        cwd: ROOT,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
        maxBuffer: 20 * 1024 * 1024,
      });
      return extractJsonObject(stdout).rows ?? [];
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

async function httpJson(url, options = {}) {
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

async function createUser(label) {
  const email = `qa-rls-${label}-${RUN_ID}@example.com`;
  const password = `Qa!${randomUUID()}a1`;
  cleanupEmails.push(email);

  const signup = await httpJson(`${SUPABASE_URL}/auth/v1/signup`, {
    method: "POST",
    body: JSON.stringify({
      email,
      password,
      data: { full_name: `QA RLS ${label.toUpperCase()}` },
    }),
  });
  if (!signup.response.ok) {
    throw new Error(`signup ${label} failed ${signup.response.status}: ${signup.text.slice(0, 500)}`);
  }

  let userID = signup.body?.user?.id ?? signup.body?.id ?? null;
  let accessToken = signup.body?.access_token ?? signup.body?.session?.access_token ?? null;

  if (!accessToken) {
    runLinkedQuery(`
      update auth.users
         set email_confirmed_at = coalesce(email_confirmed_at, now())
       where email = ${sqlLiteral(email)};
    `);
    const token = await httpJson(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
    if (!token.response.ok) {
      throw new Error(`token ${label} failed ${token.response.status}: ${token.text.slice(0, 500)}`);
    }
    userID = userID ?? token.body?.user?.id ?? null;
    accessToken = token.body?.access_token ?? null;
  }

  if (!userID || !accessToken) {
    throw new Error(`No user/token for ${label}`);
  }
  return { email, password, userID, accessToken };
}

async function restSelect(table, token, id) {
  return await httpJson(`${SUPABASE_URL}/rest/v1/${table}?id=eq.${id}&select=id,user_id`, {
    headers: { Authorization: `Bearer ${token}` },
  });
}

async function restInsert(table, token, payload) {
  return await httpJson(`${SUPABASE_URL}/rest/v1/${table}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      Prefer: "return=minimal",
    },
    body: JSON.stringify(payload),
  });
}

function expectRows(name, result, expectedLength) {
  if (!result.response.ok) {
    addCheck(name, "FAIL", `${result.response.status}: ${result.text.slice(0, 500)}`);
    return false;
  }
  const rows = Array.isArray(result.body) ? result.body : [];
  const ok = rows.length === expectedLength;
  addCheck(name, ok ? "PASS" : "FAIL", `expected ${expectedLength}, got ${rows.length}`);
  return ok;
}

async function cleanup() {
  if (cleanupEmails.length === 0) return;
  try {
    runLinkedQuery(`
      delete from auth.users
       where email in (${cleanupEmails.map(sqlLiteral).join(", ")});
    `);
    addCheck("Cleanup temp auth users", "PASS", cleanupEmails.map((email) => email.split("@")[0]).join(", "));
  } catch (error) {
    addCheck("Cleanup temp auth users", "WARN", `${error.message ?? error}`.slice(0, 800));
  }
}

function writeReport() {
  mkdirSync(REPORT_DIR, { recursive: true });
  const lines = [
    `# Live RLS Isolation QA - ${new Date().toISOString().slice(0, 10)}`,
    "",
    `Generated: ${new Date().toISOString()}`,
    `Project: ${PROJECT_REF}`,
    `Run ID: ${RUN_ID}`,
    "",
    "## Summary",
    "",
    `- PASS: ${checks.filter((check) => check.status === "PASS").length}`,
    `- WARN: ${checks.filter((check) => check.status === "WARN").length}`,
    `- FAIL: ${checks.filter((check) => check.status === "FAIL").length}`,
    "",
    "## Checks",
    "",
    "| Status | Check | Detail |",
    "| --- | --- | --- |",
    ...checks.map((check) => `| ${check.status} | ${check.name} | ${check.detail.replaceAll("|", "\\|")} |`),
    "",
    "## Scope",
    "",
    "- Creates two temporary Supabase auth users.",
    "- Inserts temporary `analyses`, `photos`, and `reports` rows for user A through authenticated REST.",
    "- Verifies user A can select own rows and user B sees zero rows for those IDs.",
    "- Verifies user B cannot insert an `analyses` row using user A's `user_id`.",
    "- Deletes temporary auth users at the end; cascades clean user-owned rows.",
    "",
  ];
  writeFileSync(REPORT_PATH, `${lines.join("\n")}\n`);
  console.log(`Report: ${REPORT_PATH}`);
}

async function main() {
  let failed = false;
  try {
    const userA = await createUser("a");
    const userB = await createUser("b");
    addCheck("Create temp users", "PASS", `${userA.userID.slice(0, 8)}..., ${userB.userID.slice(0, 8)}...`);

    const analysisID = randomUUID();
    const photoID = randomUUID();
    const reportID = randomUUID();

    const analysisInsert = await restInsert("analyses", userA.accessToken, {
      id: analysisID,
      user_id: userA.userID,
      title: "QA RLS Isolation Analysis",
      kind: "text",
      canvas: "general",
      text_input: "QA RLS isolation text input",
      status: "pending",
    });
    addCheck(
      "User A inserts own analysis",
      analysisInsert.response.ok ? "PASS" : "FAIL",
      analysisInsert.response.ok ? analysisID : `${analysisInsert.response.status}: ${analysisInsert.text.slice(0, 500)}`,
    );
    if (!analysisInsert.response.ok) failed = true;

    const photoInsert = await restInsert("photos", userA.accessToken, {
      id: photoID,
      analysis_id: analysisID,
      user_id: userA.userID,
      storage_path: `${userA.userID}/${analysisID}/qa-rls-photo.jpg`,
      width: 16,
      height: 16,
      size_bytes: 128,
      mime_type: "image/jpeg",
    });
    addCheck(
      "User A inserts own photo",
      photoInsert.response.ok ? "PASS" : "FAIL",
      photoInsert.response.ok ? photoID : `${photoInsert.response.status}: ${photoInsert.text.slice(0, 500)}`,
    );
    if (!photoInsert.response.ok) failed = true;

    const reportInsert = await restInsert("reports", userA.accessToken, {
      id: reportID,
      user_id: userA.userID,
      analysis_id: analysisID,
      document_no: `QA-RLS-${RUN_ID}`,
      format: "pdf",
      kind: "standard",
      method: "fine_kinney",
      title: "QA RLS Isolation Report",
      storage_path: `${userA.userID}/${analysisID}/qa-rls-report.pdf`,
      file_name: "qa-rls-report.pdf",
      mime_type: "application/pdf",
      file_size: 128,
      size_bytes: 128,
    });
    addCheck(
      "User A inserts own report",
      reportInsert.response.ok ? "PASS" : "FAIL",
      reportInsert.response.ok ? reportID : `${reportInsert.response.status}: ${reportInsert.text.slice(0, 500)}`,
    );
    if (!reportInsert.response.ok) failed = true;

    failed = !expectRows("User A selects own analysis", await restSelect("analyses", userA.accessToken, analysisID), 1) || failed;
    failed = !expectRows("User B cannot select user A analysis", await restSelect("analyses", userB.accessToken, analysisID), 0) || failed;
    failed = !expectRows("User A selects own photo", await restSelect("photos", userA.accessToken, photoID), 1) || failed;
    failed = !expectRows("User B cannot select user A photo", await restSelect("photos", userB.accessToken, photoID), 0) || failed;
    failed = !expectRows("User A selects own report", await restSelect("reports", userA.accessToken, reportID), 1) || failed;
    failed = !expectRows("User B cannot select user A report", await restSelect("reports", userB.accessToken, reportID), 0) || failed;

    const forbiddenInsert = await restInsert("analyses", userB.accessToken, {
      id: randomUUID(),
      user_id: userA.userID,
      title: "QA RLS Forbidden Analysis",
      kind: "text",
      canvas: "general",
      text_input: "This insert should be rejected by RLS.",
      status: "pending",
    });
    const rejected = forbiddenInsert.response.status === 401 || forbiddenInsert.response.status === 403;
    addCheck(
      "User B cannot insert analysis for user A",
      rejected ? "PASS" : "FAIL",
      `${forbiddenInsert.response.status}: ${forbiddenInsert.text.slice(0, 400)}`,
    );
    if (!rejected) failed = true;
  } catch (error) {
    failed = true;
    addCheck("Live RLS isolation runner", "FAIL", `${error.stack ?? error}`.slice(0, 1200));
  } finally {
    await cleanup();
    writeReport();
  }

  if (failed || checks.some((check) => check.status === "FAIL")) {
    process.exitCode = 1;
  }
}

await main();
