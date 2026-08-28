import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") {
    console.warn(
      `Skipping static source assertion; rerun with --allow-read=${path}`,
    );
    return null;
  }
  return await Deno.readTextFile(path);
}

Deno.test("iOS photo compression keeps balanced quality floor", async () => {
  const source = await readTextIfAllowed(
    new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "balanced-v3-1536-floor1024");
  assertStringIncludes(source, ".init(maxDimension: 1536, jpegQuality: 0.78)");
  assertStringIncludes(source, ".init(maxDimension: 1024, jpegQuality: 0.52)");
  assertStringIncludes(source, "decodedByteCount: data.count");
  assertStringIncludes(source, "qualityPolicy: analysisPhotoQualityPolicy");
  assertStringIncludes(source, 'storage_strategy: "client-storage-paths-v1"');
  assert(!source.includes(".init(maxDimension: 1000"));
  assert(!source.includes(".init(maxDimension: 900"));
  assert(!source.includes(".init(maxDimension: 800"));
});

Deno.test("iOS sends dynamic build metadata without hardcoded build gate", async () => {
  const source = await readTextIfAllowed(
    new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "enum AppClientMetadata");
  assertStringIncludes(
    source,
    'object(forInfoDictionaryKey: "CFBundleVersion")',
  );
  assertStringIncludes(source, "static let apiContractVersion = 3");
  assertStringIncludes(source, '"safety_claim_v4_scoreless": true');
  assertStringIncludes(source, "let client_app_build: String");
  assertStringIncludes(source, "let api_contract_version: Int");
  assert(!source.includes("build == 63"));
  assert(!source.includes('build == "63"'));
});

Deno.test("iOS remote capability resolver applies release gate", async () => {
  const source = await readTextIfAllowed(
    new URL("../../../App/AppState.swift", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "isReleaseGateOpenForCurrentBuild");
  assertStringIncludes(source, 'case "build_allowlist"');
  assertStringIncludes(source, "minIOSBuild.map { buildNumber >= $0 } == true");
  assertStringIncludes(source, 'case "min_build"');
  assertStringIncludes(source, "flags.effectiveEnableMultiPhotoAnalysis");
  assertStringIncludes(source, "flags.effectiveEnableEditableFindings");
});

Deno.test("AI payload labels every image before the image part", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "function imagePartMarkerText(",
  );
  assertStringIncludes(source, 'outputLanguage: "tr" | "en" = "tr"');
  assertStringIncludes(source, 'label="FOTO_${part.photoIndex}"');
  assertStringIncludes(source, 'label="PHOTO_${part.photoIndex}"');
  assertStringIncludes(
    source,
    "Bu marker yalnızca makine-okunur kaynak eşleştirme içindir",
  );
  assertStringIncludes(
    source,
    "Kullanıcıya gösterilecek title, observed_evidence, description",
  );
  assertStringIncludes(
    source,
    'text: imagePartMarkerText(img, options.outputLanguage ?? "tr")',
  );
  assertStringIncludes(
    source,
    "parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });",
  );
  assertStringIncludes(
    source,
    'text: imagePartMarkerText(img, options.outputLanguage ?? "tr"),',
  );
  assertStringIncludes(source, 'type: "image_url"');
});

Deno.test("legacy text analysis is rejected before quota and queue", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "const hasLegacyTextInput");
  assertStringIncludes(source, "TEXT_ANALYSIS_REMOVED");
  assertStringIncludes(source, "text-disabled-v1");
  assertStringIncludes(source, "photo-with-text-disabled-v1");
  assertStringIncludes(source, "PHOTO_REQUIRED");
  assert(
    source.indexOf("TEXT_ANALYSIS_REMOVED") <
      source.indexOf("reserve_analysis_quota"),
  );
  assert(
    source.indexOf("TEXT_ANALYSIS_REMOVED") <
      source.indexOf("await enqueueAnalysisJob({"),
  );
});

Deno.test("photo marker names are stripped from user-facing finding text", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "function stripPhotoMarkerReferences");
  assertStringIncludes(source, "function sanitizePhotoHazardTextFields");
  assertStringIncludes(
    source,
    "FOTO_* marker adlarını kullanıcıya gösterilecek hiçbir metin alanında yazma",
  );
  assertStringIncludes(source, "sanitizePhotoHazardTextFields(");
  assertStringIncludes(
    source,
    "scene_summary: stripPhotoMarkerReferences(record.scene_summary)",
  );
  assertStringIncludes(source, "ai_summary: safeAISummary");
});

