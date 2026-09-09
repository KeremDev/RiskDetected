import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  MODULE_IDS,
  PHOTO_ANALYSIS_JSON_SCHEMA,
  type PhotoAnalysisV3,
} from "./contracts.ts";
import { buildEngineProduct, type PhotoResult } from "./engine.ts";
import { buildPrimaryPhotoPrompt, buildTargetedPrompt } from "./prompt.ts";
import {
  getSectorProfile,
  resolveVNextSectorSelection,
  SECTOR_IDS,
  SECTOR_PROFILE_VERSION,
  SECTOR_PROFILES,
  sectorCheckCodesForEntity,
  sectorEquipmentForEntity,
  validSectorModifierEvidence,
} from "./sector-profile.ts";

const EXPECTED_DEFAULTS: Record<string, number | null> = {
  general: null,
  construction: 3,
  manufacturing: 6,
  mining: 6,
  energy: 2,
  office: 6,
  logistics_warehouse: 6,
  chemical_laboratory: 3,
  healthcare: 10,
  food_production: 6,
  agriculture_livestock: 3,
  retail: 6,
  municipal_field_services: 3,
  education: 6,
  hospitality: 10,
};

function output(
  overrides: Partial<PhotoAnalysisV3> = {},
): PhotoAnalysisV3 {
  return {
    scene_inventory: [{
      entity_ref: "guard-1",
      equipment_family: "machine_press",
      component: "machine guard",
      visible_condition_summary: "Guard opening is visibly deformed.",
    }],
    module_audit: MODULE_IDS.map((module_id) => ({
      module_id,
      entity_refs: [],
      status: "scanned_no_positive_evidence" as const,
    })),
    mandatory_module_outcomes: [],
    sector_context_evidence: [],
    hazard_facts: [{
      fact_id: "fact-1",
      photo_index: 1,
      assessment_basis: "observed_nonconformity",
      evidence: {
        normalized_region: {
          x: 0.1,
          y: 0.1,
          width: 0.2,
          height: 0.2,
          is_global: false,
        },
        affirmative_cues: [
          "The fixed guard has a visibly deformed opening into the moving zone.",
        ],
      },
      entity: {
        entity_ref: "guard-1",
        equipment_family: "machine_press",
        component: "machine guard",
        identity_basis: "Visible press frame and operation zone",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "guarding_condition",
        short_text: "Deformed machine guard opening",
      },
      mechanism_code: "caught_in_pinch_shear",
      hazard_mechanism: "Access to the moving zone can cause crushing.",
      energy_source: "mechanical motion",
      barrier_state: "partial_event_direct_or_conditional",
      initiating_event_state: "A hand enters the accessible opening.",
      credible_event_path:
        "Access through the opening can cause a crushing injury.",
      exposed_entity: "worker",
      technical_assessment: {
        observation_narrative: "The fixed guard has a deformed opening.",
        technical_significance: "The opening weakens separation from motion.",
        root_cause_mode: "not_determinable",
        root_cause_text: "",
      },
      consequence_class: "serious_reversible",
      frequency_basis: "sector_scene_proxy",
      verification: { model_required: false, reason_code: "" },
      confidence: {
        entity: "high",
        condition: "high",
        localization: "high",
        mechanism: "high",
      },
      depth_tags: [],
      control_intents: [{
        action_code: "install_guard",
        target: "machine guard",
        priority: "immediate",
      }],
    }],
    inspection_signals: [],
    ...overrides,
  };
}

function result(analysis: PhotoAnalysisV3): PhotoResult {
  return {
    photoID: "photo-1",
    photoIndex: 1,
    storagePath: "test/photo.jpg",
    provider: "test",
    model: "test",
    output: analysis,
  };
}

Deno.test("sector-profile-v2 contains all 15 valid typed profiles", () => {
  assertEquals(SECTOR_PROFILE_VERSION, "sector-profile-v2");
  assertEquals(SECTOR_IDS.length, 15);
  assertEquals(Object.keys(SECTOR_PROFILES).sort(), [...SECTOR_IDS].sort());
  for (const sectorID of SECTOR_IDS) {
    const profile = getSectorProfile(sectorID);
    assert(profile);
    assertEquals(profile.sectorId, sectorID);
    assertEquals(profile.frequencyPrior.defaultF, EXPECTED_DEFAULTS[sectorID]);
    assert(profile.mandatoryModules.length > 0);
    assert(profile.mandatoryModules.every((id) => MODULE_IDS.includes(id)));
    assert(profile.priorityModules.every((id) => MODULE_IDS.includes(id)));
    for (const equipment of profile.criticalEquipment) {
      assert(equipment.familyCode.length > 0);
      assert(equipment.components.length > 0);
      assert(equipment.checkCodes.length > 0);
    }
    assert(profile.allowedControlIntents.length > 0);
    assert(profile.negativeRuleCodes.length > 0);
  }
  assertEquals(
    SECTOR_IDS.flatMap((id) => SECTOR_PROFILES[id].frequencyPrior.modifiers)
      .length,
    9,
  );
});

