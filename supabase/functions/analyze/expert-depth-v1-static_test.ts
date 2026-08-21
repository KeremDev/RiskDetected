import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { INSPECTION_LAYER_KEYS } from "./inspection-layer-audit.ts";
import {
  PROCESS_SAFETY_CHECK_KEYS,
  PROCESS_SAFETY_LAYER_MAP,
} from "./process-safety-audit.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const processSource = await Deno.readTextFile(
  new URL("./process-safety-audit.ts", import.meta.url),
);
const qualitySource = await Deno.readTextFile(
  new URL("../_shared/photo-finding-quality.ts", import.meta.url),
);
const copySource = await Deno.readTextFile(
  new URL("../_shared/user-facing-copy.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260821182522_ai_expert_depth_v1_shadow.sql",
    import.meta.url,
  ),
);
const activationMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260821191758_ai_expert_depth_v1_on.sql",
    import.meta.url,
  ),
);
const reportRegistrationSource = await Deno.readTextFile(
  new URL("../register-report/index.ts", import.meta.url),
);
const excelReportSource = await Deno.readTextFile(
  new URL("../generate-excel-report/index.ts", import.meta.url),
);

Deno.test("expert depth keeps exactly twelve canonical layers and versions the audit", () => {
  assertEquals(INSPECTION_LAYER_KEYS.length, 12);
  assertEquals(new Set(INSPECTION_LAYER_KEYS).size, 12);
  assertStringIncludes(
    analyzeSource,
    'const LAYER_AUDIT_POLICY_VERSION = "single-pass-12-layer-audit-v5"',
  );
  assertStringIncludes(
    analyzeSource,
    'const LEGACY_LAYER_AUDIT_POLICY_VERSION = "single-pass-12-layer-audit-v4"',
  );
  assertStringIncludes(
    analyzeSource,
    "expertDepthEnabled\n        ? LAYER_AUDIT_POLICY_VERSION",
  );
  assertStringIncludes(analyzeSource, '"ai_expert_depth_v1"');
  assertStringIncludes(processSource, "EXPERT_DEPTH_POLICY_VERSION = 1");
  assertStringIncludes(migrationSource, "'rollout_mode', 'shadow'");
  assertStringIncludes(migrationSource, "'kill_switch', false");
  assertStringIncludes(activationMigrationSource, "'rollout_mode', 'on'");
  assertStringIncludes(activationMigrationSource, "'kill_switch', false");
});

Deno.test("applicable process equipment uses all twelve structured checks once", () => {
  assertEquals(PROCESS_SAFETY_CHECK_KEYS.length, 12);
  assertEquals(new Set(PROCESS_SAFETY_CHECK_KEYS).size, 12);
  for (const key of PROCESS_SAFETY_CHECK_KEYS) {
    assert(PROCESS_SAFETY_LAYER_MAP[key].length > 0, key);
    for (const layer of PROCESS_SAFETY_LAYER_MAP[key]) {
      assert(INSPECTION_LAYER_KEYS.includes(layer), `${key}:${layer}`);
    }
  }
  assertStringIncludes(analyzeSource, "equipment_depth_scan");
  assertStringIncludes(analyzeSource, "process_safety_scope");
  assertStringIncludes(analyzeSource, "process_safety_checks");
  assertStringIncludes(analyzeSource, "PROCESS_SAFETY_CHECK_KEYS.length");
});

Deno.test("live tank crane excavator regression has deterministic recovery and cab PPE guard", () => {
  assertStringIncludes(
    analyzeSource,
    "salvageEquipmentDepthScanFromScene(",
  );
  assertStringIncludes(
    analyzeSource,
    "completeApplicableProcessSafetyAudit(",
  );
  assertStringIncludes(analyzeSource, "applyContextualFindingGuard(");
  assertStringIncludes(
    analyzeSource,
    '"contextual_ppe_guard_rejected_count"',
  );
  assertStringIncludes(
    analyzeSource,
    'options.expertDepthV1 === true ? "relaxed" : "strict"',
  );
  assertStringIncludes(
    analyzeSource,
    "options.expertDepthV1 !== true",
  );
  assertStringIncludes(
    analyzeSource,
    "equipment_depth_scan MUST NOT be empty",
  );
  assertStringIncludes(
    analyzeSource,
    "Kapalı iş makinesi kabini içindeki operatör",
  );
});

Deno.test("mechanism prompt prioritizes engineered retention and preserves sharp-wire risk", () => {
  assertStringIncludes(analyzeSource, "ikincil kilitleme/fail-safe");
  assertStringIncludes(analyzeSource, "orijinal pim/kopilya/klips yerine tel");
  assertStringIncludes(analyzeSource, "dışarı uzanan keskin ucu ayrı");
  assertStringIncludes(analyzeSource, "secondary locking/fail-safe");
  assertStringIncludes(analyzeSource, "protruding sharp end as a separate");
  assertStringIncludes(analyzeSource, "İçerik, tasarım basıncı");
  assertStringIncludes(analyzeSource, "Never invent contents, design pressure");
});

