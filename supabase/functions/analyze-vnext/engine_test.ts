import {
  assert,
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type HazardFactV3,
  MODULE_IDS,
  PHOTO_ANALYSIS_JSON_SCHEMA,
  type PhotoAnalysisV3,
} from "./contracts.ts";
import {
  buildEngineProduct,
  constrainTargetedFacts,
  constrainTargetedFactsWithTrace,
  EQUIPMENT_GROUP_CODES,
  evidenceRejectionReason,
  FINDING_CATEGORY_CODES,
  FINDING_TAXONOMY_VERSION,
  parsePhotoAnalysisV3,
  parsePhotoAnalysisV3WithSalvage,
  selectTargetedDecision,
  selectTargetedSignal,
  targetedSourceFacts,
  targetedSourceSignals,
} from "./engine.ts";

function fact(overrides: Partial<HazardFactV3> = {}): HazardFactV3 {
  return {
    fact_id: "pin-1",
    photo_index: 1,
    assessment_basis: "observed_nonconformity",
    evidence: {
      normalized_region: {
        x: 0.1,
        y: 0.2,
        width: 0.2,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Bağlantı kulağındaki pim ucunda segman bulunmuyor ve pim dışa kaymış",
      ],
    },
    entity: {
      entity_ref: "lift-arm-a",
      equipment_family: "Kaldırma bağlantısı",
      component: "Pim ve segman",
      identity_basis: "sarı kol üzerindeki sol bağlantı kulağı",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: "retainer_missing_pin_displaced",
      short_text: "Segman eksik ve pim dışa kaymış",
    },
    mechanism_code: "mechanical_separation_release",
    hazard_mechanism: "Bağlantı piminin çıkmasıyla yük yolunun ayrılması",
    energy_source: "Yerçekimi ve mekanik yük",
    barrier_state: "absent_or_failed_event_direct",
    initiating_event_state: "Yük veya titreşim altında pim ilerleyebilir",
    credible_event_path:
      "Pim çıkar, bağlantı ayrılır ve hareketli/yüklü parça çalışana çarpar",
    exposed_entity: "Operatör ve yakın çalışanlar",
    technical_assessment: {
      observation_narrative:
        "Kaldırma bağlantısındaki pim ucunda açık segman kanalı görülmekte ve pim bağlantı kulağından dışa doğru kaymış durumdadır.",
      technical_significance:
        "Segman, pimin eksenel hareketini sınırlayan mekanik tutucudur. Tutucunun bulunmaması ve pimin dışa kayması, yük aktarım bağlantısının ilerleyici biçimde ayrılmasına neden olabilir.",
      root_cause_mode: "probable_factor",
      root_cause_text:
        "Muhtemel temel etken, pim tutucusunun uygun şekilde takılmaması veya bağlantı üzerindeki titreşim ve yük etkisiyle yerinden ayrılmasıdır.",
    },
    consequence_class: "single_fatality",
    frequency_basis: "missing_invalid_fallback",
    verification: { model_required: false, reason_code: "" },
    confidence: {
      entity: "high",
      condition: "high",
      localization: "high",
      mechanism: "high",
    },
    depth_tags: ["pin", "retainer", "load_path"],
    control_intents: [{
      action_code: "secure_connection",
      target: "Pim ve segman",
      priority: "immediate",
    }],
    ...overrides,
  };
}

function output(photoIndex: number, facts: HazardFactV3[]): PhotoAnalysisV3 {
  return {
    scene_inventory: [{
      entity_ref: `equipment-${photoIndex}`,
      equipment_family: "Kaldırma ekipmanı",
      component: "Bağlantı",
      visible_condition_summary: "Bağlantı bileşenleri görünür",
    }],
    module_audit: MODULE_IDS.map((module_id) => ({
      module_id,
      entity_refs: [],
      status: "scanned_no_positive_evidence" as const,
    })),
    mandatory_module_outcomes: [],
    sector_context_evidence: [],
    hazard_facts: facts,
    inspection_signals: [],
  };
}

function photoResult(photoIndex: number, facts: HazardFactV3[]) {
  return {
    photoID: null,
    photoIndex,
    storagePath: `u/a/photo_${photoIndex}.jpg`,
    provider: "gemini",
    model: "gemini-2.5-flash",
    output: output(photoIndex, facts),
  };
}

Deno.test("HazardFactV3 parser accepts sparse module audits and completes them server-side", () => {
  const valid = output(1, [fact()]);
  assertEquals(parsePhotoAnalysisV3(valid, 1).module_audit.length, 20);
  const sparse = parsePhotoAnalysisV3WithSalvage({
    ...valid,
    module_audit: [valid.module_audit[0]],
  }, 1);
  assertEquals(sparse.module_audit.length, 20);
  assertEquals(sparse.module_audit[0], valid.module_audit[0]);
  assertEquals(sparse.module_audit[1].status, "not_applicable");
  assertEquals(sparse._schema_diagnostics_v1?.salvaged, false);
  assertEquals(sparse._schema_diagnostics_v1?.missing_module_ids.length, 19);
  assert(
    sparse._schema_diagnostics_v1?.reason_codes.includes(
      "module_audit_server_defaulted",
    ),
  );
});

Deno.test("v3.5 scanned module ids reconstruct legacy audit without provider prose", () => {
  const legacy = output(1, [fact()]) as unknown as Record<string, unknown>;
  delete legacy.module_audit;
  legacy.scanned_module_ids = [...MODULE_IDS];
  const parsed = parsePhotoAnalysisV3WithSalvage(legacy, 1);
  assertEquals(parsed.module_audit.length, MODULE_IDS.length);
  assertEquals(parsed._schema_diagnostics_v1?.missing_module_ids, []);
  assertEquals(
    parsed.module_audit.find((item) =>
      item.module_id === "structural_mechanical_integrity"
    )?.status,
    "positive_evidence",
  );
  assertEquals(
    parsed.module_audit.find((item) => item.module_id === "electrical_safety")
      ?.status,
    "scanned_no_positive_evidence",
  );
});

Deno.test("missing mechanism_code is conservatively inferred only by salvage", () => {
  const raw = output(1, [fact()]) as unknown as Record<string, unknown>;
  const rawFacts = raw.hazard_facts as Array<Record<string, unknown>>;
  delete rawFacts[0].mechanism_code;
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 1);
  assertEquals(
    salvaged.hazard_facts[0].mechanism_code,
    "mechanical_separation_release",
  );
  assertEquals(salvaged._schema_diagnostics_v1?.salvaged, true);
  assert(
    salvaged._schema_diagnostics_v1?.reason_codes.includes(
      "mechanism_code_inferred",
    ),
  );
});

Deno.test("pre-v3.2 checkpoints salvage missing technical assessment safely", () => {
  const raw = output(1, [fact()]) as unknown as Record<string, unknown>;
  const rawFacts = raw.hazard_facts as Array<Record<string, unknown>>;
  delete rawFacts[0].technical_assessment;
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 1);
  assertEquals(
    salvaged.hazard_facts[0].technical_assessment.root_cause_mode,
    "not_determinable",
  );
  assert(
    salvaged._schema_diagnostics_v1?.reason_codes.includes(
      "technical_assessment_defaulted",
    ),
  );
});

Deno.test("schema salvage preserves valid facts and reports invalid siblings", () => {
  const raw = output(1, [fact()]) as unknown as Record<string, unknown>;
  raw.module_audit = (raw.module_audit as unknown[]).slice(1);
  raw.hazard_facts = [...(raw.hazard_facts as unknown[]), { invalid: true }];
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 1);
  assertEquals(salvaged.hazard_facts.length, 1);
  assertEquals(salvaged._schema_diagnostics_v1?.salvaged, true);
  assertEquals(salvaged._schema_diagnostics_v1?.raw_fact_count, 2);
  assertEquals(salvaged._schema_diagnostics_v1?.invalid_fact_count, 1);
  assertEquals(salvaged._schema_diagnostics_v1?.missing_module_ids.length, 1);
  assert(
    salvaged._schema_diagnostics_v1?.reason_codes.includes("invalid_record"),
  );
  const resumed = parsePhotoAnalysisV3WithSalvage(salvaged, 1);
  assertEquals(resumed._schema_diagnostics_v1?.salvaged, true);
  assertEquals(resumed._schema_diagnostics_v1?.invalid_fact_count, 1);
});

Deno.test("schema salvage rebinds provider photo index to the trusted photo call", () => {
  const raw = output(3, [{ ...fact(), photo_index: 1 }]);
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 3);
  assertEquals(salvaged.hazard_facts.length, 1);
  assertEquals(salvaged.hazard_facts[0].photo_index, 3);
  assert(
    salvaged._schema_diagnostics_v1?.reason_codes.includes(
      "fact_photo_index_rebound",
    ),
  );
});

Deno.test("inspection signal IDs are namespaced by photo and signal order", () => {
  const signal = {
    signal_id: "signal_1",
    photo_index: 1,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: ["Hortum yüzeyinde yerel aşınma izi görülüyor"],
    potential_consequence_class: "serious_reversible" as const,
    reason_code: "hose_surface_detail_requires_reinspection",
  };
  const first = parsePhotoAnalysisV3({
    ...output(1, []),
    inspection_signals: [signal],
  }, 1);
  const second = parsePhotoAnalysisV3({
    ...output(2, []),
    inspection_signals: [{ ...signal, photo_index: 2 }],
  }, 2);

  assertEquals(first.inspection_signals[0].signal_id, "p1:s1:signal_1");
  assertEquals(second.inspection_signals[0].signal_id, "p2:s1:signal_1");

  const product = buildEngineProduct(
    [{
      ...photoResult(1, []),
      output: first,
    }, {
      ...photoResult(2, []),
      output: second,
    }],
    "tr",
    "plus",
  );
  assertEquals(
    product.inspectionSignals.map((item) => item.signal_id),
    ["p1:s1:signal_1", "p2:s1:signal_1"],
  );
  assertEquals(
    new Set(product.inspectionSignals.map((item) => item.signal_id)).size,
    2,
  );
});

Deno.test("schema salvage clips provider evidence regions to image bounds", () => {
  const raw = output(3, [{
    ...fact(),
    photo_index: 3,
    evidence: {
      ...fact().evidence,
      normalized_region: {
        x: 0.72,
        y: 0.81,
        width: 0.55,
        height: 0.42,
        is_global: false,
      },
    },
  }]);
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 3);
  assertEquals(salvaged.hazard_facts.length, 1);
  assertEquals(
    Math.round(
      salvaged.hazard_facts[0].evidence.normalized_region.width * 100,
    ),
    28,
  );
  assertEquals(
    Math.round(
      salvaged.hazard_facts[0].evidence.normalized_region.height * 100,
    ),
    19,
  );
  assert(
    salvaged._schema_diagnostics_v1?.reason_codes.includes(
      "evidence_region_clipped",
    ),
  );
});

Deno.test("inventory safety claims are removed from strict and salvaged outputs", () => {
  const raw = output(1, []) as unknown as Record<string, unknown>;
  raw.scene_inventory = [{
    entity_ref: "pipe-1",
    equipment_family: "process piping",
    component: "pipe connection",
    visible_condition_summary: "Boru bağlantısı sağlam ve iyi durumda.",
  }, {
    entity_ref: "rope-1",
    equipment_family: "overhead_crane",
    component: "wire_rope",
    visible_condition_summary:
      "Çelik halatın genel durumu iyi görünmektedir, belirgin bir aşınma veya kopuk tel seçilememektedir.",
  }, {
    entity_ref: "bucket-1",
    equipment_family: "mobile_equipment",
    component: "bucket",
    visible_condition_summary:
      "Kovanın yapısal bütünlüğü iyi görünmektedir, çatlak detayları net değildir.",
  }, {
    entity_ref: "rope-latest",
    equipment_family: "overhead_crane",
    component: "wire_rope",
    visible_condition_summary:
      "Çelik halatlarda belirgin bir hasar veya aşınma izi seçilemiyor.",
  }, {
    entity_ref: "tank-motor-latest",
    equipment_family: "tank_top_drive",
    component: "motor_guard",
    visible_condition_summary:
      "Motorun dış koruyucu kapakları mevcut görünüyor.",
  }, {
    entity_ref: "floor-latest",
    equipment_family: "work_area",
    component: "floor",
    visible_condition_summary:
      "Zemin genel olarak temiz ancak bazı bölgelerde dağınık malzemeler bulunuyor.",
  }, {
    entity_ref: "rack-latest",
    equipment_family: "storage_rack",
    component: "rack",
    visible_condition_summary:
      "Rafın genel yapısal bütünlüğü iyi ancak üst seviyede dengesiz kutular bulunuyor.",
  }, {
    entity_ref: "boom-latest",
    equipment_family: "mobile_equipment",
    component: "boom",
    visible_condition_summary:
      "Bomda belirgin bir hasar veya deformasyon görülmemektedir.",
  }];
  const strict = parsePhotoAnalysisV3(raw, 1);
  assertFalse(
    strict.scene_inventory[0].visible_condition_summary.includes("sağlam"),
  );
  assertStringIncludes(
    strict.scene_inventory[0].visible_condition_summary,
    "uygunluk sonucu oluşturmaz",
  );
  assert(
    [0, 1, 2, 3, 4, 7].every((index) =>
      strict.scene_inventory[index].visible_condition_summary.includes(
        "uygunluk sonucu oluşturmaz",
      )
    ),
  );
  assertStringIncludes(
    strict.scene_inventory[5].visible_condition_summary,
    "bazı bölgelerde dağınık malzemeler",
  );
  assertFalse(
    strict.scene_inventory[5].visible_condition_summary.includes(
      "genel olarak temiz",
    ),
  );
  assertStringIncludes(
    strict.scene_inventory[6].visible_condition_summary,
    "üst seviyede dengesiz kutular",
  );
  assertFalse(
    strict.scene_inventory[6].visible_condition_summary.includes(
      "yapısal bütünlüğü iyi",
    ),
  );

  raw.module_audit = (raw.module_audit as unknown[]).slice(1);
  const salvaged = parsePhotoAnalysisV3WithSalvage(raw, 1);
  assertFalse(
    salvaged.scene_inventory[0].visible_condition_summary.includes(
      "iyi durumda",
    ),
  );
});

Deno.test("absence-only document uncertainty is rejected even with fatal severity", () => {
  const absence = fact({
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Periyodik kontrol belgesi fotoğrafta görünmüyor"],
    },
    observed_condition: {
      condition_code: "inspection_record_unknown",
      short_text: "Kontrol kaydı bilinmiyor",
    },
    credible_event_path: "Belge yokluğu nedeniyle ekipman arızalanabilir",
    consequence_class: "multiple_fatality_major_environmental",
  });
  assertEquals(evidenceRejectionReason(absence), "absence_only_claim");
  const product = buildEngineProduct([photoResult(1, [absence])], "tr", "plus");
  assertEquals(product.findings.length, 0);
});

Deno.test("semantic scoring always emits numeric F fallback and promotes verification", () => {
  const product = buildEngineProduct([photoResult(1, [fact()])], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const finding = product.findings[0];
  assertEquals(finding.fk_probability, 6);
  assertEquals(finding.fk_frequency, 1);
  assertEquals(finding.fk_severity, 40);
  assertEquals(finding.fk_band, "high");
  assertEquals(finding.m5_probability, 4);
  assertEquals(finding.m5_severity, 5);
  assertEquals(finding.m5_band, "critical");
  assertEquals(finding.needs_field_verification, true);
  assertEquals(finding.residual_fk_probability, 6);
  assert(
    (product.factLineage[0].reason_codes as string[]).includes(
      "fk_frequency_missing_fallback",
    ),
  );
  assert(
    (product.factLineage[0].reason_codes as string[]).includes(
      "residual_not_reduced_without_control_confirmation",
    ),
  );
});

Deno.test("score policy adjustments do not independently require field verification", () => {
  const sharpEdge = fact({
    fact_id: "sharp-edge-policy-cap",
    entity: {
      ...fact().entity,
      entity_ref: "sheet-edge-1",
      equipment_family: "metal fabrication workpiece",
      component: "projecting sheet edge",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Keskin sac kenarı çalışma alanına doğru çıkıntı yapıyor",
      ],
    },
    observed_condition: {
      condition_code: "PROJECTING_SHARP_EDGE",
      short_text: "Çalışma alanına uzanan keskin sac kenarı",
    },
    mechanism_code: "sharp_edge_contact",
    hazard_mechanism: "Keskin kenarla doğrudan temas",
    credible_event_path: "Çalışan keskin sac kenarına temas ederek kesilebilir",
    consequence_class: "single_fatality",
    frequency_basis: "sector_scene_proxy",
  });
  const product = buildEngineProduct(
    [photoResult(1, [sharpEdge])],
    "tr",
    "plus",
  );
  const finding = product.findings[0];
  assertEquals(finding.fk_severity, 7);
  assertEquals(finding.score_policy_adjusted, true);
  assertEquals(finding.score_policy_reason_codes, [
    "severity_capped_by_mechanism_policy",
  ]);
  assertEquals(finding.needs_field_verification, false);
  assertEquals(finding.field_verification_reason_codes, []);
  assertEquals(
    (product.qualityTrace.verification_summary as Record<string, unknown>)
      .score_policy_adjusted_count,
    1,
  );
  assertEquals(
    (product.qualityTrace.verification_summary as Record<string, unknown>)
      .required_count,
    0,
  );
});

Deno.test("finding taxonomy uses closed stable codes and a stable display group", () => {
  const product = buildEngineProduct([photoResult(1, [fact()])], "tr", "plus");
  const finding = product.findings[0];
  assertEquals(finding.taxonomy_version, FINDING_TAXONOMY_VERSION);
  assertEquals(finding.category_code, "lifting_safety");
  assertEquals(finding.equipment_group_code, "lifting_equipment");
  assertEquals(finding.assessment_section, "observed_risk");
  assertEquals(finding.display_group, "lifting_equipment");
  assert(
    new Set<string>(FINDING_CATEGORY_CODES).has(String(finding.category_code)),
  );
  assert(
    new Set<string>(EQUIPMENT_GROUP_CODES).has(
      String(finding.equipment_group_code),
    ),
  );
  const snapshot = finding.ai_original_snapshot as Record<string, unknown>;
  assertEquals(
    (snapshot.taxonomy as Record<string, unknown>).version,
    FINDING_TAXONOMY_VERSION,
  );
  assertEquals(
    product.qualityTrace.finding_taxonomy_version,
    FINDING_TAXONOMY_VERSION,
  );
});

Deno.test("provider schema excludes still-photo frequency claims that cannot be verified", () => {
  const schema = JSON.stringify(PHOTO_ANALYSIS_JSON_SCHEMA);
  assertFalse(schema.includes("continuous_visible_work"));
  assertFalse(schema.includes("daily_repeated_workstation"));
  assertStringIncludes(schema, "active_single_exposure");
  assertStringIncludes(schema, "sector_scene_proxy");
});

