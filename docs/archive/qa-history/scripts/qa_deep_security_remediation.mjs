#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();
const checks = [];

function read(relPath) {
  return readFileSync(path.join(ROOT, relPath), "utf8");
}

function addCheck(name, ok, detail = "") {
  checks.push({ name, ok, detail });
  const marker = ok ? "PASS" : "FAIL";
  console.log(`${marker} ${name}${detail ? ` - ${detail}` : ""}`);
}

function includesAll(source, fragments) {
  return fragments.every((fragment) => source.includes(fragment));
}

function indexAfter(source, first, second) {
  const firstIndex = source.indexOf(first);
  const secondIndex = source.indexOf(second);
  return firstIndex >= 0 && secondIndex >= 0 && firstIndex < secondIndex;
}

const analyze = read("supabase/functions/analyze/index.ts");
const analyzeServe = analyze.slice(analyze.indexOf("serve(async"));
addCheck(
  "Analyze validates inline photo input before enqueue",
  indexAfter(analyzeServe, "const inlinePhotoValidation = validateInlinePhotoInput", "await enqueueAnalysisJob"),
);
addCheck(
  "Analyze reserves quota before enqueue",
  indexAfter(analyzeServe, ".rpc(\"reserve_analysis_quota\"", "await enqueueAnalysisJob"),
);
addCheck(
  "Analyze releases quota when enqueue fails",
  includesAll(analyzeServe, [
    "catch (error) {",
    "await releaseAnalysisQuota(supabase, analysisID, user.id);",
    "analysis_enqueue_failed",
  ]),
);
addCheck(
  "Analyze enforces backend image count and byte limits",
  includesAll(analyze, [
    "MAX_ANALYSIS_IMAGE_PARTS",
    "MAX_INLINE_PHOTO_DECODED_BYTES",
    "decodedBase64ByteLength(data)",
    "too_many_photos",
  ]),
);

const support = read("supabase/functions/support-contact/index.ts");
addCheck(
  "Support validates real decoded attachment bytes",
  includesAll(support, [
    "MAX_ATTACHMENT_BYTES",
    "MAX_ATTACHMENT_TOTAL_BYTES",
    "decodedBase64ByteLength(data)",
    "size_bytes: decodedBytes",
  ]) && !support.includes("item.size_bytes >= 0"),
);
addCheck(
  "Support uses durable rate-limit RPC",
  includesAll(support, [
    "check_support_request_rate_limit",
    "support_rate_limited",
    "retry_after_seconds",
  ]),
);

const migrationPath = "supabase/migrations/20260601064449_deep_security_remediation.sql";
const migration = read(migrationPath);
addCheck(
  "Migration makes quota reservation idempotent",
  includesAll(migration, [
    "existing_event_type",
    "'already_reserved', true",
    "usage_events_analysis_feature_unique",
  ]) || includesAll(migration, [
    "existing_event_type",
    "'already_reserved', true",
    "on conflict (user_id, feature, source_id)",
  ]),
);
addCheck(
  "Migration defines support rate limiter",
  includesAll(migration, [
    "private.support_request_rate_limits",
    "check_support_request_rate_limit",
    "support_hourly_rate_limited",
    "support_daily_rate_limited",
  ]),
);
addCheck(
  "Migration hardens findings and reports grants",
  includesAll(migration, [
    "revoke all on public.findings from authenticated",
    "grant select on public.findings to authenticated",
    "revoke all on public.reports from authenticated",
    "grant select, delete on public.reports to authenticated",
  ]),
);
addCheck(
  "Migration limits authenticated analysis updates to company_id",
  includesAll(migration, [
    "revoke all on public.analyses from authenticated",
    "grant select, delete on public.analyses to authenticated",
    "grant insert (",
    "grant update (company_id) on public.analyses to authenticated",
  ]),
);

const registerReportPath = "supabase/functions/register-report/index.ts";
const registerReportExists = existsSync(path.join(ROOT, registerReportPath));
const registerReport = registerReportExists ? read(registerReportPath) : "";
addCheck("Register-report function exists", registerReportExists);
addCheck(
  "Register-report validates owner, status, path, storage bytes",
  includesAll(registerReport, [
    ".eq(\"user_id\", user.id)",
    "analysisRow.status !== \"completed\"",
    "storagePath.toLowerCase().startsWith(expectedPrefix)",
    ".download(storagePath)",
    "storedBytes !== fileSize",
  ]),
);

const config = read("supabase/config.toml");
const rdConfig = read("App/Services/RDConfig.swift");
const analysisService = read("App/Services/AnalysisService.swift");
addCheck(
  "Register-report is configured and used by iOS PDF flow",
  includesAll(config, ["[functions.register-report]", "verify_jwt = true"]) &&
    rdConfig.includes("registerReportFunctionName = \"register-report\"") &&
    analysisService.includes("RDConfig.registerReportFunctionName") &&
    !analysisService.includes(".from(\"reports\")\n                .insert(payload)"),
);

const failed = checks.filter((check) => !check.ok);
console.log(`\nSummary: ${checks.length - failed.length} PASS, ${failed.length} FAIL`);
if (failed.length > 0) {
  process.exit(1);
}
