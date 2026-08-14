#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  ASC_BUILD_ID,
  CANDIDATE_BUILD,
  buildRuntimeConfigSQL,
  buildWindowMetricsSQL,
  createBeginEvidence,
  createFinishEvidence,
  parseASCUsageOutput,
  parseSupabaseQueryOutput,
  sha256JSON,
  verifyRolloutSequence,
} from "./localization_testflight_rollout_lib.mjs";
import {
  evaluateRolloutGate,
} from "./verify_localization_testflight_rollout_gate.mjs";

const DEFAULT_THRESHOLDS =
  "docs/localization/phase-6/TESTFLIGHT_ROLLOUT_THRESHOLDS_2026-08-01.json";
const DEFAULT_OUTPUT_DIR =
  "docs/localization/phase-6/testflight-rollout";
const STAGE1_SESSION_DELAY_WAIVER =
  "docs/localization/phase-6/STAGE_1_ASC_SESSION_DELAY_OWNER_WAIVER_2026-08-01.json";
const PHYSICAL_BUILD_78_EVIDENCE =
  "docs/localization/phase-8/PHYSICAL_BUILD_78_SMOKE_READINESS_2026-08-01.json";
const TESTFLIGHT_METRIC_WAIT_STATE =
  "docs/localization/phase-6/testflight-rollout/TESTFLIGHT_METRIC_WAIT_STATE_2026-08-01.json";

function readJSON(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

function writeJSON(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
    flag: "wx",
  });
}

function writeDerivedJSON(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
  });
}