Deno.test("cross-photo dedup merges only high-confidence identical identity", () => {
  const second = fact({
    fact_id: "pin-2",
    photo_index: 2,
    evidence: {
      normalized_region: {
        x: 0.5,
        y: 0.4,
        width: 0.2,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Aynı bağlantının diğer açısından boş segman kanalı ve dışa kaymış pim görülüyor",
      ],
    },
  });
  const product = buildEngineProduct(
    [
      photoResult(1, [fact()]),
      photoResult(2, [second]),
    ],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(product.findings[0].source_photo_indices, [1, 2]);
  assertEquals((product.qualityTrace.merge_ledger as unknown[]).length, 1);
});

Deno.test("different physical conditions on the same equipment stay atomic", () => {
  const sharp = fact({
    fact_id: "sharp-1",
    entity: { ...fact().entity, component: "Keskin çıkıntı" },
    observed_condition: {
      condition_code: "sharp_projection",
      short_text: "Korunmamış keskin çıkıntı",
    },
    hazard_mechanism: "Temas halinde kesilme veya delinme",
    credible_event_path: "Çalışan geçişte çıkıntıya temas ederek kesilir",
    consequence_class: "serious_reversible",
    frequency_basis: "active_single_exposure",
  });
  const product = buildEngineProduct(
    [
      photoResult(1, [fact(), sharp]),
    ],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 2);
});

Deno.test("same-photo dedup keeps identical conditions on distinct physical entities", () => {
  const hookA = fact({
    fact_id: "hook-a",
    entity: {
      ...fact().entity,
      entity_ref: "left-hook",
      equipment_family: "lifting hook",
      component: "hook safety latch",
    },
  });
  const hookB = fact({
    // Providers occasionally repeat fact_id across distinct objects. The
    // deterministic trace layer must still preserve both physical findings.
    fact_id: "hook-a",
    entity: {
      ...fact().entity,
      entity_ref: "right-hook",
      equipment_family: "lifting hook",
      component: "hook safety latch",
    },
  });
  const duplicateHookA = fact({
    fact_id: "hook-a-duplicate",
    entity: { ...hookA.entity },
  });
  const product = buildEngineProduct(
    [photoResult(1, [hookA, hookB, duplicateHookA])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 2);
  assertEquals(
    new Set(product.factLineage.map((entry) => entry.fact_trace_id)).size,
    2,
  );
  assert(
    product.factLineage.some((entry) => entry.fact_trace_id === "p1:hook-a#2"),
  );
  assertEquals(
    (product.qualityTrace.rejection_ledger as Array<Record<string, unknown>>)
      .filter((entry) => entry.reason_code === "duplicate_exact").length,
    1,
  );
});

Deno.test("equivalent vent conditions on matching equipment merge within one photo", () => {
  const ventA = fact({
    fact_id: "vent-a",
    entity: {
      ...fact().entity,
      entity_ref: "tank-1-vent",
      equipment_family: "process_piping",
      component: "vent_pipe",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Birinci havalık ağzında kırık ve hasarlı koruyucu tel",
      ],
    },
    observed_condition: {
      condition_code: "damaged_vent_opening_protection",
      short_text: "Havalık ağzı korumasında görünür hasar",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Havalık hattına yabancı cisim girişi",
    credible_event_path:
      "Yabancı cisim hatta girerek proses bütünlüğünü bozabilir.",
    consequence_class: "serious_reversible",
  });
  const ventB = {
    ...ventA,
    fact_id: "vent-b",
    entity: { ...ventA.entity, entity_ref: "tank-2-vent" },
    evidence: {
      ...ventA.evidence,
      affirmative_cues: [
        "İkinci havalık ağzında kırık ve hasarlı koruyucu tel",
      ],
    },
  };
  const product = buildEngineProduct(
    [photoResult(1, [ventA, ventB])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    (product.findings[0].source_photo_observations as unknown[]).length,
    2,
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) => entry.reason_code === "same_photo_equivalent_condition",
    ),
  );
});

Deno.test("equivalent hook-latch findings on distinct equipment merge without public addresses", () => {
  const upper = fact({
    fact_id: "upper-hook-latch",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst vinç kancasında mandal bağlantı noktası boş görülüyor",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "CRN-001-HK-001",
      equipment_family: "overhead_crane",
      component: "hook_latch",
      identity_basis: "üst vinç kancası",
    },
    observed_condition: {
      condition_code: "hook_latch_missing",
      short_text: "Kanca emniyet mandalı eksikliği",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Yükün kancadan istem dışı ayrılması",
    credible_event_path: "Yük kancadan ayrılarak aşağıdaki çalışana çarpabilir",
    control_intents: [{
      action_code: "replace_component",
      target: "CRN-001-HK-001",
      priority: "immediate",
    }],
  });
  const lower: HazardFactV3 = {
    ...upper,
    fact_id: "lower-hook-latch",
    evidence: {
      normalized_region: {
        ...upper.evidence.normalized_region,
        x: 0.6,
      },
      affirmative_cues: [
        "Alt vinç kancasında mandal bağlantı noktası boş görülüyor",
      ],
    },
    entity: {
      ...upper.entity,
      entity_ref: "CRN-002-HK-001",
      identity_basis: "alt vinç kancası",
    },
  };
  const product = buildEngineProduct(
    [photoResult(1, [upper, lower])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    product.findings[0].title,
    "Köprü vinç kancalarında emniyet mandalı eksikliği",
  );
  assertFalse(/numaralı|üstteki|alttaki/iu.test(product.findings[0].title));
  assertEquals(
    (product.findings[0].source_photo_observations as unknown[]).length,
    2,
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) =>
        entry.reason_code === "same_photo_equivalent_hook_latch_condition",
    ),
  );
});

Deno.test("targeted facts are namespaced away from primary provider fact IDs", () => {
  const targetedSharp = fact({
    fact_id: "pin-1",
    entity: {
      ...fact().entity,
      entity_ref: "sharp-edge-a",
      component: "Keskin çıkıntı",
    },
    observed_condition: {
      condition_code: "sharp_projection",
      short_text: "Korunmamış keskin çıkıntı",
    },
    mechanism_code: "sharp_edge_contact",
    hazard_mechanism: "Keskin yüzeyle temas",
    credible_event_path: "Çalışan keskin yüzeye temas ederek kesilebilir",
    consequence_class: "serious_reversible",
  });
  const product = buildEngineProduct(
    [photoResult(1, [fact()])],
    "tr",
    "plus",
    [targetedSharp],
  );
  assertEquals(product.findings.length, 2);
  assertEquals(
    product.factLineage.map((entry) => entry.fact_trace_id),
    ["p1:pin-1", "targeted:p1:pin-1"],
  );
});

Deno.test("targeted reinspection cannot add a duplicate of a primary finding", () => {
  const primary = fact({
    fact_id: "slope-primary",
    entity: {
      ...fact().entity,
      entity_ref: "ground-1",
      equipment_family: "site_infrastructure",
      component: "ground_surface",
    },
    evidence: {
      normalized_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: ["Gevşek kazı şevi ve kopabilecek kaya parçaları"],
    },
    observed_condition: {
      condition_code: "SLOPE_INSTABILITY",
      short_text: "Kazı şevinde gevşek malzeme",
    },
    mechanism_code: "excavation_collapse_rockfall",
    hazard_mechanism: "Şevden kaya ve toprak düşmesi",
  });
  const targeted = fact({
    ...primary,
    fact_id: "slope-targeted",
    evidence: {
      normalized_region: {
        x: 0.4,
        y: 0.6,
        width: 0.5,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: ["Kazı bölgesindeki gevşek taş ve toprak"],
    },
  });
  const product = buildEngineProduct(
    [photoResult(1, [primary])],
    "tr",
    "plus",
    [targeted],
  );
  assertEquals(product.findings.length, 1);
  assert(
    (product.qualityTrace.rejection_ledger as Array<Record<string, unknown>>)
      .some((entry) => entry.reason_code === "targeted_duplicate_primary"),
  );
  const targetedStage = (product.qualityTrace.stages as Array<
    Record<string, unknown>
  >).find((stage) => stage.name === "targeted_added_fact");
  assertEquals(targetedStage?.delta_from_previous, 0);
});

Deno.test("targeted output is constrained to the selected fact entity and mechanism", () => {
  const uncertainPin = fact({
    fact_id: "pin-uncertain",
    observed_condition: {
      condition_code: "PIN_RETAINER_UNCLEAR",
      short_text: "Pim tutucu ayrıntısı net değil",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Pim ucunda gevşeklik izi var ancak tutucu net değil"],
    },
  });
  const source = photoResult(1, [uncertainPin]);
  const signal = selectTargetedSignal([source]);
  assert(signal);
  const unrelatedSlope = fact({
    fact_id: "wandered-slope",
    entity: {
      ...fact().entity,
      entity_ref: "ground-1",
      equipment_family: "site_infrastructure",
      component: "ground_surface",
    },
    mechanism_code: "excavation_collapse_rockfall",
    observed_condition: {
      condition_code: "SLOPE_INSTABILITY",
      short_text: "Kazı şevinde gevşek malzeme",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Gevşek taş ve toprak"],
    },
  });
  assertEquals(
    constrainTargetedFacts([source], signal, [unrelatedSlope]),
    [],
  );
});

Deno.test("uncertainty without a positive anomaly does not spend targeted tokens", () => {
  const unresolved = fact({
    fact_id: "pin-resolution-only",
    observed_condition: {
      condition_code: "PIN_RETAINER_UNCLEAR",
      short_text: "Pim tutucu ayrıntısı net değil",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Pim yerinde görünüyor ancak segman ayrıntısı çözünürlük nedeniyle seçilemiyor",
      ],
    },
  });
  assertEquals(selectTargetedSignal([photoResult(1, [unresolved])]), null);
});

Deno.test("latest-analysis machine tags never leak into public title or description", () => {
  const hose = fact({
    fact_id: "HF001",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "hidrolik_hortumlar",
        "sürtünme_izleri",
        "aşınma_belirtisi",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "iş_makinesi",
      component: "hidrolik_hortum",
    },
    observed_condition: {
      condition_code: "hose_routing_abrasion_risk",
      short_text: "Hidrolik hortumların aşınma riski taşıyan güzergahı",
    },
    hazard_mechanism:
      "Sürtünme nedeniyle hortum dış katmanında aşınma ve basınç kaybı.",
    credible_event_path:
      "Aşınan hortum patlar ve yüksek basınçlı akışkan çevreye fışkırır.",
    technical_assessment: {
      observation_narrative:
        "Bom boyunca ilerleyen hidrolik hortumun hareketli mafsala yakın geçtiği ve dış yüzeyinde yerel sürtünme izleri bulunduğu görülmektedir.",
      technical_significance:
        "Hareketli mafsala temas eden hortum, tekrarlı hareket sırasında dış katmanını kaybedebilir. Kesit zayıfladığında basınçlı akışkan salımı ve kontrol kaybı oluşabilir.",
      root_cause_mode: "probable_factor",
      root_cause_text:
        "Muhtemel temel etken, hortum güzergâhı ve destek aralıklarının hareketli mafsaldan yeterli ayrımı sağlamamasıdır.",
    },
    consequence_class: "serious_reversible",
    frequency_basis: "continuous_visible_work",
  });
  const product = buildEngineProduct(
    [photoResult(1, [hose])],
    "tr",
    "plus",
    [],
    {
      safetyProfileID: "tr-tr-current-v1",
      regulatoryReferencePolicy: "tr_current",
      structuredRegulatoryReferencesEnabled: true,
    },
  );
  const finding = product.findings[0];
  assertEquals(
    finding.title,
    "Hidrolik hortum güzergâhında sürtünme ve aşınma riski",
  );
  assertFalse(String(finding.title).includes("_"));
  assertFalse(String(finding.title).startsWith("hidrolik hortum:"));
  assertFalse(String(finding.description).includes("_"));
  assertFalse(String(finding.description).includes("hidrolik hortumlar;"));
  assertFalse(String(finding.description).includes(".."));
  assertFalse(
    String(finding.description).includes("Fotoğrafta gözlenen koşul:"),
  );
  assertFalse(String(finding.description).includes("Risk mekanizması:"));
  assertFalse(String(finding.description).includes("Olası olay:"));
  assertStringIncludes(String(finding.description), "hareketli mafsala yakın");
  assertStringIncludes(String(finding.description), "dış katmanını");
  assertStringIncludes(
    String(finding.description),
    "\n\nEtkilenebilecekler: Operatör ve yakın çalışanlar.",
  );
  assertEquals((finding.recommended_measures as unknown[]).length, 2);
  assertStringIncludes(String(finding.root_cause_text), "Muhtemel temel etken");
  assertFalse(String(finding.root_cause_text).includes("saha incelemesiyle"));
  assertStringIncludes(
    String(finding.references_text),
    "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
  );
  assertEquals(finding.fk_frequency, 2);
  assert(
    (product.factLineage[0].reason_codes as string[]).includes(
      "fk_frequency_normalized_by_scene_policy",
    ),
  );
});

Deno.test("latest-analysis PPE visibility and unsupported retainer absence are rejected", () => {
  const missingPPE = fact({
    fact_id: "HF003",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "operatör",
        "gözlük_yok",
        "eldiven_yok",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "insan",
      component: "operatör",
    },
    observed_condition: {
      condition_code: "missing_ppe",
      short_text: "Operatörde gözlük ve eldiven görünmüyor.",
    },
  });
  const unsupportedRetainer = fact({
    fact_id: "HF002",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["kova_bağlantı_pimi", "emniyet_segmanı_eksikliği"],
    },
    observed_condition: {
      condition_code: "missing_retaining_pin",
      short_text: "Kova bağlantı piminde segman görünmüyor.",
    },
  });
  assertEquals(
    evidenceRejectionReason(missingPPE),
    "contextual_ppe_rejected",
  );
  assertEquals(
    evidenceRejectionReason(unsupportedRetainer),
    "absence_only_claim",
  );
});

Deno.test("hard-hat absence inside an enclosed machine cab is rejected", () => {
  const cabHardHat = fact({
    fact_id: "HF-004",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Operatör kabini içinde baretin takılı olmayıp koltukta veya konsolda durması.",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "personnel",
      component: "operator",
    },
    observed_condition: {
      condition_code: "ppe_not_worn",
      short_text: "Operatörün baretini takmaması",
    },
    hazard_mechanism: "Kapalı kabindeki operatörün baş koruyucu kullanmaması",
    credible_event_path:
      "Kabin içindeki operatör dışarıdaki bir cisimden etkilenebilir.",
  });
  assertEquals(
    evidenceRejectionReason(cabHardHat),
    "contextual_ppe_rejected",
  );
  const product = buildEngineProduct(
    [photoResult(1, [cabHardHat])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 0);
});

Deno.test("targeted reinspection requires a concrete visible anomaly", () => {
  const uncertainOutput = output(1, []);
  uncertainOutput.inspection_signals = [{
    signal_id: "IS-002",
    photo_index: 1,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: ["Belirsiz koruyucular, ayrıntılı inceleme gerekli"],
    potential_consequence_class: "serious_reversible",
    reason_code: "guard_details_unclear",
  }];
  const positiveOutput = output(2, []);
  positiveOutput.inspection_signals = [{
    signal_id: "IS-003",
    photo_index: 2,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: ["Hortum dış yüzeyinde yerel sürtünme ve aşınma izi"],
    potential_consequence_class: "serious_reversible",
    reason_code: "hose_surface_detail_requires_reinspection",
  }];
  const uncertain = {
    ...photoResult(1, []),
    output: uncertainOutput,
  };
  assertEquals(selectTargetedSignal([uncertain]), null);
  const positive = {
    ...photoResult(2, []),
    output: positiveOutput,
  };
  assertEquals(
    selectTargetedSignal([uncertain, positive])?.signal_id,
    "IS-003",
  );

  const routingOutput = output(3, []);
  routingOutput.inspection_signals = [{
    signal_id: "IS-004",
    photo_index: 3,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: [
      "Bom boyunca uzanan hortum güzergâhı hareketli mafsala yakın ilerliyor",
    ],
    potential_consequence_class: "serious_reversible",
    reason_code: "hose_routing_near_moving_joint",
  }];
  assertEquals(
    selectTargetedSignal([{
      ...photoResult(3, []),
      output: routingOutput,
    }])?.signal_id,
    "IS-004",
  );
});

Deno.test("unresolved scored facts are rejected without an uncertainty-only second call", () => {
  const uncertainHook = fact({
    fact_id: "hook-uncertain",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca ağzındaki mandal geometrisi net değil"],
    },
    entity: {
      ...fact().entity,
      equipment_family: "lifting hook",
      component: "hook safety latch",
    },
    observed_condition: {
      condition_code: "hook_latch_unclear",
      short_text: "Kanca emniyet mandalının durumu belirsiz",
    },
    consequence_class: "serious_reversible",
    verification: {
      model_required: true,
      reason_code: "latch_geometry_unclear",
    },
  });
  assertEquals(
    evidenceRejectionReason(uncertainHook),
    "uncertain_condition_requires_confirmation",
  );
  assertEquals(
    buildEngineProduct([photoResult(1, [uncertainHook])], "tr", "plus")
      .findings.length,
    0,
  );
  assertEquals(selectTargetedSignal([photoResult(1, [uncertainHook])]), null);
});

Deno.test("critical hook hardware with an explicitly empty pivot receives targeted reinspection", () => {
  const emptyHookPivot = fact({
    fact_id: "HF001",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "overhead-crane-hook-1",
      equipment_family: "overhead_crane",
      component: "hook_block",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Kanca ağzının açık olması",
        "Mandalın bağlı olduğu pivot noktasının boş görünmesi",
      ],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca emniyet mandalı eksik",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Yükün kanca ağzından ayrılması",
    credible_event_path: "Sapan kancadan çıkar ve yük aşağı düşer",
  });
  assertEquals(evidenceRejectionReason(emptyHookPivot), "absence_only_claim");
  const signal = selectTargetedSignal([photoResult(2, [emptyHookPivot])]);
  assertEquals(signal?.signal_id, "uncertain-fact:HF001");
  assertEquals(
    signal?.reason_code,
    "critical_hardware_absence_requires_geometry_confirmation",
  );

  const visibilityOnly = fact({
    fact_id: "HF002",
    photo_index: 2,
    entity: emptyHookPivot.entity,
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca emniyet mandalı fotoğrafta görünmüyor"],
    },
    observed_condition: emptyHookPivot.observed_condition,
    mechanism_code: "falling_object",
  });
  assertEquals(evidenceRejectionReason(visibilityOnly), "absence_only_claim");
  assertEquals(selectTargetedSignal([photoResult(2, [visibilityOnly])]), null);
});

Deno.test("high-confidence localized missing hook latch receives a bounded geometry check", () => {
  const missingLatch = fact({
    fact_id: "HL1_Missing",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "crane1_hook",
      equipment_family: "overhead_crane",
      component: "hook_block",
    },
    evidence: {
      normalized_region: {
        x: 0.1,
        y: 0.1,
        width: 0.2,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Kanca emniyet mandalının eksik olması",
        "Kanca ağzının engelsiz açık olması",
      ],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca emniyet mandalı eksik",
    },
    mechanism_code: "falling_object",
    verification: {
      model_required: true,
      reason_code: "critical_lifting_hardware_geometry_confirmation",
    },
  });
  assertEquals(evidenceRejectionReason(missingLatch), "absence_only_claim");
  assertEquals(
    selectTargetedSignal([photoResult(2, [missingLatch])])?.reason_code,
    "critical_hardware_absence_requires_geometry_confirmation",
  );
});

Deno.test("two equivalent hook candidates share one bounded targeted pass", () => {
  const base = fact({
    fact_id: "HL1_Missing",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "crane1_hook",
      equipment_family: "overhead_crane",
      component: "hook_block",
    },
    evidence: {
      normalized_region: {
        x: 0.1,
        y: 0.1,
        width: 0.2,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Kanca emniyet mandalının eksik olması ve kanca ağzının açık olması",
      ],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca emniyet mandalı eksik",
    },
    mechanism_code: "falling_object",
    verification: {
      model_required: true,
      reason_code: "critical_lifting_hardware_geometry_confirmation",
    },
  });
  const sibling = {
    ...base,
    fact_id: "HL2_Missing",
    entity: { ...base.entity, entity_ref: "crane2_hook" },
    evidence: {
      ...base.evidence,
      normalized_region: {
        x: 0.65,
        y: 0.1,
        width: 0.2,
        height: 0.2,
        is_global: false,
      },
    },
  } satisfies HazardFactV3;
  const source = photoResult(2, [base, sibling]);
  const signal = selectTargetedSignal([source]);
  assert(signal);
  const confirmed = [base, sibling].map((candidate) => ({
    ...candidate,
    evidence: {
      ...candidate.evidence,
      affirmative_cues: [
        "Mandal pivot yatağı boş ve bağlantı noktası açık görünüyor",
      ],
    },
    verification: { model_required: false, reason_code: "" },
  }));
  assertEquals(
    constrainTargetedFacts([source], signal, confirmed).map((item) =>
      item.fact_id
    ),
    ["HL1_Missing", "HL2_Missing"],
  );
});

