import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const trackerSource = await Deno.readTextFile(
  new URL("./provider-attempt-tracker.ts", import.meta.url),
);
const analysisServiceSource = await Deno.readTextFile(
  new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
);
const appErrorSource = await Deno.readTextFile(
  new URL("../../../App/Services/AppErrorMessage.swift", import.meta.url),
);
const geminiProviderClientSource = await Deno.readTextFile(
  new URL("../_shared/gemini-provider-client.ts", import.meta.url),
);
const photoSourceIndicesSource = await Deno.readTextFile(
  new URL("../_shared/photo-source-indices.ts", import.meta.url),
);
const findingConfidenceSource = await Deno.readTextFile(
  new URL("../_shared/finding-confidence.ts", import.meta.url),
);

function sourceBetween(start: string, end: string): string {
  const startIndex = indexSource.indexOf(start);
  const endIndex = indexSource.indexOf(end, startIndex + start.length);
  assert(startIndex >= 0, `Missing start marker: ${start}`);
  assert(endIndex > startIndex, `Missing end marker: ${end}`);
  return indexSource.slice(startIndex, endIndex);
}

Deno.test("Phase 4 validates output before usage success and persistence", () => {
  const providerBlock = sourceBetween(
    "const out = await callAIForAnalysis(",
    "} catch (err) {",
  );
  const validationIndex = providerBlock.indexOf(
    "validateAIOutputWithSingleRepair",
  );
  assert(validationIndex >= 0);
  assert(
    validationIndex < providerBlock.indexOf(
      "successUsageLogID = await logUsage",
    ),
  );
  assert(
    validationIndex < indexSource.indexOf("const findingRows = hazards.map"),
  );
});

Deno.test("AI-001 Turkish baseline is preserved byte-for-byte for legacy snapshots", () => {
  const promptBlock = sourceBetween(
    "function buildSystemPrompt(",
    "function layerAuditPromptRule(",
  );
  assertStringIncludes(promptBlock, 'snapshot.source === "legacy_tr_default"');
  assertStringIncludes(promptBlock, 'snapshot.source === "legacy_tr_backfill"');
  assertStringIncludes(promptBlock, "CORE_ANALYSIS_PROMPT");
  assertStringIncludes(promptBlock, 'layerIDs: ["legacy_turkish_prompt"]');
  assertStringIncludes(promptBlock, "buildAILocalizationPromptContract(snapshot)");
  assertEquals(
    promptBlock.includes("[contract.prompt, legacyTurkishEvidenceBaseline]"),
    false,
  );
});

Deno.test("AI-016 and AI-017 preserve plan limits and exact photo coverage", () => {
  const turkishScope = sourceBetween(
    "function buildSubscriptionContext(",
    "// localization-inventory: machine-prompt-begin",
  );
  const englishScope = sourceBetween(
    "function buildEnglishSubscriptionContext(",
    "// localization-inventory: machine-prompt-end",
  );
  for (const block of [turkishScope, englishScope]) {
    assertStringIncludes(block, "PLAN_LIMITS[tier].minHazards");
    assertStringIncludes(block, "PLAN_LIMITS[tier].maxHazards");
    assertStringIncludes(block, "findingPolicy.maxFindingsTotal");
    assertStringIncludes(block, "findingPolicy.targetFindingsPerPhotoMax");
  }
  assertStringIncludes(indexSource, "expectedPhotoIndices");
  assertStringIncludes(indexSource, "inspectPhotoCoverageContract(");
});

Deno.test("language repair is one direct call on the same provider, model and key", () => {
  const repairBlock = sourceBetween(
    "const callSameProviderLanguageRepair = async",
    "const effectiveRepairPhotoIndices",
  );
  assertStringIncludes(
    repairBlock,
    'providerAttemptReason: "language_contract_repair"',
  );
  assertStringIncludes(repairBlock, "params.model");
  assertStringIncludes(repairBlock, "item.alias === params.apiKeyAlias");
  assertStringIncludes(repairBlock, "callGemini(");
  assertStringIncludes(repairBlock, "callGroq(");
  assertEquals(repairBlock.includes("callAIForAnalysis("), false);
  assertEquals(repairBlock.includes("reserveAnalysisQuota"), false);
  assertEquals(repairBlock.includes("consume"), false);
  assertStringIncludes(
    trackerSource,
    '| "language_contract_repair"',
  );
  assertStringIncludes(repairBlock, "...params.options");
  assertEquals(repairBlock.includes("outputLanguage:"), false);
  assertStringIncludes(
    indexSource,
    "outputLanguage: localizationSnapshot.output_language",
  );
});

Deno.test("AI-019 retries preserve the same prompt, context and output-language options", () => {
  const retryBlock = sourceBetween(
    "async function callGeminiWithFallback(",
    "async function callAIWithFreeProviderPool(",
  );
  assertStringIncludes(
    retryBlock,
    "systemPrompt,\n        analysisContext,\n        userText,\n        imageBase64Parts",
  );
  assertStringIncludes(retryBlock, "...options");
  assertEquals(retryBlock.includes("outputLanguage:"), false);
});

Deno.test("production analyze and live canary share one Gemini transport", () => {
  assertStringIncludes(indexSource, "sendGeminiGenerateContent({");
  assertStringIncludes(
    geminiProviderClientSource,
    '"x-goog-api-key": request.apiKey',
  );
  assertStringIncludes(geminiProviderClientSource, "fetchWithDeadline(");
  assertEquals(indexSource.includes(":generateContent?key="), false);
});

