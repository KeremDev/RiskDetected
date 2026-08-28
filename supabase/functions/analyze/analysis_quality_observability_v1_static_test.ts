import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const traceSource = await Deno.readTextFile(
  new URL("./analysis-quality-trace.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260823120000_analysis_quality_observability_v1.sql",
    import.meta.url,
  ),
);

Deno.test("quality observability is stored beside the input audit", () => {
  assertStringIncludes(analyzeSource, "_quality_trace_v1: finalQualityTrace");
  assertStringIncludes(
    analyzeSource,
    "_quality_trace_v1: intermediateQualityTrace",
  );
  assertStringIncludes(traceSource, 'trace_mode: "full_trace"');
  assertStringIncludes(traceSource, "delta_from_previous");
  assertStringIncludes(traceSource, "finding_trace_ids");
});

Deno.test("required rejection and score mutation reason codes are explicit", () => {
  for (
    const reason of [
      "invalid_record",
      "finding_budget_exceeded",
      "duplicate_exact",
      "duplicate_fuzzy",
      "evidence_unlinked",
      "evidence_non_actionable",
      "process_link_invalid",
      "contextual_ppe_rejected",
      "repair_duplicate",
      "repair_unsupported",
      "final_limit_applied",
      "fk_value_clamped_to_allowed_scale",
      "fk_frequency_missing_fallback",
      "height_fatality_minimum_severity",
      "m5_value_clamped",
      "verification_derived_from_confidence",
      "reference_removed_by_plan",
      "reference_removed_by_safety_profile",
    ]
  ) {
    assertStringIncludes(traceSource + analyzeSource, reason);
  }
});

Deno.test("instrumentation remains fail-open", () => {
  assertStringIncludes(analyzeSource, "Quality trace build failed open");
  assertStringIncludes(analyzeSource, 'trace_mode: "trace_error"');
  assertStringIncludes(
    analyzeSource,
    'error_code: "quality_trace_build_failed"',
  );
});

Deno.test("phase one leaves finding-pressure constants and flag cable unchanged", () => {
  assertStringIncludes(analyzeSource, "const SINGLE_PHOTO_TARGET_MIN = 1;");
  assertStringIncludes(analyzeSource, "const MULTI_PHOTO_TARGET_MIN = 1;");
  const policyStart = analyzeSource.indexOf("function coveragePolicyFor(");
  const policyEnd = analyzeSource.indexOf(
    "function normalizeCoverageStatus",
    policyStart,
  );
  const policySource = analyzeSource.slice(policyStart, policyEnd);
  assertEquals(
    policySource.includes("capabilities.targetFindingsPerPhotoMin"),
    false,
  );
});

Deno.test("admin quality RPC and alarm contracts are service role only", () => {
  assertStringIncludes(
    migrationSource,
    "public.admin_analysis_quality_run_v1",
  );
  assertStringIncludes(
    migrationSource,
    "public.admin_analysis_quality_metrics_v1",
  );
  assertStringIncludes(migrationSource, "legacy_aggregate");
  assertStringIncludes(migrationSource, "insufficient_sample");
  assertStringIncludes(migrationSource, "'15 3 * * *'");
  assertStringIncludes(migrationSource, "to service_role");
  assertStringIncludes(migrationSource, "from public, anon, authenticated");
});