Deno.test("two concrete hook signals share one bounded targeted pass", () => {
  const firstSignal = {
    signal_id: "HOOK-SIGNAL-1",
    photo_index: 2,
    evidence_region: {
      x: 0.45,
      y: 0.35,
      width: 0.05,
      height: 0.08,
      is_global: false,
    },
    affirmative_cues: [
      "Üst kanca emniyet mandalında deformasyon izi görülüyor",
    ],
    potential_consequence_class: "permanent_disability" as const,
    reason_code: "visual_ambiguity",
  };
  const secondSignal = {
    ...firstSignal,
    signal_id: "HOOK-SIGNAL-2",
    evidence_region: {
      x: 0.62,
      y: 0.56,
      width: 0.05,
      height: 0.08,
      is_global: false,
    },
    affirmative_cues: [
      "Alt kanca emniyet mandalında deformasyon izi görülüyor",
    ],
  };
  const source = photoResult(2, []);
  source.output.inspection_signals = [firstSignal, secondSignal];
  const signal = selectTargetedSignal([source]);
  assert(signal);
  assertEquals(
    targetedSourceSignals([source], signal).map((item) => item.signal_id),
    ["HOOK-SIGNAL-1", "HOOK-SIGNAL-2"],
  );
  const confirmed = [firstSignal, secondSignal].map((item, index) =>
    fact({
      fact_id: `CONFIRMED-HOOK-${index + 1}`,
      photo_index: 2,
      entity: {
        ...fact().entity,
        entity_ref: `crane_${index + 1}_hook`,
        equipment_family: "overhead_crane",
        component: "hook_safety_latch",
      },
      evidence: {
        normalized_region: item.evidence_region,
        affirmative_cues: [
          "Kanca emniyet mandalında kırık parça ve kapanmayı engelleyen deformasyon görülüyor",
        ],
      },
      observed_condition: {
        condition_code: "HOOK_LATCH_DAMAGED",
        short_text: "Kanca emniyet mandalında kırık ve deformasyon",
      },
      mechanism_code: "falling_object",
      hazard_mechanism: "Hasarlı mandal nedeniyle yük bağlantısının ayrılması",
      credible_event_path:
        "Sapan kancadan ayrılarak yükün düşmesine yol açabilir",
    })
  );
  assertEquals(
    constrainTargetedFacts([source], signal, confirmed).map((item) =>
      item.fact_id
    ),
    ["CONFIRMED-HOOK-1", "CONFIRMED-HOOK-2"],
  );
});

Deno.test("targeted pass rejects unresolved hook-latch alternatives", () => {
  const ambiguous = fact({
    fact_id: "HOOK-AMBIGUOUS-TARGETED",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "main_hoist_hook",
      equipment_family: "overhead_crane",
      component: "hook_safety_latch",
      identity_basis: "üst vinç kancası",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst vinç kancasının mandalı açık konumda veya eksik",
      ],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING_OR_OPEN",
      short_text: "Üst vinç kancası mandalı eksik veya açık",
    },
    mechanism_code: "falling_object",
  });
  assertEquals(
    evidenceRejectionReason(ambiguous),
    "uncertain_condition_requires_confirmation",
  );
  const source = photoResult(2, []);
  const signal = {
    signal_id: "HOOK-SIGNAL-AMBIGUOUS",
    photo_index: 2,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: ["Kanca mandalında deformasyon izi görülüyor"],
    potential_consequence_class: "permanent_disability" as const,
    reason_code: "visual_ambiguity",
  };
  source.output.inspection_signals = [signal];
  assertEquals(constrainTargetedFacts([source], signal, [ambiguous]), []);
});

Deno.test("latest two-hook pivot geometry is sent and accepted only by the targeted pass", () => {
  const first = fact({
    fact_id: "crane_1_hook_latch_missing",
    photo_index: 2,
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "crane_1_hook",
      equipment_family: "overhead_crane",
      component: "hook",
    },
    evidence: {
      normalized_region: {
        x: 0.47,
        y: 0.35,
        width: 0.03,
        height: 0.05,
        is_global: false,
      },
      affirmative_cues: [
        "Kanca ağzı açık ve mandalın pivot noktası boş görünüyor",
      ],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca emniyet mandalı eksik",
    },
    mechanism_code: "falling_object",
    consequence_class: "serious_reversible",
    verification: { model_required: false, reason_code: "" },
  });
  const second: HazardFactV3 = {
    ...first,
    fact_id: "crane_2_hook_latch_missing",
    entity: { ...first.entity, entity_ref: "crane_2_hook" },
    evidence: {
      ...first.evidence,
      normalized_region: {
        x: 0.53,
        y: 0.58,
        width: 0.03,
        height: 0.05,
        is_global: false,
      },
    },
  };
  const source = photoResult(2, [first, second]);
  assertEquals(evidenceRejectionReason(first), "absence_only_claim");
  assertEquals(evidenceRejectionReason(second), "absence_only_claim");
  const signal = selectTargetedSignal([source]);
  assert(signal);
  assertEquals(
    targetedSourceFacts([source], signal).map((item) => item.fact_id),
    ["crane_1_hook_latch_missing", "crane_2_hook_latch_missing"],
  );

  const targeted = [first, second].map((candidate) => ({
    ...candidate,
    evidence: {
      ...candidate.evidence,
      affirmative_cues: [
        "Mandalın pivot noktası boş ve kanca ağzı engelsiz açık görülüyor",
      ],
    },
  }));
  assertEquals(evidenceRejectionReason(targeted[0]), "absence_only_claim");
  assertEquals(
    constrainTargetedFacts([source], signal, targeted).map((item) =>
      item.fact_id
    ),
    ["crane_1_hook_latch_missing", "crane_2_hook_latch_missing"],
  );
  const product = buildEngineProduct([source], "tr", "plus", targeted);
  assertEquals(product.findings.length, 1);
  assert(
    product.factLineage.every((entry) =>
      String(entry.fact_trace_id).startsWith("targeted:")
    ),
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) =>
        entry.reason_code === "same_photo_equivalent_hook_latch_condition",
    ),
  );
});

Deno.test("latest live hook findings merge without ordinal addresses or generic root-cause filler", () => {
  const liveHook = (suffix: number): HazardFactV3 =>
    fact({
      fact_id: `HF-LIVE-HOOK-${suffix}`,
      photo_index: 2,
      assessment_basis: "observed_nonconformity",
      entity: {
        ...fact().entity,
        entity_ref: `hook_block_${suffix}`,
        equipment_family: "overhead_crane",
        component: "hook_safety_latch",
        identity_basis: `${suffix} numaralı vinç kancası`,
      },
      evidence: {
        normalized_region: {
          x: 0.42 + suffix * 0.05,
          y: 0.32 + suffix * 0.18,
          width: 0.05,
          height: 0.08,
          is_global: false,
        },
        affirmative_cues: [
          `Fotoğraf 2'de ${suffix} numaralı kancanın emniyet mandalı açık konumdadır`,
        ],
      },
      observed_condition: {
        condition_code: "LIF-001",
        short_text: "Kanca emniyet mandalının açık kalması",
      },
      mechanism_code: "falling_object",
      hazard_mechanism:
        "Açık mandal nedeniyle yük bağlantısının kanca ağzından ayrılması",
      credible_event_path:
        "Sapan kancadan ayrılarak yükün kontrolsüz biçimde düşmesine yol açabilir",
      consequence_class: "single_fatality",
      technical_assessment: {
        observation_narrative:
          `Fotoğraf 2'de ${suffix} numaralı köprü vinç kancasının emniyet mandalı açık görülmektedir.`,
        technical_significance:
          "Açık mandal, yük bağlantısının kanca ağzından istem dışı ayrılmasına karşı korumayı zayıflatır.",
        root_cause_mode: "not_determinable",
        root_cause_text: "Fotoğraftan kesin kök neden tespit edilememektedir.",
      },
      control_intents: [{
        action_code: "restore_hook_latch",
        target: `hook_block_${suffix}`,
        priority: "immediate",
      }, {
        action_code: "lifting_accessory_inspection",
        target: `hook_block_${suffix}`,
        priority: "planned",
      }],
    });
  const product = buildEngineProduct(
    [photoResult(2, [liveHook(1), liveHook(2)])],
    "tr",
    "plus",
  );
  const singleHookProduct = buildEngineProduct(
    [photoResult(2, [liveHook(1)])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    product.analysisResult.total_score_fk,
    singleHookProduct.analysisResult.total_score_fk,
  );
  const finding = product.findings[0];
  const publicText = JSON.stringify({
    title: finding.title,
    description: finding.description,
    root_cause_text: finding.root_cause_text,
    recommended_action: finding.recommended_action,
    recommended_measures: finding.recommended_measures,
    source_photo_observations: finding.source_photo_observations,
  });
  assertStringIncludes(String(finding.title), "kancalarında");
  assertStringIncludes(String(finding.description), "2 köprü vinç kancasının");
  assertStringIncludes(
    String(finding.root_cause_text),
    "Olası temel etkenler:",
  );
  assertFalse(
    /(?:fotoğraf|fotograf|görsel|gorsel|görüntü|goruntu)|\b[12]\s+numaralı\b/iu
      .test(publicText),
    publicText,
  );
  assertEquals(
    (finding.source_photo_observations as unknown[]).length,
    2,
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) =>
        entry.reason_code === "same_photo_equivalent_hook_latch_condition",
    ),
  );
});

Deno.test("targeted hook absence without positive pivot geometry remains rejected", () => {
  const sourceFact = fact({
    fact_id: "hook-source-pivot",
    entity: {
      ...fact().entity,
      entity_ref: "hook-1",
      equipment_family: "overhead_crane",
      component: "hook",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Mandal pivot noktası boş ve kanca ağzı açık"],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca mandalı eksik",
    },
    mechanism_code: "falling_object",
  });
  const source = photoResult(1, [sourceFact]);
  const signal = selectTargetedSignal([source]);
  assert(signal);
  const missingOnly = {
    ...sourceFact,
    evidence: {
      ...sourceFact.evidence,
      affirmative_cues: ["Kanca emniyet mandalı görünmüyor"],
    },
  } satisfies HazardFactV3;
  assertEquals(constrainTargetedFacts([source], signal, [missingOnly]), []);
});

Deno.test("a serious concrete signal on a zero-fact photo gets targeted priority", () => {
  const emptyOutput = output(1, []);
  emptyOutput.inspection_signals = [{
    signal_id: "pipe-wrap-detail",
    photo_index: 1,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: [
      "Boru yüzeyinde düzensiz beyaz sarım ve yerel yüzey süreksizliği",
    ],
    potential_consequence_class: "permanent_disability",
    reason_code: "pipe_surface_detail",
  }];
  assertEquals(
    selectTargetedSignal([{
      ...photoResult(1, []),
      output: emptyOutput,
    }])?.signal_id,
    "pipe-wrap-detail",
  );
});

Deno.test("zero-fact photo can recover a concrete cue even when provider labels the signal negligible", () => {
  const emptyOutput = output(1, []);
  emptyOutput.inspection_signals = [{
    signal_id: "wrapped-pipe-detail",
    photo_index: 1,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: [
      "Mavi boru hattı üzerinde beyaz bir malzeme ile sarılmış bölüm",
      "Malzemenin ne olduğunun belirsizliği",
    ],
    potential_consequence_class: "negligible",
    reason_code: "wrapped_section_requires_detail",
  }];
  assertEquals(
    selectTargetedSignal([{
      ...photoResult(1, []),
      output: emptyOutput,
    }])?.signal_id,
    "wrapped-pipe-detail",
  );
});

Deno.test("ASCII normalization keeps uppercase English condition codes scorable", () => {
  const trip = fact({
    fact_id: "trip-uppercase",
    mechanism_code: "other_visible_physical",
    entity: {
      ...fact().entity,
      entity_ref: "floor-zone-a",
      equipment_family: "work area",
      component: "floor route",
    },
    observed_condition: {
      condition_code: "TRIP_HAZARD_OBSTRUCTION",
      short_text: "Geçiş güzergâhında engel",
    },
    hazard_mechanism: "Takılma ve aynı seviyede düşme",
    credible_event_path: "Çalışan engele takılarak aynı seviyede düşebilir",
    consequence_class: "permanent_disability",
  });
  const pinch = fact({
    fact_id: "pinch-uppercase",
    mechanism_code: "other_visible_physical",
    entity: {
      ...fact().entity,
      entity_ref: "pivot-a",
      equipment_family: "machine linkage",
      component: "pivot joint",
    },
    observed_condition: {
      condition_code: "PINCH_CRUSH_POINT",
      short_text: "Erişilebilir sıkışma aralığı",
    },
    hazard_mechanism: "Hareketli mafsalda sıkışma",
    credible_event_path: "El hareketli mafsalda sıkışabilir",
    consequence_class: "single_fatality",
  });
  const product = buildEngineProduct(
    [photoResult(1, [trip, pinch])],
    "tr",
    "plus",
  );
  const byTrace = new Map(
    product.factLineage.map((entry) => [entry.fact_trace_id, entry]),
  );
  const tripScore = byTrace.get("p1:trip-uppercase")?.score_output as
    | Record<string, unknown>
    | undefined;
  const pinchScore = byTrace.get("p1:pinch-uppercase")?.score_output as
    | Record<string, unknown>
    | undefined;
  assertEquals(tripScore?.fk_probability, 6);
  assertEquals(tripScore?.fk_frequency, 1);
  assertEquals(tripScore?.fk_severity, 15);
  assertEquals(pinchScore?.fk_probability, 6);
  assertEquals(pinchScore?.fk_frequency, 1);
  assertEquals(pinchScore?.fk_severity, 15);
});

Deno.test("semantic P and S follow barrier and consequence inputs without keyword overrides", () => {
  const ground = fact({
    fact_id: "ground-a",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Ekskavatör paletleri düzensiz ve gevşek kaya üzerinde konumlanmış",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "paletli ekskavatör",
      component: "paletler ve çalışma zemini",
    },
    observed_condition: {
      condition_code: "uneven_loose_rock_work_surface",
      short_text: "Ekskavatörün engebeli zeminde çalışması",
    },
    hazard_mechanism: "Makine stabilitesinin bozulması ve devrilme",
    credible_event_path:
      "Ekskavatör devrilerek operatörün ölümcül yaralanmasına yol açabilir",
    barrier_state: "absent_or_failed_event_direct",
    frequency_basis: "daily_repeated_workstation",
    consequence_class: "permanent_disability",
  });
  const variant = {
    ...ground,
    fact_id: "ground-b",
    barrier_state: "partial_event_direct_or_conditional" as const,
    frequency_basis: "active_single_exposure" as const,
    consequence_class: "single_fatality" as const,
  };
  const first = buildEngineProduct([photoResult(1, [ground])], "tr", "plus")
    .findings[0];
  const second = buildEngineProduct([photoResult(1, [variant])], "tr", "plus")
    .findings[0];
  assertEquals(
    [first.fk_probability, first.fk_frequency, first.fk_severity],
    [6, 3, 15],
  );
  assertEquals(
    [second.fk_probability, second.fk_frequency, second.fk_severity],
    [3, 3, 40],
  );
});

Deno.test("hook policy cannot promote serious reversible consequence to permanent harm", () => {
  const hook = fact({
    fact_id: "hook-open",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Kanca ağzı engelsiz açık ve mandal yuvası boş",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "lifting hook",
      component: "hook safety latch",
    },
    observed_condition: {
      condition_code: "hook_latch_open",
      short_text: "Kanca emniyet mandalı açık",
    },
    credible_event_path:
      "Yük kanca ağzından ayrılarak yakındaki çalışana çarpabilir",
    consequence_class: "serious_reversible",
    frequency_basis: "sector_scene_proxy",
  });
  const finding = buildEngineProduct([photoResult(1, [hook])], "tr", "plus")
    .findings[0];
  assertEquals(finding.fk_severity, 7);
});

Deno.test("incomplete midrail does not drift from permanent harm to fatal severity", () => {
  const midrail = fact({
    fact_id: "midrail-fatal-drift",
    entity: {
      ...fact().entity,
      entity_ref: "platform-midrail-1",
      equipment_family: "platform guardrail",
      component: "midrail",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst platform korkuluğunda ara korkuluk bulunmayan açık boşluk",
      ],
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "Üst platform korkuluğunda ara korkuluk eksikliği",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Ara korkuluk boşluğundan yüksekten düşme",
    credible_event_path:
      "Çalışan ara korkuluğu eksik platform kenarından alt seviyeye düşebilir",
    consequence_class: "single_fatality",
    frequency_basis: "sector_scene_proxy",
  });
  const finding = buildEngineProduct(
    [photoResult(1, [midrail])],
    "tr",
    "plus",
  ).findings[0];
  assertEquals(finding.fk_severity, 15);
  assert(
    (finding.score_policy_reason_codes as string[]).includes(
      "incomplete_guardrail_severity_normalized",
    ),
  );
});

Deno.test("semantic mapping preserves housekeeping and rack consequence inputs", () => {
  const clutter = fact({
    fact_id: "clutter-a",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Zeminde dağınık kutular ve geçiş engeli"],
    },
    entity: {
      ...fact().entity,
      equipment_family: "building area",
      component: "floor",
    },
    observed_condition: {
      condition_code: "poor_housekeeping_obstruction",
      short_text: "Zeminde dağınık malzemeler",
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Takılma ve düşme",
    credible_event_path: "Çalışan malzemeye takılarak aynı seviyede düşebilir",
    barrier_state: "partial_event_direct_or_conditional",
    frequency_basis: "active_single_exposure",
    consequence_class: "serious_reversible",
  });
  const rack = fact({
    fact_id: "rack-a",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Raf üstünde dengesiz istiflenmiş kutular"],
    },
    entity: {
      ...fact().entity,
      equipment_family: "storage rack",
      component: "stacked materials",
    },
    observed_condition: {
      condition_code: "unstable_stacking",
      short_text: "Raf üzerinde dengesiz istifleme",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Malzeme düşmesi",
    credible_event_path: "Malzeme raftan düşerek çalışana çarpabilir",
    barrier_state: "absent_or_failed_event_direct",
    frequency_basis: "daily_repeated_workstation",
    consequence_class: "permanent_disability",
  });
  const product = buildEngineProduct(
    [photoResult(1, [clutter, rack])],
    "tr",
    "plus",
  );
  assertEquals(
    [
      product.findings[0].fk_probability,
      product.findings[0].fk_frequency,
      product.findings[0].fk_severity,
    ],
    [3, 2, 7],
  );
  assertEquals(
    [
      product.findings[1].fk_probability,
      product.findings[1].fk_frequency,
      product.findings[1].fk_severity,
    ],
    [3, 2, 15],
  );
  assert(
    (product.findings[1].score_policy_reason_codes as string[]).includes(
      "storage_stacking_probability_normalized",
    ),
  );
});

Deno.test("critical visible components without a fact remain measurable coverage gaps", () => {
  const pinOutput = output(1, []);
  pinOutput.scene_inventory = [{
    entity_ref: "bucket_joint",
    equipment_family: "paletli ekskavatör",
    component: "kova bağlantı pimleri ve mafsal",
    visible_condition_summary:
      "Kova bağlantı pimleri ve mafsal bölgesi genel olarak görünür",
  }];
  const product = buildEngineProduct(
    [{
      ...photoResult(1, []),
      output: pinOutput,
    }],
    "tr",
    "plus",
  );
  const coverage = product.qualityTrace.component_coverage as Array<
    Record<string, unknown>
  >;
  assertEquals(coverage.length, 1);
  assertEquals(coverage[0].check_code, "pin_retainer_joint_integrity");
  assertEquals(coverage[0].status, "unresolved_no_candidate");
});

Deno.test("critical component coverage requires accepted entity-linked condition evidence", () => {
  const pipingOutput = output(1, [fact()]);
  pipingOutput.scene_inventory = [{
    entity_ref: "pipe-1",
    equipment_family: "process piping system",
    component: "pipe line",
    visible_condition_summary: "Boru hattı görüntüde tanımlandı",
  }, {
    entity_ref: "pivot-1",
    equipment_family: "excavator linkage",
    component: "pivot pins and joint",
    visible_condition_summary: "Mafsal bölgesi görüntüde tanımlandı",
  }];
  pipingOutput.hazard_facts[0] = {
    ...pipingOutput.hazard_facts[0],
    entity: {
      ...pipingOutput.hazard_facts[0].entity,
      entity_ref: "pivot-1",
      equipment_family: "excavator linkage",
      component: "pivot joint",
    },
    observed_condition: {
      condition_code: "accessible_pinch_point",
      short_text: "Mafsalda erişilebilir sıkışma aralığı",
    },
    hazard_mechanism: "Hareketli mafsalda sıkışma",
    credible_event_path: "El mafsal aralığında sıkışarak yaralanabilir",
  };
  const product = buildEngineProduct(
    [{
      ...photoResult(1, pipingOutput.hazard_facts),
      output: pipingOutput,
    }],
    "tr",
    "plus",
  );
  const coverage = product.qualityTrace.component_coverage as Array<
    Record<string, unknown>
  >;
  assertEquals(
    coverage.map((entry) => entry.check_code),
    ["hose_line_route_integrity", "pin_retainer_joint_integrity"],
  );
  assertEquals(coverage.map((entry) => entry.status), [
    "unresolved_no_candidate",
    "unresolved_no_candidate",
  ]);
});

