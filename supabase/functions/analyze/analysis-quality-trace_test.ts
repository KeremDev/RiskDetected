import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  AnalysisQualityTraceCollector,
  assignQualityTraceIDs,
  buildQualityScoreMutationTrace,
  mergeQualityTraceIDs,
  qualityTraceIDs,
} from "./analysis-quality-trace.ts";

function finding(
  title: string,
  photoIndex: number,
): Record<string, unknown> {
  return {
    title,
    source_photo_indices: [photoIndex],
    fk_probability: 3,
    fk_frequency: 2,
    fk_severity: 15,
    m5_probability: 3,
    m5_severity: 3,
    confidence: 0.8,
  };
}

Deno.test("internal finding trace ids never change serialized finding JSON", () => {
  const frozenOutput = finding("Açık kenar", 1);
  const before = JSON.stringify(frozenOutput);

  assignQualityTraceIDs(frozenOutput, ["i:p1:f1:r1"]);
  const copied = { ...frozenOutput };

  assertEquals(JSON.stringify(frozenOutput), before);
  assertEquals(JSON.stringify(copied), before);
  assertEquals(qualityTraceIDs(copied), ["i:p1:f1:r1"]);
});

Deno.test("merged findings preserve both lineage ids without copying text into trace", () => {
  const first = assignQualityTraceIDs(finding("A", 1), ["i:p1:f1:r1"]);
  const second = assignQualityTraceIDs(finding("B", 1), ["i:p1:f2:r1"]);
  const merged = mergeQualityTraceIDs({ ...first }, first, second);

  assertEquals(qualityTraceIDs(merged), ["i:p1:f1:r1", "i:p1:f2:r1"]);
});

Deno.test("quality trace records stages deltas reason codes and score mutations", () => {
  const providerFinding = finding("Korumasız çalışma", 1);
  const response = {
    photo_findings: [{ photo_index: 1, findings: [providerFinding] }],
  };
  const collector = new AnalysisQualityTraceCollector(1, "analysis");
  collector.observeProviderResponse(response);
  collector.capture("normalization", [providerFinding]);
  collector.capture("evidence_process_guard", [providerFinding]);
  collector.capture("finding_budget", [providerFinding]);
  collector.capture("dedup", [providerFinding]);
  collector.capture("first_pass_final_candidates", [providerFinding]);
  collector.addScoreTrace({
    finding_trace_id: qualityTraceIDs(providerFinding)[0],
    source_photo_indices: [1],
    lineage_trace_ids: qualityTraceIDs(providerFinding),
    model_raw: {
      fk_probability: 3,
      fk_frequency: null,
      fk_severity: 15,
      m5_probability: 3,
      m5_severity: 3,
      confidence: 0.8,
      needs_field_verification: true,
    },
    server_final: {
      fk_probability: 3,
      fk_frequency: 0.5,
      fk_severity: 40,
      m5_probability: 3,
      m5_severity: 5,
      confidence: 0.8,
      needs_field_verification: false,
    },
    mutations: [
      {
        field: "fk_frequency",
        before: null,
        after: 0.5,
        reason_code: "fk_frequency_missing_fallback",
      },
    ],
  });

  const trace = collector.build({
    promptVersion: "v1",
    policyVersion: "policy-v1",
    model: "fixture-model",
    provider: "fixture-provider",
    plan: "plus",
    outputLanguage: "tr",
    schemaFallbackUsed: false,
    repairCandidatePhotoIndices: [],
    repairAddedCount: 0,
    repairCalled: false,
    persistenceFindings: [providerFinding],
    totalDurationMs: 1250,
    providerRequestCount: 1,
    tokens: { input: 10, output: 20, cached: 0, thoughts: 0, total: 30 },
  });

  assertEquals(trace.version, 1);
  assertEquals(trace.trace_mode, "full_trace");
  const summary = trace.summary as Record<string, unknown>;
  assertEquals(summary.raw_findings, 1);
  assertEquals(summary.final_findings, 1);
  assertEquals(summary.raw_to_final_retention, 1);
  const scoreTraces = trace.score_traces as Array<Record<string, unknown>>;
  assertEquals(scoreTraces.length, 1);
  assertEquals(
    (scoreTraces[0].mutations as Array<Record<string, unknown>>)[0].reason_code,
    "fk_frequency_missing_fallback",
  );
  assertEquals(JSON.stringify(trace).includes("Korumasız çalışma"), false);
});