Deno.test("multi-photo prompt asks for complete evidence-backed findings", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "Her fotoğraf için 12 katmanlı taramadan çıkan tüm anlamlı bulgu adaylarını yaz",
  );
  assertStringIncludes(
    source,
    "Kanıt varsa listeyi gereksiz kısaltma",
  );
  assertStringIncludes(
    source,
    "farklı fotoğraftaki farklı tehlikeleri yalnız sayıyı azaltmak için birleştirme",
  );
  assertStringIncludes(source, "photo_findings[]");
  assertStringIncludes(source, "coverage_status");
  assertStringIncludes(source, "coverage_gap_reason");
  assertStringIncludes(
    source,
    "yalnız kanıta dayalı ve duplicate olmayan bulguları üret",
  );
  assertStringIncludes(
    source,
    "listeyi doldurmak için aynı tehlikeyi farklı başlıklarla tekrar yazma",
  );
  assertStringIncludes(
    source,
    "Temiz, ilgisiz, çok bulanık veya risk kanıtı zayıf fotoğrafta bulgu uydurma",
  );
});

Deno.test("atomic finding contract keeps independently correctable hazards separate", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    'const ATOMIC_FINDING_POLICY_VERSION = "distinct-physical-hazard-v3"',
  );
  assertStringIncludes(
    source,
    "Her bulgu yalnızca bağımsız olarak düzeltilebilen tek bir fiziksel tehlikeyi anlatsın",
  );
  assertStringIncludes(
    source,
    "korkuluk eksikliği ile sabitlenmemiş merdiven aynı yüksekte çalışma katmanında olsa da ayrı fiziksel tehlikelerdir",
  );
  assertStringIncludes(
    source,
    "bağımsız müdahale gerektiren ikinci bir fiziksel koşul ekliyorsa iki ayrı bulgu oluştur",
  );
  assertStringIncludes(
    source,
    "A shared category, inspection layer or root cause alone never justifies merging",
  );
  assertStringIncludes(
    source,
    "Exactly one independently correctable physical hazard; never join distinct hazards in one title.",
  );
  assertStringIncludes(
    source,
    "atomic_finding_policy_version: ATOMIC_FINDING_POLICY_VERSION",
  );
  assert(
    !source.includes("Aynı kök nedenli riskleri tek bulguda topla."),
    "legacy root-cause-only merge rule must not return",
  );
});

Deno.test("fire equipment obstruction prompt does not treat people as material", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "Yangın dolabı veya söndürücü önünde yalnızca geçici olarak duran/çalışan insan varsa",
  );
  assertStringIncludes(
    source,
    "Geçici insan varlığını sabit engel/malzeme gibi yorumlama",
  );
  assertStringIncludes(
    source,
    "Yangın ekipmanı önünde yalnızca insan varsa bunu malzeme/istif/erişim engeli sayma",
  );
});

Deno.test("photo persistence failures stop analysis before AI call", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "const failPhotoPersistence = async");
  assertStringIncludes(source, 'status: "failed"');
  assertStringIncludes(
    source,
    "await releaseAnalysisQuota(supabase, analysisID, user.id);",
  );
  assertStringIncludes(source, 'code: "photo_download_failed"');
  assertStringIncludes(source, ".upsert(\n        {");
  assertStringIncludes(source, 'onConflict: "analysis_id,sequence_index"');
  assertStringIncludes(
    source,
    "cleanup here would recreate the original race",
  );
});

Deno.test("AI input audit records photo quality metrics without base64", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "photo_payload_total_base64_bytes");
  assertStringIncludes(
    source,
    "photo_input_audit: imageBase64Parts.map(imagePartAudit)",
  );
  assertStringIncludes(source, "decoded_byte_count: part.decodedByteCount");
  assertStringIncludes(source, "jpeg_quality: part.jpegQuality");
  assert(!source.includes("data: part.data"));
});

