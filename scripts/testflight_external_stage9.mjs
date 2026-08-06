#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  ASC_BUILD_ID,
  findForbiddenEvidenceKeys,
} from "./localization_testflight_rollout_lib.mjs";

const APP_ID = "6769498181";
const GROUP_NAME = "RiskDetected 1.3.0 External Review Candidate";
const MANIFEST =
  "docs/localization/phase-6/testflight-rollout/TESTFLIGHT_ROLLOUT_MANIFEST.json";
const DEFAULT_OUTPUT =
  "docs/localization/phase-6/TESTFLIGHT_STAGE9_EXTERNAL_READINESS_2026-08-01.json";

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error(`${command} operation failed`);
  }
  return result.stdout;
}

function json(stdout, label) {
  try {
    return JSON.parse(stdout);
  } catch {
    throw new Error(`${label} did not return valid JSON`);
  }
}

function asc(args) {
  return json(run("asc", [...args, "--output", "json"]), "asc");
}

function parseArguments(argv) {
  const [command, ...raw] = argv;
  if (!["status", "prepare"].includes(command)) {
    throw new Error(
      "usage: testflight_external_stage9.mjs status|prepare [options]",
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
    command === "prepare" &&
    values.confirm !== "submit-beta-review-candidate"
  ) {
    throw new Error(
      "prepare requires --confirm=submit-beta-review-candidate",
    );
  }
  return values;
}

export function stage9SequenceReady(manifest) {
  return manifest?.schema_version === 1 &&
    manifest?.status === "hold" &&
    manifest?.completed_stages === 8 &&
    manifest?.required_stages === 9 &&
    manifest?.next_stage === 9 &&
    Array.isArray(manifest?.issues) &&
    manifest.issues.length === 0;
}

function groupRecords(payload) {
  return Array.isArray(payload?.data) ? payload.data : [];
}

export function sanitizeStage9State({
  manifest,
  groupsPayload,
  testersPayload,
  submissionsPayload,
  distributionPayload,
  operation,
}) {
  const groups = groupRecords(groupsPayload);
  const testers = groupRecords(testersPayload);
  const submissions = groupRecords(submissionsPayload);
  const distribution = groupRecords(distributionPayload)[0]?.attributes ?? {};
  const externalGroups = groups.filter((group) =>
    group?.attributes?.isInternalGroup === false
  );
  const targetGroups = externalGroups.filter((group) =>
    group?.attributes?.name === GROUP_NAME
  );
  const testerStates = {};
  for (const tester of testers) {
    const state = String(tester?.attributes?.state ?? "UNKNOWN");
    testerStates[state] = (testerStates[state] ?? 0) + 1;
  }
  const submissionStates = {};
  for (const submission of submissions) {
    const attributes = submission?.attributes ?? {};
    const state = String(
      attributes.betaReviewState ??
        attributes.state ??
        "UNKNOWN",
    );
    submissionStates[state] = (submissionStates[state] ?? 0) + 1;
  }
  const sequenceReady = stage9SequenceReady(manifest);
  const externalState = String(
    distribution.externalBuildState ?? "UNKNOWN",
  );
  const betaReviewSubmitted = submissions.length > 0 ||
    !["READY_FOR_BETA_SUBMISSION", "UNKNOWN"].includes(externalState);
  const evidence = {
    schema_version: 1,
    observed_at: new Date().toISOString(),
    operation,
    candidate_build_id: ASC_BUILD_ID,
    sequence: {
      completed_stages: Number(manifest?.completed_stages ?? 0),
      required_stages: Number(manifest?.required_stages ?? 9),
      next_stage: manifest?.next_stage ?? null,
      stage9_prepare_allowed: sequenceReady,
    },
    groups: {
      total_count: groups.length,
      internal_count: groups.filter((group) =>
        group?.attributes?.isInternalGroup === true
      ).length,
      external_count: externalGroups.length,
      target_external_group_count: targetGroups.length,
    },
    testers: {
      total_count: testers.length,
      state_counts: testerStates,
      personal_fields_included: false,
    },
    beta_review: {
      submission_count: submissions.length,
      state_counts: submissionStates,
      external_build_state: externalState,
      submitted: betaReviewSubmitted,
    },
    status: !sequenceReady
      ? "hold_prior_stages_incomplete"
      : targetGroups.length === 1 && betaReviewSubmitted
      ? "stage9_external_candidate_ready"
      : "ready_for_authorized_stage9_prepare",
    safety: {
      app_store_review_submitted: false,
      app_store_release_performed: false,
      beta_review_submission_is_separate: true,
      tester_names_included: false,
      tester_emails_included: false,
      tester_ids_included: false,
    },
  };
  const privacyIssues = findForbiddenEvidenceKeys(evidence);
  if (privacyIssues.length > 0) {
    throw new Error(
      `stage 9 evidence contains forbidden keys: ${privacyIssues.join(", ")}`,
    );
  }
  return evidence;
}

function collectState(manifest, operation) {
  return sanitizeStage9State({
    manifest,
    groupsPayload: asc([
      "testflight",
      "groups",
      "list",
      "--app",
      APP_ID,
    ]),
    testersPayload: asc([
      "testflight",
      "testers",
      "list",
      "--app",
      APP_ID,
    ]),
    submissionsPayload: asc([
      "testflight",
      "review",
      "submissions",
      "list",
      "--build-id",
      ASC_BUILD_ID,
    ]),
    distributionPayload: asc([
      "testflight",
      "distribution",
      "view",
      "--build-id",
      ASC_BUILD_ID,
    ]),
    operation,
  });
}

function targetGroup(payload) {
  const matches = groupRecords(payload).filter((group) =>
    group?.attributes?.isInternalGroup === false &&
    group?.attributes?.name === GROUP_NAME
  );
  if (matches.length > 1) {
    throw new Error("multiple target external TestFlight groups exist");
  }
  return matches[0] ?? null;
}

function prepareStage9(manifest) {
  if (!stage9SequenceReady(manifest)) {
    throw new Error(
      "stage 9 cannot be prepared before stages 1 through 8 pass",
    );
  }
  let groups = asc([
    "testflight",
    "groups",
    "list",
    "--app",
    APP_ID,
  ]);
  let group = targetGroup(groups);
  if (!group) {
    asc([
      "testflight",
      "groups",
      "create",
      "--app",
      APP_ID,
      "--name",
      GROUP_NAME,
    ]);
    groups = asc([
      "testflight",
      "groups",
      "list",
      "--app",
      APP_ID,
    ]);
    group = targetGroup(groups);
  }
  if (!group?.id) {
    throw new Error("target external TestFlight group was not created");
  }
  const testers = groupRecords(asc([
    "testflight",
    "testers",
    "list",
    "--app",
    APP_ID,
  ]));
  const testerIDs = testers
    .map((tester) => tester?.id)
    .filter((value) => typeof value === "string" && value.length > 0);
  if (testerIDs.length === 0) {
    throw new Error("no existing app tester is available for stage 9");
  }
  run("asc", [
    "testflight",
    "groups",
    "add-testers",
    "--group",
    group.id,
    "--tester",
    testerIDs.join(","),
  ]);
  const existingSubmissions = groupRecords(asc([
    "testflight",
    "review",
    "submissions",
    "list",
    "--build-id",
    ASC_BUILD_ID,
  ]));
  if (existingSubmissions.length === 0) {
    asc([
      "builds",
      "add-groups",
      "--build-id",
      ASC_BUILD_ID,
      "--group",
      group.id,
      "--submit",
      "--confirm",
    ]);
  }
}

function writeEvidence(file, evidence) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(evidence, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
  });
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const manifest = JSON.parse(readFileSync(MANIFEST, "utf8"));
  if (options.command === "prepare") prepareStage9(manifest);
  const evidence = collectState(manifest, options.command);
  if (
    options.command === "prepare" &&
    evidence.status !== "stage9_external_candidate_ready"
  ) {
    throw new Error(`stage 9 verification failed: ${evidence.status}`);
  }
  writeEvidence(options.output, evidence);
  process.stdout.write(`${JSON.stringify({
    status: evidence.status,
    output: options.output,
    sequence: evidence.sequence,
    groups: evidence.groups,
    testers: evidence.testers,
    beta_review: evidence.beta_review,
    safety: evidence.safety,
  }, null, 2)}\n`);
  process.exitCode = evidence.status === "hold_prior_stages_incomplete"
    ? 3
    : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}
