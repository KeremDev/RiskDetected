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
  assertStringIncludes(source, "static let apiContractVersion = 2");
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
    "function imagePartMarkerText(part: AIImagePart)",
  );
  assertStringIncludes(source, 'label="FOTO_${part.photoIndex}"');
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
    "parts.push({ text: imagePartMarkerText(img) });",
  );
  assertStringIncludes(
    source,
    "parts.push({ inlineData: { mimeType: img.mimeType, data: img.data } });",
  );
  assertStringIncludes(source, "text: imagePartMarkerText(img),");
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
  assertStringIncludes(source, 'case "min_build"');
  assertStringIncludes(
    source,
    "resolvePhotoCapabilities(\n    supabase,\n    planTier,\n    clientRelease,",
  );
  assertStringIncludes(source, '"multi_photo_coverage_v2"');
  assertStringIncludes(source, "flags.enable_multi_photo_coverage_v2");
  assertStringIncludes(source, "coveragePolicyFor(");
});

Deno.test("expand migration keeps build 62 safe", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260622195418_multi_photo_editable_findings.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "'rollout_mode', 'build_allowlist'");
  assertStringIncludes(normalizedSQL, "'kill_switch', true");
  assertStringIncludes(
    normalizedSQL,
    "'enabled_ios_builds', jsonb_build_array('63', '64', '65', '66')",
  );
  assert(!normalizedSQL.includes("jsonb_build_array('62'"));
  assertStringIncludes(normalizedSQL, "'enable_multi_photo_analysis', false");
  assertStringIncludes(normalizedSQL, "'ios_release_policy'");
  assert(
    !normalizedSQL.includes("drop trigger if exists findings_after_change"),
  );
  assert(!normalizedSQL.includes("update public.photos set byte_size"));
});

Deno.test("analysis prompt limit migration raises coverage targets", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260630115105_analysis_prompt_limit_integration.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "needs_field_verification boolean");
  assertStringIncludes(normalizedSQL, "max_findings_per_photo = 13");
  assertStringIncludes(normalizedSQL, "max_findings_per_analysis = 65");
  assertStringIncludes(normalizedSQL, "target_findings_per_photo_min");
  assertStringIncludes(normalizedSQL, "'9'::jsonb");
  assertStringIncludes(normalizedSQL, "target_findings_per_photo_max");
  assertStringIncludes(normalizedSQL, "'13'::jsonb");
  assertStringIncludes(normalizedSQL, "target_findings_total_max");
  assertStringIncludes(normalizedSQL, "'65'::jsonb");
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
    'const LAYER_AUDIT_POLICY_VERSION = "single-pass-12-layer-audit-v4"',
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
  if (analyzeSource == null || workerSource == null) return;

  assertStringIncludes(analyzeSource, "const MAIN_AI_TIMEOUT_MS = 120_000");
  assertStringIncludes(analyzeSource, "const REPAIR_AI_TIMEOUT_MS = 45_000");
  assertStringIncludes(
    analyzeSource,
    "thinkingBudget: isRepairPass ? 1024 : normalizeThinkingBudget(",
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
    "const ANALYZE_WORKER_TIMEOUT_MS = 135_000",
  );
  assertStringIncludes(
    workerSource,
    "const ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS = 180",
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
    "single_photo_compact_layer_schema_enabled: false",
  );
  assertStringIncludes(source, "single_photo_evidence_guard_enabled: false");
  assertStringIncludes(source, "single_photo_thinking_budget: 3072");
  assertStringIncludes(source, "multi_photo_thinking_budget: 3072");
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
  assertStringIncludes(source, "evidenceGuardEnabled");
  assertStringIncludes(source, "expectedPhotoCount");
  assertStringIncludes(source, "options.isRepairPass !== true");
});

Deno.test("layer audit degrades to legacy schema and audits malformed coverage", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "res.status === 400 && schemaAuditEnabled");
  assertStringIncludes(source, "layerAuditSchemaFallbackUsed = true");
  assertStringIncludes(source, "layerAuditSchemaFallbackError");
  assertStringIncludes(source, "applyInspectionLayerEvidenceGuard(");
  assertStringIncludes(source, "normalizeInspectionLayers(");
  assertStringIncludes(source, "missing_layer_keys");
  assertStringIncludes(source, "duplicate_layer_keys");
  assertStringIncludes(source, "invalid_layer_statuses_count");
  assertStringIncludes(source, "unrepresented_actionable_layers");
  assertStringIncludes(source, "unlinked_finding_count");
  assertStringIncludes(source, "invalid_finding_layer_keys_count");
  assertStringIncludes(source, 'provider === "groq" ? "prompt_only_groq"');
  assertStringIncludes(
    source,
    "repairEnabled: layerAuditEnabled\n      ? false",
  );
});

Deno.test("compact layer quality rollout is single-photo and backend gated", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260714170000_enable_single_photo_compact_layer_quality.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(
    normalizedSQL,
    "single_photo_compact_layer_schema_enabled",
  );
  assertStringIncludes(normalizedSQL, "single_photo_evidence_guard_enabled");
  assert(!normalizedSQL.includes("multi_photo_layer_audit_enabled"));
  assert(!normalizedSQL.includes("single_photo_thinking_budget"));
  assert(!normalizedSQL.includes("multi_photo_thinking_budget"));
});

Deno.test("single-photo layer audit rollout leaves multi-photo disabled", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260712193000_enable_single_photo_layer_audit.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "single_photo_layer_audit_enabled");
  assertStringIncludes(normalizedSQL, "multi_photo_layer_audit_enabled");
  assertStringIncludes(normalizedSQL, "single_photo_thinking_budget");
  assertStringIncludes(normalizedSQL, "multi_photo_thinking_budget");
  assertStringIncludes(normalizedSQL, "'6144'::jsonb");
  assertStringIncludes(normalizedSQL, "'3072'::jsonb");
  assertStringIncludes(normalizedSQL, "'false'::jsonb");
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
