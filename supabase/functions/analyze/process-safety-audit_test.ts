import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  applyProcessSafetyEvidenceGuard,
  completeApplicableProcessSafetyAudit,
  type EquipmentDepthGroup,
  isFieldVerificationFinding,
  normalizeEquipmentDepthScan,
  normalizeProcessSafetyAudit,
  periodicInspectionEligible,
  physicalFindings,
  PROCESS_SAFETY_CHECK_KEYS,
  PROCESS_SAFETY_LAYER_MAP,
  type ProcessSafetyCheckKey,
  salvageEquipmentDepthScanFromScene,
  unrepresentedActionableProcessChecks,
} from "./process-safety-audit.ts";

function completeChecks(
  statusFor: Partial<Record<ProcessSafetyCheckKey, string>> = {},
) {
  return PROCESS_SAFETY_CHECK_KEYS.map((check_key) => ({
    check_key,
    status: statusFor[check_key] ?? "checked_no_hazard",
    visual_evidence: `visible:${check_key}`,
    linked_layer_keys: [PROCESS_SAFETY_LAYER_MAP[check_key][0]],
    equipment_instance_key: "equipment_1",
  }));
}

Deno.test("complete applicable process audit requires every check once", () => {
  const audit = normalizeProcessSafetyAudit("applicable", completeChecks());
  assertEquals(audit.complete, true);
  assertEquals(audit.checks.length, 12);
  assertEquals(audit.missing_check_keys, []);
});

Deno.test("missing or duplicate process checks make the v1 contract incomplete", () => {
  const incomplete = normalizeProcessSafetyAudit(
    "applicable",
    [...completeChecks().slice(1), completeChecks()[1]],
  );
  assertEquals(incomplete.complete, false);
  assert(incomplete.missing_check_keys.includes("equipment_process_identity"));
  assert(incomplete.duplicate_check_keys.includes("containment_integrity"));
});

Deno.test("empty evidence, instance identity or invalid layer mapping makes the contract incomplete", () => {
  const emptyEvidence = completeChecks();
  emptyEvidence[0].visual_evidence = "";
  assertEquals(
    normalizeProcessSafetyAudit("applicable", emptyEvidence).complete,
    false,
  );

  const emptyInstance = completeChecks();
  emptyInstance[0].equipment_instance_key = "";
  assertEquals(
    normalizeProcessSafetyAudit("applicable", emptyInstance).complete,
    false,
  );

  const wrongLayer = completeChecks();
  wrongLayer[0].linked_layer_keys = ["ppe"];
  assertEquals(
    normalizeProcessSafetyAudit("applicable", wrongLayer).complete,
    false,
  );
});

Deno.test("not-applicable scenes keep an empty process audit complete", () => {
  const audit = normalizeProcessSafetyAudit("not_applicable", []);
  assertEquals(audit.complete, true);
  assertEquals(audit.checks, []);
});

Deno.test("not-applicable and invalid scopes fail closed when their contract is inconsistent", () => {
  assertEquals(
    normalizeProcessSafetyAudit("not_applicable", completeChecks()).complete,
    false,
  );
  assertEquals(normalizeProcessSafetyAudit("invented", []).complete, false);
});

Deno.test("process guard accepts actionable links and marks uncertain links", () => {
  const audit = normalizeProcessSafetyAudit(
    "applicable",
    completeChecks({
      containment_integrity: "actionable",
      instrumentation_indication: "uncertain",
    }),
  );
  const result = applyProcessSafetyEvidenceGuard(
    [
      {
        title: "leak",
        confidence: 0.9,
        process_safety_check_keys: ["containment_integrity"],
      },
      {
        title: "gauge",
        confidence: 0.8,
        process_safety_check_keys: ["instrumentation_indication"],
      },
    ],
    audit,
    true,
  );
  assertEquals(result.findings.length, 2);
  assertEquals(result.findings[1].confidence, 0.69);
  assertEquals(result.findings[1].needs_field_verification, true);
  assertEquals(result.marked_uncertain_process_count, 1);
});