Deno.test("storage-backed photos use the inline byte budgets before base64", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "bytes.byteLength > MAX_INLINE_PHOTO_DECODED_BYTES",
  );
  assertStringIncludes(
    source,
    "totalAnalysisEncodedBytes + projectedEncodedBytes",
  );
  assertStringIncludes(source, "MAX_INLINE_PHOTO_TOTAL_BASE64_BYTES");
  assertStringIncludes(source, "const base64 = bytesToBase64(bytes)");
  assertStringIncludes(source, "return errorResponse(413, message");
});

Deno.test("AI telemetry persists usage and audit for multi-photo success", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    "raw_ai_response: {",
  );
  assertStringIncludes(source, "...geminiResult");
  assertStringIncludes(source, "_input_audit: inputAudit");
  assertStringIncludes(source, "ai_models_used: [modelUsed]");
  assertStringIncludes(source, "await logUsage(supabase, {");
  assertStringIncludes(source, "provider: providerUsed");
  assertStringIncludes(source, "model: modelUsed");
  assertStringIncludes(source, "tokens_in: inputTokens");
  assertStringIncludes(source, "tokens_out: outputTokens");
  assertStringIncludes(source, "cached_tokens: cachedTokens");
  assertStringIncludes(source, "thoughts_tokens: thoughtsTokens");
  assertStringIncludes(source, "total_tokens: totalTokens");
  assertStringIncludes(source, "ai_execution_route: aiExecutionRoute");
  assertStringIncludes(
    source,
    "photo_input_audit: imageBase64Parts.map(imagePartAudit)",
  );
});

Deno.test("multi-photo features require build gated API contract", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "type ClientReleaseContext");
  assertStringIncludes(source, "function parseClientReleaseContext");
  assertStringIncludes(source, "function releaseGateDecision");
  assertStringIncludes(source, "client.apiContractVersion < 2");
  assertStringIncludes(source, "flags.rollout_mode");
  assertStringIncludes(source, 'case "build_allowlist"');
  assertStringIncludes(source, '"build_min_allowlist_floor"');
  assertStringIncludes(source, 'case "min_build"');
  assertStringIncludes(
    source,
    "resolvePhotoCapabilities(\n    supabase,\n    planTier,\n    clientRelease,",
  );
  assertStringIncludes(source, '"multi_photo_coverage_v2"');
  assertStringIncludes(source, "flags.enable_multi_photo_coverage_v2");
  assertStringIncludes(source, "coveragePolicyFor(");
});

Deno.test("canonical expand and current attestation keep build 62 safe", async () => {
  const expandMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260622195418_multi_photo_editable_findings.sql",
      import.meta.url,
    ),
  );
  const attestationMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728202000_attest_current_runtime_configuration_state.sql",
      import.meta.url,
    ),
  );
  if (expandMigration == null || attestationMigration == null) return;
  const normalizedExpand = expandMigration.toLowerCase().replace(/\s+/g, " ");
  const normalizedAttestation = attestationMigration.toLowerCase().replace(
    /\s+/g,
    " ",
  );

  assertStringIncludes(normalizedExpand, "'rollout_mode', 'build_allowlist'");
  assertStringIncludes(normalizedExpand, "'kill_switch', true");
  assertStringIncludes(
    normalizedExpand,
    "'enabled_ios_builds', jsonb_build_array('63')",
  );
  assert(!normalizedExpand.includes("jsonb_build_array('62'"));
  assertStringIncludes(
    normalizedExpand,
    "'enable_multi_photo_analysis', false",
  );
  assertStringIncludes(normalizedExpand, "'ios_release_policy'");
  assert(
    !normalizedExpand.includes("drop trigger if exists findings_after_change"),
  );
  assert(!normalizedExpand.includes("update public.photos set byte_size"));
  assertStringIncludes(
    normalizedAttestation,
    '"enabled_ios_builds":["63","64","65","66","67","68","69","70","71","72","73","74","75","76","77"]',
  );
  assert(!normalizedAttestation.includes('"enabled_ios_builds":["62"'));
});