Deno.test("provider v3.4 schema requires sector outputs in the same call", () => {
  const required = [...PHOTO_ANALYSIS_JSON_SCHEMA.required];
  assert(required.includes("mandatory_module_outcomes"));
  assert(required.includes("sector_context_evidence"));
  assertEquals(
    PHOTO_ANALYSIS_JSON_SCHEMA.properties.mandatory_module_outcomes.items
      .properties.status.enum,
    ["actionable", "checked_no_hazard", "not_visible", "uncertain"],
  );
});

Deno.test("vNext sector selection makes DB authoritative and keeps legacy fallback", () => {
  assertEquals(
    resolveVNextSectorSelection("manufacturing", "construction"),
    {
      sectorID: "manufacturing",
      source: "database",
      requestMismatch: true,
      shouldBackfillDatabase: false,
    },
  );
  assertEquals(resolveVNextSectorSelection(null, "office"), {
    sectorID: "office",
    source: "request_fallback",
    requestMismatch: false,
    shouldBackfillDatabase: true,
  });
  assertEquals(resolveVNextSectorSelection(null, null), {
    sectorID: null,
    source: "none",
    requestMismatch: false,
    shouldBackfillDatabase: false,
  });
});

Deno.test("primary prompt contains only the selected sector profile", () => {
  const prompt = buildPrimaryPhotoPrompt({
    photoIndex: 1,
    sector: "construction",
    focuses: ["general"],
    language: "tr",
  });
  assert(prompt.includes("Kimlik: construction"));
  assert(prompt.includes("sector-profile-v2"));
  assert(prompt.includes("scaffold"));
  assertFalse(prompt.includes("Kimlik: manufacturing"));
  assertFalse(prompt.includes("Otel / Konaklama"));
  assertFalse(prompt.includes("TS EN 13374"));
});

Deno.test("compact prompt uses scanned ids and keeps dynamic context after cacheable prefix", () => {
  const construction = buildPrimaryPhotoPrompt({
    photoIndex: 1,
    sector: "construction",
    focuses: ["general"],
    language: "tr",
    compactProviderContractEnabled: true,
  });
  const office = buildPrimaryPhotoPrompt({
    photoIndex: 2,
    sector: "office",
    focuses: ["ergonomics"],
    language: "en",
    compactProviderContractEnabled: true,
  });
  const marker = "DEĞİŞKEN ANALİZ BAĞLAMI";
  assertEquals(construction.split(marker)[0], office.split(marker)[0]);
  assert(construction.indexOf(marker) > 8_000);
  assert(construction.includes("scanned_module_ids"));
  assert(construction.includes("Modül başına status/entity_refs"));
});

Deno.test("sector prompt kill switch restores neutral behavior", () => {
  const prompt = buildPrimaryPhotoPrompt({
    photoIndex: 1,
    sector: "manufacturing",
    focuses: [],
    language: "tr",
    sectorProfileEnabled: false,
  });
  assert(prompt.includes("Nötr v20 davranışını koru"));
  assertFalse(prompt.includes("Kimlik: manufacturing"));
  assertFalse(prompt.includes("maintenance_state_visible"));
});

Deno.test("targeted prompt receives only matching target component rules", () => {
  const prompt = buildTargetedPrompt({
    photoIndex: 1,
    language: "tr",
    sector: "manufacturing",
    signal: {
      selected_targets: [{
        equipment_family: "machine_press",
        component: "machine guard",
      }],
    },
  });
  assert(prompt.includes("manufacturing"));
  assert(prompt.includes("machine_guard_integrity"));
  assertFalse(prompt.includes("pressure_relief_integrity"));
});