Deno.test("critical component coverage preserves an entity-linked rejected fact", () => {
  const rejectedHook = fact({
    fact_id: "hook-candidate",
    entity: {
      ...fact().entity,
      entity_ref: "hook-1",
      equipment_family: "lifting hook",
      component: "hook latch",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca mandalı görünmüyor"],
    },
    observed_condition: {
      condition_code: "HOOK_LATCH_MISSING",
      short_text: "Kanca emniyet mandalı eksik",
    },
    mechanism_code: "falling_object",
  });
  const result = photoResult(1, [rejectedHook]);
  result.output.scene_inventory = [{
    entity_ref: "hook-1",
    equipment_family: "lifting hook",
    component: "hook latch",
    visible_condition_summary: "Kanca bloğu görünür",
  }];
  const coverage = buildEngineProduct([result], "tr", "plus").qualityTrace
    .component_coverage as Array<Record<string, unknown>>;
  assertEquals(coverage[0].status, "rejected_fact");
  assertEquals(coverage[0].rejection_reason_codes, ["absence_only_claim"]);
});

Deno.test("targeted confirmation reconciles hook coverage and remains before assurance", () => {
  const uncertainHook = fact({
    fact_id: "hook-primary-uncertain",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "crane_1_hook",
      equipment_family: "overhead_crane",
      component: "hook_block",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca mandalı görünmüyor"],
    },
    observed_condition: {
      condition_code: "hook_latch_missing_or_open",
      short_text: "Kanca mandalı eksik veya açık",
    },
    mechanism_code: "falling_object",
  });
  const targetedHook = fact({
    fact_id: "hook-targeted-confirmed",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "crane_1_hook",
      equipment_family: "overhead_crane",
      component: "hook_block",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Kanca mandalı açık konumda görülüyor",
        "Kanca ağzı engelsiz açık",
      ],
    },
    observed_condition: {
      condition_code: "hook_latch_open",
      short_text: "Kanca emniyet mandalı açık",
    },
    mechanism_code: "falling_object",
    consequence_class: "permanent_disability",
    frequency_basis: "active_single_exposure",
  });
  const secondUncertainHook = fact({
    ...uncertainHook,
    fact_id: "hook-primary-second-uncertain",
    entity: {
      ...uncertainHook.entity,
      entity_ref: "crane_2_hook",
    },
  });
  const source = photoResult(2, [uncertainHook, secondUncertainHook]);
  source.output.scene_inventory = [{
    entity_ref: "crane_1_hook",
    equipment_family: "overhead_crane",
    component: "hook_block",
    visible_condition_summary: "Kanca bloğu ve mandal görülüyor.",
  }, {
    entity_ref: "crane_2_hook",
    equipment_family: "overhead_crane",
    component: "hook_block",
    visible_condition_summary: "İkinci kanca bloğu ve mandal görülüyor.",
  }, {
    entity_ref: "panel-1",
    equipment_family: "electrical_panel",
    component: "enclosure",
    visible_condition_summary: "Kapalı elektrik dağıtım panosu görülüyor.",
  }];
  const product = buildEngineProduct(
    [source],
    "tr",
    "plus",
    [targetedHook],
    {},
    { sectorID: "manufacturing" },
  );
  assertEquals(product.findings[0].assessment_section, "observed_risk");
  assertEquals(
    product.findings.at(-1)?.assessment_section,
    "equipment_assurance",
  );
  assertEquals(product.findings[0].category_code, "lifting_safety");
  assertEquals(
    product.findings[0].category,
    "Kaldırma ekipmanları ve yük güvenliği",
  );
  const componentCoverage = product.qualityTrace.component_coverage as Array<
    Record<string, unknown>
  >;
  assertEquals(componentCoverage[0].status, "accepted_fact");
  const sectorCoverage = (product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >).critical_equipment_coverage as Array<Record<string, unknown>>;
  const hookCoverage = sectorCoverage.find((entry) =>
    entry.entity_ref === "crane_1_hook" &&
    entry.check_code === "pin_retainer_joint_integrity"
  );
  assertEquals(hookCoverage?.status, "accepted_fact");
  const unresolvedHookCoverage = sectorCoverage.find((entry) =>
    entry.entity_ref === "crane_2_hook" &&
    entry.check_code === "pin_retainer_joint_integrity"
  );
  assertEquals(unresolvedHookCoverage?.status, "unresolved_no_fact");
  assertEquals(
    unresolvedHookCoverage?.reason_code,
    "sector_critical_component_candidate_unresolved",
  );
});

Deno.test("hook-latch absence needs positive open-hook geometry", () => {
  const ambiguous = fact({
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca mandalı görünmüyor"],
    },
    entity: {
      ...fact().entity,
      equipment_family: "lifting equipment",
      component: "hook latch",
    },
    observed_condition: {
      condition_code: "missing_safety_latch",
      short_text: "Kanca emniyet mandalı eksikliği",
    },
  });
  const geometric = {
    ...ambiguous,
    fact_id: "hook-geometric",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Mandal bağlantı noktası boş ve mandal yatağı açık görülüyor",
      ],
    },
  };
  const openMouthOnly = {
    ...ambiguous,
    fact_id: "hook-open-mouth-only",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca ağzı engelsiz ve açık görülüyor"],
    },
  };
  assertEquals(evidenceRejectionReason(ambiguous), "absence_only_claim");
  assertEquals(evidenceRejectionReason(geometric), null);
  assertEquals(evidenceRejectionReason(openMouthOnly), "absence_only_claim");
});

Deno.test("directly visible open-edge geometry remains actionable", () => {
  const guardrail = fact({
    fact_id: "HF_001",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Korkuluk açıklığında açık kenar ve orta bariyer boşluğu",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "guardrail",
      component: "mid_rail",
    },
    observed_condition: {
      condition_code: "GUARDRAIL_MIDRAIL_MISSING",
      short_text: "Alt platform korkuluğunda orta bariyer eksikliği.",
    },
    hazard_mechanism: "Yüksekten düşme.",
    credible_event_path:
      "Çalışan açık kenardan düşerek kalıcı yaralanmaya uğrar.",
    consequence_class: "permanent_disability",
    frequency_basis: "daily_repeated_workstation",
  });
  const product = buildEngineProduct(
    [photoResult(1, [guardrail])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(product.findings[0].fk_frequency, 2);
  const measures = product.findings[0].recommended_measures as Array<
    Record<string, unknown>
  >;
  assertEquals(measures.map((measure) => measure.kind), [
    "corrective",
    "preventive",
  ]);
  assertStringIncludes(String(measures[1].text), "koruyucu");
});

Deno.test("directly visible missing midrail is accepted without a targeted call", () => {
  const guardrail = fact({
    fact_id: "HF-visible-midrail",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Korkulukta ara korkuluğun eksik olduğu açıkça görülüyor",
        "Platform kenarında düşme boşluğu bulunuyor",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "lower-platform-railing",
      equipment_family: "guardrail",
      component: "mid_rail",
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "Korkulukta eksik ara korkuluk",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Platform kenarından yüksekten düşme",
    credible_event_path:
      "Çalışan korkuluk boşluğundan alt seviyeye düşerek ciddi yaralanabilir.",
    consequence_class: "permanent_disability",
  });
  assertEquals(evidenceRejectionReason(guardrail), null);
  assertEquals(selectTargetedSignal([photoResult(1, [guardrail])]), null);
  assertEquals(
    buildEngineProduct([photoResult(1, [guardrail])], "tr", "plus").findings
      .length,
    1,
  );
});

Deno.test("incident HF001 HF002 and HF004 survive the structured critical barrier gate", () => {
  const hf001 = fact({
    fact_id: "HF001",
    entity: {
      ...fact().entity,
      entity_ref: "scaffolding_platform_1_guardrail",
      equipment_family: "scaffold",
      component: "guardrail",
    },
    observed_condition: {
      condition_code: "missing_guardrail",
      short_text: "İskele platformunun açık kenarında korkuluk eksik",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "İskele platformunun kenarında çalışan ve bariyersiz düşme hattı birlikte açıkça görülüyor",
      ],
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Açık kenardan yüksekten düşme",
    credible_event_path:
      "Çalışan bariyersiz platform kenarından aşağı düşebilir",
    exposed_entity: "worker_foreground_1",
    barrier_state: "absent_or_failed_event_direct",
    consequence_class: "single_fatality",
  });
  const hf002 = fact({
    ...hf001,
    fact_id: "HF002",
    entity: {
      ...hf001.entity,
      entity_ref: "concrete_slab_open_edge_1",
      equipment_family: "edge_protection",
      component: "open_edge",
    },
    observed_condition: {
      condition_code: "unguarded_open_edge",
      short_text: "Betonarme döşemede korumasız açık kenar",
    },
    evidence: {
      normalized_region: {
        x: 0.45,
        y: 0.15,
        width: 0.3,
        height: 0.45,
        is_global: false,
      },
      affirmative_cues: [
        "Döşeme sınırı ile hemen yakınındaki çalışan aynı yerel bölgede görülüyor",
      ],
    },
  });
  const hf004 = fact({
    ...hf001,
    fact_id: "HF004",
    entity: {
      ...hf001.entity,
      entity_ref: "concrete_mixer_1",
      equipment_family: "concrete_mixer",
      component: "moving_drive_parts",
    },
    observed_condition: {
      condition_code: "unguarded_moving_parts",
      short_text: "Beton mikserinin hareketli tahrik parçaları koruyucusuz",
    },
    evidence: {
      normalized_region: {
        x: 0.05,
        y: 0.45,
        width: 0.35,
        height: 0.35,
        is_global: false,
      },
      affirmative_cues: [
        "Operatör erişimindeki döner tahrik parçaları doğrudan görülüyor",
      ],
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Hareketli parçaya kapılma ve sıkışma",
    credible_event_path:
      "Operatör koruyucusuz hareketli parçaya temas ederek kapılabilir",
    exposed_entity: "operator_1",
  });
  for (const candidate of [hf001, hf002, hf004]) {
    assertEquals(evidenceRejectionReason(candidate), null);
  }
  const result = photoResult(1, [hf001, hf002, hf004]);
  result.output.scene_inventory = [{
    entity_ref: "scaffolding_1",
    equipment_family: "scaffold",
    component: "platform",
    visible_condition_summary: "Yükseltilmiş iskele platformu görünür",
  }, {
    entity_ref: "concrete_mixer_1",
    equipment_family: "concrete_mixer",
    component: "moving_drive_parts",
    visible_condition_summary: "Beton mikseri ve tahrik bölgesi görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus", [], {}, {
    sectorID: "construction",
  });
  assertEquals(
    product.findings.filter((finding) =>
      finding.assessment_section === "observed_risk"
    ).length,
    3,
  );
  assert(
    product.findings.filter((finding) =>
      String(finding.title).toLocaleLowerCase("tr-TR").includes("korkuluk") ||
      String(finding.title).toLocaleLowerCase("tr-TR").includes("açık kenar")
    ).length >= 2,
  );
  assertFalse(product.analysisResult.highest_band_fk === "medium");
  assertFalse(JSON.stringify(product.findings).includes("Worker 1"));
});

Deno.test("occluded critical barrier claim is not accepted as visible evidence", () => {
  const occluded = fact({
    observed_condition: {
      condition_code: "missing_guardrail",
      short_text: "Korkuluk bölümü örtülü olduğundan seçilemiyor",
    },
    entity: {
      ...fact().entity,
      equipment_family: "scaffold",
      component: "guardrail",
    },
    mechanism_code: "fall_from_height",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Korkuluk bölümü malzeme arkasında görünmüyor"],
    },
    exposed_entity: "worker_1",
  });
  assertEquals(
    evidenceRejectionReason(occluded),
    "uncertain_condition_requires_confirmation",
  );
  assertEquals(
    selectTargetedDecision([photoResult(1, [occluded])], "construction").signal
      ?.reason_code,
    "critical_barrier_visibility_requires_confirmation",
  );
  const unresolved = buildEngineProduct(
    [photoResult(1, [occluded])],
    "tr",
    "plus",
  );
  assertStringIncludes(
    String(unresolved.analysisResult.ai_summary),
    "yüksek sonuçlu aday",
  );
  assertEquals(
    (unresolved.qualityTrace.high_consequence_rejection_guard as Record<
      string,
      unknown
    >).unresolved_count,
    1,
  );
});

Deno.test("primary rejection ratios above fifty percent emit an explicit quality alarm", () => {
  const rejected = [1, 2, 3].map((index) =>
    fact({
      fact_id: `REJECTED-${index}`,
      evidence: {
        normalized_region: fact().evidence.normalized_region,
        affirmative_cues: ["Belgenin bulunup bulunmadığı görünmüyor"],
      },
      observed_condition: {
        condition_code: "document_missing",
        short_text: "Kontrol belgesi görünmüyor",
      },
    })
  );
  const product = buildEngineProduct(
    [photoResult(1, [...rejected, fact({ fact_id: "ACCEPTED" })])],
    "tr",
    "plus",
  );
  const alert = product.qualityTrace.evidence_rejection_alert as Record<
    string,
    unknown
  >;
  assertEquals(alert.triggered, true);
  assertEquals(alert.rejection_ratio, 0.75);
});

Deno.test("scaffold parent inventory closes coverage with a child guardrail fact", () => {
  const guardrail = fact({
    fact_id: "SCAFFOLD-CHILD-GUARDRAIL",
    entity: {
      ...fact().entity,
      entity_ref: "scaffolding_platform_1_guardrail_1",
      equipment_family: "scaffold",
      component: "midrail ara korkuluk",
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "İskele platformunda ara korkuluk eksik",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Çalışanın bulunduğu iskele platformunda ara korkuluk boşluğu görülüyor",
      ],
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Korkuluk boşluğundan düşme",
    credible_event_path: "Çalışan korkuluk boşluğundan alt seviyeye düşebilir",
    exposed_entity: "worker_1",
    barrier_state: "absent_or_failed_event_direct",
    consequence_class: "single_fatality",
  });
  const result = photoResult(1, [guardrail]);
  result.output.scene_inventory = [{
    entity_ref: "scaffolding_1",
    equipment_family: "scaffold",
    component: "platform",
    visible_condition_summary: "İskele platformu görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus", [], {}, {
    sectorID: "construction",
  });
  const coverage = (product.qualityTrace.sector_profile as Record<
    string,
    unknown
  >).critical_equipment_coverage as Array<Record<string, unknown>>;
  assert(
    coverage.some((entry) =>
      entry.equipment_family_code === "scaffold" &&
      entry.check_code === "guard_barrier_integrity" &&
      entry.status === "accepted_fact"
    ),
  );
});

Deno.test("live middle-barrier wording restores both independently repairable guardrails", () => {
  const lower = fact({
    fact_id: "F1",
    evidence: {
      normalized_region: {
        x: 0.0001,
        y: 0.613,
        width: 0.4,
        height: 0.12,
        is_global: false,
      },
      affirmative_cues: [
        "Alt platform korkuluğunda orta bariyer elemanının eksik olduğu açıkça görülmektedir.",
        "Korkuluk direkleri arasında boşluk bulunmaktadır.",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "railing_lower_platform_left",
      equipment_family: "guardrail",
      component: "mid_rail",
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "Alt platform korkuluğunda eksik orta bariyer elemanı",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism:
      "Korkulukta eksik orta bariyer elemanı nedeniyle düşme korumasının yetersiz kalması",
    credible_event_path:
      "Çalışan eksik orta bariyer elemanı olan korkuluk boşluğundan düşebilir.",
    consequence_class: "permanent_disability",
    technical_assessment: {
      observation_narrative:
        "Alt platformun sol tarafındaki korkulukta orta bariyer elemanının eksik olduğu açıkça görülmektedir.",
      technical_significance:
        "Orta bariyer elemanının eksikliği korkuluğun düşme koruma fonksiyonunu azaltır.",
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Korkuluk orta bariyer elemanının fiziksel olarak eksik olması.",
    },
  });
  const upper: HazardFactV3 = {
    ...lower,
    fact_id: "F2",
    evidence: {
      normalized_region: {
        x: 0.4,
        y: 0.3,
        width: 0.3,
        height: 0.1,
        is_global: false,
      },
      affirmative_cues: [
        "Üst platform korkuluğunda orta bariyer elemanının eksik olduğu açıkça görülmektedir.",
        "Korkuluk direkleri arasında boşluk bulunmaktadır.",
      ],
    },
    entity: {
      ...lower.entity,
      entity_ref: "railing_upper_platform_middle",
    },
    observed_condition: {
      ...lower.observed_condition,
      short_text: "Üst platform korkuluğunda eksik orta bariyer elemanı",
    },
    technical_assessment: {
      ...lower.technical_assessment,
      observation_narrative:
        "Üst platformun orta kısmındaki korkulukta orta bariyer elemanının eksik olduğu açıkça görülmektedir.",
    },
  };
  assertEquals(evidenceRejectionReason(lower), null);
  assertEquals(evidenceRejectionReason(upper), null);
  const product = buildEngineProduct(
    [photoResult(1, [lower, upper])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 2);
  assertEquals(
    (product.qualityTrace.merge_ledger as unknown[]).length,
    0,
  );
  const publicText = JSON.stringify(product.findings);
  assertFalse(/sol taraf|orta kısmı|fotoğraf/iu.test(publicText), publicText);
});

Deno.test("a bare process vent opening is not scored as a visible defect", () => {
  const openVent = fact({
    fact_id: "open-vent-1",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Tank üzerindeki dikey havalandırma borusunun ağzı açık",
        "Boru ağzı platform seviyesinden erişilebilir",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "tank-1-vent",
      equipment_family: "process_piping",
      component: "vent_pipe",
    },
    observed_condition: {
      condition_code: "open_pipe_end",
      short_text: "Tank havalandırma borusu açık ağzı",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Tank içine nesne düşmesi",
    credible_event_path:
      "Bir nesne açık boru ağzından tanka girerek prosesi etkileyebilir.",
    consequence_class: "serious_reversible",
  });
  assertEquals(
    evidenceRejectionReason(openVent),
    "process_vent_opening_requires_design_basis",
  );
  assertEquals(selectTargetedSignal([photoResult(1, [openVent])]), null);
  assertEquals(
    buildEngineProduct([photoResult(1, [openVent])], "tr", "plus").findings
      .length,
    0,
  );
});

Deno.test("housekeeping receives relevant controls and no generic component replacement", () => {
  const housekeeping = fact({
    fact_id: "HF1",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Zeminde dağınık karton parçaları",
        "Geçişte küçük malzemeler",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "building",
      component: "concrete_slab",
    },
    observed_condition: {
      condition_code: "housekeeping_clutter",
      short_text:
        "Zeminde dağınık malzemeler ve karton parçaları takılma tehlikesi oluşturuyor.",
    },
    hazard_mechanism: "Takılma ve düşme",
    credible_event_path:
      "Çalışan zemindeki dağınık malzemelere takılarak düşer.",
    consequence_class: "first_aid",
    frequency_basis: "daily_repeated_workstation",
    control_intents: [{
      action_code: "secure_connection",
      target: "zemin",
      priority: "immediate",
    }],
  });
  const product = buildEngineProduct(
    [photoResult(1, [housekeeping])],
    "tr",
    "plus",
  );
  const measures = product.findings[0].recommended_measures as Array<
    Record<string, unknown>
  >;
  assertEquals(measures[0].action_code, "clear_walkway");
  assertEquals(measures[1].action_code, "housekeeping_program");
  assertFalse(JSON.stringify(measures).includes("secure_connection"));
  assertFalse(JSON.stringify(measures).includes("replace_component"));
  assertFalse(JSON.stringify(measures).includes("stop_use"));
});

Deno.test("controls distinguish hose routing, pinch access and confirmed hook latch", () => {
  const hoseRouting = fact({
    fact_id: "hose-routing",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Hortum hareketli mafsala temas ediyor ve dış yüzeyinde sürtünme izi görülüyor",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "excavator hydraulic system",
      component: "hydraulic hose route",
    },
    observed_condition: {
      condition_code: "hose_route_near_moving_joint",
      short_text: "Hidrolik hortum hareketli mafsala yakın",
    },
    mechanism_code: "hydraulic_pneumatic_release",
    hazard_mechanism: "Hortumun hareketli parçaya sürtünmesi",
    credible_event_path:
      "Sürtünme hortumu zamanla zayıflatarak akışkan salımına yol açabilir",
    consequence_class: "serious_reversible",
    frequency_basis: "sector_scene_proxy",
  });
  const pinch = fact({
    fact_id: "pinch",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Mafsal ile gövde arasında erişilebilir dar hareket aralığı",
      ],
    },
    entity: {
      ...fact().entity,
      equipment_family: "excavator linkage",
      component: "pivot joint",
    },
    observed_condition: {
      condition_code: "accessible_pinch_point",
      short_text: "Mafsalda erişilebilir sıkışma noktası",
    },
    hazard_mechanism: "Hareket sırasında sıkışma ve kesilme",
    credible_event_path: "Uzuv hareketli mafsal arasında sıkışabilir",
    consequence_class: "permanent_disability",
    frequency_basis: "sector_scene_proxy",
  });
  const hook = fact({
    fact_id: "hook-confirmed",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Kanca ağzı engelsiz açık ve mandal yuvası boş"],
    },
    entity: {
      ...fact().entity,
      equipment_family: "lifting hook",
      component: "hook safety latch",
    },
    observed_condition: {
      condition_code: "hook_latch_missing_confirmed",
      short_text: "Kanca emniyet mandalı eksik",
    },
    credible_event_path: "Yük kanca ağzından ayrılarak düşebilir",
    consequence_class: "single_fatality",
    frequency_basis: "sector_scene_proxy",
  });
  const product = buildEngineProduct(
    [photoResult(1, [hoseRouting, pinch, hook])],
    "tr",
    "plus",
  );
  const measures = product.findings.map((finding) =>
    finding.recommended_measures as Array<Record<string, unknown>>
  );
  assertFalse(JSON.stringify(measures[0]).includes("replace_component"));
  assert(
    (measures[0][1].action_codes as string[]).includes("reroute_hose"),
  );
  assertFalse(JSON.stringify(measures[1]).includes("secure_connection"));
  assert(
    (measures[1][1].action_codes as string[]).includes("guard_pinch_point"),
  );
  assertEquals(measures[2][0].action_code, "stop_use");
  assert(
    (measures[2][1].action_codes as string[]).includes("restore_hook_latch"),
  );
});

Deno.test("structured controls keep guard, rack and slope actions in the correct domain", () => {
  const guard = fact({
    fact_id: "guard-gap",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Boru geçişi çevresinde korkuluk sürekliliğini kesen açık boşluk",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "guardrail-1",
      equipment_family: "guardrail",
      component: "handrail",
    },
    observed_condition: {
      condition_code: "pipe_penetration_guard_gap",
      short_text: "Korkulukta boru geçişi çevresinde açık boşluk",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Açık korkuluk bölümünden yüksekten düşme",
    credible_event_path: "Çalışan korkuluk boşluğundan alt seviyeye düşebilir",
    consequence_class: "permanent_disability",
    control_intents: [{
      action_code: "restore_barrier",
      target: "guardrail-1",
      priority: "immediate",
    }],
  });
  const rack = fact({
    fact_id: "rack-stack",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Raf üst seviyesinde sınır dışına taşan dengesiz malzeme",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "rack-1",
      equipment_family: "storage_racking",
      component: "stored_material",
    },
    observed_condition: {
      condition_code: "unstable_stacking",
      short_text: "Rafın üst seviyesinde dengesiz istif",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Dengesiz malzemenin raftan düşmesi",
    credible_event_path: "Malzeme raftan düşerek aşağıdaki çalışana çarpabilir",
    consequence_class: "serious_reversible",
    control_intents: [{
      action_code: "reorganize_storage",
      target: "rack-1",
      priority: "immediate",
    }],
  });
  const slope = fact({
    fact_id: "slope-rockfall",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Şev yüzeyinde çalışma alanına doğru kopabilecek gevşek kaya parçaları",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "slope-1",
      equipment_family: "natural_feature",
      component: "slope",
    },
    observed_condition: {
      condition_code: "gevsek_malzeme_kaymasi",
      short_text: "Şev yüzeyinde gevşek malzeme",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Gevşek malzemenin şevden çalışma alanına kayması",
    credible_event_path:
      "Kaya ve toprak parçaları kayarak çalışan veya ekipmana çarpabilir",
    consequence_class: "serious_reversible",
    control_intents: [{
      action_code: "stabilize_slope",
      target: "slope-1",
      priority: "planned",
    }, {
      action_code: "clear_loose_material",
      target: "slope-1",
      priority: "immediate",
    }],
  });
  const findings = buildEngineProduct(
    [photoResult(1, [guard, rack, slope])],
    "tr",
    "plus",
  ).findings;
  const controls = findings.map((finding) =>
    finding.recommended_measures as Array<Record<string, unknown>>
  );
  assertEquals(controls[0][0].action_code, "restrict_access");
  assert(
    (controls[0][1].action_codes as string[]).includes("restore_barrier"),
  );
  assertFalse(JSON.stringify(controls[0]).includes("clear_walkway"));
  assertEquals(controls[1][0].action_code, "reorganize_storage");
  assert(
    (controls[1][1].action_codes as string[]).includes(
      "storage_stacking_standard",
    ),
  );
  assertFalse(JSON.stringify(controls[1]).includes("install_fall_protection"));
  assertEquals(controls[2][0].action_code, "clear_loose_material");
  assert(
    (controls[2][1].action_codes as string[]).includes("stabilize_slope"),
  );
  assertFalse(JSON.stringify(controls[2]).includes("stabilize_ground"));
});

Deno.test("latest elevated loose material stays out of walkway controls", () => {
  const elevatedBag = fact({
    fact_id: "HF002",
    entity: {
      ...fact().entity,
      entity_ref: "process_piping_upper",
      equipment_family: "egress_housekeeping",
      component: "loose_material",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Boru üzerinde duran beyaz plastik torba",
        "desteksiz ve gevşek duruş",
      ],
    },
    observed_condition: {
      condition_code: "UNSECURED_MATERIAL",
      short_text: "Üst platform seviyesindeki boru üzerinde gevşek malzeme",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Düşen cisim",
    credible_event_path:
      "Boru üzerindeki gevşek plastik torba aşağı düşerek bir kişiye çarpabilir.",
    consequence_class: "first_aid",
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text: "Malzemenin boru üzerine bırakılması ve sabitlenmemesi.",
    },
    control_intents: [{
      action_code: "clear_loose_material",
      target: "process_piping_upper",
      priority: "immediate",
    }],
  });
  const finding = buildEngineProduct(
    [photoResult(1, [elevatedBag])],
    "tr",
    "plus",
  ).findings[0];
  const controls = finding.recommended_measures as Array<
    Record<string, unknown>
  >;
  assertEquals(controls[0].action_code, "clear_loose_material");
  assertFalse(JSON.stringify(controls).includes("clear_walkway"));
  assertStringIncludes(finding.title, "gevşek malzemenin düşme");
  assertStringIncludes(String(finding.category), "Düşen cisim");
  assertEquals(
    finding.root_cause_text,
    "Olası temel etkenler: malzemenin güvenli sınırlar içinde tutulmaması, sabitlenmemesi veya düşme yolunun yeterince kontrol edilmemesi.",
  );
});

