import assert from "node:assert/strict";
import test from "node:test";
import {
  CANDIDATE_BUILD,
  CONTRACT_ID,
  LOCALIZATION_FLAG_KEYS,
  buildWindowMetricsSQL,
  createBeginEvidence,
  createFinishEvidence,
  findForbiddenEvidenceKeys,
  normalizeAcceleratedValidationEvidence,
  parseASCUsageOutput,
  parseSupabaseQueryOutput,
  sha256JSON,
  verifyRolloutSequence,
} from "./localization_testflight_rollout_lib.mjs";
import {
  validateStage1SessionDelayWaiver,
} from "./localization_testflight_rollout.mjs";

const thresholds = {
  schema_version: 1,
  contract_id: CONTRACT_ID,
  count_thresholds: {
    crash_count_max: 0,
  },
  accelerated_validation_policy: {
    policy_id: "rd-owner-approved-device-simulator-validation-2026-08-01",
    owner_authorized: true,
    applies_to_stages: [2, 3, 4, 5, 6, 7, 8, 9],
    app_store_connect_usage_is_gate_input: false,
    app_store_connect_usage_collection_required: false,
    strict_stage_order_remains_required: true,
    zero_tolerance_thresholds_remain_enforced: true,
  },
  stages: Array.from({ length: 9 }, (_, index) => ({
    stage: index + 1,
    key: `stage_${index + 1}`,
    validation: index === 0
      ? undefined
      : {
        mode: "simulator",
        minimum_launches: 1,
        required_profiles: ["en-intl-generic-v1"],
        required_checks: ["profile_matrix"],
      },
  })),
};

function ascUsage(values = {}) {
  return {
    data: [{
      dataPoints: [{
        values: {
          installCount: 1,
          crashCount: 0,
          sessionCount: 4,
          inviteCount: 1,
          feedbackCount: 0,
          ...values,
        },
      }],
    }],
  };
}

function runtimeConfig(mode = "off") {
  return {
    localization_flags: LOCALIZATION_FLAG_KEYS.map((key) => ({
      key,
      rollout_mode: mode,
      enabled_user_hash_count: mode === "allowlist" ? 1 : 0,
      enabled_ios_builds: [],
      min_ios_build: null,
      kill_switch: false,
    })),
  };
}

function beginEvidence(stage = 1) {
  return createBeginEvidence({
    thresholds,
    stage,
    candidateBuild: CANDIDATE_BUILD,
    windowStart: `2026-08-01T${String(stage).padStart(2, "0")}:00:00Z`,
    ascUsage: ascUsage(),
    runtimeConfig: runtimeConfig(),
  });
}

function observation() {
  return {
    metrics: {
      analyses: {
        total: 1,
        completed: 1,
        failed: 0,
        pending: 0,
        wrong_language: 0,
        repaired: 0,
        telemetry_missing: 0,
        telemetry_null: 0,
        not_evaluated: 0,
      },
      reports: { observed_successful: 1 },
      notifications: {
        attempts: 1,
        template_misses: 0,
        telemetry_missing: 0,
      },
      queue: { jobs: 1, retried_jobs: 0, ambiguous_dispatches: 0 },
    },
    runtime_config: runtimeConfig(),
  };
}

function acceleratedEvidence(stage = 2) {
  return {
    schema_version: 1,
    kind: "device_simulator_rollout_validation",
    policy_id:
      "rd-owner-approved-device-simulator-validation-2026-08-01",
    contract_id: CONTRACT_ID,
    candidate_build: CANDIDATE_BUILD,
    stage,
    mode: "simulator",
    status: "passed",
    launches: 1,
    crashes: 0,
    profiles: ["en-intl-generic-v1"],
    checks: ["profile_matrix"],
    proof_digests: ["a".repeat(64)],
    privacy: {
      aggregate_only: true,
      device_identifiers_included: false,
      user_or_account_data_included: false,
      user_content_included: false,
    },
  };
}

test("App Store Connect metrics are reduced to aggregate totals", () => {
  assert.deepEqual(parseASCUsageOutput(JSON.stringify(ascUsage())), {
    install_count: 1,
    crash_count: 0,
    session_count: 4,
    invite_count: 1,
    feedback_count: 0,
  });
});

test("Supabase response parser accepts only the bounded snapshot row", () => {
  assert.deepEqual(
    parseSupabaseQueryOutput(JSON.stringify({
      rows: [{ snapshot: { metrics: { count: 1 } } }],
    })),
    { metrics: { count: 1 } },
  );
  assert.throws(
    () => parseSupabaseQueryOutput(JSON.stringify({ rows: [] })),
    /rows\[0\]\.snapshot/u,
  );
});

test("generated SQL is build/window bounded and excludes content columns", () => {
  const sql = buildWindowMetricsSQL({
    candidateBuild: "78",
    windowStart: "2026-08-01T01:00:00Z",
    windowEnd: "2026-08-01T02:00:00Z",
  });
  assert.match(sql, /a\.client_build = p\.candidate_build/u);
  assert.match(sql, /a\.created_at >= p\.window_start/u);
  assert.doesNotMatch(sql, /raw_ai_response|\btitle\b|\bbody\b|\buser_id\b/u);
});

