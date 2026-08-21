import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const workerSource = await Deno.readTextFile(
  new URL("../process-analysis-jobs/index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260821132715_ai_finding_coverage_quality_v2_shadow.sql",
    import.meta.url,
  ),
);
const copySource = await Deno.readTextFile(
  new URL("../_shared/user-facing-copy.ts", import.meta.url),
);

Deno.test("coverage quality v2 starts shadowed behind the generic policy gate", () => {
  assertStringIncludes(analyzeSource, '"ai_finding_coverage_quality_v2"');
  assertStringIncludes(analyzeSource, "COVERAGE_QUALITY_POLICY_VERSION");
  assertStringIncludes(migrationSource, "'policy_version', 2");
  assertStringIncludes(migrationSource, "'rollout_mode', 'shadow'");
  assertStringIncludes(migrationSource, "'kill_switch', false");
  assertStringIncludes(migrationSource, "on conflict (key) do nothing");
});

Deno.test("coverage quality reuses the existing repair queue and targets only selected photos", () => {
  assertStringIncludes(analyzeSource, 'job_mode: "repair"');
  assertStringIncludes(analyzeSource, "repair_kind: params.repairKind");
  assertStringIncludes(
    analyzeSource,
    "repair_photo_indices: params.repairPhotoIndices",
  );
  assertStringIncludes(analyzeSource, '"transition_analysis_to_repair_v2"');
  assertStringIncludes(analyzeSource, 'jobMode === "analysis" &&');
  assertStringIncludes(analyzeSource, "qualityRepairCandidates");
});

Deno.test("coverage quality has one pinned request and no nested language repair", () => {
  assertStringIncludes(analyzeSource, "callPinnedCoverageQualityRepair");
  assertStringIncludes(analyzeSource, "maxProviderRequests: 1");
  assertStringIncludes(analyzeSource, "COVERAGE_QUALITY_REPAIR_TIMEOUT_MS");
  assertStringIncludes(
    analyzeSource,
    "COVERAGE_QUALITY_VALIDATION_FAILED_NO_SECOND_REPAIR",
  );
  assertStringIncludes(analyzeSource, "model_generation_pass_count");
  assertStringIncludes(analyzeSource, "provider_request_count_total");
  assertStringIncludes(workerSource, "forceCoverageQualityFallback");
  assertStringIncludes(workerSource, "__queue_read_count");
  assertStringIncludes(analyzeSource, "coverageQualityFallbackAttemptState");
});

Deno.test("all repair validation failures fail open to the previous valid output", () => {
  const catchGate = analyzeSource.indexOf(
    'if (\n        jobMode === "repair" &&\n        previousCoverageRecords',
  );
  assert(catchGate > 0);
  const preceding = analyzeSource.slice(
    Math.max(0, catchGate - 160),
    catchGate,
  );
  assertEquals(preceding.includes("OutputLanguageContractError"), false);
  assertStringIncludes(
    analyzeSource,
    'coverage_quality_status = "failed_open"',
  );
  assertStringIncludes(analyzeSource, '"deadline_skipped"');
  assertStringIncludes(analyzeSource, "coverageQualityDeadlineExpired");
  assertStringIncludes(
    analyzeSource,
    "COVERAGE_QUALITY_SCHEMA_CONTRACT_FAILED",
  );
  assertStringIncludes(
    analyzeSource,
    'localizationSnapshot.source === "explicit_request" ||\n        isCoverageQualityRepair',
  );
});

Deno.test("quality repair preserves prior findings and validates additions against prior layers", () => {
  assertStringIncludes(
    analyzeSource,
    "applyInspectionLayerEvidenceGuard(\n        repair.findings",
  );
  assertStringIncludes(analyzeSource, "duplicateRejectedCount += 1");
  assertStringIncludes(analyzeSource, "unsupportedRejectedCount += 1");
  assertStringIncludes(analyzeSource, "if (!options.coverageQualityV2)");
  assertStringIncludes(analyzeSource, "no_additional_reason_code");
  assertStringIncludes(analyzeSource, "remainingTotalBudget");
  assertStringIncludes(analyzeSource, "qualityComparisonFindings");
  assertStringIncludes(
    analyzeSource,
    "isCoverageRepairSubfindingAlreadyCovered(existing, finding)",
  );
  assertStringIncludes(
    analyzeSource,
    "photo_findings: coverageRecords.map",
  );
});

Deno.test("quality repair carries queue and end-to-end latency telemetry", () => {
  assertStringIncludes(analyzeSource, "quality_repair_enqueued_at");
  assertStringIncludes(analyzeSource, "quality_repair_queue_delay_ms");
  assertStringIncludes(analyzeSource, "initial_analysis_duration_ms");
  assertStringIncludes(analyzeSource, "total_analysis_duration_ms");
  assertStringIncludes(analyzeSource, "COVERAGE_QUALITY_REPAIR_DEADLINE_MS");
});

Deno.test("quality reason copy is centralized and paired", () => {
  for (
    const key of [
      "analysisQualityNoDistinctAdditionalHazard",
      "analysisQualityInsufficientVisualEvidence",
      "analysisQualityExistingFindingsCoverScene",
    ]
  ) {
    assertStringIncludes(copySource, key);
    assertStringIncludes(analyzeSource, key);
  }
});

Deno.test("Turkish and English focus blocks remain singular and separate", () => {
  assertEquals((analyzeSource.match(/<odak>/g) ?? []).length, 1);
  assertEquals((analyzeSource.match(/<\/odak>/g) ?? []).length, 1);
  assertEquals((analyzeSource.match(/<focus>/g) ?? []).length, 1);
  assertEquals((analyzeSource.match(/<\/focus>/g) ?? []).length, 1);
});