Deno.test("same fact changes only F under different sector priors", () => {
  const construction = buildEngineProduct(
    [result(output())],
    "en",
    "free",
    [],
    {},
    { sectorID: "construction", source: "database" },
  ).findings[0];
  const manufacturing = buildEngineProduct(
    [result(output())],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  ).findings[0];
  assertEquals(construction.fk_probability, manufacturing.fk_probability);
  assertEquals(construction.fk_severity, manufacturing.fk_severity);
  assertEquals(construction.fk_frequency, 3);
  assertEquals(manufacturing.fk_frequency, 6);
  // The prior estimates how often exposure recurs; it is not a doubt about
  // what the photo shows. Flagging every finding it touched made
  // needs_field_verification true on all five findings of a live run, against
  // the model's own "Görsel kanıt yeterlidir". It stays a score reason code.
  assertEquals(construction.needs_field_verification, false);
  assert(
    (construction.score_policy_reason_codes as string[]).some((code) =>
      code.includes("sector")
    ),
    JSON.stringify(construction.score_policy_reason_codes),
  );
});

Deno.test("general profile and sectorless legacy frequency remain distinct", () => {
  const inactiveGeneral = buildEngineProduct(
    [result(output())],
    "en",
    "free",
    [],
    {},
    { sectorID: "general", source: "database" },
  ).findings[0];
  const activeOutput = output();
  activeOutput.hazard_facts[0].evidence.affirmative_cues.push(
    "Worker visible with direct access to the opening.",
  );
  const activeGeneral = buildEngineProduct(
    [result(activeOutput)],
    "en",
    "free",
    [],
    {},
    { sectorID: "general", source: "database" },
  ).findings[0];
  const legacy = buildEngineProduct(
    [result(output())],
    "en",
    "free",
  ).findings[0];
  const disabled = buildEngineProduct(
    [result(output())],
    "en",
    "free",
    [],
    {},
    {
      sectorID: "manufacturing",
      source: "database",
      frequencyPriorEnabled: false,
    },
  ).findings[0];
  assertEquals(inactiveGeneral.fk_frequency, 1);
  assertEquals(activeGeneral.fk_frequency, 3);
  assertEquals(legacy.fk_frequency, 2);
  assertEquals(disabled.fk_frequency, 2);
});

Deno.test("validated visible modifier overrides default sector F", () => {
  const analysis = output({
    sector_context_evidence: [{
      code: "maintenance_state_visible",
      entity_refs: ["guard-1"],
      affirmative_cues: [
        "A maintenance lock and opened service guard are visible.",
      ],
    }],
  });
  assertEquals(
    validSectorModifierEvidence(SECTOR_PROFILES.manufacturing, analysis)[0].f,
    2,
  );
  const product = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  assertEquals(product.findings[0].fk_frequency, 2);
  const lineage = product.factLineage[0].semantic_inputs as Record<
    string,
    unknown
  >;
  assertEquals(lineage.sector_modifier_code, "maintenance_state_visible");
});

Deno.test("mandatory outcomes map to legacy audits and omissions do not fail", () => {
  const analysis = output({
    mandatory_module_outcomes: [{
      module_id: "machine_safety_loto",
      entity_refs: ["guard-1"],
      status: "actionable",
    }],
  });
  const product = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  assertEquals(
    product.moduleAudits.find((audit) =>
      audit.module_id === "machine_safety_loto"
    )?.status,
    "positive_evidence",
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  assertEquals(
    (sectorTrace.mandatory_module_omissions as unknown[]).length,
    SECTOR_PROFILES.manufacturing.mandatoryModules.length - 1,
  );
});

Deno.test("unlinked actionable module is downgraded without inventing a fact", () => {
  const analysis = output({
    mandatory_module_outcomes: [{
      module_id: "machine_safety_loto",
      entity_refs: ["unknown-entity"],
      status: "actionable",
    }],
  });
  const product = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  assertEquals(
    product.moduleAudits.find((audit) =>
      audit.module_id === "machine_safety_loto"
    )?.status,
    "scanned_no_positive_evidence",
  );
  assertEquals(product.findings.length >= 1, true);
});

Deno.test("sector regulation anchors remain disabled in rendered references", () => {
  const product = buildEngineProduct(
    [result(output())],
    "tr",
    "free",
    [],
    {},
    {
      sectorID: "construction",
      source: "database",
      regulationAnchorsEnabled: false,
    },
  );
  assertFalse(
    String(product.findings[0].references_text).includes("TS EN 13374"),
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  assertEquals(sectorTrace.regulation_anchors_rendered, false);
});

Deno.test("sector profile does not change equipment assurance F=2", () => {
  const analysis = output();
  analysis.scene_inventory[0].equipment_family = "cnc_machine";
  analysis.scene_inventory[0].component = "cnc_lathe";
  analysis.hazard_facts = [];
  const product = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "healthcare", source: "database" },
  );
  const assurance = product.findings.filter((finding) =>
    finding.assessment_section === "equipment_assurance"
  );
  assert(assurance.length > 0);
  assert(assurance.every((finding) => finding.fk_frequency === 2));
  assert(
    assurance.every((finding) =>
      !(finding.field_verification_reason_codes as string[]).includes(
        "sector_frequency_prior_unverified",
      )
    ),
  );
});

