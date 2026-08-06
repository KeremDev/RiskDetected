import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { evaluateRolloutGate } from "./verify_localization_testflight_rollout_gate.mjs";

const thresholds = JSON.parse(
  readFileSync(
    "docs/localization/phase-6/TESTFLIGHT_ROLLOUT_THRESHOLDS_2026-08-01.json",
    "utf8",
  ),
);

function snapshot(overrides = {}) {
  return {
    schema_version: 1,
    contract_id: thresholds.contract_id,
    stage: 1,
    candidate_build: "78",
    window_start: "2026-08-01T11:00:00Z",
    window_end: "2026-08-01T12:00:00Z",
    metrics: {
      analyses: { total: 1, failed: 0, wrong_language: 0, repaired: 0 },
      reports: { requests: 1, failed: 0 },
      notifications: { attempts: 1, template_misses: 0 },
      stability: { sessions: 1, crashes: 0 },
      queue: { jobs: 1, retried_jobs: 0, ambiguous_dispatches: 0 },
    },
    privacy: { aggregate_only: true },
    ...overrides,
  };
}

function validStage1SessionDelayWaiver() {
  return {
    waiver_id: "stage1_asc_session_propagation_owner_waiver_2026-08-01",
    kind: "stage1_asc_session_propagation",
    stage: 1,
    metric: "sessions",
    owner_authorized: true,
    actual_session_delta: 0,
    required_session_delta: 1,
    installed_tester_count: 1,
    physical_candidate_installed: true,
    physical_launch_succeeded: true,
    apple_documented_latency_hours_max: 24,
    evidence_verified: true,
    waiver_record_sha256: "a".repeat(64),
  };
}

function validStage2Validation() {
  return {
    policy_id:
      "rd-owner-approved-device-simulator-validation-2026-08-01",
    mode: "physical_device",
    status: "passed",
    launches: 3,
    crashes: 0,
    profiles: ["tr-tr-current-v1"],
    checks: [
      "cold_launch",
      "analysis_pipeline",
      "standard_report",
      "linked_notification",
      "queue_terminal",
    ],
    proof_digests: ["a".repeat(64)],
    source_sha256: "b".repeat(64),
    privacy: {
      aggregate_only: true,
      device_identifiers_included: false,
      user_or_account_data_included: false,
      user_content_included: false,
    },
  };
}

test("a complete zero-defect stage passes", () => {
  assert.equal(evaluateRolloutGate(thresholds, snapshot()).status, "passed");
});

test("missing samples hold without claiming success", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      metrics: {
        analyses: { total: 0, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 0, failed: 0 },
        notifications: { attempts: 0, template_misses: 0 },
        stability: { sessions: 0, crashes: 0 },
        queue: { jobs: 0, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "hold");
  assert.equal(result.insufficient_samples.length, 5);
});

test("stage 1 owner waiver resolves only delayed ASC sessions", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      waivers: [validStage1SessionDelayWaiver()],
      metrics: {
        analyses: { total: 1, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 1, failed: 0 },
        notifications: { attempts: 1, template_misses: 0 },
        stability: { sessions: 0, crashes: 0 },
        queue: { jobs: 1, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "passed");
  assert.deepEqual(result.insufficient_samples, []);
  assert.deepEqual(result.applied_waivers, [{
    waiver_id: "stage1_asc_session_propagation_owner_waiver_2026-08-01",
    metric: "sessions",
    actual: 0,
    required: 1,
  }]);
});

test("stage 1 owner waiver cannot hide another missing minimum", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      waivers: [validStage1SessionDelayWaiver()],
      metrics: {
        analyses: { total: 0, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 1, failed: 0 },
        notifications: { attempts: 1, template_misses: 0 },
        stability: { sessions: 0, crashes: 0 },
        queue: { jobs: 1, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "hold");
  assert.deepEqual(
    result.insufficient_samples.map((sample) => sample.metric),
    ["analyses"],
  );
});

test("session-delay waiver is rejected outside stage 1", () => {
  const waiver = validStage1SessionDelayWaiver();
  waiver.stage = 2;
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      stage: 2,
      waivers: [waiver],
      metrics: {
        analyses: { total: 3, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 1, failed: 0 },
        notifications: { attempts: 1, template_misses: 0 },
        stability: { sessions: 0, crashes: 0 },
        queue: { jobs: 3, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "blocked");
  assert.match(result.contract_issues.join(" "), /waiver is invalid/u);
});

test("stage 2 passes with physical-device evidence and no ASC session propagation", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      stage: 2,
      validation: validStage2Validation(),
      observation: {
        stability_source: "device_simulator_validation",
        app_store_connect_usage_gate_input: false,
      },
      metrics: {
        analyses: { total: 3, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 1, failed: 0 },
        notifications: { attempts: 4, template_misses: 0 },
        stability: { sessions: 3, crashes: 0 },
        queue: { jobs: 3, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "passed");
  assert.deepEqual(result.insufficient_samples, []);
});

test("stage 2 fails closed when device/simulator evidence is missing", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      stage: 2,
      metrics: {
        analyses: { total: 3, failed: 0, wrong_language: 0, repaired: 0 },
        reports: { requests: 1, failed: 0 },
        notifications: { attempts: 4, template_misses: 0 },
        stability: { sessions: 0, crashes: 0 },
        queue: { jobs: 3, retried_jobs: 0, ambiguous_dispatches: 0 },
      },
    }),
  );
  assert.equal(result.status, "blocked");
  assert.match(
    result.contract_issues.join(" "),
    /device\/simulator validation evidence is invalid/u,
  );
});

test("wrong-language, crash and ambiguous dispatch block rollout", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({
      metrics: {
        analyses: { total: 10, failed: 0, wrong_language: 1, repaired: 0 },
        reports: { requests: 2, failed: 0 },
        notifications: { attempts: 2, template_misses: 0 },
        stability: { sessions: 10, crashes: 1 },
        queue: { jobs: 10, retried_jobs: 0, ambiguous_dispatches: 1 },
      },
    }),
  );
  assert.equal(result.status, "blocked");
  assert.deepEqual(
    result.threshold_violations.map((violation) => violation.metric),
    [
      "wrong_language_rate",
      "crash_count",
      "ambiguous_dispatch_count",
    ],
  );
});

test("non-aggregate snapshots fail closed", () => {
  const result = evaluateRolloutGate(
    thresholds,
    snapshot({ privacy: { aggregate_only: false } }),
  );
  assert.equal(result.status, "blocked");
  assert.match(result.contract_issues.join(" "), /aggregate-only/u);
});