Deno.test("periodic inspection is deterministic field verification, not model output", () => {
  assertStringIncludes(analyzeSource, "periodicVerificationFinding");
  assertStringIncludes(
    analyzeSource,
    'verification_reason_code: "periodic_inspection_status"',
  );
  assertStringIncludes(analyzeSource, 'display_group: "field_verification"');
  assertStringIncludes(analyzeSource, "MAX_FIELD_VERIFICATION_FINDINGS = 4");
  assertStringIncludes(
    analyzeSource,
    "Do not create periodic-inspection findings yourself",
  );
  assertStringIncludes(analyzeSource, "Repair sırasında periyodik kontrol");
  assertStringIncludes(copySource, "analysisPeriodicInspectionTitle");
  assertStringIncludes(copySource, "analysisApplicableInspectionTitle");
});

Deno.test("field verification does not inflate physical quality coverage", () => {
  assertStringIncludes(qualitySource, "isFieldVerificationFinding");
  assertStringIncludes(
    qualitySource,
    'finding.display_group === "field_verification"',
  );
  assertStringIncludes(
    qualitySource,
    'triggerReasons.push("unrepresented_actionable_process_check")',
  );
});

Deno.test("expert depth stays in the first generation and reuses coverage repair", () => {
  assertFalse(analyzeSource.includes('providerAttemptReason: "expert_depth"'));
  assertFalse(analyzeSource.includes('repair_kind: "process_safety"'));
  assertStringIncludes(
    qualitySource,
    '"unrepresented_actionable_process_check"',
  );
  assertStringIncludes(analyzeSource, 'job_mode: "repair"');
});

Deno.test("shadow mode leaves provider prompt and normalized result unchanged", () => {
  assertStringIncludes(analyzeSource, "expert_depth_shadow: expertDepthShadow");
  assertStringIncludes(analyzeSource, "expertDepthV1: expertDepthEnabled,");
  assertFalse(
    analyzeSource.includes("expertDepthEnabled || expertDepthShadow"),
  );
  assertFalse(analyzeSource.includes("expertDepthV1Shadow"));
});

Deno.test("process contract errors fail open and preserve normal findings", () => {
  assertStringIncludes(processSource, "!audit.complete");
  assertStringIncludes(processSource, "findings,");
  assertStringIncludes(
    analyzeSource,
    "process_safety_contract_incomplete",
  );
  assertStringIncludes(analyzeSource, "quality_repair_failed_open");
  assertStringIncludes(
    analyzeSource,
    'expertDepthV1: expertDepthEnabled && jobMode !== "repair"',
  );
  assertStringIncludes(
    analyzeSource,
    "applyProcessSafetyEvidenceGuard(\n        guardedFindings.findings,\n        base.process_safety_audit",
  );
  assertFalse(analyzeSource.includes('repair_kind="process_safety"'));
});

Deno.test("repair preserves first-pass expert and schema fallback telemetry", () => {
  assertStringIncludes(analyzeSource, "INITIAL_ANALYSIS_AUDIT_KEYS");
  assertStringIncludes(analyzeSource, "initialAnalysisAuditSnapshot(");
  assertStringIncludes(
    analyzeSource,
    'initial_analysis_audit: jobMode === "repair"',
  );
  assertStringIncludes(
    analyzeSource,
    '"layer_audit_schema_fallback_error"',
  );
  assertStringIncludes(analyzeSource, '"expert_depth_equipment_scan"');
  assertStringIncludes(
    analyzeSource,
    '"process_safety_contract_incomplete"',
  );
});

Deno.test("existing finding row contract persists grouping without a client model change", () => {
  assertStringIncludes(
    analyzeSource,
    "display_group: safeText(h.display_group).slice(0, 60) || null",
  );
  assertStringIncludes(migrationSource, "display_group,");
  assertStringIncludes(
    migrationSource,
    "nullif(v_finding->>'display_group', '')",
  );
  assertStringIncludes(analyzeSource, "ai_original_snapshot: {");
  assertStringIncludes(analyzeSource, "process_safety_check_keys");
});

Deno.test("PDF snapshot and Excel export retain field-verification findings", () => {
  assertStringIncludes(
    reportRegistrationSource,
    "confidence,needs_field_verification,fk_probability",
  );
  assertStringIncludes(
    reportRegistrationSource,
    '.eq("report_visibility", "visible")',
  );
  assertStringIncludes(excelReportSource, '.from("findings")');
  assertStringIncludes(excelReportSource, '.select("*")');
  assertFalse(
    reportRegistrationSource.includes(
      '.neq("display_group", "field_verification")',
    ),
  );
  assertFalse(
    excelReportSource.includes('.neq("display_group", "field_verification")'),
  );
});