Deno.test("latest falling-object slope fact gets slope taxonomy title and controls", () => {
  const slope = fact({
    fact_id: "HF-3",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "work_area_ground",
      equipment_family: "ground_surface",
      component: "uneven_rocky_terrain",
    },
    evidence: {
      normalized_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: [
        "gevşek kayaçlar",
        "şev yüzeyinde çatlak ve kopma izi",
        "engebeli zemin",
        "dik şev",
        "kazı alanı",
      ],
    },
    observed_condition: {
      condition_code: "LOOSE-MAT",
      short_text: "Çalışma alanında ve şevde gevşek kayaç ve toprak birikimi",
    },
    mechanism_code: "falling_object",
    hazard_mechanism:
      "Dik şevde bulunan gevşek kayaçların veya toprağın düşmesi ve kayması",
    credible_event_path:
      "Şevdeki gevşek kayaçlar düşerek personele veya ekipmana zarar verebilir.",
    consequence_class: "serious_reversible",
    control_intents: [{
      action_code: "clear_loose_material",
      target: "work_area_ground",
      priority: "immediate",
    }, {
      action_code: "stabilize_slope",
      target: "background_slope",
      priority: "planned",
    }],
  });
  const finding = buildEngineProduct(
    [photoResult(3, [{ ...slope, photo_index: 3 }])],
    "tr",
    "plus",
  ).findings[0];
  const controls = finding.recommended_measures as Array<
    Record<string, unknown>
  >;
  assertStringIncludes(finding.title, "Şevdeki gevşek kayaç");
  assertEquals(finding.category_code, "excavation_slope_safety");
  assertEquals(finding.equipment_group_code, "access_work_area");
  assertEquals(controls[0].action_code, "clear_loose_material");
  assert(
    (controls[1].action_codes as string[]).includes("stabilize_slope"),
  );
  assertFalse(JSON.stringify(controls).includes("heavy_component_storage"));
});

Deno.test("ordinary excavation bucket movement is not scored as a falling-material hazard", () => {
  const excavation = fact({
    fact_id: "active-excavation-loose-material",
    photo_index: 3,
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "excavation-area-1",
      equipment_family: "mobile_equipment",
      component: "bucket",
    },
    evidence: {
      normalized_region: {
        x: 0.2,
        y: 0.35,
        width: 0.55,
        height: 0.5,
        is_global: false,
      },
      affirmative_cues: [
        "Ekskavatörün kovasının aktif olarak gevşek kayaçları kazması",
        "Kazı alanında gevşek kaya ve toprak yığınları",
      ],
    },
    observed_condition: {
      condition_code: "LOOSE_MATERIAL_IN_EXCAVATION",
      short_text: "Kazı alanında gevşek malzemelerin düşme hattı",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Kazı sırasında gevşek malzemelerin düşmesi",
    credible_event_path:
      "Kova ile kazılan gevşek malzeme kazı alanına düşerek yakındaki kişiye çarpabilir",
    consequence_class: "serious_reversible",
    frequency_basis: "active_single_exposure",
    verification: { model_required: false, reason_code: "" },
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Çalışma alanının doğal zemin koşulları ve yetersiz zemin hazırlığı.",
    },
    control_intents: [{
      action_code: "clear_loose_material",
      target: "bucket",
      priority: "immediate",
    }, {
      action_code: "stabilize_slope",
      target: "bucket",
      priority: "planned",
    }, {
      action_code: "slope_acceptance",
      target: "bucket",
      priority: "planned",
    }],
  });
  const product = buildEngineProduct(
    [photoResult(3, [excavation])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 0);
  assert(
    (product.qualityTrace.rejection_ledger as Array<Record<string, unknown>>)
      .some((entry) =>
        entry.reason_code ===
          "ordinary_excavation_material_handling_rejected"
      ),
  );
});

Deno.test("visible inherent overturn always carries the existing field-verification flag", () => {
  const overturn = fact({
    fact_id: "excavator-overturn",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "excavator-1",
      equipment_family: "tracked_excavator",
      component: "tracks_and_ground",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Ekskavatör paletleri engebeli ve gevşek doğal zeminde konumlanmış",
      ],
    },
    observed_condition: {
      condition_code: "UNSTABLE_GROUND_POSITION",
      short_text: "Ekskavatörün engebeli zeminde çalışması",
    },
    mechanism_code: "equipment_overturn",
    hazard_mechanism: "Zemin stabilitesinin bozulmasıyla devrilme",
    credible_event_path: "Ekskavatör dengesini kaybederek devrilebilir",
    consequence_class: "single_fatality",
    frequency_basis: "active_single_exposure",
    verification: { model_required: false, reason_code: "" },
  });
  const finding = buildEngineProduct(
    [photoResult(1, [overturn])],
    "tr",
    "plus",
  ).findings[0];
  assertEquals(finding.needs_field_verification, true);
  assertEquals(finding.field_verification_reason_codes, [
    "site_stability_requires_field_confirmation",
  ]);
});

Deno.test("heavy floor-stored parts and electrical facts use exact routes", () => {
  const heavyPart = fact({
    fact_id: "floor-dished-head",
    entity: {
      ...fact().entity,
      entity_ref: "dished-head-1",
      equipment_family: "fabricated_component",
      component: "dished_head",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Zemindeki büyük metal tank bombesi takozsuz ve sabitlenmemiş durumda",
      ],
    },
    observed_condition: {
      condition_code: "unrestrained_heavy_floor_component",
      short_text: "Zeminde sabitlenmemiş ağır metal parça",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Ağır parçanın yuvarlanması veya devrilmesi",
    credible_event_path:
      "Ağır parça yuvarlanarak veya devrilerek çalışana çarpabilir.",
    consequence_class: "serious_reversible",
    control_intents: [],
  });
  const electrical = fact({
    fact_id: "exposed-electrical",
    entity: {
      ...fact().entity,
      entity_ref: "drive-1",
      equipment_family: "industrial_mixer",
      component: "motor_drive",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Motor rakorunda açıkta kalan elektrik iletkeni"],
    },
    observed_condition: {
      condition_code: "exposed_electrical_wiring",
      short_text: "Kısmen açıkta kalmış elektrik tesisatı",
    },
    mechanism_code: "electrical_contact_arc",
    hazard_mechanism: "Elektrik çarpması veya ark flaşı",
    credible_event_path:
      "Çalışan açık iletkene temas ederek elektrik çarpmasına uğrayabilir.",
    consequence_class: "permanent_disability",
    control_intents: [],
  });
  const findings = buildEngineProduct(
    [photoResult(1, [heavyPart, electrical])],
    "tr",
    "plus",
  ).findings;
  const heavyMeasures = findings[0].recommended_measures as Array<
    Record<string, unknown>
  >;
  assertEquals(heavyMeasures[0].action_code, "secure_heavy_floor_component");
  assert(
    (heavyMeasures[1].action_codes as string[]).includes(
      "heavy_component_storage_standard",
    ),
  );
  assertFalse(
    JSON.stringify(heavyMeasures).includes("install_fall_protection"),
  );
  assertEquals(
    findings[0].category,
    "Ağır parça depolama ve sabitleme güvenliği",
  );
  assertEquals(findings[1].category, "Elektrik güvenliği");
});

Deno.test("references remain gated by plan and approved safety profile", () => {
  const enabledContext = {
    safetyProfileID: "tr-tr-current-v1",
    regulatoryReferencePolicy: "tr_current",
    structuredRegulatoryReferencesEnabled: true,
  };
  const free = buildEngineProduct(
    [photoResult(1, [fact()])],
    "tr",
    "free",
    [],
    enabledContext,
  );
  const nonTR = buildEngineProduct(
    [photoResult(1, [fact()])],
    "en",
    "plus",
    [],
    enabledContext,
  );
  assertEquals(free.findings[0].references_text, "");
  assertEquals(nonTR.findings[0].references_text, "");
});

Deno.test("structured references do not treat wrapped or upper as PPE", () => {
  const enabledContext = {
    safetyProfileID: "tr-tr-current-v1",
    regulatoryReferencePolicy: "tr_current",
    structuredRegulatoryReferencesEnabled: true,
  };
  const wrappedFlange = fact({
    fact_id: "wrapped-flange",
    entity: {
      ...fact().entity,
      entity_ref: "process-line-1",
      equipment_family: "piping",
      component: "flanged_connection",
    },
    observed_condition: {
      condition_code: "PIPE_CONNECTION_WRAPPED",
      short_text: "Flanş bağlantısında sarılı örtü",
    },
    mechanism_code: "environmental_release",
  });
  const upperRack = fact({
    fact_id: "upper-rack",
    entity: {
      ...fact().entity,
      entity_ref: "rack-1",
      equipment_family: "storage_racking",
      component: "upper_shelves_stored_items",
    },
    observed_condition: {
      condition_code: "UNSTABLE_STACKING",
      short_text: "Rafın üst seviyesinde dengesiz depolama",
    },
    mechanism_code: "falling_object",
  });
  const product = buildEngineProduct(
    [photoResult(1, [wrappedFlange, upperRack])],
    "tr",
    "plus",
    [],
    enabledContext,
  );
  const references = product.findings.map((finding) =>
    String(finding.references_text)
  );
  assertFalse(
    references.some((value) => value.includes("Kişisel Koruyucu Donanımların")),
  );
  assertStringIncludes(
    references[0],
    "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
  );
  assertStringIncludes(
    references[1],
    "İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik",
  );
});

Deno.test("flange anomalies and mobile articulation receive component-appropriate controls", () => {
  const wrappedFlange = fact({
    fact_id: "wrapped-flange-controls",
    entity: {
      ...fact().entity,
      entity_ref: "process-line-1",
      equipment_family: "piping",
      component: "flanged_connection",
    },
    observed_condition: {
      condition_code: "PIPE_CONNECTION_WRAPPED",
      short_text: "Flanş bağlantısında sarılı örtü",
    },
    mechanism_code: "environmental_release",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Flanş çevresine sarılmış beyaz örtü"],
    },
    control_intents: [{
      action_code: "engineering_inspection",
      target: "flanged_connection",
      priority: "planned",
    }],
  });
  const articulation = fact({
    fact_id: "excavator-joint-controls",
    entity: {
      ...fact().entity,
      entity_ref: "excavator-joint-1",
      equipment_family: "heavy_equipment",
      component: "articulated_joint",
    },
    observed_condition: {
      condition_code: "PINCH_POINT",
      short_text: "Ekskavatör mafsalında erişilebilir sıkışma aralığı",
    },
    mechanism_code: "caught_in_pinch_shear",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Bom ve kova mafsalı arasında hareketli sıkışma aralığı",
      ],
    },
    control_intents: [{
      action_code: "restrict_access",
      target: "articulated_joint",
      priority: "immediate",
    }],
  });
  const product = buildEngineProduct(
    [photoResult(1, [wrappedFlange, articulation])],
    "tr",
    "plus",
  );
  const controls = product.findings.map((finding) =>
    finding.recommended_measures as Array<Record<string, unknown>>
  );
  assertEquals(controls[0][0].action_code, "restrict_access");
  assert(
    (controls[0][1].action_codes as string[]).includes(
      "verify_process_condition",
    ),
  );
  assertFalse(JSON.stringify(controls[0]).includes("reroute_hose"));
  assertEquals(controls[1][0].action_code, "restrict_access");
  assert(
    (controls[1][1].action_codes as string[]).includes("isolate_energy"),
  );
  assertFalse(JSON.stringify(controls[1]).includes("guard_pinch_point"));
});

Deno.test("critical process-vessel inventory produces scoped scored assurance findings without another provider call", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "tank-1",
    equipment_family: "process_vessel",
    component: "tank",
    visible_condition_summary: "Proses tankı görünür",
  }, {
    entity_ref: "tank-2",
    equipment_family: "process_vessel",
    component: "tank",
    visible_condition_summary: "Proses tankı görünür",
  }, {
    entity_ref: "drive-1",
    equipment_family: "process_equipment",
    component: "motor_ve_aktarma_organi",
    visible_condition_summary: "Tank üstü tahrik ekipmanı görünür",
  }, {
    entity_ref: "pipe-1",
    equipment_family: "piping",
    component: "boru_hatti",
    visible_condition_summary: "Bağlı proses hattı görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus", [], {
    safetyProfileID: "tr-tr-current-v1",
    regulatoryReferencePolicy: "tr_current",
    structuredRegulatoryReferencesEnabled: true,
  });
  assertEquals(product.findings.length, 3);
  assert(
    product.findings.every((finding) =>
      finding.fk_probability === 1 && finding.fk_frequency === 2 &&
      finding.needs_field_verification === true
    ),
  );
  assert(
    product.findings.some((finding) =>
      String(finding.title).includes("mekanik bütünlüğü")
    ),
  );
  assert(
    product.findings.some((finding) =>
      String(finding.title).includes("tahrik ekipmanında")
    ),
  );
  assert(
    product.findings.some((finding) =>
      String(finding.title).includes("proses hattının") ||
      String(finding.title).includes("Proses hattının")
    ),
  );
  const integrity = product.findings.find((finding) =>
    String(finding.title).includes("mekanik bütünlüğü")
  );
  assert(integrity);
  const integrityText = JSON.stringify(integrity);
  assertStringIncludes(integrityText, "API 650");
  assertStringIncludes(integrityText, "API 653");
  assertStringIncludes(integrityText, "radyografi");
  assertStringIncludes(integrityText, "process_safeguard_function_test");
  assertStringIncludes(String(integrity.references_text), "API 650 / API 653");
  const processLine = product.findings.find((finding) =>
    String(finding.title).toLocaleLowerCase("tr-TR").includes("proses hattının")
  );
  assert(processLine);
  assertEquals(
    processLine.category,
    "Proses güvenliği ve ekipman bütünlüğü",
  );
  assertFalse(
    String(processLine.references_text).includes(
      "Kimyasal Maddelerle Çalışmalarda",
    ),
  );
  assertFalse(JSON.stringify(product.findings).includes("sahada teyit"));
  assert(
    (product.qualityTrace.stages as Array<Record<string, unknown>>).some(
      (stage) =>
        stage.name === "asset_assurance_added_fact" && stage.total === 4,
    ),
  );
  assert(
    (product.qualityTrace.stages as Array<Record<string, unknown>>).some(
      (stage) =>
        stage.name === "within_photo_dedup" &&
        stage.delta_from_previous === -1,
    ),
  );
  assertEquals(
    product.qualityTrace.asset_assurance_catalog_version,
    "asset-assurance-v8",
  );
});