function parseArguments(argv) {
  const [command, ...raw] = argv;
  if (!["begin", "finish", "verify"].includes(command)) {
    throw new Error("usage: localization_testflight_rollout.mjs begin|finish|verify [options]");
  }
  const values = {
    command,
    thresholds: DEFAULT_THRESHOLDS,
    outputDir: DEFAULT_OUTPUT_DIR,
    stage: null,
    reportRequests: null,
    reportFailures: null,
    reportCountersAttested: false,
    ownerWaiveStage1SessionDelay: false,
    validationEvidence: null,
    expectIncomplete: false,
  };
  for (const argument of raw) {
    if (argument.startsWith("--thresholds=")) {
      values.thresholds = argument.slice("--thresholds=".length);
    } else if (argument.startsWith("--output-dir=")) {
      values.outputDir = argument.slice("--output-dir=".length);
    } else if (argument.startsWith("--stage=")) {
      values.stage = Number(argument.slice("--stage=".length));
    } else if (argument.startsWith("--report-requests=")) {
      values.reportRequests = Number(
        argument.slice("--report-requests=".length),
      );
    } else if (argument.startsWith("--report-failures=")) {
      values.reportFailures = Number(
        argument.slice("--report-failures=".length),
      );
    } else if (argument === "--attest-report-counters") {
      values.reportCountersAttested = true;
    } else if (argument === "--owner-waive-stage1-session-delay") {
      values.ownerWaiveStage1SessionDelay = true;
    } else if (argument.startsWith("--validation-evidence=")) {
      values.validationEvidence = argument.slice(
        "--validation-evidence=".length,
      );
    } else if (argument === "--expect-incomplete") {
      values.expectIncomplete = true;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (
    ["begin", "finish"].includes(command) &&
    (!Number.isInteger(values.stage) || values.stage < 1 || values.stage > 9)
  ) {
    throw new Error("--stage must be an integer from 1 through 9");
  }
  if (
    command === "finish" &&
    (!Number.isInteger(values.reportRequests) ||
      !Number.isInteger(values.reportFailures) ||
      !values.reportCountersAttested)
  ) {
    throw new Error(
      "finish requires --report-requests=N --report-failures=N " +
        "--attest-report-counters",
    );
  }
  if (
    values.ownerWaiveStage1SessionDelay &&
    (command !== "finish" || values.stage !== 1)
  ) {
    throw new Error(
      "--owner-waive-stage1-session-delay is valid only for stage 1 finish",
    );
  }
  if (
    command === "finish" &&
    values.stage >= 2 &&
    !values.validationEvidence
  ) {
    throw new Error(
      "stage 2-9 finish requires --validation-evidence=PATH",
    );
  }
  if (
    values.validationEvidence &&
    (command !== "finish" || values.stage === 1)
  ) {
    throw new Error(
      "--validation-evidence is valid only for stage 2-9 finish",
    );
  }
  return values;
}

function proofFor(record, kind, expectedPath) {
  const matches = Array.isArray(record?.proofs)
    ? record.proofs.filter((proof) =>
      proof?.kind === kind && proof?.path === expectedPath
    )
    : [];
  if (
    matches.length !== 1 ||
    !/^[a-f0-9]{64}$/u.test(matches[0]?.sha256 ?? "")
  ) {
    throw new Error(`stage 1 waiver is missing ${kind} proof`);
  }
  return matches[0];
}

export function validateStage1SessionDelayWaiver({
  waiverRecord,
  physicalEvidence,
  metricWaitState,
}) {
  if (
    waiverRecord?.schema_version !== 1 ||
    waiverRecord?.contract_id !== "rd-global-localization-testflight-rollout-v1" ||
    waiverRecord?.candidate_build !== CANDIDATE_BUILD ||
    waiverRecord?.stage !== 1 ||
    waiverRecord?.authorization?.authorized !== true ||
    waiverRecord?.authorization?.authorized_by_role !== "project_owner" ||
    waiverRecord?.scope?.metric !== "sessions" ||
    waiverRecord?.scope?.actual !== 0 ||
    waiverRecord?.scope?.required !== 1 ||
    waiverRecord?.scope?.treatment !== "accept_stage_1_only" ||
    waiverRecord?.constraints?.stage_1_only !== true ||
    waiverRecord?.constraints?.other_minimums_waived !== false ||
    waiverRecord?.constraints?.zero_tolerance_thresholds_waived !== false ||
    waiverRecord?.constraints?.reported_session_count_overwritten !== false ||
    waiverRecord?.constraints?.stage_2_or_later_affected !== false
  ) {
    throw new Error("stage 1 owner waiver contract is invalid");
  }
  const physicalProof = proofFor(
    waiverRecord,
    "physical_build_78_smoke",
    PHYSICAL_BUILD_78_EVIDENCE,
  );
  const waitProof = proofFor(
    waiverRecord,
    "asc_metric_wait_state",
    TESTFLIGHT_METRIC_WAIT_STATE,
  );
  if (
    physicalProof.sha256 !== sha256JSON(physicalEvidence) ||
    waitProof.sha256 !== sha256JSON(metricWaitState)
  ) {
    throw new Error("stage 1 owner waiver proof digest does not match");
  }
  if (
    physicalEvidence?.candidate?.build !== CANDIDATE_BUILD ||
    physicalEvidence?.status !== "passed" ||
    physicalEvidence?.launch_requested !== true ||
    physicalEvidence?.launch_succeeded !== true ||
    physicalEvidence?.summary?.candidate_install_count < 1 ||
    physicalEvidence?.privacy?.aggregate_only !== true ||
    physicalEvidence?.privacy?.device_identifiers_included !== false ||
    physicalEvidence?.privacy?.user_or_account_data_included !== false
  ) {
    throw new Error("physical Build 78 evidence does not support the waiver");
  }
  if (
    metricWaitState?.candidate?.build !== CANDIDATE_BUILD ||
    metricWaitState?.stage !== 1 ||
    metricWaitState?.status !== "waiting_for_apple_metric_propagation" ||
    metricWaitState?.asc_state?.installed_tester_count < 1 ||
    metricWaitState?.asc_state?.session_count !== 0 ||
    metricWaitState?.asc_state?.crash_count !== 0 ||
    metricWaitState?.physical_device?.candidate_installed !== true ||
    metricWaitState?.physical_device?.candidate_launch_succeeded !== true ||
    metricWaitState?.safety?.stage_2_started !== false ||
    metricWaitState?.safety?.runtime_flags_changed !== false
  ) {
    throw new Error("ASC metric wait state does not support the waiver");
  }
  return {
    waiver_id: String(waiverRecord.waiver_id),
    kind: "stage1_asc_session_propagation",
    stage: 1,
    metric: "sessions",
    owner_authorized: true,
    actual_session_delta: 0,
    required_session_delta: 1,
    installed_tester_count:
      metricWaitState.asc_state.installed_tester_count,
    physical_candidate_installed: true,
    physical_launch_succeeded: true,
    apple_documented_latency_hours_max:
      waiverRecord.basis.apple_documented_latency_hours_max,
    evidence_verified: true,
    waiver_record_sha256: sha256JSON(waiverRecord),
  };
}

function loadStage1SessionDelayWaiver() {
  return validateStage1SessionDelayWaiver({
    waiverRecord: readJSON(STAGE1_SESSION_DELAY_WAIVER),
    physicalEvidence: readJSON(PHYSICAL_BUILD_78_EVIDENCE),
    metricWaitState: readJSON(TESTFLIGHT_METRIC_WAIT_STATE),
  });
}

function stagePrefix(stage) {
  return `stage-${String(stage).padStart(2, "0")}`;
}

function stagePaths(outputDir, stage) {
  const prefix = stagePrefix(stage);
  return {
    begin: path.join(outputDir, `${prefix}-begin.json`),
    snapshot: path.join(outputDir, `${prefix}-snapshot.json`),
    result: path.join(outputDir, `${prefix}-result.json`),
  };
}

function probePath(outputDir, stage, windowEnd) {
  const stamp = windowEnd.replaceAll(/[-:.]/gu, "");
  return path.join(
    outputDir,
    `${stagePrefix(stage)}-probe-${stamp}.json`,
  );
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    throw new Error(`${command} failed (${result.status}): ${detail}`);
  }
  return result.stdout;
}

function collectASCUsage() {
  const stdout = run("asc", [
    "builds",
    "metrics",
    "beta-usages",
    "--build-id",
    ASC_BUILD_ID,
    "--output",
    "json",
  ]);
  const totals = parseASCUsageOutput(stdout);
  return {
    data: [{
      dataPoints: [{
        values: {
          installCount: totals.install_count,
          crashCount: totals.crash_count,
          sessionCount: totals.session_count,
          inviteCount: totals.invite_count,
          feedbackCount: totals.feedback_count,
        },
      }],
    }],
  };
}

function emptyASCUsage() {
  return {
    data: [{
      dataPoints: [{
        values: {
          installCount: 0,
          crashCount: 0,
          sessionCount: 0,
          inviteCount: 0,
          feedbackCount: 0,
        },
      }],
    }],
  };
}

function collectASCUsageForStage(stage) {
  return stage === 1 ? collectASCUsage() : emptyASCUsage();
}

function querySupabase(sql) {
  const stdout = run("supabase", [
    "db",
    "query",
    "--linked",
    "--output",
    "json",
    sql,
  ]);
  return parseSupabaseQueryOutput(stdout);
}

function loadStageRecords(outputDir) {
  if (!existsSync(outputDir)) return [];
  const files = readdirSync(outputDir);
  const snapshotFiles = files
    .filter((file) => /^stage-[0-9]{2}-snapshot\.json$/u.test(file))
    .sort();
  return snapshotFiles.map((snapshotFile) => {
    const prefix = snapshotFile.slice(0, -"snapshot.json".length);
    const resultFile = `${prefix}result.json`;
    const resultPath = path.join(outputDir, resultFile);
    return {
      snapshot: readJSON(path.join(outputDir, snapshotFile)),
      result: existsSync(resultPath) ? readJSON(resultPath) : null,
    };
  });
}

function verifyExistingSequence(thresholds, outputDir) {
  return verifyRolloutSequence({
    thresholds,
    stageRecords: loadStageRecords(outputDir),
    candidateBuild: CANDIDATE_BUILD,
  });
}

function begin(options, thresholds) {
  const paths = stagePaths(options.outputDir, options.stage);
  if (Object.values(paths).some(existsSync)) {
    throw new Error(`stage ${options.stage} evidence already exists`);
  }
  const sequence = verifyExistingSequence(thresholds, options.outputDir);
  if (sequence.status === "blocked") {
    throw new Error(`existing rollout sequence is blocked: ${sequence.issues.join("; ")}`);
  }
  if (sequence.next_stage !== options.stage) {
    throw new Error(
      `stage ${options.stage} cannot begin; next required stage is ` +
        `${sequence.next_stage ?? "none"}`,
    );
  }
  const evidence = createBeginEvidence({
    thresholds,
    stage: options.stage,
    candidateBuild: CANDIDATE_BUILD,
    windowStart: new Date().toISOString(),
    ascUsage: collectASCUsageForStage(options.stage),
    runtimeConfig: querySupabase(buildRuntimeConfigSQL()),
  });
  writeJSON(paths.begin, evidence);
  return {
    status: "begun",
    stage: options.stage,
    stage_key: evidence.stage_key,
    begin_file: paths.begin,
    runtime_config_sha256: evidence.baseline.runtime_config.sha256,
    privacy: evidence.privacy,
  };
}

function finish(options, thresholds) {
  const paths = stagePaths(options.outputDir, options.stage);
  if (!existsSync(paths.begin)) {
    throw new Error(`stage ${options.stage} begin evidence is missing`);
  }
  if (existsSync(paths.snapshot) || existsSync(paths.result)) {
    throw new Error(`stage ${options.stage} finish evidence already exists`);
  }
  const beginEvidence = readJSON(paths.begin);
  if (beginEvidence.stage !== options.stage) {
    throw new Error("begin evidence stage does not match --stage");
  }
  const windowEnd = new Date().toISOString();
  const supabaseObservation = querySupabase(buildWindowMetricsSQL({
    candidateBuild: CANDIDATE_BUILD,
    windowStart: beginEvidence.window_start,
    windowEnd,
  }));
  const snapshot = createFinishEvidence({
    thresholds,
    beginEvidence,
    windowEnd,
    supabaseObservation,
    ascUsage: collectASCUsageForStage(options.stage),
    reportRequests: options.reportRequests,
    reportFailures: options.reportFailures,
    reportCountersAttested: options.reportCountersAttested,
    stage1SessionDelayWaiver: options.ownerWaiveStage1SessionDelay
      ? loadStage1SessionDelayWaiver()
      : null,
    acceleratedValidationEvidence: options.validationEvidence
      ? readJSON(options.validationEvidence)
      : null,
  });
  const gate = evaluateRolloutGate(thresholds, snapshot);
  const result = {
    ...gate,
    integrity_status: snapshot.integrity.status,
    snapshot_sha256: sha256JSON(snapshot),
    effective_status: snapshot.integrity.status === "passed"
      ? gate.status
      : snapshot.integrity.status,
  };
  if (result.effective_status === "hold") {
    const holdProbePath = probePath(
      options.outputDir,
      options.stage,
      windowEnd,
    );
    writeJSON(holdProbePath, { snapshot, result });
    return {
      status: "hold",
      stage: options.stage,
      stage_key: snapshot.stage_key,
      probe_file: holdProbePath,
      integrity_issues: snapshot.integrity.issues,
      insufficient_samples: gate.insufficient_samples,
      threshold_violations: gate.threshold_violations,
      applied_waivers: gate.applied_waivers ?? [],
    };
  }
  writeJSON(paths.snapshot, snapshot);
  writeJSON(paths.result, result);
  return {
    status: result.effective_status,
    stage: options.stage,
    stage_key: snapshot.stage_key,
    snapshot_file: paths.snapshot,
    result_file: paths.result,
    integrity_issues: snapshot.integrity.issues,
    insufficient_samples: gate.insufficient_samples,
    threshold_violations: gate.threshold_violations,
    applied_waivers: gate.applied_waivers ?? [],
  };
}

function verify(options, thresholds) {
  const manifest = verifyExistingSequence(thresholds, options.outputDir);
  const manifestPath = path.join(
    options.outputDir,
    "TESTFLIGHT_ROLLOUT_MANIFEST.json",
  );
  writeDerivedJSON(manifestPath, manifest);
  return { ...manifest, manifest_file: manifestPath };
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const thresholds = readJSON(options.thresholds);
  const output = options.command === "begin"
    ? begin(options, thresholds)
    : options.command === "finish"
    ? finish(options, thresholds)
    : verify(options, thresholds);
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  if (options.command === "finish") {
    process.exitCode = output.status === "passed"
      ? 0
      : output.status === "hold"
      ? 3
      : 2;
  } else if (options.command === "verify") {
    process.exitCode = output.status === "passed" ||
        (options.expectIncomplete && output.status === "hold")
      ? 0
      : output.status === "hold"
      ? 3
      : 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}