test("finish evidence is aggregate-only and cross-checks report counters", () => {
  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(),
    windowEnd: "2026-08-01T02:00:00Z",
    supabaseObservation: observation(),
    ascUsage: ascUsage({ sessionCount: 5 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
  });
  assert.equal(evidence.integrity.status, "passed");
  assert.equal(evidence.metrics.stability.sessions, 1);
  assert.deepEqual(findForbiddenEvidenceKeys(evidence), []);
});

test("pending analyses and delayed report rows hold without closing the stage", () => {
  const observed = observation();
  observed.metrics.analyses.pending = 1;
  observed.metrics.analyses.completed = 0;
  observed.metrics.reports.observed_successful = 0;
  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(),
    windowEnd: "2026-08-01T02:00:00Z",
    supabaseObservation: observed,
    ascUsage: ascUsage({ sessionCount: 5 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
  });
  assert.equal(evidence.integrity.status, "hold");
  assert.match(evidence.integrity.issues.join(" "), /terminal state/u);
  assert.match(evidence.integrity.issues.join(" "), /successful reports/u);
});

test("runtime flag drift during a stage fails closed", () => {
  const observed = observation();
  observed.runtime_config = runtimeConfig("allowlist");
  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(),
    windowEnd: "2026-08-01T02:00:00Z",
    supabaseObservation: observed,
    ascUsage: ascUsage({ sessionCount: 5 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
  });
  assert.equal(evidence.integrity.status, "blocked");
  assert.match(evidence.integrity.issues.join(" "), /configuration changed/u);
});

test("stage 1 permits expected not-evaluated legacy telemetry", () => {
  const observed = observation();
  observed.metrics.analyses.telemetry_missing = 1;
  observed.metrics.analyses.not_evaluated = 1;
  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(1),
    windowEnd: "2026-08-01T02:00:00Z",
    supabaseObservation: observed,
    ascUsage: ascUsage({ sessionCount: 5 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
  });
  assert.equal(evidence.integrity.status, "passed");
  assert.equal(evidence.observation.analyses.not_evaluated, 1);
  assert.equal(evidence.observation.analyses.telemetry_null, 0);
});

test("stage 2 still blocks not-evaluated language telemetry", () => {
  const observed = observation();
  observed.metrics.analyses.telemetry_missing = 1;
  observed.metrics.analyses.not_evaluated = 1;
  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(2),
    windowEnd: "2026-08-01T03:00:00Z",
    supabaseObservation: observed,
    ascUsage: ascUsage({ sessionCount: 5 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
    acceleratedValidationEvidence: acceleratedEvidence(2),
  });
  assert.equal(evidence.integrity.status, "blocked");
  assert.match(evidence.integrity.issues.join(" "), /not evaluated/u);
});

test("accelerated validation replaces delayed ASC usage with digest-bound simulator evidence", () => {
  const normalized = normalizeAcceleratedValidationEvidence({
    thresholds,
    stage: 2,
    candidateBuild: CANDIDATE_BUILD,
    evidence: acceleratedEvidence(2),
  });
  assert.equal(normalized.status, "passed");
  assert.equal(normalized.launches, 1);
  assert.match(normalized.source_sha256, /^[a-f0-9]{64}$/u);

  const evidence = createFinishEvidence({
    thresholds,
    beginEvidence: beginEvidence(2),
    windowEnd: "2026-08-01T03:00:00Z",
    supabaseObservation: observation(),
    ascUsage: ascUsage({ sessionCount: 0, inviteCount: 0 }),
    reportRequests: 1,
    reportFailures: 0,
    reportCountersAttested: true,
    acceleratedValidationEvidence: acceleratedEvidence(2),
  });
  assert.equal(evidence.integrity.status, "passed");
  assert.equal(evidence.metrics.stability.sessions, 1);
  assert.equal(evidence.metrics.stability.crashes, 0);
  assert.equal(
    evidence.observation.stability_source,
    "device_simulator_validation",
  );
  assert.equal(
    evidence.observation.app_store_connect_usage_gate_input,
    false,
  );
});