Deno.test("an isolated uncertain tank head does not activate full tank assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "metal-object-1",
    equipment_family: "process_vessel",
    component: "tank_head",
    visible_condition_summary:
      "Zeminde duran yuvarlak metal parça, muhtemelen bir tank başlığı",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 0);
});

Deno.test("tank assurance programmes merge across photo angles without photo suffixes", () => {
  const first = photoResult(1, []);
  first.output.scene_inventory = [{
    entity_ref: "tank-a-view-1",
    equipment_family: "process_vessel",
    component: "storage_tank",
    visible_condition_summary: "Proses tankı birinci açıdan görülüyor",
  }];
  const second = photoResult(2, []);
  second.output.scene_inventory = [{
    entity_ref: "tank-a-view-2",
    equipment_family: "process_vessel",
    component: "storage_tank",
    visible_condition_summary: "Proses tankı ikinci açıdan görülüyor",
  }];
  const product = buildEngineProduct([first, second], "tr", "plus");
  assertEquals(product.findings.length, 1);
  assert(
    product.findings.every((finding) =>
      JSON.stringify(finding.source_photo_indices) === "[1,2]"
    ),
  );
  assertFalse(
    product.findings.some((finding) =>
      String(finding.title).toLocaleLowerCase("tr-TR").includes("fotoğraf")
    ),
  );
});

Deno.test("machine tools receive guarding and LOTO assurance without alleging a visible defect", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "cnc-1",
    equipment_family: "cnc_machine",
    component: "cnc_lathe",
    visible_condition_summary: "Kapalı CNC tezgahı görülüyor",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "machine_guarding_function_test");
  assertStringIncludes(serialized, "machine_loto_maintenance_control");
  assertFalse(serialized.includes("eksik olduğu"));
  assert(
    product.findings.every((finding) =>
      finding.fk_probability === 1 && finding.fk_frequency === 2 &&
      finding.needs_field_verification === true
    ),
  );
});

Deno.test("mobile equipment receives integrity and operational safety-function assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "excavator-1",
    equipment_family: "heavy_equipment excavator",
    component: "boom_chassis_hydraulics",
    visible_condition_summary: "Ekskavatör çalışma alanında görülüyor",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "mobile_equipment_periodic_inspection");
  assertStringIncludes(serialized, "mobile_equipment_safety_function_test");
  assertStringIncludes(serialized, "geri hareket sesli-görsel ikazı");
  assert(
    product.findings.some((finding) =>
      finding.title ===
        "Mobil iş ekipmanının mekanik bütünlüğü ve periyodik kontrolü"
    ),
  );
  assertFalse(serialized.toLocaleLowerCase("tr-TR").includes("fotoğraf)"));
});

Deno.test("LNG storage receives cryogenic, safeguard and Ex assurance only", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "lng-tank-1",
    equipment_family: "lng_storage_tank",
    component: "cryogenic_tank_system",
    visible_condition_summary:
      "LNG etiketi ve ilişkili kriyojenik hatları bulunan depolama tankı",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "lng_cryogenic_integrity_inspection");
  assertStringIncludes(serialized, "lng_safeguard_emergency_control");
  assertStringIncludes(serialized, "hazardous_area_ex_equipment_control");
  assertStringIncludes(serialized, "API 625");
  assertStringIncludes(serialized, "IEC 60079-10-1");
  assertStringIncludes(serialized, "IEC 60079-14/17");
  assertFalse(serialized.includes("API 650"));
  assertFalse(serialized.includes("API 653"));
  assert(
    product.findings.every((finding) =>
      finding.fk_probability === 1 && finding.fk_frequency === 2 &&
      finding.needs_field_verification === true
    ),
  );
});

Deno.test("LPG storage receives pressure-integrity, safeguards and Ex assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "lpg-bullet-1",
    equipment_family: "lpg_storage_tank",
    component: "lpg_bullet_tank",
    visible_condition_summary:
      "LPG işaretli yatay basınçlı depolama tankı ve bağlantıları",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "lpg_installation_integrity_inspection");
  assertStringIncludes(serialized, "lpg_safeguard_periodic_test");
  assertStringIncludes(serialized, "hazardous_area_ex_equipment_control");
  assertStringIncludes(serialized, "API 2510");
  assertStringIncludes(serialized, "Ex ekipman");
  assertFalse(serialized.includes("API 650"));
  assertFalse(serialized.includes("API 653"));
});

Deno.test("pressure equipment gets NDT and safety-device guidance without an API tank claim", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "receiver-1",
    equipment_family: "pressure_vessel air_receiver",
    component: "shell_nozzle_relief_valve",
    visible_condition_summary: "Basınçlı hava tankı görülüyor",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "pressure_equipment_integrity_inspection");
  assertStringIncludes(serialized, "pressure_safety_device_test");
  assertStringIncludes(serialized, "PT/MT/UT/RT");
  assertFalse(serialized.includes("API 650"));
  assertFalse(serialized.includes("API 653"));
});

Deno.test("chemical inventory receives SDS and compatibility guidance without alleging missing documents", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "ibc-1",
    equipment_family: "chemical_container IBC",
    component: "chemical_storage_area",
    visible_condition_summary: "Kimyasal IBC ve kaplar görülüyor",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings);
  assertStringIncludes(serialized, "chemical_sds_storage_control");
  assertEquals(
    product.findings[0].recommended_action,
    "Doğrulanmış kimyasal kap ve kullanım alanlarını envanter, etiket-SDS eşleşmesi, uyumluluk ayrımı ve ikincil tutma kapsamında kontrol et; kimliği doğrulanamayan kabı kimyasal olarak sınıflandırma.",
  );
  assertEquals(product.findings[0].category_code, "chemical_safety");
  assertEquals(product.findings[0].display_group, "chemical_storage");
  assertFalse(serialized.includes("SDS bulunmuyor"));
  assertFalse(serialized.includes("MSDS bulunmuyor"));
  assertFalse(
    /fotoğraf|fotograf|görselde|gorselde|görüntü|goruntu/iu.test(serialized),
  );
});

Deno.test("an unlabeled generic blue bucket does not create chemical assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "blue-bucket-1",
    equipment_family: "chemical_container",
    component: "blue_plastic_bucket",
    visible_condition_summary: "Etiketi okunmayan genel mavi plastik kova",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 0);
  assert(
    (product.qualityTrace.asset_assurance_identity_rejections as Array<
      Record<string, unknown>
    >).some((entry) =>
      entry.reason_code === "asset_assurance_unidentified_generic_container"
    ),
  );
});

Deno.test("tower crane inventory is never rendered as an overhead crane assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "tower-crane-1",
    equipment_family: "tower_crane",
    component: "tower_jib_hook",
    visible_condition_summary: "Kule vinç bomu ve kanca bloğu görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus", [], {}, {
    sectorID: "construction",
  });
  const serialized = JSON.stringify(product.findings);
  assertFalse(/Köprü vinç|overhead crane/iu.test(serialized));
});

Deno.test("ambiguous container and cabinet identities do not create assurance findings", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "metal-container-1",
    equipment_family: "chemical_container",
    component: "container",
    visible_condition_summary:
      "Zeminde büyük metal kap veya tank başlığı görülüyor; içeriği bilinmiyor.",
  }, {
    entity_ref: "cabinet-1",
    equipment_family: "electrical_panel",
    component: "enclosure",
    visible_condition_summary:
      "Kapalı bir elektrik panosu veya dolap görülüyor.",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 0);
  const rejections = product.qualityTrace
    .asset_assurance_identity_rejections as Array<Record<string, unknown>>;
  assertEquals(rejections.length, 2);
  assert(
    rejections.every((entry) =>
      entry.reason_code === "asset_assurance_ambiguous_equipment_identity"
    ),
  );
});

Deno.test("confirmed electrical panel keeps electrical taxonomy and specific action", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "panel-1",
    equipment_family: "electrical_panel",
    component: "enclosure",
    visible_condition_summary: "Kapalı elektrik dağıtım panosu görülüyor.",
  }];
  const finding = buildEngineProduct([result], "tr", "plus").findings[0];
  assertEquals(finding.category, "Elektrik bütünlüğü ve periyodik test");
  assertEquals(finding.category_code, "electrical_safety");
  assertEquals(finding.display_group, "electrical_equipment");
  assertStringIncludes(
    String(finding.recommended_action),
    "Elektrik panosu veya şalt ekipmanının",
  );
});

Deno.test("crane assurance counts equipment identities rather than visible components", () => {
  const result = photoResult(2, []);
  result.output.scene_inventory = [
    "crane_1_girder",
    "crane_1_trolley",
    "crane_1_wire_rope",
    "crane_1_hook",
    "crane_2_girder",
    "crane_2_trolley",
    "crane_2_wire_rope",
    "crane_2_hook",
  ].map((entity_ref) => ({
    entity_ref,
    equipment_family: "overhead_crane",
    component: entity_ref.split("_").slice(2).join("_"),
    visible_condition_summary: "Köprü vinç bileşeni görünür.",
  }));
  const finding = buildEngineProduct([result], "tr", "plus").findings[0];
  const observations = JSON.stringify(finding.source_photo_observations);
  assertStringIncludes(observations, "2 köprü vinç");
  assertFalse(observations.includes("4 köprü vinç"));
});

Deno.test("ordinary Turkish words containing baz do not activate chemical assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "floor-1",
    equipment_family: "egress_housekeeping",
    component: "floor",
    visible_condition_summary: "Bazı alanlarda dağınıklık ve malzeme görülüyor",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 0);
});

Deno.test("inventory prose containing yelek does not activate screening machinery", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "operator-1",
    equipment_family: "person",
    component: "operator",
    visible_condition_summary: "Operatör üzerinde reflektif yelek görülüyor",
  }];
  assertEquals(buildEngineProduct([result], "tr", "plus").findings.length, 0);
});

Deno.test("guardrail identity does not activate rail-system assurance", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "guardrail-1",
    equipment_family: "guardrail_system",
    component: "midrail",
    visible_condition_summary: "Platform korkuluk sistemi görünür",
  }];
  assertEquals(buildEngineProduct([result], "tr", "plus").findings.length, 0);
});

Deno.test("detached dished end is not counted as a process tank", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "dished-end-1",
    equipment_family: "process_tank_component",
    component: "dished_end",
    visible_condition_summary: "Zeminde ayrı bir tank bombesi görülüyor",
  }];
  assertEquals(buildEngineProduct([result], "tr", "plus").findings.length, 0);
});

Deno.test("equipment assurance is limited to one consolidated item per asset", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [{
    entity_ref: "receiver-1",
    equipment_family: "pressure_vessel air_receiver",
    component: "pressure_boundary",
    visible_condition_summary: "Basınçlı hava tankı",
  }, {
    entity_ref: "excavator-1",
    equipment_family: "mobile_equipment excavator",
    component: "boom_hydraulics",
    visible_condition_summary: "Ekskavatör",
  }, {
    entity_ref: "cnc-1",
    equipment_family: "cnc_machine",
    component: "lathe",
    visible_condition_summary: "CNC torna",
  }, {
    entity_ref: "furnace-1",
    equipment_family: "industrial_furnace",
    component: "burner",
    visible_condition_summary: "Endüstriyel fırın",
  }, {
    entity_ref: "rail-1",
    equipment_family: "rail_system",
    component: "rail_vehicle",
    visible_condition_summary: "Raylı taşıma sistemi",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 5);
});

Deno.test("generic crane trolley motion is rejected and replaced by periodic-control assurance", () => {
  const genericTrolley = fact({
    fact_id: "generic-crane-trolley",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "crane-1-trolley",
      equipment_family: "overhead_crane",
      component: "crane_trolley",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Vinç arabasında hareketli tambur ve hareketli parçalar arasında boşluklar görülüyor",
      ],
    },
    observed_condition: {
      condition_code: "trolley_moving_parts",
      short_text: "Vinç arabasının hareketli parçaları",
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Hareketli parçalar arasında sıkışma",
    credible_event_path:
      "Vinç arabasının hareketi sırasında teorik sıkışma bölgesi oluşabilir",
  });
  assertEquals(
    evidenceRejectionReason(genericTrolley),
    "generic_inherent_hazard_rejected",
  );
  const result = photoResult(1, [genericTrolley]);
  result.output.scene_inventory = [{
    entity_ref: "CRANE_01",
    equipment_family: "overhead_crane",
    component: "kopru_vinc",
    visible_condition_summary: "Köprü vinç görünür",
  }, {
    entity_ref: "CRANE_01_TROLLEY",
    equipment_family: "overhead_crane",
    component: "vinc_arabasi",
    visible_condition_summary: "Vinç arabası görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  assertStringIncludes(
    product.findings[0].title,
    "periyodik kontrolü ve emniyet fonksiyonlarının",
  );
  assertEquals(product.findings[0].fk_probability, 1);
  assertEquals(product.findings[0].fk_frequency, 2);
  const measures = product.findings[0]
    .recommended_measures as Array<Record<string, unknown>>;
  assertEquals(measures[0].action_code, "verify_periodic_control_status");
  assert(
    (measures[1].action_codes as string[]).includes(
      "crane_safety_function_test",
    ),
  );
  assertStringIncludes(
    String(measures[1].text),
    "sesli-görsel hareket uyarılarını",
  );
});

Deno.test("crane assurance counts crane roots rather than visible subcomponents", () => {
  const result = photoResult(1, []);
  result.output.scene_inventory = [
    "bridge",
    "trolley",
    "hoist",
    "wire_rope",
    "hook_block",
  ].flatMap((component) =>
    [1, 2].map((crane) => ({
      entity_ref: `crane${crane}_${component}`,
      equipment_family: "overhead_crane",
      component,
      visible_condition_summary: "Köprü vinç bileşeni görünür",
    }))
  );
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  const serialized = JSON.stringify(product.findings[0]);
  assertStringIncludes(serialized, "2 köprü vinç");
  assertFalse(
    /fotoğraf|fotograf|görselde|gorselde|görüntü|goruntu/iu.test(serialized),
    serialized,
  );
  assertFalse(serialized.includes("10 köprü vinç"));
});

Deno.test("uncertain impression language cannot enter the scored finding set", () => {
  const uncertain = fact({
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Hortum desteklerinin gevşek olduğu izlenimi oluşuyor",
      ],
    },
    observed_condition: {
      condition_code: "hose_support_uncertain",
      short_text: "Hortum desteğinde gevşeklik izlenimi",
    },
  });
  assertEquals(
    evidenceRejectionReason(uncertain),
    "uncertain_condition_requires_confirmation",
  );
});

Deno.test("potential guard coverage with no confirmed defect is rejected", () => {
  const uncertainGuard = fact({
    assessment_basis: "visible_inherent_hazard",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Tahrik ünitesindeki mekanik bileşenler görünür",
      ],
    },
    observed_condition: {
      condition_code: "POTENTIAL_EXPOSED_ROTATING_PARTS",
      short_text: "Tahrik ünitesindeki dönen parçaların korunması",
    },
  });
  assertEquals(
    evidenceRejectionReason(uncertainGuard),
    "uncertain_condition_requires_confirmation",
  );
});

Deno.test("root-cause renderer omits repeated field-verification boilerplate", () => {
  const product = buildEngineProduct([photoResult(1, [fact()])], "tr", "plus");
  const rootCause = String(product.findings[0].root_cause_text);
  assertFalse(rootCause.includes("sahada teyit"));
  assertFalse(rootCause.includes("saha incelemesiyle"));
  assertStringIncludes(rootCause, "Muhtemel temel etken");
});

Deno.test("photo-only installation and material-placement causes are not asserted", () => {
  const midrail = fact({
    fact_id: "midrail-root",
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Korkuluk sisteminin kurulumunda veya bakımında ara korkuluğun takılmamış veya çıkarılmış olması.",
    },
  });
  const looseMaterial = fact({
    fact_id: "material-root",
    entity: { ...fact().entity, entity_ref: "material-1" },
    observed_condition: {
      condition_code: "UNSECURED_MATERIAL",
      short_text: "Boru üzerinde gevşek malzeme",
    },
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text: "Malzemenin boru üzerine bırakılması ve sabitlenmemesi.",
    },
  });
  const findings = buildEngineProduct(
    [photoResult(1, [midrail, looseMaterial])],
    "tr",
    "plus",
  ).findings;
  assert(
    findings.every((finding) =>
      String(finding.root_cause_text).startsWith("Olası temel etkenler:") &&
      !/fotoğraf|görsel|görüntü/iu.test(String(finding.root_cause_text))
    ),
  );
});

Deno.test("latest housekeeping and ground-preparation causes cannot be stated as observed facts", () => {
  const housekeeping = fact({
    fact_id: "housekeeping-root-latest",
    entity: {
      ...fact().entity,
      entity_ref: "floor-root-1",
      equipment_family: "work_area",
      component: "floor",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Zeminde dağınık malzemeler bulunuyor"],
    },
    observed_condition: {
      condition_code: "POOR_HOUSEKEEPING",
      short_text: "Zemindeki dağınık malzemeler",
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Dağınık malzemeye takılarak düşme",
    credible_event_path: "Çalışan malzemeye takılarak düşebilir",
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Çalışma alanında iyi bir düzen ve temizlik (housekeeping) eksikliği.",
    },
    frequency_basis: "sector_scene_proxy",
  });
  const ground = fact({
    fact_id: "ground-root-latest",
    entity: {
      ...fact().entity,
      entity_ref: "ground-root-1",
      equipment_family: "tracked_excavator",
      component: "tracks_and_ground",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Paletler engebeli doğal zemin üzerinde"],
    },
    observed_condition: {
      condition_code: "UNEVEN_GROUND",
      short_text: "Engebeli çalışma zemini",
    },
    mechanism_code: "equipment_overturn",
    hazard_mechanism: "Ekskavatör stabilitesinin bozulması",
    credible_event_path: "Ekskavatör dengesini kaybederek devrilebilir",
    technical_assessment: {
      ...fact().technical_assessment,
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Çalışma alanının doğal zemin koşulları ve yetersiz zemin hazırlığı.",
    },
    frequency_basis: "sector_scene_proxy",
  });
  const housekeepingRoot = String(
    buildEngineProduct(
      [photoResult(1, [housekeeping])],
      "tr",
      "plus",
    ).findings[0].root_cause_text,
  );
  const groundRoot = String(
    buildEngineProduct(
      [photoResult(1, [ground])],
      "tr",
      "plus",
    ).findings[0].root_cause_text,
  );
  assertStringIncludes(housekeepingRoot, "Olası temel etkenler:");
  assertStringIncludes(housekeepingRoot, "malzeme ve atık toplama");
  assertFalse(/zemin veya şev/iu.test(housekeepingRoot));
  assertStringIncludes(groundRoot, "Olası temel etkenler:");
  assertFalse(/fotoğraf|görsel|görüntü/iu.test(housekeepingRoot));
  assertFalse(/fotoğraf|görsel|görüntü/iu.test(groundRoot));
});

