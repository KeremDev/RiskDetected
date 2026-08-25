import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { HazardFactV3 } from "./contracts.ts";
import { structuredBarrierGateFailures } from "./engine.ts";

const ALIAS_ON = { contextualFallBarrierAliasEnabled: true };

function fallFact(conditionCode: string): HazardFactV3 {
  return {
    fact_id: "hf-1",
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
      affirmative_cues: [
        "Döşeme kenarında korkuluk hattı kesintiye uğramış, açık kenar boyunca çalışan duruyor",
      ],
    },
    entity: {
      entity_ref: "building_structure_1",
      equipment_family: "Bina yapısı",
      component: "Döşeme kenarı",
      identity_basis: "beton kalıp üzerindeki açık kat kenarı",
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: conditionCode,
      short_text: "Döşeme kenarında korkuluk eksikliği",
    },
    mechanism_code: "fall_from_height",
    hazard_mechanism: "Korunmasız kenardan yüksekten düşme",
    energy_source: "Yerçekimi",
    barrier_state: "absent_or_failed_event_direct",
    initiating_event_state: "Çalışan açık kenarın hemen yanında hareket ediyor",
    credible_event_path:
      "Çalışan dengesini kaybeder ve korunmasız kenardan alt kota düşer",
    exposed_entity: "Kenarda çalışan personel",
    technical_assessment: {
      observation_narrative:
        "Kat döşemesinin kenarında korkuluk hattı bulunmamakta ve kenar boyunca çalışma sürmektedir.",
      technical_significance:
        "Kenar koruması, yüksekten düşmeye karşı birincil toplu bariyerdir. Bariyerin bulunmaması düşme olayı ile sonuç arasındaki tek engeli kaldırır.",
      root_cause_mode: "probable_factor",
      root_cause_text: "Muhtemel etken kenar koruma planının uygulanmamasıdır.",
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
    depth_tags: ["edge", "fall"],
    control_intents: [{
      action_code: "install_edge_protection",
      target: "Döşeme kenarı",
      priority: "immediate",
    }],
  };
}

function vocabularyFailure(
  conditionCode: string,
  options = ALIAS_ON,
): boolean {
  return structuredBarrierGateFailures(fallFact(conditionCode), options)
    .some((entry) => entry.startsWith("condition_code_not_whitelisted:"));
}

Deno.test("condition codes seen rejecting live fatal fall facts now resolve", () => {
  // 2026-08-24, three consecutive construction analyses: every single_fatality
  // fall fact the model produced died on `absence_only_claim`, because the gate
  // needs a closed vocabulary the prompt never published. The ledger named the
  // exact strings the model invented instead.
  for (
    const code of [
      "unguarded_edge_work",
      "unguarded_edge_work_distant",
      "fall_protection_absent",
      "FALL_PROTECTION_ABSENT",
      "no_guardrail",
      "missing_edge_protection",
      "unprotected_slab_edge",
      "incomplete_guardrail_system",
      "missing_fall_arrest_anchor",
    ]
  ) {
    assertFalse(vocabularyFailure(code), code);
  }
});

Deno.test("the published vocabulary still resolves directly", () => {
  for (
    const code of [
      "missing_guardrail",
      "unguarded_open_edge",
      "missing_mid_rail",
      "missing_toeboard",
    ]
  ) {
    assertFalse(vocabularyFailure(code), code);
  }
});

Deno.test("widening the vocabulary does not widen the mechanism", () => {
  // An absence word alone must not open the fall gate: the code has to name a
  // fall barrier. Otherwise any unmet control would enter through this door.
  for (
    const code of [
      "no_spill_containment",
      "missing_sds_label",
      "open_valve_position",
      "absent_ventilation_record",
    ]
  ) {
    assert(vocabularyFailure(code), code);
  }
});

Deno.test("the alias flag still switches the widened vocabulary off", () => {
  assert(
    vocabularyFailure("unguarded_edge_work", {
      contextualFallBarrierAliasEnabled: false,
    }),
  );
  // The literal map is not flag-gated and must keep working regardless.
  assertFalse(
    vocabularyFailure("missing_guardrail", {
      contextualFallBarrierAliasEnabled: false,
    }),
  );
});

Deno.test("a machine-guard code keeps its own mechanism", () => {
  // missing_machine_guard is whitelisted, so it never reports an unknown
  // vocabulary. It fails the fall fact on mechanism instead.
  assert(
    structuredBarrierGateFailures(fallFact("missing_machine_guard"), ALIAS_ON)
      .some((entry) =>
        entry === "mechanism_mismatch:missing_machine_guard->fall_from_height"
      ),
  );
});