Deno.test("reconciled schema and current attestation preserve coverage targets", async () => {
  const schemaMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728201500_reconcile_untracked_production_schema_state.sql",
      import.meta.url,
    ),
  );
  const attestationMigration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728202000_attest_current_runtime_configuration_state.sql",
      import.meta.url,
    ),
  );
  if (schemaMigration == null || attestationMigration == null) return;
  const normalizedSchema = schemaMigration.toLowerCase().replace(/\s+/g, " ");
  const normalizedAttestation = attestationMigration.toLowerCase().replace(
    /\s+/g,
    " ",
  );

  assertStringIncludes(normalizedSchema, "needs_field_verification boolean");
  assertStringIncludes(normalizedAttestation, '"max_findings_per_photo":13');
  assertStringIncludes(
    normalizedAttestation,
    '"target_findings_per_photo_min":1',
  );
  assertStringIncludes(
    normalizedAttestation,
    '"target_findings_per_photo_max":13',
  );
  assertStringIncludes(
    normalizedAttestation,
    '"target_findings_total_max":39',
  );
  assertStringIncludes(
    normalizedAttestation,
    "('plus', 3, 3, 13, 39, true, true, false)",
  );
});

Deno.test("coverage v2 pipeline normalizes repair and summaries", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "type MultiPhotoCoveragePolicy");
  assertStringIncludes(source, "function normalizePhotoFindingCoverage");
  assertStringIncludes(source, "function coverageRepairCandidates");
  assertStringIncludes(source, "function buildCoverageRepairContext");
  assertStringIncludes(source, "mergeDuplicateCoverageHazards(");
  assertStringIncludes(source, "function effectiveCoverageTargetMinForRecord");
  assertStringIncludes(
    source,
    "function representedActionableInspectionLayerCount",
  );
  assertStringIncludes(source, "function coverageProgressCountForRecord");
  assertStringIncludes(source, "function areMergeableCoverageFindings");
  assertStringIncludes(source, "buildPhotoSummariesFromCoverage(");
  assertStringIncludes(
    source,
    "target_findings_per_photo_min: multiPhotoCoveragePolicy.targetMin",
  );
  assertStringIncludes(source, "coverage_repair_candidate_photo_indices");
});

Deno.test("single-photo reports avoid forced overgeneration and repeated descriptions", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "const SINGLE_PHOTO_TARGET_MIN = 1;");
  assertStringIncludes(source, "const SINGLE_PHOTO_TARGET_MAX = 14;");
  assertStringIncludes(source, "const MULTI_PHOTO_TARGET_MIN = 1;");
  assertStringIncludes(source, "function composeFindingDescription");
  assertStringIncludes(source, "areLikelyDuplicateCoverageFindings,");
  assertStringIncludes(source, "preferredCoverageFinding,");
  assertStringIncludes(source, "tokenOverlapRatio(evidence, description)");
  assertStringIncludes(
    source,
    "Minimumu doldurmak için bulgu üretme.",
  );
  assertStringIncludes(
    source,
    "listeyi doldurmak için aynı tehlikeyi farklı başlıklarla tekrar yazma",
  );
  assert(
    !source.includes(
      "description: `${h.observed_evidence}\\n\\n${h.description}`.trim(),",
    ),
  );
});

Deno.test("analysis schema and policy use single and multi photo targets", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    'const LEGACY_PHOTO_POLICY_VERSION = "evidence-first-soft-min-v2"',
  );
  assertStringIncludes(
    source,
    'const LAYER_AUDIT_POLICY_VERSION = "single-pass-12-layer-audit-v5"',
  );
  assertStringIncludes(source, "const SINGLE_PHOTO_TARGET_MIN = 1");
  assertStringIncludes(source, "const SINGLE_PHOTO_TARGET_MAX = 14");
  assertStringIncludes(source, "const MULTI_PHOTO_TARGET_MIN = 1");
  assertStringIncludes(source, "const MULTI_PHOTO_TARGET_MAX = 13");
  assertStringIncludes(source, "const PHOTO_TARGET_TOTAL_MAX = 65");
  assertStringIncludes(source, 'root_cause: { type: "STRING" }');
  assertStringIncludes(source, 'needs_field_verification: { type: "BOOLEAN" }');
  assertStringIncludes(source, "if (includesPaidFields)");
  assertStringIncludes(source, "hazardProperties.references");
  assertStringIncludes(source, "photo_findings");
});