Deno.test("production missing-midrail and toe-board wording is accepted as positive barrier geometry", () => {
  const midrail = fact({
    fact_id: "HF001",
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst platform korkuluğunda orta korkuluk elemanının eksik olması veya hasarlı olması nedeniyle oluşan boşluk.",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "RAIL-LOWER-MID",
      equipment_family: "guardrail",
      component: "ara_korkuluk",
    },
    observed_condition: {
      condition_code: "MISSING_MID_RAIL",
      short_text: "Alt platform korkuluğunda ara eleman eksikliği",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Korkuluk boşluğundan yüksekten düşme",
    credible_event_path:
      "Çalışan açık korkuluk boşluğundan alt seviyeye düşebilir.",
    consequence_class: "permanent_disability",
  });
  const toeBoard = fact({
    fact_id: "HF002",
    evidence: {
      normalized_region: {
        x: 0.2,
        y: 0.6,
        width: 0.4,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Korkuluk etek elemanının eksik olması",
        "Platform kenarında açıkta kalan boşluk",
      ],
    },
    entity: {
      ...fact().entity,
      entity_ref: "RAIL-LOWER-TOE",
      equipment_family: "guardrail",
      component: "etek_elemanı",
    },
    observed_condition: {
      condition_code: "MISSING_TOE_BOARD",
      short_text: "Platform korkuluğunda etek elemanı eksikliği",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Platformdan alt seviyeye malzeme düşmesi",
    credible_event_path:
      "Platform kenarındaki malzeme boşluktan alt seviyeye düşebilir.",
    consequence_class: "serious_reversible",
  });
  assertEquals(evidenceRejectionReason(midrail), null);
  assertEquals(evidenceRejectionReason(toeBoard), null);
  midrail.technical_assessment.observation_narrative =
    "Orta korkuluk elemanının eksik olduğu veya ciddi şekilde hasar gördüğü açıkça görülmektedir.";
  midrail.technical_assessment.root_cause_mode = "observed_condition";
  midrail.technical_assessment.root_cause_text =
    "Korkuluk elemanının fiziksel olarak eksik veya hasarlı olması.";
  const product = buildEngineProduct(
    [photoResult(1, [midrail, toeBoard])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 2);
  assertFalse(String(product.findings[0].description).includes("veya"));
  assertFalse(String(product.findings[0].root_cause_text).includes("veya"));
});

Deno.test("live etek sacı wording with an exposed edge is not rejected as absence-only", () => {
  const toeBoard = fact({
    fact_id: "LIVE-TOE-BOARD",
    entity: {
      ...fact().entity,
      entity_ref: "guardrail-platform-upper-left",
      equipment_family: "access_and_work_at_height",
      component: "guardrail",
    },
    observed_condition: {
      condition_code: "missing_toeboard",
      short_text: "Üst platform korkuluğunda etek sacı eksikliği",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst platform korkuluğunda etek sacı elemanı eksikliği",
        "Açıkta kalan kenar",
      ],
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Platform kenarından malzeme düşmesi",
    credible_event_path:
      "Platformdaki malzeme açık kenardan alt seviyeye düşerek çalışana çarpabilir.",
    consequence_class: "serious_reversible",
  });
  assertEquals(evidenceRejectionReason(toeBoard), null);
  const product = buildEngineProduct(
    [photoResult(1, [toeBoard])],
    "tr",
    "plus",
    [],
    {},
    { sectorID: "manufacturing", source: "database" },
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    product.findings[0].title,
    "Üst platform korkuluğunda etek sacı eksikliği",
  );
  assertEquals(product.findings[0].fk_frequency, 6);
});

Deno.test("same floor condition split into left and right regions becomes one finding", () => {
  const floorRight = fact({
    fact_id: "FLOOR-RIGHT",
    entity: {
      ...fact().entity,
      entity_ref: "FLOOR_AREA_RIGHT",
      equipment_family: "work area",
      component: "walkway",
    },
    evidence: {
      normalized_region: {
        x: 0.55,
        y: 0.55,
        width: 0.35,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: ["Sağ zemin bölgesinde dağınık malzemeler"],
    },
    observed_condition: {
      condition_code: "housekeeping_poor_debris",
      short_text: "Zeminde dağınık malzemeler",
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Dağınık malzemeye takılarak düşme",
    credible_event_path: "Çalışan dağınık malzemeye takılarak düşebilir.",
    consequence_class: "serious_reversible",
  });
  const floorLeft: HazardFactV3 = {
    ...floorRight,
    fact_id: "FLOOR-LEFT",
    entity: {
      ...floorRight.entity,
      entity_ref: "FLOOR_AREA_LEFT",
      component: "work_area",
    },
    evidence: {
      normalized_region: {
        x: 0.08,
        y: 0.55,
        width: 0.35,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: ["Sol zemin bölgesinde aynı dağınık malzemeler"],
    },
    observed_condition: {
      condition_code: "housekeeping_poor_equipment",
      short_text: "Zeminde dağınık ekipman parçaları",
    },
  };
  const product = buildEngineProduct(
    [photoResult(1, [floorRight, floorLeft])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    (product.findings[0].source_photo_observations as unknown[]).length,
    2,
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) =>
        entry.reason_code === "same_scene_housekeeping_condition_merged",
    ),
  );
});

Deno.test("same rack region overhang and overheight become one semantic finding", () => {
  const overhang = fact({
    fact_id: "HF004",
    entity: {
      ...fact().entity,
      entity_ref: "storage_rack_1",
      equipment_family: "storage_racking",
      component: "rack_structure",
    },
    evidence: {
      normalized_region: {
        x: 0.85,
        y: 0.5,
        width: 0.15,
        height: 0.4,
        is_global: false,
      },
      affirmative_cues: [
        "Rafın üst kısmında paletli ürünlerin raf sınırını aşması",
        "Rafın üst kısmında dengesiz görünen istifleme",
      ],
    },
    observed_condition: {
      condition_code: "storage_overhang",
      short_text: "Depolama rafında paletli ürünlerin raf sınırını aşması",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Raf sınırını aşan paletli ürünlerin düşmesi",
    credible_event_path:
      "Raf sınırını aşan ürünler düşerek çalışana çarpabilir.",
    consequence_class: "serious_reversible",
    technical_assessment: {
      observation_narrative:
        "Sağ taraftaki depolama rafının üst kısmında bulunan paletli ürünler rafın ön sınırını aşacak şekilde istiflenmiştir.",
      technical_significance:
        "Raf sınırını aşan ürünler dengesiz konumda kalarak düşebilir.",
      root_cause_mode: "observed_condition",
      root_cause_text: "Uygun olmayan istifleme uygulaması.",
    },
  });
  const overheight: HazardFactV3 = {
    ...overhang,
    fact_id: "HF005",
    observed_condition: {
      condition_code: "storage_overheight",
      short_text: "Depolama rafında ürünlerin raf yüksekliğini aşması",
    },
    hazard_mechanism: "Raf yüksekliğini aşan paletli ürünlerin düşmesi",
  };
  const product = buildEngineProduct(
    [photoResult(1, [overhang, overheight])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 1);
  assertEquals(
    (product.findings[0].source_photo_observations as unknown[]).length,
    2,
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) =>
        entry.reason_code === "same_rack_region_storage_condition_merged",
    ),
  );
  assertStringIncludes(
    String(product.findings[0].root_cause_text),
    "Olası temel etkenler:",
  );
  assertFalse(
    /Sağ taraf|Taki depolama|Uygun olmayan istifleme/iu.test(
      JSON.stringify(product.findings[0]),
    ),
  );
});

Deno.test("generic tank-top motor guarding claim is rejected while drive assurance remains", () => {
  const genericMotor = fact({
    fact_id: "GENERIC-MOTOR-GUARD",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "DRIVE-1",
      equipment_family: "process_equipment",
      component: "motor_drive",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Motor ve tahrik ünitesinin açıkta olması",
        "Döner parçaların görünür olması",
      ],
    },
    observed_condition: {
      condition_code: "OPEN_DRIVE_PARTS",
      short_text: "Koruyucusuz hareketli parçalar",
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Döner parçaya temas",
    credible_event_path: "Bir çalışan döner parçaya temas ederek sıkışabilir.",
    consequence_class: "permanent_disability",
  });
  assertEquals(
    evidenceRejectionReason(genericMotor),
    "generic_guarding_hazard_rejected",
  );
  const result = photoResult(1, [genericMotor]);
  result.output.scene_inventory = [{
    entity_ref: "TANK-1",
    equipment_family: "process_vessel",
    component: "tank",
    visible_condition_summary: "Proses tankı görünür",
  }, {
    entity_ref: "DRIVE-1",
    equipment_family: "process_equipment",
    component: "motor_drive",
    visible_condition_summary: "Tank üstü tahrik ekipmanı görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assert(
    product.findings.some((finding) =>
      finding.title ===
        "Tank üstü tahrik ekipmanında koruyucu ve enerji izolasyonu kontrolü"
    ),
  );
  assert(
    (product.qualityTrace.rejection_ledger as Array<Record<string, unknown>>)
      .some((entry) =>
        entry.reason_code === "generic_guarding_hazard_rejected"
      ),
  );
});

Deno.test("ambiguous pipe wrap cannot become a falling-object finding", () => {
  const pipeWrap = fact({
    fact_id: "PIPE-WRAP",
    entity: {
      ...fact().entity,
      entity_ref: "PIPE-1",
      equipment_family: "process_piping",
      component: "pipe_valve",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Boru üzerinde beyaz sabitlenmemiş malzeme görülüyor",
      ],
    },
    observed_condition: {
      condition_code: "LOOSE_MATERIAL_ON_PIPE",
      short_text: "Boru üzerinde sabitlenmemiş malzeme",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Malzemenin borudan düşmesi",
    credible_event_path: "Malzeme borudan düşerek çalışana çarpabilir.",
    consequence_class: "serious_reversible",
  });
  assertEquals(
    evidenceRejectionReason(pipeWrap),
    "ambiguous_pipe_object_rejected",
  );
  const livePlasticBag: HazardFactV3 = {
    ...pipeWrap,
    fact_id: "PIPE-PLASTIC-BAG",
    evidence: {
      ...pipeWrap.evidence,
      affirmative_cues: [
        "Mavi proses borusuna bağlı beyaz bir plastik torba görülmektedir.",
        "Torba boruya gevşek bir şekilde bağlanmış gibi durmaktadır.",
      ],
    },
    observed_condition: {
      condition_code: "loose_material_on_piping",
      short_text: "Proses boru hattı üzerinde gevşek plastik torba",
    },
  };
  assertEquals(
    evidenceRejectionReason(livePlasticBag),
    "ambiguous_pipe_object_rejected",
  );
  assertEquals(
    selectTargetedSignal([photoResult(1, [livePlasticBag])]),
    null,
  );
});

Deno.test("generic mobile hose routing and normal articulation are replaced by assurance", () => {
  const hose = fact({
    fact_id: "GENERIC-HOSE",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "EXC-HOSE",
      equipment_family: "heavy_equipment excavator",
      component: "hydraulic_hose_route",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Hidrolik hortumlar bom boyunca uzanıyor"],
    },
    observed_condition: {
      condition_code: "HOSE_ROUTE",
      short_text: "Hidrolik hortum güzergâhı",
    },
    mechanism_code: "hydraulic_pneumatic_release",
    hazard_mechanism: "Hidrolik akışkan salımı",
    credible_event_path: "Hortum hasar görürse akışkan salınabilir.",
    consequence_class: "serious_reversible",
  });
  const articulation = fact({
    fact_id: "GENERIC-ARTICULATION",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "EXC-JOINT",
      equipment_family: "heavy_equipment excavator",
      component: "boom_bucket_articulation",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Bom ile kova arasındaki normal mafsal görülüyor"],
    },
    observed_condition: {
      condition_code: "ARTICULATION_PINCH_ZONE",
      short_text: "Bom-kova mafsalındaki hareketli aralık",
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Mafsal hareketinde sıkışma",
    credible_event_path: "Bir çalışan mafsalda sıkışabilir.",
    consequence_class: "permanent_disability",
  });
  assertEquals(
    evidenceRejectionReason(hose),
    "generic_hose_routing_rejected",
  );
  const observedProximityOnly: HazardFactV3 = {
    ...hose,
    fact_id: "OBSERVED-HOSE-PROXIMITY-ONLY",
    assessment_basis: "observed_nonconformity",
    evidence: {
      ...hose.evidence,
      affirmative_cues: [
        "Hidrolik hortumların bom bağlantısında sıkışma riski taşıyan güzergahı",
        "Hortumların metal yüzeylere yakınlığı",
      ],
    },
    observed_condition: {
      condition_code: "hose_pinch_point",
      short_text: "Hidrolik hortum güzergahında sıkışma ve aşınma riski",
    },
  };
  assertEquals(
    evidenceRejectionReason(observedProximityOnly),
    "generic_hose_routing_rejected",
  );
  assertEquals(
    evidenceRejectionReason(articulation),
    "generic_articulation_hazard_rejected",
  );
  const result = photoResult(1, [hose, articulation]);
  result.output.scene_inventory = [{
    entity_ref: "EXC-1",
    equipment_family: "heavy_equipment excavator",
    component: "boom_chassis_hydraulics",
    visible_condition_summary: "Ekskavatör çalışma alanında görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  assert(
    product.findings.every((finding) => finding.fk_probability === 1),
  );
});

Deno.test("visible inherent rockfall uses evidence-capped P and mechanism-capped S", () => {
  const rockfall = fact({
    fact_id: "ROCKFALL",
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "SLOPE-1",
      equipment_family: "quarry excavation slope",
      component: "loose_rock_face",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Şev yüzeyinde kopma çatlağı bulunan ve yüzeyden ayrılmış kaya parçaları görülüyor",
      ],
    },
    observed_condition: {
      condition_code: "LOOSE_ROCK_SLOPE",
      short_text: "Şev yüzeyindeki gevşek kaya parçaları",
    },
    mechanism_code: "excavation_collapse_rockfall",
    hazard_mechanism: "Şevden kaya düşmesi",
    credible_event_path: "Kaya parçası çalışma alanına düşebilir.",
    consequence_class: "multiple_fatality_major_environmental",
    frequency_basis: "sector_scene_proxy",
  });
  const product = buildEngineProduct(
    [photoResult(1, [rockfall])],
    "tr",
    "plus",
  );
  assertEquals(product.findings[0].fk_probability, 1);
  assertEquals(product.findings[0].fk_frequency, 2);
  assertEquals(product.findings[0].fk_severity, 40);
  assertEquals(product.analysisResult.total_score_fk, 80);
  const reasons = product.factLineage[0].reason_codes as string[];
  assert(reasons.includes("inherent_hazard_probability_capped_by_evidence"));
  assert(reasons.includes("severity_capped_by_mechanism_policy"));
});

Deno.test("specific observed agitator guard finding absorbs duplicate assurance controls", () => {
  const exposedCoupling = fact({
    fact_id: "EXPOSED-COUPLING",
    assessment_basis: "observed_nonconformity",
    entity: {
      ...fact().entity,
      entity_ref: "DRIVE-1",
      equipment_family: "tank_top_drive",
      component: "motor_coupling",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Motor kaplini açıkta ve kaplin koruyucusunda açık boşluk görülüyor",
      ],
    },
    observed_condition: {
      condition_code: "EXPOSED_COUPLING",
      short_text: "Tank üstü tahrikte açıkta kalan kaplin",
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Açık kapline temas ederek sıkışma",
    credible_event_path: "Çalışan açık kapline temas ederek sıkışabilir.",
    consequence_class: "permanent_disability",
    control_intents: [{
      action_code: "install_guard",
      target: "motor_coupling",
      priority: "immediate",
    }],
  });
  const result = photoResult(1, [exposedCoupling]);
  result.output.scene_inventory = [{
    entity_ref: "TANK-1",
    equipment_family: "process_vessel",
    component: "tank",
    visible_condition_summary: "Proses tankı görünür",
  }, {
    entity_ref: "DRIVE-1",
    equipment_family: "process_equipment",
    component: "motor_drive",
    visible_condition_summary: "Tank üstü tahrik görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(
    product.findings.filter((finding) =>
      String(finding.title).includes("tahrik ekipmanında koruyucu")
    ).length,
    0,
  );
  const observed = product.findings.find((finding) =>
    finding.title === "Tank üstü tahrikte açıkta kalan kaplin"
  );
  assert(observed);
  const controls = observed.recommended_measures as Array<
    Record<string, unknown>
  >;
  assert(
    (controls[1].action_codes as string[]).includes(
      "agitator_guard_loto_inspection",
    ),
  );
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) => entry.reason_code === "assurance_absorbed_by_observed_finding",
    ),
  );
});

