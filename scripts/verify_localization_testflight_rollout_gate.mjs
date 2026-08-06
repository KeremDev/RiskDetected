#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const DEFAULT_THRESHOLDS =
  "docs/localization/phase-6/TESTFLIGHT_ROLLOUT_THRESHOLDS_2026-08-01.json";

const isNonNegativeInteger = (value) =>
  Number.isInteger(value) && value >= 0;

function rate(numerator, denominator) {
  return denominator === 0 ? null : numerator / denominator;
}

function requireMetric(record, key, issues) {
  const value = record?.[key];
  if (!isNonNegativeInteger(value)) {
    issues.push(`${key} must be a non-negative integer`);
    return 0;
  }
  return value;
}

export function evaluateRolloutGate(thresholds, snapshot) {
  const contractIssues = [];
  if (
    thresholds?.schema_version !== 1 ||
    thresholds?.contract_id !== "rd-global-localization-testflight-rollout-v1"
  ) {
    contractIssues.push("unsupported threshold contract");
  }
  if (
    snapshot?.schema_version !== 1 ||
    snapshot?.contract_id !== thresholds?.contract_id
  ) {
    contractIssues.push("snapshot contract does not match thresholds");
  }
  if (!Number.isInteger(snapshot?.stage)) {
    contractIssues.push("snapshot stage must be an integer");
  }
  if (
    typeof snapshot?.window_start !== "string" ||
    typeof snapshot?.window_end !== "string" ||
    !Number.isFinite(Date.parse(snapshot.window_start)) ||
    !Number.isFinite(Date.parse(snapshot.window_end)) ||
    Date.parse(snapshot.window_start) >= Date.parse(snapshot.window_end)
  ) {
    contractIssues.push("snapshot observation window is invalid");
  }
  if (
    typeof snapshot?.candidate_build !== "string" ||
    !/^[1-9][0-9]{0,8}$/.test(snapshot.candidate_build)
  ) {
    contractIssues.push("candidate_build must be a positive build string");
  }
  if (snapshot?.privacy?.aggregate_only !== true) {
    contractIssues.push("snapshot must attest aggregate-only telemetry");
  }

  const declaredWaivers = snapshot?.waivers === undefined
    ? []
    : snapshot.waivers;
  if (!Array.isArray(declaredWaivers)) {
    contractIssues.push("snapshot waivers must be an array");
  }
  const waiverList = Array.isArray(declaredWaivers)
    ? declaredWaivers
    : [];
  let validStage1SessionDelayWaiver = null;
  if (waiverList.length > 0) {
    const waiver = waiverList[0];
    const policy = thresholds?.waiver_policy
      ?.stage1_asc_session_propagation;
    if (
      waiverList.length !== 1 ||
      policy?.allowed !== true ||
      policy?.stage !== 1 ||
      policy?.metric !== "sessions" ||
      policy?.zero_tolerance_thresholds_remain_enforced !== true ||
      policy?.later_stages_affected !== false ||
      snapshot?.stage !== 1 ||
      waiver?.kind !== "stage1_asc_session_propagation" ||
      waiver?.stage !== 1 ||
      waiver?.metric !== "sessions" ||
      waiver?.owner_authorized !== true ||
      waiver?.actual_session_delta !== 0 ||
      waiver?.required_session_delta !== 1 ||
      !Number.isInteger(waiver?.installed_tester_count) ||
      waiver.installed_tester_count < 1 ||
      waiver?.physical_candidate_installed !== true ||
      waiver?.physical_launch_succeeded !== true ||
      waiver?.apple_documented_latency_hours_max !== 24 ||
      waiver?.evidence_verified !== true ||
      typeof waiver?.waiver_id !== "string" ||
      waiver.waiver_id.length < 16 ||
      !/^[a-f0-9]{64}$/u.test(waiver?.waiver_record_sha256 ?? "")
    ) {
      contractIssues.push("stage 1 session-delay waiver is invalid");
    } else {
      validStage1SessionDelayWaiver = waiver;
    }
  }

  const stage = thresholds?.stages?.find(
    (candidate) => candidate.stage === snapshot?.stage,
  );
  if (!stage) contractIssues.push("snapshot stage is not defined");
  if (snapshot?.stage >= 2) {
    const policy = thresholds?.accelerated_validation_policy;
    const validation = snapshot?.validation;
    const requirement = stage?.validation;
    if (
      policy?.owner_authorized !== true ||
      policy?.app_store_connect_usage_is_gate_input !== false ||
      policy?.app_store_connect_usage_collection_required !== false ||
      policy?.strict_stage_order_remains_required !== true ||
      policy?.zero_tolerance_thresholds_remain_enforced !== true ||
      !Array.isArray(policy?.applies_to_stages) ||
      !policy.applies_to_stages.includes(snapshot.stage) ||
      !requirement
    ) {
      contractIssues.push("accelerated validation policy is invalid");
    } else {
      const profiles = Array.isArray(validation?.profiles)
        ? validation.profiles
        : [];
      const checks = Array.isArray(validation?.checks)
        ? validation.checks
        : [];
      const proofDigests = Array.isArray(validation?.proof_digests)
        ? validation.proof_digests
        : [];
      if (
        validation?.policy_id !== policy.policy_id ||
        validation?.mode !== requirement.mode ||
        validation?.status !== "passed" ||
        !isNonNegativeInteger(validation?.launches) ||
        validation.launches < requirement.minimum_launches ||
        !isNonNegativeInteger(validation?.crashes) ||
        validation.crashes > thresholds.count_thresholds.crash_count_max ||
        !requirement.required_profiles.every((profile) =>
          profiles.includes(profile)
        ) ||
        !requirement.required_checks.every((check) => checks.includes(check)) ||
        proofDigests.length === 0 ||
        proofDigests.some((digest) =>
          !/^[a-f0-9]{64}$/u.test(digest)
        ) ||
        !/^[a-f0-9]{64}$/u.test(validation?.source_sha256 ?? "") ||
        validation?.privacy?.aggregate_only !== true ||
        validation?.privacy?.device_identifiers_included !== false ||
        validation?.privacy?.user_or_account_data_included !== false ||
        validation?.privacy?.user_content_included !== false ||
        snapshot?.observation?.stability_source !==
          "device_simulator_validation" ||
        snapshot?.observation?.app_store_connect_usage_gate_input !== false
      ) {
        contractIssues.push(
          `stage ${snapshot.stage} device/simulator validation evidence is invalid`,
        );
      }
    }
  } else if (
    snapshot?.validation !== undefined &&
    snapshot.validation !== null
  ) {
    contractIssues.push("stage 1 must not use accelerated validation evidence");
  }

  const metricIssues = [];
  const analyses = requireMetric(
    snapshot?.metrics?.analyses,
    "total",
    metricIssues,
  );
  const analysisFailures = requireMetric(
    snapshot?.metrics?.analyses,
    "failed",
    metricIssues,
  );
  const wrongLanguage = requireMetric(
    snapshot?.metrics?.analyses,
    "wrong_language",
    metricIssues,
  );
  const repaired = requireMetric(
    snapshot?.metrics?.analyses,
    "repaired",
    metricIssues,
  );
  const reportRequests = requireMetric(
    snapshot?.metrics?.reports,
    "requests",
    metricIssues,
  );
  const reportFailures = requireMetric(
    snapshot?.metrics?.reports,
    "failed",
    metricIssues,
  );
  const notificationAttempts = requireMetric(
    snapshot?.metrics?.notifications,
    "attempts",
    metricIssues,
  );
  const templateMisses = requireMetric(
    snapshot?.metrics?.notifications,
    "template_misses",
    metricIssues,
  );
  const sessions = requireMetric(
    snapshot?.metrics?.stability,
    "sessions",
    metricIssues,
  );
  const crashes = requireMetric(
    snapshot?.metrics?.stability,
    "crashes",
    metricIssues,
  );
  const queueJobs = requireMetric(
    snapshot?.metrics?.queue,
    "jobs",
    metricIssues,
  );
  const retriedJobs = requireMetric(
    snapshot?.metrics?.queue,
    "retried_jobs",
    metricIssues,
  );
  const ambiguousDispatches = requireMetric(
    snapshot?.metrics?.queue,
    "ambiguous_dispatches",
    metricIssues,
  );

  for (
    const [numerator, denominator, label] of [
      [analysisFailures, analyses, "analysis failures"],
      [wrongLanguage, analyses, "wrong-language outcomes"],
      [repaired, analyses, "language repairs"],
      [reportFailures, reportRequests, "report failures"],
      [templateMisses, notificationAttempts, "template misses"],
      [retriedJobs, queueJobs, "retried queue jobs"],
    ]
  ) {
    if (numerator > denominator) {
      metricIssues.push(`${label} cannot exceed its denominator`);
    }
  }

  if (contractIssues.length > 0 || metricIssues.length > 0 || !stage) {
    return {
      status: "blocked",
      stage: snapshot?.stage ?? null,
      stage_key: stage?.key ?? null,
      contract_issues: contractIssues,
      metric_issues: metricIssues,
      insufficient_samples: [],
      threshold_violations: [],
      rates: {},
    };
  }

  const rates = {
    analysis_failure_rate: rate(analysisFailures, analyses),
    wrong_language_rate: rate(wrongLanguage, analyses),
    language_repair_rate: rate(repaired, analyses),
    report_failure_rate: rate(reportFailures, reportRequests),
    notification_template_miss_rate: rate(
      templateMisses,
      notificationAttempts,
    ),
    queue_retry_rate: rate(retriedJobs, queueJobs),
  };
  const insufficientSamples = [];
  for (
    const [actual, required, label] of [
      [analyses, stage.minimums.analyses, "analyses"],
      [
        reportRequests,
        stage.minimums.report_requests,
        "report_requests",
      ],
      [
        notificationAttempts,
        stage.minimums.notification_attempts,
        "notification_attempts",
      ],
      [sessions, stage.minimums.sessions, "sessions"],
      [queueJobs, stage.minimums.queue_jobs, "queue_jobs"],
    ]
  ) {
    if (actual < required) {
      insufficientSamples.push({ metric: label, actual, required });
    }
  }
  const appliedWaivers = [];
  const effectiveInsufficientSamples = insufficientSamples.filter((sample) => {
    const applies = sample.metric === "sessions" &&
      validStage1SessionDelayWaiver !== null &&
      sample.actual === validStage1SessionDelayWaiver.actual_session_delta &&
      sample.required ===
        validStage1SessionDelayWaiver.required_session_delta;
    if (applies) {
      appliedWaivers.push({
        waiver_id: validStage1SessionDelayWaiver.waiver_id,
        metric: "sessions",
        actual: sample.actual,
        required: sample.required,
      });
      return false;
    }
    return true;
  });

  const thresholdViolations = [];
  const rateThresholdPairs = [
    [
      "analysis_failure_rate",
      thresholds.rate_thresholds.analysis_failure_rate_max,
    ],
    [
      "wrong_language_rate",
      thresholds.rate_thresholds.wrong_language_rate_max,
    ],
    [
      "language_repair_rate",
      thresholds.rate_thresholds.language_repair_rate_max,
    ],
    [
      "report_failure_rate",
      thresholds.rate_thresholds.report_failure_rate_max,
    ],
    [
      "notification_template_miss_rate",
      thresholds.rate_thresholds.notification_template_miss_rate_max,
    ],
    [
      "queue_retry_rate",
      thresholds.rate_thresholds.queue_retry_rate_max,
    ],
  ];
  for (const [metric, maximum] of rateThresholdPairs) {
    if (rates[metric] !== null && rates[metric] > maximum) {
      thresholdViolations.push({
        metric,
        actual: rates[metric],
        maximum,
      });
    }
  }
  if (crashes > thresholds.count_thresholds.crash_count_max) {
    thresholdViolations.push({
      metric: "crash_count",
      actual: crashes,
      maximum: thresholds.count_thresholds.crash_count_max,
    });
  }
  if (
    ambiguousDispatches >
      thresholds.count_thresholds.ambiguous_dispatch_count_max
  ) {
    thresholdViolations.push({
      metric: "ambiguous_dispatch_count",
      actual: ambiguousDispatches,
      maximum: thresholds.count_thresholds.ambiguous_dispatch_count_max,
    });
  }

  return {
    status: thresholdViolations.length > 0
      ? "blocked"
      : effectiveInsufficientSamples.length > 0
      ? "hold"
      : "passed",
    stage: snapshot.stage,
    stage_key: stage.key,
    contract_issues: [],
    metric_issues: [],
    insufficient_samples: effectiveInsufficientSamples,
    threshold_violations: thresholdViolations,
    rates,
    applied_waivers: appliedWaivers,
  };
}

function parseArguments(argv) {
  const values = { thresholds: DEFAULT_THRESHOLDS, snapshot: null };
  for (const argument of argv) {
    if (argument.startsWith("--thresholds=")) {
      values.thresholds = argument.slice("--thresholds=".length);
    } else if (argument.startsWith("--snapshot=")) {
      values.snapshot = argument.slice("--snapshot=".length);
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  if (!values.snapshot) throw new Error("--snapshot is required");
  return values;
}

function main() {
  const paths = parseArguments(process.argv.slice(2));
  const thresholds = JSON.parse(readFileSync(paths.thresholds, "utf8"));
  const snapshot = JSON.parse(readFileSync(paths.snapshot, "utf8"));
  const result = evaluateRolloutGate(thresholds, snapshot);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exitCode = result.status === "passed"
    ? 0
    : result.status === "hold"
    ? 3
    : 2;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}