Deno.test("AI timeout and token budgets are explicit", async () => {
  const analyzeSource = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const workerSource = await readTextIfAllowed(
    new URL("../process-analysis-jobs/index.ts", import.meta.url),
  );
  const providerPolicySource = await readTextIfAllowed(
    new URL("../_shared/provider-execution-policy.ts", import.meta.url),
  );
  if (
    analyzeSource == null || workerSource == null ||
    providerPolicySource == null
  ) return;

  assertStringIncludes(analyzeSource, "const MAIN_AI_TIMEOUT_MS = 120_000");
  assertStringIncludes(analyzeSource, "const REPAIR_AI_TIMEOUT_MS = 45_000");
  // The repair budget moved from a hard-coded 1024 to the
  // `repair_thinking_budget` flag; 1024 remains the floor for repair calls that
  // request nothing of their own.
  assertStringIncludes(
    analyzeSource,
    "isRepairPass ? MINIMAL_REPAIR_THINKING_BUDGET : 3072,",
  );
  assertStringIncludes(
    analyzeSource,
    "const MINIMAL_REPAIR_THINKING_BUDGET = 1024;",
  );
  assertStringIncludes(analyzeSource, "return 14_000");
  assertStringIncludes(analyzeSource, "return 16_000");
  assertStringIncludes(analyzeSource, "return 18_000");
  assertStringIncludes(
    analyzeSource,
    "Math.min(48_000, 8_000 + photoCount * perPhoto)",
  );
  assertStringIncludes(analyzeSource, 'finishReason === "MAX_TOKENS"');
  assertStringIncludes(
    workerSource,
    "const LEGACY_ANALYZE_WORKER_TIMEOUT_MS = 210_000",
  );
  assertStringIncludes(
    providerPolicySource,
    "export const ANALYZE_NESTED_REQUEST_TIMEOUT_MS = 145_000",
  );
  assertStringIncludes(
    workerSource,
    "nestedAnalysisTimeoutMs(analysisFunctionName)",
  );
  assertStringIncludes(
    workerSource,
    "const ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS = 240",
  );
  assertStringIncludes(
    workerSource,
    "p_visibility_timeout: ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS",
  );
});

Deno.test("single-pass layer audit is flag gated and schema bounded", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const auditSource = await readTextIfAllowed(
    new URL("./inspection-layer-audit.ts", import.meta.url),
  );
  if (source == null || auditSource == null) return;

  assertStringIncludes(source, "single_photo_layer_audit_enabled: false");
  assertStringIncludes(source, "multi_photo_layer_audit_enabled: false");
  assertStringIncludes(
    source,
    "multi_photo_layer_audit_enabled_ios_builds: []",
  );
  assertStringIncludes(source, "multi_photo_layer_audit_min_ios_build: null");
  assertStringIncludes(
    source,
    "single_photo_compact_layer_schema_enabled: false",
  );
  assertStringIncludes(source, "single_photo_evidence_guard_enabled: false");
  assertStringIncludes(source, "single_photo_thinking_budget: 3072");
  assertStringIncludes(source, "multi_photo_thinking_budget: 3072");
  assertStringIncludes(
    source,
    "multi_photo_thinking_budget_min_ios_build: null",
  );
  assertStringIncludes(
    source,
    "multi_photo_thinking_budget_min_ios_build_value: null",
  );
  assertStringIncludes(
    source,
    "flags.multi_photo_layer_audit_min_ios_build,",
  );
  assertStringIncludes(source, 'client.platform === "ios"');
  assertStringIncludes(source, "INSPECTION_LAYER_KEYS,");
  assertStringIncludes(
    auditSource,
    '"environment_emergency_signage_competence"',
  );
  assertStringIncludes(source, "minItems: 12");
  assertStringIncludes(source, "maxItems: 12");
  assertStringIncludes(source, "inspection_layer_keys");
  assertStringIncludes(source, "coverage_conclusion");
  assertStringIncludes(source, "compactLayerSchemaEnabled");
  assertStringIncludes(
    source,
    "photoCount > 1 ||\n        capabilities.featureFlags.single_photo_compact_layer_schema_enabled",
  );
  assertStringIncludes(source, "evidenceGuardEnabled");
  assertStringIncludes(source, "expectedPhotoCount");
  assertStringIncludes(source, "options.isRepairPass !== true");
});