test("stage 1 owner waiver requires digest-bound physical and ASC evidence", () => {
  const physicalEvidence = {
    candidate: { build: CANDIDATE_BUILD },
    status: "passed",
    launch_requested: true,
    launch_succeeded: true,
    summary: { candidate_install_count: 1 },
    privacy: {
      aggregate_only: true,
      device_identifiers_included: false,
      user_or_account_data_included: false,
    },
  };
  const metricWaitState = {
    candidate: { build: CANDIDATE_BUILD },
    stage: 1,
    status: "waiting_for_apple_metric_propagation",
    asc_state: {
      installed_tester_count: 1,
      session_count: 0,
      crash_count: 0,
    },
    physical_device: {
      candidate_installed: true,
      candidate_launch_succeeded: true,
    },
    safety: {
      stage_2_started: false,
      runtime_flags_changed: false,
    },
  };
  const waiverRecord = {
    schema_version: 1,
    waiver_id: "stage1_asc_session_propagation_owner_waiver_2026-08-01",
    contract_id: CONTRACT_ID,
    candidate_build: CANDIDATE_BUILD,
    stage: 1,
    authorization: {
      authorized: true,
      authorized_by_role: "project_owner",
    },
    scope: {
      metric: "sessions",
      actual: 0,
      required: 1,
      treatment: "accept_stage_1_only",
    },
    basis: { apple_documented_latency_hours_max: 24 },
    proofs: [
      {
        kind: "physical_build_78_smoke",
        path:
          "docs/localization/phase-8/PHYSICAL_BUILD_78_SMOKE_READINESS_2026-08-01.json",
        sha256: sha256JSON(physicalEvidence),
      },
      {
        kind: "asc_metric_wait_state",
        path:
          "docs/localization/phase-6/testflight-rollout/TESTFLIGHT_METRIC_WAIT_STATE_2026-08-01.json",
        sha256: sha256JSON(metricWaitState),
      },
    ],
    constraints: {
      stage_1_only: true,
      other_minimums_waived: false,
      zero_tolerance_thresholds_waived: false,
      reported_session_count_overwritten: false,
      stage_2_or_later_affected: false,
    },
  };
  const waiver = validateStage1SessionDelayWaiver({
    waiverRecord,
    physicalEvidence,
    metricWaitState,
  });
  assert.equal(waiver.owner_authorized, true);
  assert.equal(waiver.actual_session_delta, 0);
  assert.equal(waiver.evidence_verified, true);
  assert.throws(
    () =>
      validateStage1SessionDelayWaiver({
        waiverRecord,
        physicalEvidence: {
          ...physicalEvidence,
          launch_succeeded: false,
        },
        metricWaitState,
      }),
    /digest does not match/u,
  );
});

test("waived stage 1 remains digest-bound in the ordered sequence", () => {
  const waiver = {
    waiver_id: "stage1_asc_session_propagation_owner_waiver_2026-08-01",
    kind: "stage1_asc_session_propagation",
    stage: 1,
    metric: "sessions",
    owner_authorized: true,
    evidence_verified: true,
    waiver_record_sha256: "b".repeat(64),
  };
  const snapshot = {
    schema_version: 1,
    contract_id: CONTRACT_ID,
    stage: 1,
    stage_key: "stage_1",
    candidate_build: CANDIDATE_BUILD,
    window_start: "2026-08-01T01:00:00Z",
    window_end: "2026-08-01T01:30:00Z",
    waivers: [waiver],
    integrity: { status: "passed", issues: [] },
    privacy: {
      aggregate_only: true,
      disallowed_data_present: false,
    },
  };
  const result = verifyRolloutSequence({
    thresholds,
    stageRecords: [{
      snapshot,
      result: {
        status: "passed",
        applied_waivers: [{
          waiver_id: waiver.waiver_id,
          metric: "sessions",
        }],
        snapshot_sha256: sha256JSON(snapshot),
      },
    }],
  });
  assert.equal(result.status, "hold");
  assert.equal(result.completed_stages, 1);
  assert.equal(result.next_stage, 2);
});

test("nine ordered, non-overlapping passing stages close the sequence", () => {
  const records = thresholds.stages.map((stage) => {
    const snapshot = {
      schema_version: 1,
      contract_id: CONTRACT_ID,
      stage: stage.stage,
      stage_key: stage.key,
      candidate_build: CANDIDATE_BUILD,
      window_start: `2026-08-01T${String(stage.stage).padStart(2, "0")}:00:00Z`,
      window_end: `2026-08-01T${String(stage.stage).padStart(2, "0")}:30:00Z`,
      integrity: { status: "passed", issues: [] },
      privacy: {
        aggregate_only: true,
        disallowed_data_present: false,
      },
    };
    return {
      snapshot,
      result: { status: "passed", snapshot_sha256: sha256JSON(snapshot) },
    };
  });
  const result = verifyRolloutSequence({
    thresholds,
    stageRecords: records,
  });
  assert.equal(result.status, "passed");
  assert.equal(result.completed_stages, 9);
});

test("a stage gap or forbidden evidence key blocks the sequence", () => {
  const snapshot = {
    schema_version: 1,
    contract_id: CONTRACT_ID,
    stage: 2,
    stage_key: "stage_2",
    candidate_build: CANDIDATE_BUILD,
    window_start: "2026-08-01T02:00:00Z",
    window_end: "2026-08-01T02:30:00Z",
    integrity: { status: "passed", issues: [] },
    privacy: {
      aggregate_only: true,
      disallowed_data_present: false,
    },
    email: "must-not-appear@example.com",
  };
  const result = verifyRolloutSequence({
    thresholds,
    stageRecords: [{
      snapshot,
      result: { status: "passed", snapshot_sha256: sha256JSON(snapshot) },
    }],
  });
  assert.equal(result.status, "blocked");
  assert.match(result.issues.join(" "), /sequence gap/u);
  assert.match(result.issues.join(" "), /aggregate-only/u);
});
