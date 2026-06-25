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

  assertStringIncludes(source, "balanced-v2-1600-floor1000");
  assertStringIncludes(source, ".init(maxDimension: 1600, jpegQuality: 0.78)");
  assertStringIncludes(source, ".init(maxDimension: 1000, jpegQuality: 0.60)");
  assertStringIncludes(source, "decodedByteCount: data.count");
  assertStringIncludes(source, "qualityPolicy: analysisPhotoQualityPolicy");
  assertStringIncludes(source, 'storage_strategy: "client-storage-paths-v1"');
  assert(!source.includes(".init(maxDimension: 850"));
  assert(!source.includes(".init(maxDimension: 700"));
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
    "en az ${findingPolicy.targetFindingsPerPhotoMin}",
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
  assertStringIncludes(source, "uploadedPhotoPaths.length > 0");
  assertStringIncludes(source, ".remove(uploadedPhotoPaths)");
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

Deno.test("coverage v2 migration is client capability gated", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260625191650_multi_photo_coverage_v2.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;
  const normalizedSQL = migration.toLowerCase().replace(/\s+/g, " ");

  assertStringIncludes(normalizedSQL, "coverage_status");
  assertStringIncludes(normalizedSQL, "coverage_gap_reason");
  assertStringIncludes(normalizedSQL, "target_findings_min");
  assertStringIncludes(normalizedSQL, "target_findings_max");
  assertStringIncludes(normalizedSQL, "multi_photo_coverage_v2");
  assertStringIncludes(normalizedSQL, "target_findings_per_photo_min");
  assertStringIncludes(normalizedSQL, "'5'::jsonb");
  assertStringIncludes(normalizedSQL, "target_findings_per_photo_max");
  assertStringIncludes(normalizedSQL, "'8'::jsonb");
  assertStringIncludes(normalizedSQL, "target_findings_total_max");
  assertStringIncludes(normalizedSQL, "'40'::jsonb");
  assertStringIncludes(
    normalizedSQL,
    "requires client_capabilities.multi_photo_coverage_v2=true",
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
  assertStringIncludes(source, "buildPhotoSummariesFromCoverage(");
  assertStringIncludes(
    source,
    "target_findings_per_photo_min: multiPhotoCoveragePolicy.targetMin",
  );
  assertStringIncludes(source, "coverage_repair_candidate_photo_indices");
});