Deno.test("layer audit fallback preserves layer and expert contracts", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, 'layerAuditSchemaMode = "relaxed"');
  assertStringIncludes(source, 'layerAuditSchemaMode = "json_only"');
  assertStringIncludes(source, "configuredResponseSchema");
  assertStringIncludes(source, '"layer_schema_json_fallback"');
  assert(!source.includes("schemaAuditEnabled = false"));
  assertStringIncludes(source, "layerAuditSchemaFallbackUsed = true");
  assertStringIncludes(source, "layerAuditSchemaFallbackError");
  assertStringIncludes(source, "applyInspectionLayerEvidenceGuard(");
  assertStringIncludes(source, "normalizeInspectionLayers(");
  assertStringIncludes(source, "missing_layer_keys");
  assertStringIncludes(source, "duplicate_layer_keys");
  assertStringIncludes(source, "invalid_layer_statuses_count");
  assertStringIncludes(source, "actionable_layer_count");
  assertStringIncludes(source, "effective_target_findings_min");
  assertStringIncludes(source, "unrepresented_actionable_layers");
  assertStringIncludes(source, "unrepresented_uncertain_layers");
  assertStringIncludes(source, "unlinked_finding_count");
  assertStringIncludes(source, "invalid_finding_layer_keys_count");
  assertStringIncludes(
    source,
    "Do not merge distinct physical hazards into one finding",
  );
  assertStringIncludes(source, 'provider === "groq" ? "prompt_only_groq"');
  assertStringIncludes(
    source,
    "repairEnabled: layerAuditEnabled\n      ? false",
  );
  assertStringIncludes(source, "repair_authority_complete");
  assertStringIncludes(
    source,
    "coverage_quality_incomplete_authority_photo_indices",
  );
});

Deno.test("build 80 and later keep multi-photo layer audit and 6144 thinking budget", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260801220000_build80_multi_photo_layer_audit.sql",
      import.meta.url,
    ),
  );
  if (source == null || migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    source,
    "multi_photo_layer_audit_enabled: flags.multi_photo_layer_audit_enabled ||\n      buildScopedMultiPhotoLayerAuditEnabled",
  );
  assertStringIncludes(
    source,
    "multi_photo_thinking_budget: buildScopedMultiPhotoThinkingBudget ??",
  );
  assertStringIncludes(
    normalizedSQL,
    "'{multi_photo_layer_audit_min_ios_build}'",
  );
  assertStringIncludes(normalizedSQL, "'{min_ios_build}'");
  assertStringIncludes(
    normalizedSQL,
    "'{multi_photo_thinking_budget_min_ios_build}'",
  );
  assertStringIncludes(
    normalizedSQL,
    "'{multi_photo_thinking_budget_min_ios_build_value}'",
  );
  assertStringIncludes(normalizedSQL, "'80'::jsonb");
  assertStringIncludes(normalizedSQL, "'6144'::jsonb");
  assertStringIncludes(
    normalizedSQL,
    "global multi_photo_layer_audit_enabled must remain false",
  );
});

Deno.test("attested compact layer quality remains single-photo gated", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728202000_attest_current_runtime_configuration_state.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    normalizedSQL,
    '"single_photo_compact_layer_schema_enabled":true',
  );
  assertStringIncludes(
    normalizedSQL,
    '"single_photo_evidence_guard_enabled":true',
  );
  assertStringIncludes(
    normalizedSQL,
    '"multi_photo_layer_audit_enabled":false',
  );
});

Deno.test("attested layer audit budgets leave multi-photo audit disabled", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260728202000_attest_current_runtime_configuration_state.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    normalizedSQL,
    '"single_photo_layer_audit_enabled":true',
  );
  assertStringIncludes(
    normalizedSQL,
    '"multi_photo_layer_audit_enabled":false',
  );
  assertStringIncludes(normalizedSQL, '"single_photo_thinking_budget":6144');
  assertStringIncludes(normalizedSQL, '"multi_photo_thinking_budget":3072');
});

Deno.test("coverage repair is queued as a separate job", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  const workerSource = await readTextIfAllowed(
    new URL("../process-analysis-jobs/index.ts", import.meta.url),
  );
  if (source == null || workerSource == null) return;

  assertStringIncludes(source, "async function enqueueCoverageRepairJob");
  assertStringIncludes(source, 'job_mode: "repair"');
  assertStringIncludes(
    source,
    "repair_photo_indices: params.repairPhotoIndices",
  );
  assertStringIncludes(source, 'status: "repair_queued"');
  assertStringIncludes(source, "coverage_repair_failed_but_completed");
  assertStringIncludes(source, "coverage_repair_fallback_only");
  assertStringIncludes(workerSource, "coverage_repair_fallback_only");
  assertStringIncludes(workerSource, "repair_fallback_failed");
  assert(
    !source.includes("Coverage repair pass failed; continuing with first pass"),
  );
});

