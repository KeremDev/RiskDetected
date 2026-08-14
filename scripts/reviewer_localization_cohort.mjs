#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  LOCALIZATION_FLAG_KEYS,
  SUPABASE_PROJECT_REF,
  findForbiddenEvidenceKeys,
  parseSupabaseQueryOutput,
} from "./localization_testflight_rollout_lib.mjs";

const VERSION_ID = "9a2f5061-8992-4957-a9e8-7b8a96747323";
const ENABLE_OPERATION =
  "supabase/operations/enable_global_localization_reviewer_cohort.sql";
const DISABLE_OPERATION =
  "supabase/operations/disable_global_localization_reviewer_cohort.sql";
const DEFAULT_OUTPUT =
  "docs/localization/phase-8/REVIEWER_COHORT_PREFLIGHT_2026-08-01.json";
const ROLLOUT_MANIFEST =
  "docs/localization/phase-6/testflight-rollout/TESTFLIGHT_ROLLOUT_MANIFEST.json";

function parseArguments(argv) {
  const [command, ...raw] = argv;
  if (!["status", "activate", "rollback"].includes(command)) {
    throw new Error(
      "usage: reviewer_localization_cohort.mjs status|activate|rollback [options]",
    );
  }
  const values = { command, output: DEFAULT_OUTPUT, confirm: null };
  for (const argument of raw) {
    if (argument.startsWith("--output=")) {
      values.output = argument.slice("--output=".length);
    } else if (argument.startsWith("--confirm=")) {
      values.confirm = argument.slice("--confirm=".length);
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (
    command === "activate" &&
    values.confirm !== "reviewer-only-allowlist"
  ) {
    throw new Error(
      "activate requires --confirm=reviewer-only-allowlist",
    );
  }
  if (
    command === "rollback" &&
    values.confirm !== "rollback-reviewer-only-allowlist"
  ) {
    throw new Error(
      "rollback requires --confirm=rollback-reviewer-only-allowlist",
    );
  }
  return values;
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

export function reviewDemoAccountName(stdout) {
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error("App Store Connect review details are not valid JSON");
  }
  const record = Array.isArray(parsed?.data) ? parsed.data[0] : parsed?.data;
  const attributes = record?.attributes;
  const name = typeof attributes?.demoAccountName === "string"
    ? attributes.demoAccountName.trim()
    : "";
  if (
    attributes?.demoAccountRequired !== true ||
    name.length < 5 ||
    name.length > 254 ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/u.test(name)
  ) {
    throw new Error(
      "App Store Connect does not contain a valid required demo account name",
    );
  }
  return name;
}

function fetchDemoAccountName() {
  const result = run("asc", [
    "review",
    "details-for-version",
    "--version-id",
    VERSION_ID,
    "--output",
    "json",
  ]);
  if (!result.ok) {
    throw new Error("App Store Connect review details could not be read");
  }
  return reviewDemoAccountName(result.stdout);
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlTextList(values) {
  return values.map(sqlText).join(", ");
}

export function reviewerStatusSQL(demoAccountName) {
  return `
select json_build_object(
  'project_ref', ${sqlText(SUPABASE_PROJECT_REF)},
  'matching_auth_user_count', (
    select count(*) from auth.users
    where lower(email) = lower(${sqlText(demoAccountName)})
  ),
  'flag_count', count(*),
  'off_count', count(*) filter (
    where value ->> 'rollout_mode' = 'off'
  ),
  'allowlist_count', count(*) filter (
    where value ->> 'rollout_mode' = 'allowlist'
  ),
  'enabled_user_hash_entry_count', coalesce(sum(
    case
      when jsonb_typeof(value -> 'enabled_user_hashes') = 'array'
        then jsonb_array_length(value -> 'enabled_user_hashes')
      else 0
    end
  ), 0),
  'enabled_ios_build_entry_count', coalesce(sum(
    case
      when jsonb_typeof(value -> 'enabled_ios_builds') = 'array'
        then jsonb_array_length(value -> 'enabled_ios_builds')
      else 0
    end
  ), 0),
  'kill_switch_true_count', count(*) filter (
    where coalesce((value ->> 'kill_switch')::boolean, false)
  )
) as snapshot
from public.app_feature_flags
where key in (${sqlTextList(LOCALIZATION_FLAG_KEYS)});
`.trim();
}

export function materializeOperation(source, demoAccountName) {
  if (
    !source.includes(":'reviewer_email'") ||
    !source.includes("\\set ON_ERROR_STOP on")
  ) {
    throw new Error("reviewer cohort operation has an unsupported template");
  }
  const rendered = source
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("\\"))
    .join("\n")
    .replaceAll(":'reviewer_email'", sqlText(demoAccountName));
  if (rendered.includes(":'reviewer_email'") || rendered.includes("\\")) {
    throw new Error("reviewer cohort operation was not fully materialized");
  }
  return rendered;
}

function withPrivateSQLFile(sql, callback) {
  const directory = mkdtempSync(
    path.join(tmpdir(), "riskdetected-reviewer-cohort-"),
  );
  const file = path.join(directory, "operation.sql");
  try {
    writeFileSync(file, `${sql.trim()}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    chmodSync(file, 0o600);
    return callback(file);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function executePrivateSQL(sql) {
  return withPrivateSQLFile(sql, (file) =>
    run("supabase", [
      "db",
      "query",
      "--linked",
      "--file",
      file,
      "--output",
      "json",
    ])
  );
}

function readStatus(demoAccountName) {
  const result = executePrivateSQL(reviewerStatusSQL(demoAccountName));
  if (!result.ok) {
    throw new Error("Supabase reviewer cohort status query failed");
  }
  return parseSupabaseQueryOutput(result.stdout);
}

export function sanitizeReviewerStatus(status, operation) {
  const number = (key) => {
    const value = Number(status?.[key]);
    if (!Number.isInteger(value) || value < 0) {
      throw new Error(`reviewer cohort status has invalid ${key}`);
    }
    return value;
  };
  const normalized = {
    matching_auth_user_count: number("matching_auth_user_count"),
    flag_count: number("flag_count"),
    off_count: number("off_count"),
    allowlist_count: number("allowlist_count"),
    enabled_user_hash_entry_count: number(
      "enabled_user_hash_entry_count",
    ),
    enabled_ios_build_entry_count: number(
      "enabled_ios_build_entry_count",
    ),
    kill_switch_true_count: number("kill_switch_true_count"),
  };
  const off = normalized.flag_count === 13 &&
    normalized.off_count === 13 &&
    normalized.allowlist_count === 0 &&
    normalized.enabled_user_hash_entry_count === 0;
  const active = normalized.flag_count === 13 &&
    normalized.off_count === 0 &&
    normalized.allowlist_count === 13 &&
    normalized.enabled_user_hash_entry_count === 13;
  const commonSafe = normalized.matching_auth_user_count === 1 &&
    normalized.enabled_ios_build_entry_count === 0 &&
    normalized.kill_switch_true_count === 0;
  return {
    schema_version: 1,
    observed_at: new Date().toISOString(),
    operation,
    project_ref: SUPABASE_PROJECT_REF,
    app_store_version_id: VERSION_ID,
    app_store_demo_account: {
      required: true,
      configured: true,
      value_persisted_in_evidence: false,
    },
    state: commonSafe && off
      ? "ready_for_authorized_activation"
      : commonSafe && active
      ? "reviewer_only_allowlist_active"
      : "blocked_unknown_state",
    counts: normalized,
    safety: {
      public_rollout_enabled: false,
      build_allowlist_entries: normalized.enabled_ios_build_entry_count,
      kill_switches_active: normalized.kill_switch_true_count,
      raw_email_included: false,
      user_id_included: false,
      user_hash_included: false,
    },
  };
}

export function reviewerActivationSequenceAllowed(manifest) {
  if (
    manifest?.schema_version !== 1 ||
    !Array.isArray(manifest?.issues) ||
    manifest.issues.length > 0
  ) {
    return false;
  }
  const stage2Entry = manifest.status === "hold" &&
    manifest.completed_stages === 1 &&
    manifest.required_stages === 9 &&
    manifest.next_stage === 2;
  const postRolloutReviewAccess = manifest.status === "passed" &&
    manifest.completed_stages === 9 &&
    manifest.required_stages === 9 &&
    manifest.next_stage === null;
  return stage2Entry || postRolloutReviewAccess;
}

function writeEvidence(file, evidence) {
  const privacyIssues = findForbiddenEvidenceKeys(evidence);
  if (privacyIssues.length > 0) {
    throw new Error(
      `reviewer evidence contains forbidden keys: ${privacyIssues.join(", ")}`,
    );
  }
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(evidence, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
  });
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const rolloutManifest = JSON.parse(
    readFileSync(ROLLOUT_MANIFEST, "utf8"),
  );
  const sequenceAllowed = reviewerActivationSequenceAllowed(rolloutManifest);
  if (options.command === "activate" && !sequenceAllowed) {
    throw new Error(
      "reviewer cohort activation is sequence-locked until stage 1 passes",
    );
  }
  const demoAccountName = fetchDemoAccountName();
  if (options.command === "activate" || options.command === "rollback") {
    const sourcePath = options.command === "activate"
      ? ENABLE_OPERATION
      : DISABLE_OPERATION;
    const source = readFileSync(sourcePath, "utf8");
    const operation = executePrivateSQL(
      materializeOperation(source, demoAccountName),
    );
    if (!operation.ok) {
      throw new Error(
        `reviewer cohort ${options.command} transaction failed`,
      );
    }
  }
  const status = sanitizeReviewerStatus(
    readStatus(demoAccountName),
    options.command,
  );
  status.sequence_gate = {
    activation_allowed: sequenceAllowed,
    completed_stages: Number(rolloutManifest?.completed_stages ?? 0),
    required_stages: Number(rolloutManifest?.required_stages ?? 9),
    next_stage: rolloutManifest?.next_stage ?? null,
  };
  status.activation_status = status.state === "ready_for_authorized_activation"
    ? sequenceAllowed
      ? "ready_for_explicit_owner_authorization"
      : "hold_prior_stage_incomplete"
    : status.state;
  const expectedState = options.command === "activate"
    ? "reviewer_only_allowlist_active"
    : options.command === "rollback"
    ? "ready_for_authorized_activation"
    : null;
  if (expectedState && status.state !== expectedState) {
    throw new Error(
      `reviewer cohort ${options.command} verification failed: ${status.state}`,
    );
  }
  writeEvidence(options.output, status);
  process.stdout.write(`${JSON.stringify({
    state: status.state,
    activation_status: status.activation_status,
    operation: status.operation,
    output: options.output,
    sequence_gate: status.sequence_gate,
    counts: status.counts,
    safety: status.safety,
  }, null, 2)}\n`);
  process.exitCode = status.state === "blocked_unknown_state" ? 2 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}
