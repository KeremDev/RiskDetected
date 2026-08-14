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