Deno.test("process guard rejects findings linked only to non-actionable checks", () => {
  const audit = normalizeProcessSafetyAudit("applicable", completeChecks());
  const result = applyProcessSafetyEvidenceGuard(
    [{
      title: "invented pressure defect",
      process_safety_check_keys: ["pressure_vacuum_integrity"],
    }],
    audit,
    true,
  );
  assertEquals(result.findings, []);
  assertEquals(result.rejected_non_actionable_process_count, 1);
});

Deno.test("process guard strips not-visible and checked links from mixed findings", () => {
  const audit = normalizeProcessSafetyAudit(
    "applicable",
    completeChecks({ containment_integrity: "actionable" }),
  );
  const result = applyProcessSafetyEvidenceGuard(
    [{
      title: "visible leak",
      process_safety_check_keys: [
        "containment_integrity",
        "instrumentation_indication",
        "overpressure_relief_path",
      ],
    }],
    audit,
    true,
  );
  assertEquals(result.findings[0].process_safety_check_keys, [
    "containment_integrity",
  ]);
});

Deno.test("incomplete process contract fails open for ordinary findings", () => {
  const audit = normalizeProcessSafetyAudit(
    "applicable",
    completeChecks().slice(0, 3),
  );
  const finding = { title: "visible floor hazard" };
  const result = applyProcessSafetyEvidenceGuard([finding], audit, true);
  assertEquals(result.applied, true);
  assertEquals(result.findings, [finding]);
});

Deno.test("incomplete or not-applicable audits reject only process-linked items", () => {
  const ordinary = { title: "visible floor hazard" };
  const processLinked = {
    title: "unvalidated process hazard",
    process_safety_check_keys: ["containment_integrity"],
  };
  const incomplete = applyProcessSafetyEvidenceGuard(
    [ordinary, processLinked],
    normalizeProcessSafetyAudit("applicable", completeChecks().slice(0, 2)),
    true,
  );
  assertEquals(incomplete.findings, [ordinary]);
  assertEquals(incomplete.rejected_invalid_process_link_count, 1);

  const notApplicable = applyProcessSafetyEvidenceGuard(
    [ordinary, processLinked],
    normalizeProcessSafetyAudit("not_applicable", []),
    true,
  );
  assertEquals(notApplicable.findings, [ordinary]);
  assertEquals(notApplicable.rejected_invalid_process_link_count, 1);
});

Deno.test("uncertain equipment identity allows only supported uncertain checks", () => {
  const audit = normalizeProcessSafetyAudit("uncertain_equipment_identity", [{
    ...completeChecks({ containment_integrity: "uncertain" })[1],
    check_key: "containment_integrity",
  }]);
  assertEquals(audit.complete, true);
  const result = applyProcessSafetyEvidenceGuard(
    [{
      title: "visible residue requires field verification",
      confidence: 0.94,
      process_safety_check_keys: ["containment_integrity"],
    }],
    audit,
    true,
  );
  assertEquals(result.findings.length, 1);
  assertEquals(result.findings[0].confidence, 0.69);
  assertEquals(result.findings[0].needs_field_verification, true);
});

Deno.test("field verification is excluded from physical coverage counts", () => {
  const verification = {
    display_group: "field_verification",
    verification_reason_code: "periodic_inspection_status",
  };
  const physical = { title: "visible leak" };
  assertEquals(isFieldVerificationFinding(verification), true);
  assertEquals(physicalFindings([verification, physical]), [physical]);
});

Deno.test("unrepresented actionable process checks are deterministic", () => {
  const audit = normalizeProcessSafetyAudit(
    "applicable",
    completeChecks({
      containment_integrity: "actionable",
      overpressure_relief_path: "actionable",
    }),
  );
  assertEquals(
    unrepresentedActionableProcessChecks(audit, [{
      process_safety_check_keys: ["containment_integrity"],
    }]),
    ["overpressure_relief_path"],
  );
});