Deno.test("sector negative validator rejects a photo-derived numeric claim", () => {
  const invalid = output();
  invalid.hazard_facts[0].observed_condition.short_text =
    "85 dB gürültü maruziyeti";
  invalid.hazard_facts[0].evidence.affirmative_cues = [
    "Makinenin 85 dB gürültü ürettiği görülüyor.",
  ];
  const product = buildEngineProduct(
    [result(invalid)],
    "tr",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  assert(
    (sectorTrace.triggered_negative_rule_codes as string[]).includes(
      "sector_negative_photo_measurement_claim",
    ),
  );
  assertFalse(
    product.findings.some((finding) => String(finding.title).includes("85")),
  );
});

Deno.test("manufacturing critical equipment maps child components to only relevant checks", () => {
  const profile = getSectorProfile("manufacturing")!;
  assert(profile.mandatoryModules.includes("access_and_work_at_height"));
  assert(profile.fatalMechanismCodes.includes("fall_from_height"));
  const platform = sectorEquipmentForEntity(
    profile,
    "elevated_work_platform",
    "etek_sacı",
  ).find((entry) => entry.familyCode === "elevated_work_platform");
  assert(platform);
  assertEquals(
    sectorCheckCodesForEntity(platform, "platform_guardrail", "etek_sacı"),
    ["guard_barrier_integrity"],
  );
  const crane = sectorEquipmentForEntity(profile, "hook_block", "hook").find(
    (entry) => entry.familyCode === "overhead_crane",
  );
  assert(crane);
  assertEquals(
    sectorCheckCodesForEntity(crane, "overhead_crane", "main_girder"),
    ["load_path_integrity"],
  );
  assertEquals(
    sectorCheckCodesForEntity(crane, "hook_block", "safety_latch"),
    ["pin_retainer_joint_integrity", "load_path_integrity"],
  );
  assert(
    sectorEquipmentForEntity(profile, "process_vessel", "vessel_shell").some(
      (entry) => entry.familyCode === "pressure_vessel",
    ),
  );
  assert(
    sectorEquipmentForEntity(profile, "motor", "agitator_drive").some(
      (entry) => entry.familyCode === "rotating_drive",
    ),
  );
});

Deno.test("rejected cab PPE cannot make a mandatory module actionable", () => {
  const analysis = output();
  const rejectedPPE = structuredClone(analysis.hazard_facts[0]);
  rejectedPPE.fact_id = "cab-ppe";
  rejectedPPE.entity = {
    ...rejectedPPE.entity,
    entity_ref: "excavator-1",
    equipment_family: "excavator cab",
    component: "cab occupant",
  };
  rejectedPPE.observed_condition = {
    condition_code: "helmet_not_worn",
    short_text: "Kabin içindeki operatörde baret yok",
  };
  rejectedPPE.evidence.affirmative_cues = [
    "Ekskavatör kabinindeki operatörün baret takmadığı görülüyor.",
  ];
  rejectedPPE.mechanism_code = "falling_object";
  analysis.scene_inventory = [{
    entity_ref: "excavator-1",
    equipment_family: "excavator",
    component: "cab",
    visible_condition_summary: "Operator is inside the enclosed cab.",
  }];
  analysis.hazard_facts = [rejectedPPE];
  analysis.mandatory_module_outcomes = [{
    module_id: "ppe",
    entity_refs: ["excavator-1"],
    status: "actionable",
  }];
  const product = buildEngineProduct(
    [result(analysis)],
    "tr",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  assertEquals(
    product.moduleAudits.find((audit) => audit.module_id === "ppe")?.status,
    "scanned_no_positive_evidence",
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  assert(
    (sectorTrace.triggered_negative_rule_codes as string[]).includes(
      "sector_negative_cab_occupant_ppe_claim",
    ),
  );
  const outcomes = sectorTrace.mandatory_module_outcomes as Array<
    Record<string, unknown>
  >;
  assertEquals(
    outcomes.find((entry) => entry.module_id === "ppe")?.reason_code,
    "sector_actionable_without_accepted_evidence",
  );
});

Deno.test("salvaged missing priority modules are reported as omissions", () => {
  const analysis = output({
    _schema_diagnostics_v1: {
      salvaged: true,
      strict_error_code: "schema_validation_failed",
      raw_fact_count: 1,
      valid_fact_count: 1,
      invalid_fact_count: 0,
      raw_signal_count: 0,
      invalid_signal_count: 0,
      missing_module_ids: ["storage_racking"],
      duplicate_module_ids: [],
      reason_codes: ["missing_module_audit"],
    },
  });
  const product = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  const priority = sectorTrace.priority_module_outcomes as Array<
    Record<string, unknown>
  >;
  const storage = priority.find((entry) =>
    entry.module_id === "storage_racking"
  );
  assertEquals(storage?.omitted, true);
  assertEquals(storage?.legacy_module_audit_status, null);
  assertEquals(storage?.reason_code, "sector_priority_module_omitted");
});

Deno.test("sector control preference reorders only existing allowed controls", () => {
  const analysis = output();
  analysis.hazard_facts[0].entity.component = "retainer pin";
  analysis.hazard_facts[0].observed_condition = {
    condition_code: "pin_displaced",
    short_text: "Tutucu pim dışa kaymış",
  };
  analysis.hazard_facts[0].evidence.affirmative_cues = [
    "Tutucu pim yuvasından dışa kaymış durumda görülüyor.",
  ];
  analysis.hazard_facts[0].mechanism_code = "mechanical_separation_release";
  analysis.hazard_facts[0].hazard_mechanism =
    "Pimin ilerleyerek bağlantının ayrılması";
  analysis.hazard_facts[0].control_intents = [
    {
      action_code: "secure_connection",
      target: "retainer pin",
      priority: "planned",
    },
    {
      action_code: "engineering_inspection",
      target: "retainer pin",
      priority: "planned",
    },
  ];
  const neutral = buildEngineProduct([result(analysis)], "en", "free");
  const sector = buildEngineProduct(
    [result(analysis)],
    "en",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  const neutralCodes = (neutral.findings[0].recommended_measures as Array<
    Record<string, unknown>
  >)[1].action_codes as string[];
  const sectorCodes = (sector.findings[0].recommended_measures as Array<
    Record<string, unknown>
  >)[1].action_codes as string[];
  assertEquals(new Set(sectorCodes), new Set(neutralCodes));
  assertFalse(neutralCodes[0] === sectorCodes[0]);
  assertEquals(neutralCodes[0], "secure_connection");
  assertEquals(sectorCodes[0], "engineering_inspection");
});

Deno.test("sector critical coverage does not apply every family check to every component", () => {
  const analysis = output({
    scene_inventory: [
      {
        entity_ref: "crane-1",
        equipment_family: "overhead_crane",
        component: "main_girder",
        visible_condition_summary: "Ana kiriş görünür durumda.",
      },
      {
        entity_ref: "crane-1-hook",
        equipment_family: "hook_block",
        component: "safety_latch",
        visible_condition_summary: "Kanca mandalı durumu net değil.",
      },
      {
        entity_ref: "tank-1",
        equipment_family: "process_vessel",
        component: "vessel_shell",
        visible_condition_summary: "Tank gövdesi görünür durumda.",
      },
      {
        entity_ref: "motor-1",
        equipment_family: "motor",
        component: "agitator_drive",
        visible_condition_summary: "Motor ve tahrik bölgesi görünür durumda.",
      },
    ],
    hazard_facts: [],
  });
  const product = buildEngineProduct(
    [result(analysis)],
    "tr",
    "free",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  const sectorTrace = product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >;
  const coverage = sectorTrace.critical_equipment_coverage as Array<
    Record<string, unknown>
  >;
  assertFalse(
    coverage.some((entry) =>
      entry.entity_ref === "crane-1" &&
      entry.check_code === "pin_retainer_joint_integrity"
    ),
  );
  assert(
    coverage.some((entry) =>
      entry.entity_ref === "crane-1" &&
      entry.check_code === "load_path_integrity"
    ),
  );
  assertEquals(
    coverage.find((entry) =>
      entry.entity_ref === "crane-1-hook" &&
      entry.check_code === "pin_retainer_joint_integrity"
    )?.status,
    "unresolved_no_fact",
  );
  assertEquals(
    coverage.find((entry) =>
      entry.equipment_family_code === "pressure_vessel" &&
      entry.check_code === "pressure_relief_integrity"
    )?.status,
    "not_visible",
  );
  assertEquals(
    coverage.find((entry) =>
      entry.equipment_family_code === "rotating_drive" &&
      entry.check_code === "machine_guard_integrity"
    )?.status,
    "not_visible",
  );
});
