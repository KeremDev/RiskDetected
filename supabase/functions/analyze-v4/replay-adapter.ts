import {
  CORE_MODULE_IDS,
  type Criticality,
  type EvidenceLevel,
  type NormalizedCandidate,
  type ProviderPhotoOutput,
  V4_PROVIDER_CONTRACT_VERSION,
  type V4ModuleID,
} from "./contracts.ts";

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value.trim() : fallback;
}

function confidence(value: unknown): number {
  if (value === "high") return 0.9;
  if (value === "medium") return 0.7;
  if (value === "low") return 0.4;
  const numeric = Number(value);
  return Number.isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : 0.4;
}

function evidenceLevel(cues: string[], values: number[]): EvidenceLevel {
  if (cues.length === 0) return "E0";
  const minimum = Math.min(...values);
  if (minimum < 0.45) return "E2";
  if (minimum < 0.62) return "E3";
  if (minimum < 0.84) return "E4";
  return "E5";
}

function criticality(value: unknown): Criticality {
  const normalized = text(value).toLowerCase();
  if (normalized.includes("fatal")) return "fatal";
  if (normalized.includes("permanent") || normalized.includes("disability")) {
    return "permanent";
  }
  if (normalized.includes("serious")) return "serious";
  return "ordinary";
}

function moduleFor(
  mechanismValue: unknown,
  fact: Record<string, unknown>,
): V4ModuleID {
  const mechanism = text(mechanismValue).toLowerCase();
  const haystack = `${mechanism} ${text(fact.hazard_mechanism)} ${
    text(record(fact.observed_condition).short_text)
  }`.toLowerCase();
  if (["fall_from_height", "falling_object"].includes(mechanism)) {
    return mechanism === "fall_from_height"
      ? "work_at_height"
      : "falls_falling_objects";
  }
  if (mechanism === "fall_same_level") return "access_egress";
  if (["vehicle_equipment_strike", "equipment_overturn"].includes(mechanism)) {
    return "vehicles_mobile_equipment";
  }
  if (mechanism === "caught_in_pinch_shear") return "machinery";
  if (mechanism === "electrical_contact_arc") return "electrical";
  if (mechanism === "fire_explosion") return "fire_explosion_release";
  if (mechanism === "excavation_collapse_rockfall") return "excavation";
  if (mechanism === "chemical_contact_release") return "chemical";
  if (mechanism === "thermal_contact") return "hot_work";
  if (mechanism === "structural_collapse") {
    return /kazı|kazi|excavat|trench|hendek/u.test(haystack)
      ? "excavation"
      : "falls_falling_objects";
  }
  if (
    ["mechanical_separation_release", "hydraulic_pneumatic_release"].includes(
      mechanism,
    )
  ) {
    return "process_integrity";
  }
  if (mechanism === "sharp_edge_contact") {
    return "housekeeping_physical_contact";
  }
  if (/kaldır|kaldir|lifting|vinç|vinc|crane|askı|aski/u.test(haystack)) {
    return "lifting";
  }
  if (/makine|machine|konveyör|konveyor|conveyor/u.test(haystack)) {
    return "machinery";
  }
  if (/elektr|electric|pano|kablo/u.test(haystack)) return "electrical";
  if (/kimyasal|chemical|laboratu/u.test(haystack)) return "chemical";
  return "housekeeping_physical_contact";
}

function normalizedRegion(value: unknown) {
  const region = record(value);
  const x = Number(region.x);
  const y = Number(region.y);
  const width = Number(region.width ?? region.w);
  const height = Number(region.height ?? region.h);
  if ([x, y, width, height].every(Number.isFinite)) {
    return {
      x: Math.max(0, Math.min(1, x)),
      y: Math.max(0, Math.min(1, y)),
      width: Math.max(0.001, Math.min(1, width)),
      height: Math.max(0.001, Math.min(1, height)),
    };
  }
  return undefined;
}

export type ReplayAdaptedPhoto = {
  candidates: NormalizedCandidate[];
  output: ProviderPhotoOutput;
};