Deno.test("equipment scan normalizes source mapping and periodic threshold", () => {
  const scan = normalizeEquipmentDepthScan(
    [{
      equipment_instance_key: "Crane #1",
      equipment_group_code: "lifting_conveying",
      localized_equipment_name: "Mobil vinç",
      recognition_confidence: 0.91,
      visible_cues: ["boom", "hook"],
      source_photo_indices: [1, 2],
      fk_probability: 1,
      fk_frequency: 2,
      fk_severity: 40,
      m5_probability: 2,
      m5_severity: 5,
    }],
    1,
    2,
  );
  assertEquals(scan[0].equipment_instance_key, "crane_1");
  assertEquals(scan[0].source_photo_indices, [1]);
  assertEquals(periodicInspectionEligible(scan[0]), true);
  assertEquals(
    periodicInspectionEligible({ ...scan[0], recognition_confidence: 0.79 }),
    false,
  );
  assertEquals(
    periodicInspectionEligible({ ...scan[0], visible_cues: [] }),
    false,
  );

  const turkishKey = normalizeEquipmentDepthScan(
    [{
      ...scan[0],
      equipment_instance_key: "İş Makinesi Şasi #1",
      source_photo_indices: [1],
    }],
    1,
    1,
  );
  assertEquals(turkishKey[0].equipment_instance_key, "is_makinesi_sasi_1");
});

Deno.test("explicit tank crane and excavator scene cues salvage equipment depth", () => {
  const tank = salvageEquipmentDepthScanFromScene(
    [],
    ["Endüstriyel tanklar", "Boru hatları"],
    "Proses tesisi",
    1,
  );
  assertEquals(tank.salvaged_groups, [
    "pressure_equipment",
    "other_complex_equipment",
  ]);
  assertEquals(periodicInspectionEligible(tank.scans[0]), true);

  const factory = salvageEquipmentDepthScanFromScene(
    [],
    ["Tavan vinçleri", "Raf sistemleri"],
    "Fabrika iç alanı",
    2,
  );
  assertEquals(factory.salvaged_groups, [
    "lifting_conveying",
    "industrial_racks_doors",
  ]);

  const excavator = salvageEquipmentDepthScanFromScene(
    [],
    ["Ekskavatör", "Operatör kabini"],
    "Kazı alanı",
    3,
  );
  assertEquals(excavator.salvaged_groups, ["construction_machinery"]);
});

Deno.test("scene salvage preserves valid scans and adds only a missing explicit group", () => {
  const existing = normalizeEquipmentDepthScan(
    [{
      equipment_instance_key: "crane_1",
      equipment_group_code: "lifting_conveying",
      localized_equipment_name: "Tavan vinci",
      recognition_confidence: 0.95,
      visible_cues: ["Köprü ve kanca"],
      source_photo_indices: [1],
      fk_probability: 0.5,
      fk_frequency: 1,
      fk_severity: 40,
      m5_probability: 1,
      m5_severity: 5,
    }],
    1,
    1,
  );
  const result = salvageEquipmentDepthScanFromScene(
    existing,
    ["Ekskavatör"],
    "",
    1,
  );
  assertEquals(result.scans[0], existing[0]);
  assertEquals(result.scans.length, 2);
  assertEquals(result.salvaged_groups, ["construction_machinery"]);
});

Deno.test("incomplete applicable process audit is completed only with not-visible checks", () => {
  const equipment = salvageEquipmentDepthScanFromScene(
    [],
    ["Endüstriyel tanklar"],
    "",
    1,
  ).scans;
  const original = normalizeProcessSafetyAudit("applicable", []);
  const result = completeApplicableProcessSafetyAudit(
    original,
    equipment,
    "Gerekli ayrıntı görüntüde görünmüyor.",
  );
  assertEquals(result.completed, true);
  assertEquals(result.inserted_check_count, 12);
  assertEquals(result.audit.complete, true);
  assertEquals(result.audit.checks.length, 12);
  assertEquals(
    result.audit.checks.every((check) => check.status === "not_visible"),
    true,
  );
});

