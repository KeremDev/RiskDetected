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
  // Renamed in the Faz 1 split: these are items, not findings, and they are
  // written to field_verification_items rather than findings.
  assertStringIncludes(analyzeSource, "periodicVerificationItem");
  assertStringIncludes(
    analyzeSource,
    "targetRecord.field_verification_items.push(",
  );
  assertFalse(analyzeSource.includes("targetRecord.findings.push("));
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

// Rewritten with the shadow fix: the schema is now requested in shadow so
// there is something to measure. What must stay unchanged is behaviour, not
// the prompt — the old assertion pinned the prompt and made shadow useless.
Deno.test("shadow mode observes without changing behaviour", () => {
  assertStringIncludes(analyzeSource, "expert_depth_shadow: expertDepthShadow");
  assertStringIncludes(
    analyzeSource,
    "const expertDepthObserved = expertDepthEnabled || expertDepthShadow;",
  );
  // No verification item is injected in shadow.
  assertFalse(
    analyzeSource.includes(
      "} else if (expertDepthShadow) {\n        const periodicVerification = applyPeriodicVerificationItems(\n          coverageRecords,\n          {\n            enabled: true,",
    ),
  );
  // One flag, two meanings — no parallel shadow-only plumbing.
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
    'expertDepthV1: expertDepthObserved && jobMode !== "repair"',
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

// Regression: on 2026-08-21 analyze v173 wrote four template verification rows
// into `findings`. The persistence loop sums fk/m5 over every hazard, so an
// unreadable inspection certificate scored fk_severity 40 and the analysis fell
// from highest_band_fk critical to low while finding_count read 6 for two real
// hazards.
Deno.test("verification items never reach the hazards array or the risk totals", () => {
  // `hazards` becomes the findings rows and drives total_score_fk.
  assertStringIncludes(
    analyzeSource,
    "coverageRecords.flatMap((record) => record.findings)",
  );
  assertFalse(
    analyzeSource.includes(
      "coverageRecords.flatMap((record) => record.field_verification_items)\n" +
        "          .concat(",
    ),
  );
  // Items ride beside the hazards, in their own key.
  assertStringIncludes(
    analyzeSource,
    "field_verification_items: coverageRecords.flatMap((record) =>",
  );
});

Deno.test("a verification item carries no Fine-Kinney or 5x5 input", () => {
  const builderStart = analyzeSource.indexOf(
    "function periodicVerificationItem(",
  );
  assert(builderStart > 0, "periodicVerificationItem must exist");
  const builderEnd = analyzeSource.indexOf(
    "\nfunction ",
    builderStart + "function periodicVerificationItem(".length,
  );
  const builder = analyzeSource.slice(builderStart, builderEnd);
  for (
    const scoreField of [
      "fk_probability:",
      "fk_frequency:",
      "fk_severity:",
      "m5_probability:",
      "m5_severity:",
    ]
  ) {
    assertFalse(
      builder.includes(scoreField),
      `verification item must not set ${scoreField}`,
    );
  }
  assertStringIncludes(builder, "priority: verificationPriorityFor(scan)");
});

Deno.test("a model-emitted verification item is stripped and rerouted too", () => {
  assertStringIncludes(analyzeSource, "stripRiskInputsFromVerificationItem");
  assertStringIncludes(
    analyzeSource,
    "field_verification_items: guardedVerificationItems,",
  );
  // The physical findings array is no longer concatenated with them.
  assertStringIncludes(
    analyzeSource,
    "const findings = guardedPhysicalFindings;",
  );
});

Deno.test("merged records do not duplicate an equipment instance", () => {
  assertStringIncludes(
    analyzeSource,
    "existing.equipment_instance_key === item.equipment_instance_key",
  );
});

// Regression: a repair pass that fails open onto the first result used to
// overwrite the initial call's budgets with its own hard-coded 1024, so every
// multi-photo analysis read as thinking-starved and the multi-photo budget
// could not be measured at all.
Deno.test("a failed-open repair pass does not overwrite the first pass budgets", () => {
  assertFalse(
    analyzeSource.includes(
      "inputAudit.thinking_budget = thinkingBudgetFor(true)",
    ),
  );
  assertStringIncludes(analyzeSource, "function recordRepairPassBudgets(");
  assertStringIncludes(analyzeSource, "audit.repair_thinking_budget =");
  assertStringIncludes(analyzeSource, "audit.repair_max_output_tokens =");
  assertStringIncludes(
    analyzeSource,
    'typeof priorThinkingBudget === "number"',
  );
});

Deno.test("a repair pass keeps the first pass verification counters", () => {
  assertStringIncludes(analyzeSource, "priorAddedCount");
  assertStringIncludes(analyzeSource, "priorCandidateCount");
  assertStringIncludes(
    analyzeSource,
    "periodicVerification.addedCount,\n          priorAddedCount,",
  );
});

Deno.test("persisted verification items survive re-normalization", () => {
  assertStringIncludes(analyzeSource, "persistedVerificationItems");
  assertStringIncludes(
    analyzeSource,
    "Array.isArray(\n        record.field_verification_items,\n      )",
  );
  assertStringIncludes(
    analyzeSource,
    "{ field_verification_items: record.field_verification_items }",
  );
});

// Structured output is produced in schema order. v173 put the equipment and
// process-safety blocks between inspection_layers and findings, and the model
// arrived at findings already satisfied.
Deno.test("depth structures are emitted after findings, not before", () => {
  const findingsAt = analyzeSource.indexOf(
    '              findings: {\n                type: "ARRAY",\n                items: hazardSchema,',
  );
  const equipmentAt = analyzeSource.indexOf(
    "              equipment_depth_scan: {",
  );
  assert(findingsAt > 0, "findings schema property must exist");
  assert(equipmentAt > 0, "equipment_depth_scan schema property must exist");
  assert(
    findingsAt < equipmentAt,
    "findings must be declared before equipment_depth_scan in the response schema",
  );
  // The layer audit deliberately stays ahead of findings; that ordering is
  // proven and must not be swept along with this move.
  const layersAt = analyzeSource.indexOf(
    "                  inspection_layers: {",
  );
  assert(layersAt > 0 && layersAt < findingsAt);
});

Deno.test("the depth prompt puts findings first", () => {
  assertStringIncludes(
    analyzeSource,
    "Her fotoğrafta ÖNCE bulguları tamamla",
  );
  assertFalse(
    analyzeSource.includes("bulgulardan önce equipment_depth_scan üret"),
  );
});

// Shadow used to record a single `evaluable: false` and nothing else: the
// schema was gated on `enabled`, so the model was never asked for the
// equipment scan and there was nothing to observe.
Deno.test("shadow mode asks for the depth structures and measures them", () => {
  assertStringIncludes(
    analyzeSource,
    "const expertDepthObserved = expertDepthEnabled || expertDepthShadow;",
  );
  assertStringIncludes(analyzeSource, "expertDepthV1: expertDepthObserved,");
  assertStringIncludes(
    analyzeSource,
    "inputAudit.expert_depth_shadow_evaluable = true;",
  );
  assertStringIncludes(analyzeSource, "wouldHaveAdded.candidateCount");
});

Deno.test("shadow mode changes nothing behavioural", () => {
  // Items are only injected on the enabled branch.
  assertStringIncludes(analyzeSource, "enabled: false,");
  assertStringIncludes(
    analyzeSource,
    "inputAudit.periodic_verification_added_count = 0;",
  );
  // The process-safety guard stays off in shadow.
  assertStringIncludes(
    analyzeSource,
    "processSafetyEnabled: expertDepthEnabled && !expertDepthShadow,",
  );
});
