import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type HazardFactV3,
  MODULE_IDS,
  type PhotoAnalysisV3,
} from "./contracts.ts";
import {
  buildEngineProduct,
  evidenceRejectionReason,
  structuredBarrierGateFailures,
} from "./engine.ts";

function fact(overrides: Partial<HazardFactV3> = {}): HazardFactV3 {
  return {
    fact_id: "HF001",
    photo_index: 1,
    assessment_basis: "observed_nonconformity",
    evidence: {
      normalized_region: {
        x: 0.3,
        y: 0.2,
        width: 0.2,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: ["Kenar boyunca çalışan duruyor ve korkuluk yok"],
    },
    entity: {
      entity_ref: "e1",
      equipment_family: "Bina yapısı",
      component: "Döşeme kenarı",
      identity_basis: "beton kat kenarı",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: "unguarded_open_edge",
      short_text: "Döşeme kenarında düşme koruması bulunmamaktadır",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Korunmasız kenardan yüksekten düşme",
    energy_source: "Yerçekimi",
    barrier_state: "absent_or_failed_event_direct",
    initiating_event_state: "Çalışan açık kenarın yanında hareket ediyor",
    credible_event_path: "Çalışan korunmasız kenardan alt kota düşer",
    exposed_entity: "Kenarda çalışan personel",
    technical_assessment: {
      observation_narrative:
        "Kat döşemesinin kenarında korkuluk hattı bulunmamakta ve kenar boyunca çalışma sürmektedir.",
      technical_significance:
        "Kenar koruması yüksekten düşmeye karşı birincil toplu bariyerdir ve bulunmaması tek engeli kaldırır.",
      root_cause_mode: "probable_factor",
      root_cause_text: "Kenar koruma planının uygulanmaması.",
    },
    consequence_class: "single_fatality",
    frequency_basis: "active_single_exposure",
    verification: { model_required: false, reason_code: "" },
    confidence: {
      entity: "high",
      condition: "high",
      localization: "high",
      mechanism: "high",
    },
    depth_tags: ["edge"],
    control_intents: [{
      action_code: "restore_barrier",
      target: "Döşeme kenarı",
      priority: "immediate",
    }],
    ...overrides,
  };
}

function photoResult(facts: HazardFactV3[]) {
  const output: PhotoAnalysisV3 = {
    scene_inventory: [],
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
  return {
    photoID: null,
    photoIndex: 1,
    storagePath: "u/a/photo_1.jpg",
    provider: "gemini",
    model: "gemini-2.5-flash",
    output,
  };
}

function build(facts: HazardFactV3[]) {
  return buildEngineProduct([photoResult(facts)], "tr", "plus");
}

Deno.test("an English entity name never reaches Turkish public text", () => {
  // The live report read "Concrete slab edge yetkin kişiyle ölçülü teknik
  // kontrole al" and carried targets of "Portable cable" and "Mixer drum",
  // because entity.component is spliced into the rendered control sentence
  // verbatim. It cannot be translated here, so the equipment group's own
  // Turkish label stands in.
  const product = build([
    fact({
      entity: {
        entity_ref: "e1",
        equipment_family: "Building structure",
        component: "Concrete slab edge",
        identity_basis: "open floor edge",
        identity_confidence: "high",
      },
    }),
  ]);
  const published = JSON.stringify(product.findings);
  for (const leak of ["Concrete slab edge", "Portable cable", "Mixer drum"]) {
    assertFalse(published.includes(leak), leak);
  }
  assert(published.includes("Çalışma ve geçiş alanı"));
});

Deno.test("total absence of fall protection is not titled as a missing toeboard", () => {
  // FK 900 for a completely unprotected slab edge was published as "Korkuluk
  // sisteminde etek sacı eksikliği", because the condition text listed the
  // toeboard among the absent parts.
  const product = build([
    fact({
      observed_condition: {
        condition_code: "unguarded_open_edge",
        short_text:
          "Döşeme kenarında herhangi bir düşme koruması (korkuluk, etek tahtası) bulunmamaktadır",
      },
    }),
  ]);
  assertEquals(
    product.findings[0].title,
    "Döşeme kenarında düşme koruması bulunmaması",
  );
});

Deno.test("two findings never share one published title", () => {
  // A slab edge at FK 900 and a scaffold platform at FK 420 both resolved to
  // the qualifier "üst" and were published under one identical title. The
  // collision check ran; nothing verified its result.
  const product = build([
    fact({
      fact_id: "HF001",
      entity: {
        entity_ref: "slab_1",
        equipment_family: "Bina yapısı",
        component: "Üst kat döşeme kenarı",
        identity_basis: "üst kat açık kenarı",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "missing_toeboard",
        short_text: "Üst korkulukta etek tahtası eksikliği",
      },
    }),
    fact({
      fact_id: "HF002",
      evidence: {
        normalized_region: {
          x: 0.7,
          y: 0.2,
          width: 0.2,
          height: 0.3,
          is_global: false,
        },
        affirmative_cues: ["Üst platformda etek tahtası boşluğu görülüyor"],
      },
      entity: {
        entity_ref: "scaffold_1",
        equipment_family: "İskele",
        component: "Üst platform korkuluğu",
        identity_basis: "üst iskele platformu",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "missing_toeboard",
        short_text: "Üst korkulukta etek tahtası eksikliği",
      },
      consequence_class: "permanent_disability",
    }),
  ]);
  const titles = product.findings.map((finding) => String(finding.title));
  assertEquals(new Set(titles).size, titles.length, titles.join(" | "));
});

Deno.test("a sharp-edge hazard does not inherit work-at-height controls", () => {
  // Exposed rebar ends on the ground came back with collective fall
  // protection and a storage-rack target, because the fall branch keyed on the
  // bare word "kenar" that both hazards share.
  const product = build([
    fact({
      entity: {
        entity_ref: "rebar_1",
        equipment_family: "İnşaat malzemesi",
        component: "Donatı demirleri",
        identity_basis: "zeminde dağınık donatı",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "exposed_sharp_rebar_ends",
        short_text: "Zeminde keskin uçları açıkta olan donatı demirleri",
      },
      mechanism_code: "sharp_edge_contact",
      hazard_mechanism: "Keskin uca temas ve saplanma",
      credible_event_path:
        "Çalışan zeminde takılır ve açıkta duran keskin uca saplanır",
      evidence: {
        normalized_region: {
          x: 0.2,
          y: 0.7,
          width: 0.3,
          height: 0.2,
          is_global: false,
        },
        affirmative_cues: [
          "Zeminde keskin uçları açıkta duran donatı demirleri",
        ],
      },
      consequence_class: "permanent_disability",
    }),
  ]);
  const published = JSON.stringify(product.findings[0]);
  assertFalse(published.includes("toplu düşmeye karşı koruma"));
  assertFalse(published.includes("Depolama rafı ve istif"));
  assert(published.includes("uç başlığı"));
  assertEquals(
    product.findings[0].category,
    "Keskin kenar ve saplanma güvenliği",
  );
});

Deno.test("an electrical control does not assert an exposed conductor", () => {
  // The finding's own description says damage to the insulation *could*
  // occur; the measure claimed an exposed conductor to correct.
  const cable = fact({
    entity: {
      entity_ref: "cable_1",
      equipment_family: "Elektrik tesisatı",
      component: "Seyyar besleme kablosu",
      identity_basis: "zeminde uzanan kablo",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: "cable_in_standing_water",
      short_text: "Elektrik kablosunun su birikintisi içinde olması",
    },
    mechanism_code: "electrical_contact_arc",
    hazard_mechanism: "Su ile temas eden besleme hattından elektrik çarpması",
    energy_source: "Elektrik enerjisi",
    credible_event_path:
      "Yalıtım zarar görürse su üzerinden çalışana elektrik çarpar",
    evidence: {
      normalized_region: {
        x: 0.4,
        y: 0.8,
        width: 0.3,
        height: 0.1,
        is_global: false,
      },
      affirmative_cues: ["Kablo su birikintisinin içinden geçiyor"],
    },
    technical_assessment: {
      observation_narrative:
        "Zeminde uzanan besleme kablosu su birikintisinin içinden geçmektedir.",
      technical_significance:
        "Su iletken bir ortam olduğundan yalıtım bütünlüğü tek bariyer durumundadır.",
      root_cause_mode: "probable_factor",
      root_cause_text: "Kablonun uygun olmayan güzergâhtan geçirilmesi.",
    },
  });
  const clean = JSON.stringify(build([cable]).findings[0]);
  assertFalse(clean.includes("açık iletken"));

  const damaged = structuredClone(cable);
  damaged.technical_assessment.observation_narrative =
    "Kablonun yalıtımı sıyrılmış, açık iletken su birikintisinin içinde görülmektedir.";
  assert(JSON.stringify(build([damaged]).findings[0]).includes("açık iletken"));
});

Deno.test("a module id in an entity field never reaches a published title", () => {
  // The live run wrote equipment_family as module ids and components as
  // diacritic-stripped snake_case, and a finding was published as
  // "... - Scaffold and ladder".
  const product = build([
    fact({
      fact_id: "HF001",
      entity: {
        entity_ref: "beton_yapi_kat_2",
        equipment_family: "structural_mechanical_integrity",
        component: "beton_doseme_kenari",
        identity_basis: "görsel_kanit",
        identity_confidence: "high",
      },
    }),
    fact({
      fact_id: "HF002",
      entity: {
        entity_ref: "iskele_1",
        equipment_family: "scaffold_and_ladder",
        component: "beton_doseme_kenari",
        identity_basis: "görsel_kanit",
        identity_confidence: "high",
      },
      evidence: {
        normalized_region: {
          x: 0.7,
          y: 0.2,
          width: 0.2,
          height: 0.3,
          is_global: false,
        },
        affirmative_cues: ["Kenarda korkuluk bulunmuyor, çalışan duruyor"],
      },
      consequence_class: "permanent_disability",
    }),
  ]);
  const published = JSON.stringify(product.findings);
  for (
    const leak of [
      "Scaffold and ladder",
      "scaffold_and_ladder",
      "Structural mechanical integrity",
      "beton_doseme_kenari",
      "Beton doseme kenari",
    ]
  ) {
    assertFalse(published.includes(leak), leak);
  }
  const titles = product.findings.map((finding) => String(finding.title));
  assertEquals(new Set(titles).size, titles.length, titles.join(" | "));
});

Deno.test("a named sub-component keeps its own title", () => {
  // A scaffold mid-rail fact inherited "Döşeme kenarında düşme koruması
  // bulunmaması" because the surrounding prose reads like a total absence.
  const product = build([
    fact({
      entity: {
        entity_ref: "iskele_1",
        equipment_family: "İskele",
        component: "Ara korkuluk",
        identity_basis: "üst iskele platformu",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "missing_mid_rail",
        short_text:
          "İskele platformunda ara korkuluk bulunmamaktadır, korumasız kenar oluşmuştur",
      },
      consequence_class: "permanent_disability",
    }),
  ]);
  assertEquals(
    product.findings[0].title,
    "Korkuluk sisteminde ara korkuluk eksikliği",
  );
});

Deno.test("uncapped rebar is scored as a missing barrier, not a reversible cut", () => {
  // Exposed starter bars over a walked slab published at FK 42: the mechanism
  // cap clipped severity to 7 and the inherent-hazard rule floored probability
  // at 1, even though the fact declares an absent barrier.
  const product = build([
    fact({
      assessment_basis: "visible_inherent_hazard",
      entity: {
        entity_ref: "donati_1",
        equipment_family: "Betonarme yapı",
        component: "Donatı çubukları",
        identity_basis: "döşemeden yukarı uzanan filiz demirleri",
        identity_confidence: "high",
      },
      observed_condition: {
        condition_code: "unguarded_sharp_protrusion",
        short_text: "Korumasız sivri donatı çubukları",
      },
      mechanism_code: "sharp_edge_contact",
      hazard_mechanism: "Başlıksız donatı ucuna saplanma",
      credible_event_path:
        "Çalışan dengesini kaybeder ve başlıksız donatı ucuna saplanır",
      barrier_state: "absent_or_failed_event_direct",
      consequence_class: "permanent_disability",
      frequency_basis: "sector_scene_proxy",
      evidence: {
        normalized_region: {
          x: 0.2,
          y: 0.6,
          width: 0.3,
          height: 0.3,
          is_global: false,
        },
        affirmative_cues: [
          "Betonarme yapıdan yukarı doğru uzanan açıkta donatı çubukları",
        ],
      },
    }),
  ]);
  assertEquals(Number(product.findings[0].fk_probability), 6);
  assertEquals(Number(product.findings[0].fk_severity), 15);
});

Deno.test("a partly failed guardrail is not rejected for saying so", () => {
  // The live scaffold fact reported missing_mid_rail with barrier_state
  // partial_event_direct_or_conditional - the top rail is up, the mid-rail is
  // gone - and the gate dropped it for not claiming total absence, even though
  // missing_mid_rail is on its own whitelist.
  const midRail = fact({
    entity: {
      entity_ref: "iskele_korkulugu_1",
      equipment_family: "İskele",
      component: "İskele korkuluğu",
      identity_basis: "üst platform korkuluk sistemi",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: "missing_mid_rail",
      short_text: "Eksik ara korkuluk",
    },
    barrier_state: "partial_event_direct_or_conditional",
    consequence_class: "permanent_disability",
    evidence: {
      normalized_region: {
        x: 0.6,
        y: 0.3,
        width: 0.2,
        height: 0.3,
        is_global: false,
      },
      affirmative_cues: [
        "İskele platformunda üst korkuluk mevcutken ara korkuluk elemanı eksik, çalışan platformda duruyor",
      ],
    },
  });
  assertEquals(evidenceRejectionReason(midRail), null);
  assertFalse(
    structuredBarrierGateFailures(midRail).some((entry) =>
      entry.startsWith("barrier_state:")
    ),
  );

  // A missing toeboard drops objects rather than people.
  const toeBoard = structuredClone(midRail);
  toeBoard.observed_condition = {
    condition_code: "missing_toeboard",
    short_text: "Eksik etek tahtası",
  };
  toeBoard.mechanism_code = "falling_object";
  assertFalse(
    structuredBarrierGateFailures(toeBoard).some((entry) =>
      entry.startsWith("mechanism_mismatch:")
    ),
  );
});

Deno.test("a missing harness at an open edge survives the PPE guard", () => {
  // Fall arrest was treated as ordinary person-worn PPE, so the last barrier
  // left when collective protection is absent could never be reported.
  const harness = fact({
    entity: {
      entity_ref: "personel_1",
      equipment_family: "Personel",
      component: "Paraşüt tipi emniyet kemeri",
      identity_basis: "üst kat döşeme kenarında çalışan personel",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: "missing_fall_arrest_system",
      short_text: "Yüksekte çalışanda düşme durdurma sistemi bulunmaması",
    },
    barrier_state: "absent_or_failed_event_active",
    evidence: {
      normalized_region: {
        x: 0.45,
        y: 0.15,
        width: 0.1,
        height: 0.2,
        is_global: false,
      },
      affirmative_cues: [
        "Korumasız döşeme kenarında çalışan personelin gövdesinde emniyet kemeri veya bağlı bir yaşam hattı görünmüyor",
      ],
    },
  });
  assertEquals(evidenceRejectionReason(harness), null);

  // The exception is fall protection only; a helmet claim is still rejected.
  const helmet = structuredClone(harness);
  helmet.entity.component = "Baret";
  helmet.observed_condition = {
    condition_code: "missing_head_protection",
    short_text: "Çalışanda baret bulunmaması",
  };
  helmet.evidence.affirmative_cues = [
    "Çalışanın başında baret görünmüyor",
  ];
  assertEquals(evidenceRejectionReason(helmet), "contextual_ppe_rejected");
});