Deno.test("observed concrete-mixer guard failure suppresses generic mixer assurance rows", () => {
  const mixerGuard = fact({
    fact_id: "MIXER-GUARD",
    entity: {
      ...fact().entity,
      entity_ref: "CONCRETE-MIXER-1",
      equipment_family: "industrial_mixer concrete_mixer",
      component: "moving_drive_parts",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Operatörün erişebildiği döner tahrik elemanları açıkta görülüyor",
      ],
    },
    observed_condition: {
      condition_code: "missing_machine_guard",
      short_text: "Beton mikserinin hareketli parçalarında koruyucu eksik",
    },
    mechanism_code: "caught_in_pinch_shear",
    hazard_mechanism: "Koruyucusuz döner parçaya kapılma",
    credible_event_path:
      "Operatör açıkta kalan tahrik elemanına temas ederek kapılabilir",
    exposed_entity: "operator_1",
    barrier_state: "absent_or_failed_event_direct",
    consequence_class: "permanent_disability",
  });
  const result = photoResult(1, [mixerGuard]);
  result.output.scene_inventory = [{
    entity_ref: "CONCRETE-MIXER-1",
    equipment_family: "industrial_mixer concrete_mixer",
    component: "moving_drive_parts",
    visible_condition_summary: "Beton mikseri tahrik bölgesi görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.findings.length, 1);
  assertEquals(product.findings[0].assessment_section, "observed_risk");
  assert(
    (product.qualityTrace.merge_ledger as Array<Record<string, unknown>>).some(
      (entry) => entry.reason_code === "assurance_absorbed_by_observed_finding",
    ),
  );
});

Deno.test("assurance scores are reported separately from active analysis totals", () => {
  const result = photoResult(1, [fact()]);
  result.output.scene_inventory = [{
    entity_ref: "TANK-1",
    equipment_family: "process_vessel",
    component: "tank",
    visible_condition_summary: "Proses tankı görünür",
  }];
  const product = buildEngineProduct([result], "tr", "plus");
  assertEquals(product.analysisResult.total_score_fk, 240);
  assertEquals(product.analysisResult.total_score_m5, 20);
  const totals = product.qualityTrace.score_totals as Record<string, unknown>;
  assertEquals(totals.active_count, 1);
  assertEquals(totals.assurance_count, 1);
  assertEquals(totals.active_fk, 240);
  assertEquals(totals.assurance_fk, 30);
  assertEquals(totals.assurance_excluded_from_analysis_total, true);
  assertStringIncludes(
    String(product.analysisResult.ai_summary),
    "1 kanıtlı risk bulgusu ve 1 ekipman güvence maddesi",
  );
  const assuranceCorrectiveTexts = product.findings.slice(1).map((finding) =>
    String(
      (finding.recommended_measures as Array<Record<string, unknown>>)[0]
        .text,
    )
  );
  assertEquals(new Set(assuranceCorrectiveTexts).size, 1);
  const assuranceRootCauses = product.findings.slice(1).map((finding) =>
    String(finding.root_cause_text)
  );
  assertEquals(new Set(assuranceRootCauses).size, 1);
  assertStringIncludes(assuranceRootCauses[0], "Temel doğrulama konusu");
});

Deno.test("public narratives remove photo numbers and image-coordinate addresses", () => {
  const addressed = fact({
    fact_id: "ADDRESSED-HOUSEKEEPING",
    photo_index: 2,
    entity: {
      ...fact().entity,
      entity_ref: "floor-addressed",
      equipment_family: "work_area",
      component: "walking_surface",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Depo zemininde dağınık karton ve plastik malzeme"],
    },
    observed_condition: {
      condition_code: "CLUTTER_TRIP_HAZARD",
      short_text: "Depo zeminindeki dağınık malzemeler",
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Dağınık malzemeye takılarak düşme",
    credible_event_path: "Çalışan malzemeye takılarak aynı seviyede düşebilir",
    exposed_entity: "person, mobile_equipment",
    technical_assessment: {
      observation_narrative:
        "Fotoğraf 2'de, depo zemininde karton ve plastik malzemeler dağınık halde görülmektedir. Fotoğrafın sağ tarafında bulunan geçiş alanı daralmıştır.",
      technical_significance:
        "Arka planda da bu malzemelerin yaya ve ekipman hareketini engellediği görülmektedir.",
      root_cause_mode: "not_determinable",
      root_cause_text:
        "İkinci fotoğrafta kök neden doğrudan belirlenememektedir.",
    },
    consequence_class: "first_aid",
    frequency_basis: "sector_scene_proxy",
  });
  const finding = buildEngineProduct(
    [photoResult(2, [addressed])],
    "tr",
    "plus",
  ).findings[0];
  const publicText = JSON.stringify({
    title: finding.title,
    description: finding.description,
    root_cause_text: finding.root_cause_text,
    recommended_action: finding.recommended_action,
    recommended_measures: finding.recommended_measures,
  });
  assertFalse(
    /Fotoğraf\s*2|İkinci fotoğraf|sağ taraf|arka plan/iu.test(publicText),
    publicText,
  );
  assertStringIncludes(String(finding.description), "Depo zemininde");
  assertStringIncludes(
    String(finding.description),
    "Etkilenebilecekler: Çalışan ve mobil iş ekipmanı.",
  );
});

Deno.test("spatial-address cleanup preserves a grammatical platform sentence", () => {
  const midrail = fact({
    fact_id: "ADDRESSED-MIDRAIL",
    entity: {
      ...fact().entity,
      entity_ref: "platform-midrail-addressed",
      equipment_family: "platform guardrail",
      component: "midrail",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Üst platform korkuluğunda ara korkuluk bulunmayan açık boşluk",
      ],
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "Üst platform korkuluğunda ara korkuluk eksikliği",
    },
    mechanism_code: "fall_from_height",
    technical_assessment: {
      observation_narrative:
        "Üst platformun sağ tarafındaki korkulukta, ara korkuluğun eksik olduğu görülmektedir.",
      technical_significance:
        "Ara korkuluk boşluğu, platform kenarındaki düşmeyi önleyici bariyeri zayıflatır.",
      root_cause_mode: "not_determinable",
      root_cause_text: "",
    },
    consequence_class: "permanent_disability",
  });
  const description = String(
    buildEngineProduct([photoResult(1, [midrail])], "tr", "plus")
      .findings[0].description,
  );
  assertStringIncludes(description, "Üst platform korkuluğunda");
  assertFalse(
    /sağ taraf|platformun ki|platformun korkulukta/iu.test(description),
  );
});

Deno.test("middle and side photo addresses are removed without dangling Turkish suffixes", () => {
  const addressedHousekeeping = (
    factID: string,
    observation: string,
  ): HazardFactV3 =>
    fact({
      fact_id: factID,
      entity: {
        ...fact().entity,
        entity_ref: factID,
        equipment_family: "other work area",
        component: "floor",
      },
      evidence: {
        normalized_region: fact().evidence.normalized_region,
        affirmative_cues: ["Zeminde dağınık malzeme ve atıklar"],
      },
      observed_condition: {
        condition_code: "housekeeping_poor_debris",
        short_text: "Zeminde dağınık malzeme ve atıklar",
      },
      mechanism_code: "fall_same_level",
      hazard_mechanism: "Dağınık malzemeye takılarak düşme",
      credible_event_path: "Çalışan dağınık malzemeye takılarak düşebilir.",
      consequence_class: "serious_reversible",
      technical_assessment: {
        observation_narrative: observation,
        technical_significance:
          "Dağınık malzeme yaya geçişinde takılma ve düşme oluşturabilir.",
        root_cause_mode: "observed_condition",
        root_cause_text: "Kötü ev idaresi ve düzensiz çalışma alanı.",
      },
    });
  const middle = buildEngineProduct(
    [photoResult(1, [addressedHousekeeping(
      "floor-middle",
      "Fotoğrafın orta kısmındaki zeminde, karton parçaları ve çeşitli atıklar dağınık bir şekilde bulunmaktadır.",
    )])],
    "tr",
    "plus",
  ).findings[0];
  const left = buildEngineProduct(
    [photoResult(1, [addressedHousekeeping(
      "floor-left",
      "Fotoğrafın sol kısmındaki zeminde, metal çerçeveler ve ekipman parçaları düzensiz durmaktadır.",
    )])],
    "tr",
    "plus",
  ).findings[0];
  assertStringIncludes(String(middle.description), "Zeminde");
  assertStringIncludes(String(left.description), "Zeminde");
  const publicText = JSON.stringify([middle, left]);
  assertFalse(
    /Fotoğrafın|orta kısmı|sol kısmı|\bKi zeminde\b|\bTaki\b/iu.test(
      publicText,
    ),
    publicText,
  );
  assertStringIncludes(
    String(middle.root_cause_text),
    "malzeme ve atık toplama",
  );
});

Deno.test("rack stacking uses a specific title and named engineering control", () => {
  const rack = fact({
    fact_id: "RACK-TITLE",
    entity: {
      ...fact().entity,
      entity_ref: "rack-1",
      equipment_family: "storage_racking",
      component: "rack_structure",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Raf üst seviyesinde sınır dışına taşan dengesiz kutu istifi",
      ],
    },
    observed_condition: {
      condition_code: "UNSTABLE_STACKING_RACK",
      short_text: "Raf üzerinde dengesiz istiflenmiş malzemeler",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "Dengesiz istiflenmiş malzemelerin raftan düşmesi",
    credible_event_path: "Malzeme raftan düşerek yakındaki çalışana çarpabilir",
    consequence_class: "serious_reversible",
    control_intents: [{
      action_code: "reorganize_storage",
      target: "rack_structure",
      priority: "immediate",
    }, {
      action_code: "storage_stacking_standard",
      target: "rack_structure",
      priority: "planned",
    }],
  });
  const finding = buildEngineProduct(
    [photoResult(1, [rack])],
    "tr",
    "plus",
  ).findings[0];
  assertEquals(
    finding.title,
    "Raf üst seviyesindeki dengesiz malzeme istifi",
  );
  const controls = JSON.stringify(finding.recommended_measures);
  assertFalse(controls.includes("Hedef bileşeni"));
  assertStringIncludes(controls, "Depolama rafı ve istif");
});

Deno.test("ordinary rocky inclined terrain is not a scored slope finding", () => {
  const terrain = fact({
    fact_id: "ORDINARY-ROCKY-TERRAIN",
    photo_index: 3,
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "site_terrain",
      equipment_family: "site_infrastructure",
      component: "loose_material_slope",
    },
    evidence: {
      normalized_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: [
        "Ekskavatörün kazı yaptığı alan ve çevresindeki engebeli kayalık zemin",
        "Arka plandaki doğal veya yapay eğimli arazi",
        "Kazı sırasında yerinden oynayan toprak ve kaya parçaları",
      ],
    },
    observed_condition: {
      condition_code: "LOOSE_MATERIAL_SLOPE",
      short_text: "Gevşek malzeme ve eğimli arazi",
    },
    mechanism_code: "falling_object",
    hazard_mechanism:
      "Eğimli araziden veya kazı kenarından gevşek malzemenin düşmesi",
    credible_event_path:
      "Gevşek malzeme çalışma alanına yuvarlanarak ekipmana çarpabilir",
    consequence_class: "serious_reversible",
    frequency_basis: "active_single_exposure",
  });
  assertEquals(
    evidenceRejectionReason(terrain),
    "slope_instability_evidence_missing",
  );
  const product = buildEngineProduct(
    [photoResult(3, [terrain])],
    "tr",
    "plus",
  );
  assertEquals(product.findings.length, 0);
  assertEquals(product.analysisResult.total_score_fk, 0);
});

Deno.test("plural Turkish slope wording still requires visible instability geometry", () => {
  const pluralSlope = fact({
    fact_id: "LIVE-PLURAL-SLOPE",
    photo_index: 3,
    assessment_basis: "visible_inherent_hazard",
    entity: {
      ...fact().entity,
      entity_ref: "excavation_area_1",
      equipment_family: "site_infrastructure",
      component: "ground_and_excavation",
    },
    evidence: {
      normalized_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: [
        "Ekskavatörün eğimli ve gevşek zemin üzerinde çalışması",
        "Kazı alanında oluşan şevler",
        "Gevşek toprak ve taş birikintileri",
      ],
    },
    observed_condition: {
      condition_code: "unstable_ground",
      short_text: "Ekskavatörün çalıştığı zeminde gevşek malzeme",
    },
    mechanism_code: "excavation_collapse_rockfall",
    hazard_mechanism: "Kazı alanında malzeme düşmesi veya göçük",
    credible_event_path:
      "Gevşek malzeme hareket ederek ekipmana veya çalışana çarpabilir.",
    consequence_class: "single_fatality",
  });
  assertEquals(
    evidenceRejectionReason(pluralSlope),
    "slope_instability_evidence_missing",
  );
  assertEquals(
    buildEngineProduct(
      [photoResult(3, [pluralSlope])],
      "tr",
      "plus",
    ).findings.length,
    0,
  );
});

Deno.test("uneven excavator ground with pedestrian-fall mechanism gets access controls", () => {
  const unevenAccess = fact({
    fact_id: "UNEVEN-ACCESS",
    entity: {
      ...fact().entity,
      entity_ref: "EXC-GROUND",
      equipment_family: "heavy_equipment excavator quarry",
      component: "uneven_ground_access",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Ekskavatör çevresindeki yaya erişiminde engebeli taşlı zemin",
      ],
    },
    observed_condition: {
      condition_code: "UNEVEN_GROUND_AROUND_EXCAVATOR",
      short_text: "Ekskavatör çevresindeki engebeli zemin",
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Engebeli zeminde takılma ve aynı seviyede düşme",
    credible_event_path: "Çalışan engebeli zeminde takılarak düşebilir.",
    consequence_class: "serious_reversible",
  });
  const product = buildEngineProduct(
    [photoResult(1, [unevenAccess])],
    "tr",
    "plus",
  );
  assertEquals(
    product.findings[0].title,
    "Ekskavatör çevresindeki engebeli zeminde takılma tehlikesi",
  );
  const controls = product.findings[0].recommended_measures as Array<
    Record<string, unknown>
  >;
  assertEquals(controls[0].action_code, "restrict_access");
  assert(
    (controls[1].action_codes as string[]).includes("safe_access_route"),
  );
  assertFalse(JSON.stringify(controls).includes("clear_walkway"));
});

Deno.test("manufacturing targeted selection prefers a visible critical hook component", () => {
  const hookPhoto = photoResult(2, []);
  hookPhoto.output.scene_inventory = [{
    entity_ref: "crane-1-hook",
    equipment_family: "hook_block",
    component: "safety_latch",
    visible_condition_summary: "Kanca mandalı bağlantısı yakından seçilemiyor.",
  }];
  hookPhoto.output.inspection_signals = [{
    signal_id: "hook-check",
    photo_index: 2,
    evidence_region: {
      x: 0.2,
      y: 0.2,
      width: 0.2,
      height: 0.2,
      is_global: false,
    },
    affirmative_cues: [
      "kanca mandalının net görünmemesi",
      "kanca ağzının açık olduğu izlenimi",
    ],
    potential_consequence_class: "serious_reversible",
    reason_code: "critical_component_unclear",
  }];
  const groundPhoto = photoResult(3, []);
  groundPhoto.output.scene_inventory = [{
    entity_ref: "excavator-1",
    equipment_family: "excavator",
    component: "undercarriage",
    visible_condition_summary: "Palet çevresindeki zemin görünür.",
  }];
  groundPhoto.output.inspection_signals = [{
    signal_id: "ground-check",
    photo_index: 3,
    evidence_region: {
      x: 0.1,
      y: 0.6,
      width: 0.7,
      height: 0.3,
      is_global: false,
    },
    affirmative_cues: ["Palet altında dengesiz ve engebeli zemin görülüyor."],
    potential_consequence_class: "permanent_disability",
    reason_code: "stability_unclear",
  }];
  const decision = selectTargetedDecision(
    [hookPhoto, groundPhoto],
    "manufacturing",
  );
  assertEquals(decision.signal?.signal_id, "hook-check");
  assertEquals(decision.candidates[0].sector_critical_component, true);
});

Deno.test("single and multi-photo high-hazard sectors receive one evidence-triggered guardrail coverage pass", () => {
  const guardrailPhoto = photoResult(1, []);
  guardrailPhoto.output.scene_inventory = [{
    entity_ref: "platform-guardrail-1",
    equipment_family: "elevated_work_platform",
    component: "guardrail",
    visible_condition_summary:
      "Küpeşte ve ara korkuluk elemanları görülüyor; etek sacı seçilemiyor.",
  }];
  const photos = [guardrailPhoto, photoResult(2, []), photoResult(3, [])];
  const decision = selectTargetedDecision(photos, "manufacturing");
  assertEquals(
    decision.signal?.reason_code,
    "high_hazard_guardrail_critical_coverage",
  );
  assertEquals(decision.signal?.photo_index, 1);
  assertEquals(decision.signal?.evidence_region.is_global, true);
  assertEquals(
    decision.candidates.filter((candidate) =>
      candidate.reason_code === "high_hazard_guardrail_critical_coverage"
    ).length,
    1,
  );

  const onePhotoDecision = selectTargetedDecision(
    photos.slice(0, 1),
    "manufacturing",
  );
  assertEquals(
    onePhotoDecision.signal?.reason_code,
    "high_hazard_guardrail_critical_coverage",
  );
  assertEquals(
    selectTargetedDecision(photos, "manufacturing", false).signal,
    null,
  );
});

Deno.test("guardrail coverage pass accepts only localized height-barrier facts", () => {
  const guardrailPhoto = photoResult(1, []);
  guardrailPhoto.output.scene_inventory = [{
    entity_ref: "platform-guardrail-1",
    equipment_family: "elevated_work_platform",
    component: "guardrail",
    visible_condition_summary:
      "Platform korkuluk sistemi görünür; ara korkuluk seçilemiyor.",
  }];
  const photos = [guardrailPhoto, photoResult(2, []), photoResult(3, [])];
  const signal = selectTargetedDecision(photos, "manufacturing").signal;
  assert(signal);

  const midrail = fact({
    fact_id: "TARGETED-MIDRAIL",
    entity: {
      ...fact().entity,
      entity_ref: "platform-guardrail-midrail-1",
      equipment_family: "elevated_work_platform",
      component: "midrail",
    },
    observed_condition: {
      condition_code: "missing_midrail",
      short_text: "Platform korkuluğunda ara korkuluk eksikliği",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Korkuluk direkleri arasında açık boşluk ve açıkta kalan kenar",
        "Ara korkuluğun eksik olduğu doğrudan görülüyor",
      ],
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Korkuluk boşluğundan yüksekten düşme",
    credible_event_path:
      "Çalışan ara korkuluk boşluğundan alt seviyeye düşebilir.",
    consequence_class: "permanent_disability",
  });
  const unrelated = fact({
    fact_id: "TARGETED-UNRELATED",
    entity: {
      ...fact().entity,
      entity_ref: "floor-1",
      equipment_family: "work_area",
      component: "floor",
    },
    observed_condition: {
      condition_code: "housekeeping_poor",
      short_text: "Zeminde dağınık malzeme",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: ["Zeminde dağınık malzeme ve geçiş engeli"],
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Dağınık malzemeye takılma",
    credible_event_path: "Çalışan dağınık malzemeye takılarak düşebilir.",
    consequence_class: "serious_reversible",
  });
  const constrained = constrainTargetedFactsWithTrace(
    photos,
    signal,
    [midrail, unrelated],
  );
  assertEquals(constrained.facts.map((item) => item.fact_id), [
    "TARGETED-MIDRAIL",
  ]);
  assertEquals(
    constrained.rejections[0].reason_code,
    "targeted_guardrail_coverage_scope_mismatch",
  );
});

Deno.test("targeted rejection ledger preserves the exact evidence reason", () => {
  const source = photoResult(1, []);
  const signal = {
    signal_id: "hook-check",
    photo_index: 1,
    evidence_region: fact().evidence.normalized_region,
    affirmative_cues: ["Kanca mandalı yatağında açık boşluk görülüyor."],
    potential_consequence_class: "serious_reversible" as const,
    reason_code: "critical_component_unclear",
  };
  source.output.inspection_signals = [signal];
  const ambiguous = fact({
    fact_id: "targeted-hook",
    entity: {
      ...fact().entity,
      equipment_family: "hook_block",
      component: "safety_latch",
    },
    observed_condition: {
      condition_code: "MISSING_OR_OPEN",
      short_text: "Kanca mandalı eksik veya açık",
    },
    evidence: {
      normalized_region: signal.evidence_region,
      affirmative_cues: ["Kanca mandalı eksik veya açık görünüyor."],
    },
    mechanism_code: "falling_object",
  });
  const constrained = constrainTargetedFactsWithTrace(
    [source],
    signal,
    [ambiguous],
  );
  assertEquals(constrained.facts, []);
  assertEquals(
    constrained.rejections[0].reason_code,
    "uncertain_condition_requires_confirmation",
  );
});

Deno.test("public narrative removes generic image directions and unsupported rack capacity claims", () => {
  const rack = fact({
    fact_id: "rack-narrative",
    entity: {
      ...fact().entity,
      entity_ref: "rack-1",
      equipment_family: "storage_rack",
      component: "stacked_boxes",
    },
    evidence: {
      normalized_region: fact().evidence.normalized_region,
      affirmative_cues: [
        "Raf üzerindeki kutular düzensiz ve kenara taşmış biçimde istiflenmiş.",
      ],
    },
    observed_condition: {
      condition_code: "unstable_rack_stacking",
      short_text: "Düzensiz raf istifi",
    },
    mechanism_code: "falling_object",
    hazard_mechanism: "İstiflenen kutuların raftan düşmesi",
    credible_event_path:
      "Kutular raftan düşerek yakındaki çalışana çarpabilir.",
    technical_assessment: {
      observation_narrative:
        "Fabrika zemininde, özellikle sağ ve sol taraflarda düzensiz kutu istifi görülüyor.",
      technical_significance:
        "Raf taşıma kapasitesini aşabilir ve rafın devrilmesine yol açabilir. Kutuların düşmesi yakındaki çalışanı yaralayabilir.",
      root_cause_mode: "observed_condition",
      root_cause_text:
        "Malzemelerin depolama raflarına uygun olmayan şekilde istiflenmesi.",
    },
    consequence_class: "serious_reversible",
  });
  const product = buildEngineProduct([photoResult(1, [rack])], "tr", "free");
  const description = String(product.findings[0].description).toLocaleLowerCase(
    "tr-TR",
  );
  assertFalse(description.includes("sağ ve sol"));
  assertFalse(description.includes("özellikle"));
  assertFalse(description.includes("taşıma kapasitesi"));
  assertFalse(description.includes("rafın devril"));
  assertStringIncludes(description, "kutuların düşmesi");
  assertEquals(
    product.findings[0].root_cause_text,
    "Olası temel etkenler: yüklerin kararsız yerleştirilmesi, raf sınırlarının korunmaması veya istifin düşmeye karşı yeterince tutulmaması.",
  );
});

Deno.test("public narrative removes whole-photo floor addresses and unsupported compliance prose", () => {
  const housekeeping = fact({
    fact_id: "LIVE-HOUSEKEEPING-COPY",
    entity: {
      ...fact().entity,
      entity_ref: "factory-floor",
      equipment_family: "work_area",
      component: "floor",
    },
    observed_condition: {
      condition_code: "housekeeping_poor_debris",
      short_text: "Geçiş alanında dağınık malzemeler",
    },
    evidence: {
      normalized_region: { x: 0, y: 0, width: 1, height: 1, is_global: true },
      affirmative_cues: ["Zeminde dağınık malzeme ve geçiş engelleri"],
    },
    mechanism_code: "fall_same_level",
    hazard_mechanism: "Dağınık malzemeye takılarak düşme",
    credible_event_path: "Çalışan dağınık malzemeye takılarak düşebilir.",
    technical_assessment: {
      observation_narrative:
        "Fotoğrafın genelinde, özellikle sağ ve sol zeminde, dağınık malzemeler ve geçiş engelleri görülmektedir.",
      technical_significance:
        "Bu durum, iş sağlığı ve güvenliği standartlarına uygun olmayan çalışma ortamı oluşturur.",
      root_cause_mode: "not_determinable",
      root_cause_text: "",
    },
    consequence_class: "serious_reversible",
  });
  const description = String(
    buildEngineProduct([photoResult(1, [housekeeping])], "tr", "plus")
      .findings[0].description,
  );
  assertFalse(
    /fotoğrafın genelinde|sağ ve sol|standartlarına uygun olmayan/iu.test(
      description,
    ),
    description,
  );
  assertStringIncludes(description, "Zeminde");
  assertStringIncludes(description, "güvenli hareketi zorlaştıran");
});
