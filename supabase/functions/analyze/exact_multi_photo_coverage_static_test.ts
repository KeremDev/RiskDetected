import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("exact coverage schema constrains record count and photo indices", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "let exactCoverageSchemaEnabled");
  assertStringIncludes(source, "minItems: exactCoverage.minItems");
  assertStringIncludes(source, "maxItems: exactCoverage.maxItems");
  assertStringIncludes(source, "? { enum: exactCoverage.photoIndexEnum }");
  assertStringIncludes(
    source,
    "coverageSchemaVersion: exactCoverageSchemaEnabled",
  );
  assertStringIncludes(
    source,
    'nextAttemptReason = "layer_schema_fallback"',
  );
});

Deno.test("coverage schema fallback requires an explicit response schema error", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const helper = source.indexOf("function isExplicitGeminiResponseSchemaError");
  const gemini = source.indexOf("async function callGemini", helper);
  const branch = source.slice(
    gemini,
    source.indexOf("function decodedBase64ByteLength", gemini),
  );
  assert(helper > 0 && gemini > helper);
  assertStringIncludes(
    branch,
    "exactCoverageSchemaEnabled && explicitSchemaError",
  );
  assertStringIncludes(branch, "!coverageSchemaFallbackUsed");
  assertEquals(
    branch.includes("exactCoverageSchemaEnabled && res.status === 400"),
    false,
  );
});

Deno.test("queue snapshots trusted coverage version and repair preserves it", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const submit = source.slice(
    source.indexOf("async function enqueueAnalysisJob"),
    source.indexOf("async function enqueueCoverageRepairJob"),
  );
  const repair = source.slice(
    source.indexOf("async function enqueueCoverageRepairJob"),
    source.indexOf("async function triggerAnalysisWorker"),
  );
  assert(
    submit.indexOf("...params.body") <
      submit.indexOf("coverage_schema_version: params.coverageSchemaVersion"),
  );
  assertStringIncludes(
    repair,
    "coverage_schema_version: params.coverageSchemaVersion",
  );
  assertStringIncludes(
    source,
    "queuedCoverageSchemaVersion === 2 && !exactCoverageSchemaFlag.killSwitch",
  );
});

Deno.test("duplicate photo records merge and do not alone trigger repair", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "function mergeDuplicateCoverageRecord");
  assertStringIncludes(source, "mergeDuplicateCoverageFinding(");
  assertStringIncludes(
    source,
    "existingRecord\n        ? mergeDuplicateCoverageRecord(",
  );
  assertStringIncludes(source, "coverageRecordRequiresRepair({");
  assertStringIncludes(source, "coverageStatus: record.coverage_status");
});

Deno.test("repair remains single-generation and claim guarded", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const repairGate = source.indexOf('jobMode === "analysis" &&');
  const enqueue = source.indexOf(
    "await enqueueCoverageRepairJob({",
    repairGate,
  );
  assert(repairGate > 0 && enqueue > repairGate);
  assertStringIncludes(source, '"transition_analysis_to_repair_v2"');
  assertStringIncludes(source, 'repair_contract: jobMode === "repair"');
  assertStringIncludes(source, 'initial_contract: jobMode === "repair"');
});

Deno.test("physical request telemetry stays aggregate-safe", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const tracker = await readTextIfAllowed(
    new URL("./provider-attempt-tracker.ts", import.meta.url),
  );
  if (source == null || tracker == null) return;

  assertStringIncludes(
    source,
    "provider_request_count: providerAttemptTracker.requestCount",
  );
  assertStringIncludes(
    source,
    "provider_attempt_total_tokens: providerAttemptTracker.totalTokens",
  );
  assertStringIncludes(
    source,
    "provider_attempts: providerAttemptTracker.snapshot()",
  );
  assertStringIncludes(
    tracker,
    "if (this.#attempts.length >= MAX_PROVIDER_ATTEMPTS) return",
  );
  assertEquals(tracker.includes("prompt"), false);
  assertEquals(tracker.includes("response_body"), false);
  assertEquals(tracker.includes("api_key:"), false);
});

Deno.test("cancelled trial and paid provider isolation branches remain intact", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  const freeStart = source.indexOf(
    "if (usesFreeGeminiProviderPool(aiExecutionRoute))",
  );
  const trialStart = source.indexOf(
    'if (aiExecutionRoute === "free_paid_trial")',
    freeStart,
  );
  const paidStart = source.indexOf(
    "return await callPaidAIWithFallback",
    trialStart,
  );
  assert(freeStart > 0 && trialStart > freeStart && paidStart > trialStart);
  assertEquals(
    source.slice(freeStart, trialStart).includes("callPaidAIWithFallback"),
    false,
  );
  assertStringIncludes(
    source.slice(trialStart, paidStart),
    "callFreePaidTrialAIWithFallback",
  );
});

Deno.test("multi-photo strict schema drops the nested exact layer bounds", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  // Gemini rejected the strict multi-photo schema with 400 "too many states
  // for serving" on three of five runs, and the retry dropped the exact
  // coverage bounds too. The cost is `photo_findings` pinned to exactly N
  // items each carrying `inspection_layers` pinned to exactly twelve. Only
  // multi-photo requests have the outer bound, so only they lose the inner one.
  assertStringIncludes(
    source,
    "const exactLayerBoundsEnabled = layerAuditEnabled && !exactCoverage.enabled;",
  );
  assertStringIncludes(
    source,
    "relaxedLayerAuditSchema || !exactLayerBoundsEnabled\n                      ? {}\n                      : { minItems: 12, maxItems: 12 }",
  );

  // The outer coverage bounds are cheap and are what guarantee one record per
  // photo, so they stay.
  assertStringIncludes(source, "minItems: exactCoverage.minItems");
  assertStringIncludes(source, "? { enum: exactCoverage.photoIndexEnum }");

  // The twelve-layer contract has to keep being stated somewhere, or dropping
  // the schema bound silently drops the requirement.
  assertStringIncludes(source, "12 katman tamamlanmadan yanıtı bitirme");
});

Deno.test("budget telemetry records the pass that did the work", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  // recordRepairPassBudgets used to run only on the two failure paths, so the
  // success path overwrote thinking_budget with the repair's hard-coded 1024
  // and every completed multi-photo analysis reported 1024 with
  // repair_thinking_budget null. The provider-response path routes through the
  // same helper now.
  assertStringIncludes(
    source,
    '      recordPassBudgets(\n        inputAudit,\n        previousInputAudit,\n        jobMode === "repair",\n        out.thinkingBudget,\n        out.maxOutputTokens,\n      );',
  );
  assert(!source.includes("inputAudit.thinking_budget = out.thinkingBudget"));
  assert(
    !source.includes("inputAudit.max_output_tokens = out.maxOutputTokens"),
  );
  assertStringIncludes(
    source,
    "audit.repair_thinking_budget = thinkingBudget;",
  );
});