Deno.test("production analyze and live canary share source-photo normalization", () => {
  assertStringIncludes(
    indexSource,
    'from "../_shared/photo-source-indices.ts"',
  );
  assertStringIncludes(
    photoSourceIndicesSource,
    "export function normalizeSourcePhotoIndices(",
  );
  assertEquals(
    indexSource.includes("function normalizeSourcePhotoIndices("),
    false,
  );
});

Deno.test("production analyze and live canary share confidence normalization", () => {
  assertStringIncludes(
    indexSource,
    'from "../_shared/finding-confidence.ts"',
  );
  assertStringIncludes(
    findingConfidenceSource,
    "export function productionFindingNeedsFieldVerification(",
  );
  assertEquals(indexSource.includes("function hazardConfidence("), false);
});

Deno.test("AI-020 provider fallbacks preserve the same locale-bound request", () => {
  const freeBlock = sourceBetween(
    "async function callAIWithFreeProviderPool(",
    "async function callPaidAIWithFallback(",
  );
  const paidBlock = sourceBetween(
    "async function callPaidAIWithFallback(",
    "async function callFreePaidTrialAIWithFallback(",
  );
  const trialBlock = sourceBetween(
    "async function callFreePaidTrialAIWithFallback(",
    "function newSupportID(",
  );
  for (const block of [freeBlock, paidBlock, trialBlock]) {
    assertStringIncludes(block, "systemPrompt");
    assertStringIncludes(block, "analysisContext");
    assertStringIncludes(block, "...options");
    assertStringIncludes(block, 'providerAttemptReason: "provider_fallback"');
    assertEquals(block.includes("outputLanguage:"), false);
  }
});

Deno.test("failed language repair is fail closed and cannot enter coverage fallback", () => {
  assertStringIncludes(
    indexSource,
    "!(err instanceof OutputLanguageContractError)",
  );
  assertStringIncludes(
    indexSource,
    "code: err.code",
  );
  assertStringIncludes(
    indexSource,
    "language_validation_status: languageValidationStatus",
  );
  assertStringIncludes(
    indexSource,
    "language_validation_attempts: languageValidationAttempts",
  );
  const clientGuardIndex = analysisServiceSource.indexOf(
    'if errorCode == "OUTPUT_LANGUAGE_CONTRACT_FAILED"',
  );
  const genericRetryIndex = analysisServiceSource.indexOf(
    "let retryable = [429, 500, 502, 503, 504].contains(code)",
    clientGuardIndex,
  );
  assert(clientGuardIndex >= 0);
  assert(genericRetryIndex > clientGuardIndex);
  assertStringIncludes(
    appErrorSource,
    'lower.contains("output_language_contract_failed")',
  );
  assertStringIncludes(
    appErrorSource,
    '"analysis.analysis.service.output.language.contract.failed"',
  );
});

Deno.test("cancelled Plus trial route and quota path remain unchanged by repair", () => {
  const routeBlock = sourceBetween(
    "const callAIForAnalysis = async",
    "const providerOutputTier",
  );
  assertStringIncludes(
    routeBlock,
    "usesFreeGeminiProviderPool(aiExecutionRoute)",
  );
  assertStringIncludes(routeBlock, "CANCELLED_PLUS_TRIAL_ROUTE ? planTier :");
  assertEquals(routeBlock.includes("languageContractRepair"), false);

  const repairBlock = sourceBetween(
    "const callSameProviderLanguageRepair = async",
    "const effectiveRepairPhotoIndices",
  );
  assertEquals(repairBlock.includes("releaseAnalysisQuota"), false);
  assertEquals(repairBlock.includes("completeAnalysisQuota"), false);
  assertEquals(repairBlock.includes("reserve_analysis_quota"), false);
});

Deno.test("AI audit stores contract metadata, not prompts or user-authored values", () => {
  for (
    const forbidden of [
      "system_prompt_sent",
      "analysis_context_sent",
      "company_name_sent",
      "company_context_sent",
      "onboarding_context_sent",
      "user_prompt_sent",
    ]
  ) {
    assertEquals(indexSource.includes(forbidden), false, forbidden);
  }
  assertStringIncludes(indexSource, "prompt_contract_hash: systemPromptHash");
  assertStringIncludes(
    indexSource,
    "prompt_layer_ids: systemPromptContract.contract.layerIDs",
  );
  assertStringIncludes(
    indexSource,
    "allowedUserAuthoredValues: company?.name ? [company.name] : []",
  );
  const providerFailureBlock = sourceBetween(
    "} catch (err) {\n      aiError =",
    'if (\n        jobMode === "repair"',
  );
  assertStringIncludes(
    providerFailureBlock,
    "JSON.stringify(safeLogError(err))",
  );
  assertEquals(providerFailureBlock.includes("String(err)"), false);
  assertEquals(providerFailureBlock.includes("err.body"), false);
});

Deno.test("non-TR references and English generated fallback copy are gated", () => {
  assertStringIncludes(
    indexSource,
    "localizationSnapshot.structured_regulatory_references_enabled",
  );
  assertStringIncludes(indexSource, "safetyProfile.corrective_action_term");
  assertStringIncludes(indexSource, "safetyProfile.control_term");
  assertStringIncludes(indexSource, "localizationSnapshot.output_language");
});