Deno.test("iOS result model and UI preserve field verification flag", async () => {
  const serviceSource = await readTextIfAllowed(
    new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
  );
  const findingSource = await readTextIfAllowed(
    new URL("../../../App/Models/Finding.swift", import.meta.url),
  );
  const resultSource = await readTextIfAllowed(
    new URL("../../../App/Views/Result/ResultView.swift", import.meta.url),
  );
  const riskDetailSource = await readTextIfAllowed(
    new URL(
      "../../../App/Views/Result/RiskDetailView.swift",
      import.meta.url,
    ),
  );
  if (
    serviceSource == null || findingSource == null || resultSource == null ||
    riskDetailSource == null
  ) {
    return;
  }

  assertStringIncludes(
    serviceSource,
    'case needsFieldVerification = "needs_field_verification"',
  );
  assertStringIncludes(
    serviceSource,
    "needsFieldVerification: needsFieldVerification == true",
  );
  assertStringIncludes(serviceSource, "photoCount: images.count");
  assertStringIncludes(serviceSource, "? 420 : 300");
  assertStringIncludes(serviceSource, "deadlineSeconds = 420");
  assertStringIncludes(findingSource, "let needsFieldVerification: Bool");
  assertStringIncludes(resultSource, "finding.needsFieldVerification");
  assertStringIncludes(resultSource, "Saha teyidi");
  assertStringIncludes(resultSource, "field_verification");
  assertStringIncludes(resultSource, "SelectedFindingDetail");
  assertStringIncludes(resultSource, "resolvedSourcePhotoIndex");
  assertStringIncludes(resultSource, "photoRow(forSourceIndex:");
  assertStringIncludes(resultSource, "localPreviewImage(forSourceIndex:");
  assertStringIncludes(riskDetailSource, "var photoIndex: Int = 1");
  assertStringIncludes(riskDetailSource, "result.detail.photo_index.");
  assertStringIncludes(riskDetailSource, "RDCard(showsShadow: false)");
});

Deno.test("Android build-allowlist gate mirrors iOS's, closed by default", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  // Schema: an Android counterpart to enabled_ios_builds/min_ios_build, defaulting to
  // empty/null so an unpopulated flag row keeps every platform closed exactly as before
  // this field existed (real deploy target: behavior-neutral until an owner explicitly
  // populates enabled_android_builds/min_android_build for a real Android build).
  assertStringIncludes(source, "enabled_android_builds: string[]");
  assertStringIncludes(source, "min_android_build: number | null");
  assertStringIncludes(
    source,
    "enabled_android_builds: [],\n  min_android_build: null,",
  );
  assertStringIncludes(
    source,
    "enabled_android_builds: asStringArray(record.enabled_android_builds)",
  );
  assertStringIncludes(
    source,
    "min_android_build: asOptionalPositiveInt(record.min_android_build)",
  );

  // Gate: androidBuildMatches/androidBuildAtLeast only ever match platform === "android" —
  // same F3 fail-closed discipline as clientBuildMatches/clientBuildAtLeast for iOS, kept as
  // separate functions so the existing iOS-only call sites (multi_photo_layer_audit,
  // thinking-budget overrides) stay untouched by this addition.
  assertStringIncludes(source, "function androidBuildMatches(");
  assertStringIncludes(
    source,
    'if (client.platform !== "android") return false;',
  );
  assertStringIncludes(source, "function androidBuildAtLeast(");
  assertStringIncludes(source, 'client.platform === "android" &&');

  // releaseGateDecision: "all" stays iOS-only (opting Android into a full "all" rollout is a
  // separate, not-yet-made decision); build_allowlist/min_build branch by platform and use
  // Android's own fields, never iOS's.
  assertStringIncludes(
    source,
    'client.platform !== "ios" && client.platform !== "android"',
  );
  assertStringIncludes(
    source,
    'return client.platform === "ios"\n        ? { open: true, reason: "all" }\n        : { open: false, reason: "platform" };',
  );
  assertStringIncludes(
    source,
    "androidBuildMatches(flags.enabled_android_builds, client)",
  );
  assertStringIncludes(
    source,
    "androidBuildAtLeast(flags.min_android_build, client)",
  );
});