export function adaptV3PhotoRunForV4Replay(
  normalizedOutputValue: unknown,
  fallbackPhotoIndex: number,
): ReplayAdaptedPhoto {
  const normalizedOutput = record(normalizedOutputValue);
  const rawFacts = Array.isArray(normalizedOutput.hazard_facts)
    ? normalizedOutput.hazard_facts.map(record)
    : [];
  const candidates = rawFacts.map((fact, index): NormalizedCandidate => {
    const evidence = record(fact.evidence);
    const entity = record(fact.entity);
    const observed = record(fact.observed_condition);
    const verification = record(fact.verification);
    const confidenceRecord = record(fact.confidence);
    const cues = strings(evidence.affirmative_cues);
    const confidenceValues = [
      confidence(confidenceRecord.condition),
      confidence(confidenceRecord.localization),
      confidence(confidenceRecord.mechanism),
    ];
    const photoIndex = Number(fact.photo_index) || fallbackPhotoIndex;
    const assessment = text(fact.assessment_basis);
    const requiresAssurance = assessment === "equipment_integrity_verification";
    const region = normalizedRegion(evidence.normalized_region);
    return {
      id: crypto.randomUUID(),
      candidate_key: text(fact.fact_id, `replay-${photoIndex}-${index + 1}`),
      module_id: moduleFor(fact.mechanism_code, fact),
      raw_label: text(
        observed.short_text,
        text(fact.hazard_mechanism, "Görsel aday"),
      ),
      asset_ref: text(entity.entity_ref) || undefined,
      person_ref: /(?:worker|person|çalışan|calisan|operator|kişi|kisi)/iu.test(
          text(fact.exposed_entity),
        )
        ? text(fact.exposed_entity)
        : undefined,
      affirmative_cues: cues,
      counter_cues: [],
      evidence_region: region,
      occlusion: verification.model_required === true ? "partial" : "none",
      event_path: {
        source: text(
          fact.energy_source,
          text(entity.equipment_family, "kaynak"),
        ),
        contact_or_failure: text(
          fact.hazard_mechanism,
          "tehlikeli temas veya arıza",
        ),
        consequence: text(
          fact.credible_event_path,
          text(fact.consequence_class, "yaralanma"),
        ),
      },
      potential_consequence: criticality(fact.consequence_class),
      visually_resolvable: !requiresAssurance,
      requires_document_or_measurement: requiresAssurance,
      confidence: {
        visibility: confidenceValues[0],
        localization: confidenceValues[1],
        mechanism: confidenceValues[2],
      },
      photo_index: photoIndex,
      evidence_level: evidenceLevel(cues, confidenceValues),
      criticality: criticality(fact.consequence_class),
      condition_code: text(
        observed.condition_code,
        "visible_physical_condition",
      ),
      normalized_label: text(
        observed.short_text,
        text(fact.hazard_mechanism, "Görsel aday"),
      ),
      accessible_event_path: Boolean(text(fact.exposed_entity)) ||
        /(?:erişim|erisim|platform|geçiş|gecis|çalışma|calisma|walkway|access)/iu
          .test(
            `${text(observed.short_text)} ${text(fact.credible_event_path)}`,
          ),
    };
  });
  const output: ProviderPhotoOutput = {
    contract_version: V4_PROVIDER_CONTRACT_VERSION,
    scene_summary: "Kaydedilmiş v3 provider çıktısından sıfır maliyetli replay",
    scene_entities: [],
    people: [],
    accessible_regions:
      candidates.some((candidate) => candidate.accessible_event_path)
        ? [{
          id: `replay-access-${fallbackPhotoIndex}`,
          kind: "replay_access",
          label: "v3 erişim olayı",
          visible: true,
          accessible: true,
        }]
        : [],
    energy_sources: [],
    candidates: candidates.map((candidate) => ({
      candidate_key: candidate.candidate_key,
      module_id: candidate.module_id,
      raw_label: candidate.raw_label,
      asset_ref: candidate.asset_ref,
      person_ref: candidate.person_ref,
      affirmative_cues: candidate.affirmative_cues,
      counter_cues: candidate.counter_cues,
      evidence_region: candidate.evidence_region,
      occlusion: candidate.occlusion,
      event_path: candidate.event_path,
      potential_consequence: candidate.potential_consequence,
      visually_resolvable: candidate.visually_resolvable,
      requires_document_or_measurement:
        candidate.requires_document_or_measurement,
      confidence: candidate.confidence,
    })),
    positive_controls: [],
    module_coverage: CORE_MODULE_IDS.map((moduleID) => ({
      module_id: moduleID,
      activated_by: ["v3_replay_adapter"],
      outcome: "no_actionable_issue_visible",
      entity_refs: [],
      candidate_keys: [],
      note: "V4 provider kapsamı değil; yalnız router replay kaydı",
    })),
    untrusted_embedded_text: [],
  };
  return { candidates, output };
}