Deno.test("process completion preserves valid checks and cannot create actionable status", () => {
  const equipment = salvageEquipmentDepthScanFromScene(
    [],
    ["Basınçlı kap"],
    "",
    1,
  ).scans;
  const first = completeChecks({ containment_integrity: "actionable" })[1];
  const result = completeApplicableProcessSafetyAudit(
    normalizeProcessSafetyAudit("applicable", [first]),
    equipment,
    "Not visible",
  );
  assertEquals(result.completed, true);
  assertEquals(result.inserted_check_count, 11);
  assertEquals(
    result.audit.checks.find((check) =>
      check.check_key === "containment_integrity"
    )?.status,
    "actionable",
  );
  assertEquals(
    result.audit.checks.filter((check) => check.status === "actionable")
      .length,
    1,
  );
});

const QUALITY_SCENARIO_TUPLES: Array<[
  string,
  EquipmentDepthGroup,
  ProcessSafetyCheckKey,
]> = [
  ["basınçlı kap korozyonu", "pressure_equipment", "containment_integrity"],
  [
    "basınçlı kap şişmesi",
    "pressure_equipment",
    "pressure_vacuum_integrity",
  ],
  ["kazan tahliye yönü", "pressure_equipment", "overpressure_relief_path"],
  [
    "kompresör göstergesi hasarı",
    "pressure_equipment",
    "instrumentation_indication",
  ],
  [
    "hidrolik depolanmış enerji",
    "pressure_equipment",
    "isolation_energy_release",
  ],
  [
    "proses hortumu çatlağı",
    "pressure_equipment",
    "transfer_connections_hoses",
  ],
  [
    "yakıt statik eşpotansiyeli",
    "pressure_equipment",
    "ignition_static_explosion_controls",
  ],
  [
    "tank sekonder muhafazası",
    "pressure_equipment",
    "secondary_containment_drainage",
  ],
  [
    "tank desteği ve çarpma",
    "pressure_equipment",
    "supports_anchorage_impact_protection",
  ],
  [
    "kimyasal malzeme uyumluluğu",
    "pressure_equipment",
    "material_compatibility_reaction",
  ],
  [
    "güvensiz tahliye yönü",
    "pressure_equipment",
    "emergency_access_discharge",
  ],
  [
    "belirsiz tank kimliği",
    "other_complex_equipment",
    "equipment_process_identity",
  ],
  [
    "vinç kancası mandalı",
    "lifting_conveying",
    "supports_anchorage_impact_protection",
  ],
  [
    "kopilya yerine tel",
    "lifting_conveying",
    "supports_anchorage_impact_protection",
  ],
  [
    "sapan uç bağlantısı",
    "lifting_conveying",
    "supports_anchorage_impact_protection",
  ],
  [
    "halatta kırık teller",
    "lifting_conveying",
    "supports_anchorage_impact_protection",
  ],
  [
    "zincir deformasyonu",
    "lifting_conveying",
    "supports_anchorage_impact_protection",
  ],
  [
    "denge ayağı desteği",
    "construction_machinery",
    "supports_anchorage_impact_protection",
  ],
  [
    "kova kilitleme pimi",
    "construction_machinery",
    "supports_anchorage_impact_protection",
  ],
  [
    "yükleyici hidrolik sızıntısı",
    "construction_machinery",
    "containment_integrity",
  ],
  [
    "ekskavatör hortumu aşınması",
    "construction_machinery",
    "transfer_connections_hoses",
  ],
  [
    "makine aynası tutucusu",
    "machine_tools",
    "supports_anchorage_impact_protection",
  ],
  ["torna koruyucusu", "machine_tools", "isolation_energy_release"],
  [
    "konveyör kaplini",
    "machine_tools",
    "supports_anchorage_impact_protection",
  ],
  ["kayış koruyucusu", "machine_tools", "isolation_energy_release"],
  [
    "rack upright damage",
    "industrial_racks_doors",
    "supports_anchorage_impact_protection",
  ],
  [
    "rack impact protection",
    "industrial_racks_doors",
    "supports_anchorage_impact_protection",
  ],
  [
    "industrial door restraint",
    "industrial_racks_doors",
    "supports_anchorage_impact_protection",
  ],
  [
    "transformer enclosure",
    "electrical_installations",
    "isolation_energy_release",
  ],
  [
    "generator bonding",
    "electrical_installations",
    "ignition_static_explosion_controls",
  ],
  [
    "battery ventilation",
    "electrical_installations",
    "emergency_access_discharge",
  ],
  [
    "panel exposed conductor",
    "electrical_installations",
    "isolation_energy_release",
  ],
  ["pump flange leak", "pressure_equipment", "containment_integrity"],
  ["valve packing leak", "pressure_equipment", "containment_integrity"],
  [
    "manifold unsupported",
    "pressure_equipment",
    "supports_anchorage_impact_protection",
  ],
  [
    "steam line insulation damage",
    "pressure_equipment",
    "pressure_vacuum_integrity",
  ],
  ["refrigeration pipe leak", "pressure_equipment", "containment_integrity"],
  [
    "gas cylinder restraint",
    "pressure_equipment",
    "supports_anchorage_impact_protection",
  ],
  ["silo deformation", "pressure_equipment", "pressure_vacuum_integrity"],
  ["reactor sight glass", "pressure_equipment", "instrumentation_indication"],
  [
    "secondary drain open",
    "pressure_equipment",
    "secondary_containment_drainage",
  ],
  [
    "fuel transfer coupling",
    "pressure_equipment",
    "transfer_connections_hoses",
  ],
  [
    "chemical label mismatch",
    "pressure_equipment",
    "material_compatibility_reaction",
  ],
  [
    "emergency isolation access",
    "pressure_equipment",
    "emergency_access_discharge",
  ],
  ["line breaking setup", "pressure_equipment", "isolation_energy_release"],
  [
    "pressure vessel identity plate",
    "pressure_equipment",
    "equipment_process_identity",
  ],
  ["relief valve isolation", "pressure_equipment", "overpressure_relief_path"],
  [
    "flammable ignition source",
    "pressure_equipment",
    "ignition_static_explosion_controls",
  ],
  [
    "tank vehicle impact",
    "pressure_equipment",
    "supports_anchorage_impact_protection",
  ],
  [
    "process discharge walkway",
    "pressure_equipment",
    "emergency_access_discharge",
  ],
];

const QUALITY_SCENARIOS: Array<{
  name: string;
  language: "tr" | "en";
  group: EquipmentDepthGroup;
  check: ProcessSafetyCheckKey;
}> = QUALITY_SCENARIO_TUPLES.map(([name, group, check], index) => ({
  name,
  language: index < 25 ? "tr" : "en",
  group,
  check,
}));

Deno.test("expert-depth matrix covers fifty TR/EN process and equipment scenarios", () => {
  assertEquals(QUALITY_SCENARIOS.length, 50);
  assertEquals(
    QUALITY_SCENARIOS.filter((scenario) => scenario.language === "tr").length,
    25,
  );
  assertEquals(
    QUALITY_SCENARIOS.filter((scenario) => scenario.language === "en").length,
    25,
  );
  for (const scenario of QUALITY_SCENARIOS) {
    assert(scenario.name.length > 3);
    assert(PROCESS_SAFETY_CHECK_KEYS.includes(scenario.check));
    assert(PROCESS_SAFETY_LAYER_MAP[scenario.check].length > 0);
    assert(scenario.group.length > 0);
  }
});