Deno.test("repair trace keeps initial pass telemetry instead of overwriting it", () => {
  const first = finding("İlk bulgu", 1);
  const initial = new AnalysisQualityTraceCollector(1, "analysis");
  initial.observeProviderResponse({
    photo_findings: [{ photo_index: 1, findings: [first] }],
  });
  initial.capture("first_pass_final_candidates", [first]);
  const pending = initial.build({
    lifecycleState: "repair_pending",
    promptVersion: "v1",
    policyVersion: "policy-v1",
    model: "fixture-model",
    provider: "fixture-provider",
    plan: "plus",
    outputLanguage: "tr",
    schemaFallbackUsed: false,
    repairCandidatePhotoIndices: [1],
    repairAddedCount: 0,
    repairCalled: false,
    persistenceFindings: [],
    totalDurationMs: 100,
    providerRequestCount: 1,
    tokens: { input: 1, output: 1, cached: 0, thoughts: 0, total: 2 },
  });

  const repairFinding = finding("Ek bulgu", 1);
  const repair = new AnalysisQualityTraceCollector(1, "repair", pending);
  repair.observeProviderResponse({
    photo_findings: [{ photo_index: 1, findings: [repairFinding] }],
  });
  repair.capture("repair_merged", [first, repairFinding]);
  const completed = repair.build({
    promptVersion: "v1",
    policyVersion: "policy-v1",
    model: "fixture-model",
    provider: "fixture-provider",
    plan: "plus",
    outputLanguage: "tr",
    schemaFallbackUsed: false,
    repairCandidatePhotoIndices: [1],
    repairAddedCount: 1,
    repairCalled: true,
    persistenceFindings: [first, repairFinding],
    totalDurationMs: 200,
    providerRequestCount: 2,
    tokens: { input: 2, output: 2, cached: 0, thoughts: 0, total: 4 },
  });
  const stages = completed.stages as Array<Record<string, unknown>>;

  assertExists(stages.find((stage) => stage.name === "provider_parsed"));
  assertExists(stages.find((stage) => stage.name === "repair_provider_parsed"));
  assertEquals(
    stages.find((stage) => stage.name === "first_pass_final_candidates")
      ?.total,
    1,
  );
  assertEquals(
    stages.find((stage) => stage.name === "database_final")?.total,
    2,
  );
});

Deno.test("repair restores deterministic first-pass ids after JSON persistence", () => {
  const persisted = JSON.parse(JSON.stringify({
    photo_findings: [{
      photo_index: 1,
      findings: [finding("Persisted first-pass finding", 1)],
    }],
    _quality_trace_v1: {
      version: 1,
      trace_mode: "full_trace",
      stages: [],
      rejections: [],
      score_traces: [],
    },
  }));
  const collector = new AnalysisQualityTraceCollector(
    1,
    "repair",
    persisted._quality_trace_v1,
  );

  collector.restoreInitialProviderTraceIDs(persisted);

  assertEquals(
    qualityTraceIDs(persisted.photo_findings[0].findings[0]),
    ["i:p1:f1:r1"],
  );
});

Deno.test("score ledger distinguishes F fallback clamp and server derivations", () => {
  const ledger = buildQualityScoreMutationTrace(
    {
      fk_probability: 2.8,
      fk_frequency: "invalid",
      fk_severity: 15,
      m5_probability: 3.4,
      m5_severity: 3,
      confidence: 0.8,
      needs_field_verification: true,
      references: "6331",
    },
    {
      fkP: 3,
      fkF: 0.5,
      fkS: 40,
      m5P: 3,
      m5S: 5,
      confidence: 0.8,
      needsFieldVerification: false,
    },
    "reference_removed_by_plan",
  );
  const reasons = ledger.mutations.map((mutation) => mutation.reason_code);

  assertEquals(ledger.modelRaw.fk_frequency, null);
  assertEquals(ledger.serverFinal.fk_frequency, 0.5);
  assertEquals(reasons.includes("fk_frequency_missing_fallback"), true);
  assertEquals(reasons.includes("fk_value_clamped_to_allowed_scale"), true);
  assertEquals(reasons.includes("height_fatality_minimum_severity"), true);
  assertEquals(reasons.includes("m5_value_clamped"), true);
  assertEquals(reasons.includes("verification_derived_from_confidence"), true);
  assertEquals(reasons.includes("reference_removed_by_plan"), true);
});
