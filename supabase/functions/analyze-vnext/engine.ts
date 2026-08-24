import {
  type AssessmentBasis,
  type BarrierState,
  type ConfidenceLevel,
  type ConsequenceClass,
  type FrequencyBasis,
  HAZARD_MECHANISM_CODES,
  type HazardFactV3,
  type HazardMechanismCode,
  type InspectionSignalV1,
  MODULE_IDS,
  type ModuleID,
  type PhotoAnalysisV3,
  type RootCauseMode,
  SCHEMA_VERSION,
} from "./contracts.ts";
import {
  getSectorProfile,
  SECTOR_PROFILE_VERSION,
  sectorCheckCodesForEntity,
  sectorEquipmentForEntity,
  type SectorID,
  type SectorProfileV2,
  validSectorModifierEvidence,
} from "./sector-profile.ts";
import {
  ASSET_ASSURANCE_CATALOG_VERSION,
  resolveAssetAssuranceProfiles,
} from "./asset-assurance-catalog.ts";

type RiskBand = "low" | "medium" | "high" | "critical";

export const FINDING_TAXONOMY_VERSION = "finding-taxonomy-v4";

export const FINDING_CATEGORY_CODES = [
  "access_housekeeping",
  "work_at_height",
  "lifting_safety",
  "storage_safety",
  "mobile_equipment_safety",
  "machine_mechanical_safety",
  "pressure_hydraulic_safety",
  "electrical_safety",
  "fire_explosion_safety",
  "structural_integrity",
  "excavation_slope_safety",
  "chemical_safety",
  "thermal_safety",
  "ergonomic_safety",
  "environmental_process_safety",
  "ppe_safety",
  "general_physical_safety",
] as const;

export const EQUIPMENT_GROUP_CODES = [
  "process_equipment",
  "lifting_equipment",
  "mobile_equipment",
  "access_work_area",
  "storage_system",
  "machine_equipment",
  "pressure_equipment",
  "electrical_equipment",
  "structural_system",
  "chemical_storage",
  "rail_system",
  "thermal_equipment",
  "ppe",
  "other_equipment",
] as const;

type FindingCategoryCode = typeof FINDING_CATEGORY_CODES[number];
type EquipmentGroupCode = typeof EQUIPMENT_GROUP_CODES[number];
type AssessmentSection = "observed_risk" | "equipment_assurance";

type FindingTaxonomy = {
  categoryCode: FindingCategoryCode;
  equipmentGroupCode: EquipmentGroupCode;
  assessmentSection: AssessmentSection;
};

export type PhotoResult = {
  photoID: string | null;
  photoIndex: number;
  storagePath: string;
  provider: string;
  model: string;
  output: PhotoAnalysisV3;
  /**
   * Optional so checkpoint replays and fixtures need not synthesize it.
   *
   * Raw fact production has sat at exactly three per photo across prompt
   * versions, output budgets and a schema reordering, and nothing recorded
   * whether the model was filling its output budget or stopping on its own.
   * vNext writes no row to ai_usage_logs, so the question could not be answered
   * from production data at all.
   */
  usage?: {
    inputTokens: number;
    outputTokens: number;
    reasoningTokens: number;
    maxOutputTokens: number;
  };
};

export type FinalFindingV3 = Record<string, unknown> & {
  ordinal: number;
  title: string;
  source_photo_indices: number[];
};

export type EngineProduct = {
  findings: FinalFindingV3[];
  analysisResult: Record<string, unknown>;
  photoSummaries: Array<Record<string, unknown>>;
  factLineage: Array<Record<string, unknown>>;
  moduleAudits: Array<Record<string, unknown>>;
  inspectionSignals: Array<Record<string, unknown>>;
  qualityTrace: Record<string, unknown>;
};

export type EngineReferenceContext = {
  safetyProfileID?: string;
  regulatoryReferencePolicy?: string;
  structuredRegulatoryReferencesEnabled?: boolean;
};

export type EngineSectorContext = {
  sectorID?: SectorID | null;
  source?: "database" | "request_fallback" | "none";
  requestMismatch?: boolean;
  profileEnabled?: boolean;
  frequencyPriorEnabled?: boolean;
  controlPreferencesEnabled?: boolean;
  negativeRulesEnabled?: boolean;
  regulationAnchorsEnabled?: boolean;
};

type AggregatedFact = HazardFactV3 & {
  traceID: string;
  sourcePhotoIndices: number[];
  equivalentEntityRefs: string[];
  evidenceRegions: Array<
    { photo_index: number; region: unknown; cues: string[] }
  >;
  reasonCodes: string[];
};

const CONFIDENCE_VALUE: Record<ConfidenceLevel, number> = {
  low: 0.4,
  medium: 0.72,
  high: 0.9,
};

const P_BY_BARRIER: Record<BarrierState, number> = {
  absent_or_failed_event_active: 10,
  absent_or_failed_event_direct: 6,
  partial_event_direct_or_conditional: 3,
  visible_effective_event_conditional: 1,
  multiple_independent_visible_barriers: 0.5,
};

const F_BY_BASIS: Record<FrequencyBasis, number> = {
  continuous_visible_work: 10,
  daily_repeated_workstation: 6,
  active_single_exposure: 3,
  sector_scene_proxy: 2,
  missing_invalid_fallback: 1,
  catalogued_rare: 0.5,
};

const S_BY_CONSEQUENCE: Record<ConsequenceClass, number> = {
  negligible: 1,
  first_aid: 3,
  serious_reversible: 7,
  permanent_disability: 15,
  single_fatality: 40,
  multiple_fatality_major_environmental: 100,
};

const ALLOWED_CONFIDENCE = new Set(["low", "medium", "high"]);
const ALLOWED_BARRIERS = new Set(Object.keys(P_BY_BARRIER));
const ALLOWED_FREQUENCIES = new Set(Object.keys(F_BY_BASIS));
const ALLOWED_CONSEQUENCES = new Set(Object.keys(S_BY_CONSEQUENCE));
const ALLOWED_ROOT_CAUSE_MODES = new Set([
  "observed_condition",
  "probable_factor",
  "not_determinable",
]);
const ALLOWED_ASSESSMENT_BASES = new Set([
  "observed_nonconformity",
  "visible_inherent_hazard",
  "equipment_integrity_verification",
]);
const ALLOWED_MODULES = new Set<string>(MODULE_IDS);
const ALLOWED_MECHANISM_CODES = new Set<string>(HAZARD_MECHANISM_CODES);
const ALLOWED_MANDATORY_OUTCOMES = new Set([
  "actionable",
  "checked_no_hazard",
  "not_visible",
  "uncertain",
]);
const ALLOWED_SECTOR_CONTEXT_CODES = new Set([
  "visible_active_work",
  "maintenance_state_visible",
  "underground_production_face",
  "manned_control_area",
  "continuous_traffic_visible",
  "continuous_line_operation",
  "daily_animal_care",
]);

function text(value: unknown, max = 800): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

const INVENTORY_SAFETY_CLAIM_PATTERNS = [
  /(?:^|\s)(?:sağlam|saglam|eksiksiz|uygun|güvenli|guvenli)(?:\s|$)/iu,
  /(?:iyi|normal)(?:\s+durumda|\s+görün|\s+gorun)/iu,
  /(?:yapısal|yapisal|mekanik)?\s*bütünlüğ(?:ü|u).{0,24}(?:iyi|sağlam|saglam|uygun)/iu,
  /(?:hasar|kusur|sızıntı|sizinti|aşınma|asinma|gevşeklik|gevseklik|deformasyon|çatlak|catlak|korozyon|kopuk\s+tel|kırık\s+tel|kirik\s+tel).{0,40}(?:yok|değil|degil|görülmüyor|gorulmuyor|görünmüyor|gorunmuyor|görülmemektedir|gorulmemektedir|görünmemektedir|gorunmemektedir|seçilmiyor|secilmiyor|seçilemiyor|secilemiyor|seçilememektedir|secilememektedir|net\s+değil|net\s+degil|net\s+değildir|net\s+degildir)/iu,
  /(?:genel\s+olarak\s+)?(?:temiz|düzenli|duzenli)(?:\s+görün|\s+gorun|\s+durumda|\s*$)/iu,
  /(?:koruyucu|kapak|muhafaza|guard|cover).{0,32}(?:mevcut|yerinde|takılı|takili|present|in place).{0,24}(?:görün|gorun|appear)/iu,
  /(?:appears|looks|is)\s+(?:sound|intact|complete|compliant|safe|in good condition)/iu,
  /(?:no|without)\s+(?:visible\s+)?(?:damage|defect|leak|wear|looseness)/iu,
];

function sanitizeInventorySummary(value: unknown): string {
  const original = text(value, 350);
  if (!original) return "";
  // Preserve a concrete anomaly after a contrast conjunction while removing
  // the unsupported safe-condition claim before it ("genel olarak temiz,
  // ancak dağınık malzemeler..."). Sentence-only filtering discarded both.
  const clauses = original
    .replace(/\s*(?:,|;)?\s*\b(?:ancak|fakat|but|however)\b\s*/giu, "\n")
    .split(/\n|(?<=[.!?])\s+/u)
    .map((clause) => clause.trim())
    .filter(Boolean);
  const retained = clauses.filter((clause) =>
    !INVENTORY_SAFETY_CLAIM_PATTERNS.some((pattern) => pattern.test(clause))
  );
  if (retained.length > 0) return retained.join(" ").slice(0, 350);
  return "Bileşen tanımlandı; bu gözlem tek başına uygunluk sonucu oluşturmaz.";
}

function stringArray(value: unknown, maxItems = 20, maxText = 300): string[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, maxItems).map((item) => text(item, maxText)).filter(
    Boolean,
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function finiteUnit(value: unknown): number | null {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 && number <= 1 ? number : null;
}

function parseRegion(value: unknown, tolerant = false) {
  if (!isRecord(value)) return null;
  const x = finiteUnit(value.x);
  const y = finiteUnit(value.y);
  let width = finiteUnit(value.width);
  let height = finiteUnit(value.height);
  if (x === null || y === null || width === null || height === null) {
    return null;
  }
  if (width <= 0 || height <= 0) {
    return null;
  }
  // The provider schema can constrain every coordinate to [0, 1], but it
  // cannot express x + width <= 1. Gemini occasionally returns a box that
  // extends a few tenths beyond the image (and some vision models use the
  // third/fourth values like xMax/yMax). The request photo is authoritative;
  // clip the box to its real bounds instead of discarding an otherwise valid
  // hazard fact. Strict parsing remains unchanged for persisted fixtures.
  if (tolerant) {
    width = Math.min(width, 1 - x);
    height = Math.min(height, 1 - y);
  }
  if (width <= 0 || height <= 0 || x + width > 1.001 || y + height > 1.001) {
    return null;
  }
  return { x, y, width, height, is_global: value.is_global === true };
}

function parseConfidence(value: unknown): ConfidenceLevel | null {
  const normalized = text(value, 20);
  return ALLOWED_CONFIDENCE.has(normalized)
    ? normalized as ConfidenceLevel
    : null;
}

function inferMechanismCode(value: string): HazardMechanismCode {
  const context = normalized(value);
  if (/(?:takil|trip|same level fall)/.test(context)) return "fall_same_level";
  if (/(?:yuksekten dus|open edge|fall from height)/.test(context)) {
    return "fall_from_height";
  }
  if (/(?:malzeme dus|falling object|dropped object)/.test(context)) {
    return "falling_object";
  }
  if (/(?:arac carp|vehicle strike|equipment strike)/.test(context)) {
    return "vehicle_equipment_strike";
  }
  if (/(?:sikis|ezil|kesil|pinch|shear|crush)/.test(context)) {
    return "caught_in_pinch_shear";
  }
  if (
    /(?:pim|segman|retainer|kanca|hook).*(?:ayril|cik|release|detach)/.test(
      context,
    )
  ) {
    return "mechanical_separation_release";
  }
  if (
    /(?:hidrolik|hydraulic|pnomatik|pneumatic|basincli akiskan|pressure release)/
      .test(context)
  ) {
    return "hydraulic_pneumatic_release";
  }
  if (/(?:elektr|electric|arc|iletken|conductor)/.test(context)) {
    return "electrical_contact_arc";
  }
  if (/(?:yangin|patlama|fire|explosion)/.test(context)) {
    return "fire_explosion";
  }
  if (/(?:yapisal cok|structural collapse)/.test(context)) {
    return "structural_collapse";
  }
  if (/(?:devril|overturn|makine stabil)/.test(context)) {
    return "equipment_overturn";
  }
  if (hasExcavationContext(context)) {
    return "excavation_collapse_rockfall";
  }
  if (/(?:kimyasal|chemical contact|chemical release)/.test(context)) {
    return "chemical_contact_release";
  }
  if (/(?:sicak yuzey|yanik|thermal|burn)/.test(context)) {
    return "thermal_contact";
  }
  if (/(?:keskin|sivri|sharp edge)/.test(context)) return "sharp_edge_contact";
  if (/(?:ergonomi|manual handling|overexertion)/.test(context)) {
    return "ergonomic_overexertion";
  }
  if (/(?:cevre|environmental release|spill)/.test(context)) {
    return "environmental_release";
  }
  return "other_visible_physical";
}

function parseFact(
  value: unknown,
  photoIndex: number,
  tolerant = false,
): HazardFactV3 | null {
  if (!isRecord(value)) return null;
  // Each provider call contains exactly one trusted photo. A model-emitted
  // photo_index is lineage metadata, not an authority boundary. Rebind it in
  // tolerant mode so a repeated `1` in FOTO_3 cannot invalidate every fact.
  if (!tolerant && Number(value.photo_index) !== photoIndex) return null;
  const evidence = isRecord(value.evidence) ? value.evidence : null;
  const entity = isRecord(value.entity) ? value.entity : null;
  const condition = isRecord(value.observed_condition)
    ? value.observed_condition
    : null;
  const verification = isRecord(value.verification)
    ? value.verification
    : tolerant
    ? {}
    : null;
  const technicalAssessment = isRecord(value.technical_assessment)
    ? value.technical_assessment
    : tolerant
    ? {}
    : null;
  const confidence = isRecord(value.confidence) ? value.confidence : null;
  const region = parseRegion(evidence?.normalized_region, tolerant);
  const entityConfidence = parseConfidence(confidence?.entity);
  const conditionConfidence = parseConfidence(confidence?.condition);
  const localizationConfidence = parseConfidence(confidence?.localization);
  const mechanismConfidence = parseConfidence(confidence?.mechanism);
  const identityConfidence = parseConfidence(entity?.identity_confidence) ??
    (tolerant ? entityConfidence : null);
  const barrier = text(value.barrier_state, 80);
  const assessmentBasisValue = text(value.assessment_basis, 80);
  const assessmentBasis = ALLOWED_ASSESSMENT_BASES.has(assessmentBasisValue)
    ? assessmentBasisValue as AssessmentBasis
    : tolerant
    ? "observed_nonconformity"
    : null;
  const frequency = text(value.frequency_basis, 80);
  const consequence = text(value.consequence_class, 100);
  const mechanismText = text(value.hazard_mechanism, 350);
  const mechanismCodeText = text(value.mechanism_code, 100);
  const mechanismCode = ALLOWED_MECHANISM_CODES.has(mechanismCodeText)
    ? mechanismCodeText as HazardMechanismCode
    : tolerant
    ? inferMechanismCode(
      `${text(condition?.condition_code, 120)} ${
        text(condition?.short_text, 500)
      } ${mechanismText} ${text(value.credible_event_path, 600)}`,
    )
    : null;
  if (
    !region || !entity || !condition || !verification ||
    !technicalAssessment || !confidence ||
    !entityConfidence || !conditionConfidence || !localizationConfidence ||
    !mechanismConfidence || !identityConfidence || !mechanismCode ||
    !assessmentBasis ||
    !ALLOWED_BARRIERS.has(barrier) || !ALLOWED_FREQUENCIES.has(frequency) ||
    !ALLOWED_CONSEQUENCES.has(consequence)
  ) return null;
  const cues = stringArray(evidence?.affirmative_cues, 12, 350);
  const factID = text(value.fact_id, 120);
  const equipment = text(entity.equipment_family, 160);
  const component = text(entity.component, 160);
  const conditionText = text(condition.short_text, 500);
  const conditionCode = text(condition.condition_code, 120) ||
    (tolerant
      ? normalized(conditionText).replace(/\s+/g, "_").slice(0, 120)
      : "");
  const mechanism = mechanismText;
  const eventPath = text(value.credible_event_path, 600);
  const rootCauseModeValue = text(
    technicalAssessment.root_cause_mode,
    40,
  );
  const rootCauseMode = ALLOWED_ROOT_CAUSE_MODES.has(rootCauseModeValue)
    ? rootCauseModeValue as RootCauseMode
    : tolerant
    ? "not_determinable"
    : null;
  if (
    !factID || !equipment || !component || !conditionCode || !conditionText ||
    !mechanism || !eventPath || !rootCauseMode
  ) return null;
  const controlIntents = Array.isArray(value.control_intents)
    ? value.control_intents.slice(0, 8).flatMap((raw) => {
      if (!isRecord(raw)) return [];
      const priority = text(raw.priority, 20);
      const actionCode = text(raw.action_code, 100);
      const target = text(raw.target, 240);
      if (
        !actionCode || !target ||
        !["immediate", "planned", "monitor"].includes(priority)
      ) return [];
      return [{
        action_code: actionCode,
        target,
        priority: priority as "immediate" | "planned" | "monitor",
      }];
    })
    : [];
  return {
    fact_id: factID,
    photo_index: photoIndex,
    assessment_basis: assessmentBasis,
    evidence: { normalized_region: region, affirmative_cues: cues },
    entity: {
      entity_ref: text(entity.entity_ref, 120) || factID,
      equipment_family: equipment,
      component,
      identity_basis: text(entity.identity_basis, 350),
      identity_confidence: identityConfidence,
    },
    observed_condition: {
      condition_code: conditionCode,
      short_text: conditionText,
    },
    mechanism_code: mechanismCode,
    hazard_mechanism: mechanism,
    energy_source: text(value.energy_source, 240),
    barrier_state: barrier as BarrierState,
    initiating_event_state: text(value.initiating_event_state, 350),
    credible_event_path: eventPath,
    exposed_entity: text(value.exposed_entity, 240),
    technical_assessment: {
      observation_narrative: text(
        technicalAssessment.observation_narrative,
        1_200,
      ),
      technical_significance: text(
        technicalAssessment.technical_significance,
        1_600,
      ),
      root_cause_mode: rootCauseMode,
      root_cause_text: text(technicalAssessment.root_cause_text, 900),
    },
    consequence_class: consequence as ConsequenceClass,
    frequency_basis: frequency as FrequencyBasis,
    verification: {
      // A missing verification object is repaired conservatively. It may
      // promote field verification, but can never suppress a model `true`.
      model_required: verification.model_required === true ||
        (tolerant && !isRecord(value.verification)),
      reason_code: text(verification.reason_code, 160) ||
        (tolerant && !isRecord(value.verification)
          ? "schema_repaired_missing_verification"
          : ""),
    },
    confidence: {
      entity: entityConfidence,
      condition: conditionConfidence,
      localization: localizationConfidence,
      mechanism: mechanismConfidence,
    },
    depth_tags: stringArray(value.depth_tags, 20, 100),
    control_intents: controlIntents,
  };
}

function rawInspectionSignalID(value: unknown): string {
  return text(value, 160).replace(/^p\d+:s\d+:/u, "").slice(0, 120);
}

export function canonicalInspectionSignalID(
  value: unknown,
  photoIndex: number,
  signalIndex: number,
): string {
  const rawID = rawInspectionSignalID(value);
  return rawID ? `p${photoIndex}:s${signalIndex + 1}:${rawID}` : "";
}

export function inspectionSignalIDsEquivalent(
  left: unknown,
  right: unknown,
): boolean {
  const leftID = rawInspectionSignalID(left);
  return leftID.length > 0 && leftID === rawInspectionSignalID(right);
}

function parseSignal(
  value: unknown,
  photoIndex: number,
  tolerant = false,
  signalIndex = 0,
): InspectionSignalV1 | null {
  if (!isRecord(value)) return null;
  if (!tolerant && Number(value.photo_index) !== photoIndex) return null;
  const region = parseRegion(value.evidence_region, tolerant);
  const consequence = text(value.potential_consequence_class, 100);
  const cues = stringArray(value.affirmative_cues, 8, 350);
  const signalID = canonicalInspectionSignalID(
    value.signal_id,
    photoIndex,
    signalIndex,
  );
  const reasonCode = text(value.reason_code, 160);
  if (
    !region || !signalID || !reasonCode || cues.length === 0 ||
    !ALLOWED_CONSEQUENCES.has(consequence)
  ) return null;
  return {
    signal_id: signalID,
    photo_index: photoIndex,
    evidence_region: region,
    affirmative_cues: cues,
    potential_consequence_class: consequence as ConsequenceClass,
    reason_code: reasonCode,
  };
}

function completeModuleAudits(
  audits: PhotoAnalysisV3["module_audit"],
): PhotoAnalysisV3["module_audit"] {
  const byID = new Map(audits.map((audit) => [audit.module_id, audit]));
  return MODULE_IDS.map((moduleID) =>
    byID.get(moduleID) ?? {
      module_id: moduleID,
      entity_refs: [],
      status: "not_applicable" as const,
    }
  );
}

const COMPACT_FACT_MODULES: Record<
  HazardMechanismCode,
  readonly ModuleID[]
> = {
  fall_same_level: ["egress_housekeeping"],
  fall_from_height: ["access_and_work_at_height", "scaffold_and_ladder"],
  falling_object: ["lifting_operations", "egress_housekeeping"],
  vehicle_equipment_strike: ["mobile_equipment_traffic"],
  caught_in_pinch_shear: ["machine_safety_loto"],
  mechanical_separation_release: [
    "structural_mechanical_integrity",
    "lifting_operations",
  ],
  hydraulic_pneumatic_release: [
    "pipe_hose_connections",
    "pressure_process_safety",
  ],
  electrical_contact_arc: ["electrical_safety"],
  fire_explosion: ["hot_work_fire_explosion"],
  structural_collapse: ["structural_mechanical_integrity"],
  equipment_overturn: ["mobile_equipment_traffic"],
  excavation_collapse_rockfall: ["excavation_slope_shoring"],
  chemical_contact_release: ["chemical_risk"],
  thermal_contact: ["hot_work_fire_explosion"],
  sharp_edge_contact: ["machine_safety_loto", "egress_housekeeping"],
  ergonomic_overexertion: ["ergonomics"],
  environmental_release: ["environmental_release_leak"],
  other_visible_physical: ["sector_specific"],
};

function compactScannedModuleIDs(raw: unknown): ModuleID[] {
  if (!isRecord(raw) || !Array.isArray(raw.scanned_module_ids)) return [];
  return [
    ...new Set(raw.scanned_module_ids.flatMap((value) => {
      const moduleID = text(value, 120);
      return ALLOWED_MODULES.has(moduleID) ? [moduleID as ModuleID] : [];
    })),
  ].slice(0, MODULE_IDS.length);
}

function compactModuleAudits(
  scannedModuleIDs: ModuleID[],
  facts: HazardFactV3[],
  mandatoryOutcomes: PhotoAnalysisV3["mandatory_module_outcomes"],
): PhotoAnalysisV3["module_audit"] {
  const positiveRefs = new Map<ModuleID, Set<string>>();
  const addPositive = (moduleID: ModuleID, refs: string[]) => {
    const current = positiveRefs.get(moduleID) ?? new Set<string>();
    refs.filter(Boolean).forEach((ref) => current.add(ref));
    positiveRefs.set(moduleID, current);
  };
  for (const fact of facts) {
    for (const moduleID of COMPACT_FACT_MODULES[fact.mechanism_code]) {
      addPositive(moduleID, [fact.entity.entity_ref]);
    }
  }
  for (const outcome of mandatoryOutcomes) {
    if (outcome.status === "actionable") {
      addPositive(outcome.module_id, outcome.entity_refs);
    }
  }
  return scannedModuleIDs.map((moduleID) => {
    const refs = [...(positiveRefs.get(moduleID) ?? [])];
    return {
      module_id: moduleID,
      entity_refs: refs,
      status: refs.length > 0
        ? "positive_evidence" as const
        : "scanned_no_positive_evidence" as const,
    };
  });
}

function suppliedModuleIDs(raw: unknown): Set<string> {
  if (!isRecord(raw)) return new Set();
  const legacy = Array.isArray(raw.module_audit)
    ? raw.module_audit.flatMap((item) =>
      isRecord(item) && ALLOWED_MODULES.has(text(item.module_id, 120))
        ? [text(item.module_id, 120)]
        : []
    )
    : [];
  return new Set([...legacy, ...compactScannedModuleIDs(raw)]);
}

function parseMandatoryModuleOutcomes(
  value: unknown,
): PhotoAnalysisV3["mandatory_module_outcomes"] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.slice(0, MODULE_IDS.length).flatMap((item) => {
    if (!isRecord(item)) return [];
    const moduleID = text(item.module_id, 120);
    const status = text(item.status, 80);
    if (
      seen.has(moduleID) || !ALLOWED_MODULES.has(moduleID) ||
      !ALLOWED_MANDATORY_OUTCOMES.has(status)
    ) return [];
    seen.add(moduleID);
    return [{
      module_id: moduleID as ModuleID,
      entity_refs: stringArray(item.entity_refs, 30, 120),
      status: status as PhotoAnalysisV3["mandatory_module_outcomes"][number][
        "status"
      ],
    }];
  });
}

function parseSectorContextEvidence(
  value: unknown,
): PhotoAnalysisV3["sector_context_evidence"] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 6).flatMap((item) => {
    if (!isRecord(item)) return [];
    const code = text(item.code, 120);
    const entityRefs = stringArray(item.entity_refs, 20, 120);
    const affirmativeCues = stringArray(item.affirmative_cues, 12, 350);
    if (!ALLOWED_SECTOR_CONTEXT_CODES.has(code)) return [];
    return [{
      code: code as PhotoAnalysisV3["sector_context_evidence"][number]["code"],
      entity_refs: entityRefs,
      affirmative_cues: affirmativeCues,
    }];
  });
}

export function parsePhotoAnalysisV3(
  raw: unknown,
  photoIndex: number,
): PhotoAnalysisV3 {
  if (!isRecord(raw)) throw new Error("schema_root_invalid");
  const rawAudits = Array.isArray(raw.module_audit) ? raw.module_audit : [];
  const moduleAudit = rawAudits.flatMap((item) => {
    if (!isRecord(item)) return [];
    const moduleID = text(item.module_id, 120);
    const status = text(item.status, 80);
    if (
      !ALLOWED_MODULES.has(moduleID) ||
      ![
        "not_applicable",
        "scanned_no_positive_evidence",
        "positive_evidence",
      ].includes(status)
    ) return [];
    return [{
      module_id: moduleID as typeof MODULE_IDS[number],
      entity_refs: stringArray(item.entity_refs, 30, 120),
      status: status as
        | "not_applicable"
        | "scanned_no_positive_evidence"
        | "positive_evidence",
    }];
  });
  const rawFacts = Array.isArray(raw.hazard_facts) ? raw.hazard_facts : [];
  if (rawFacts.length > 50) throw new Error("schema_fact_limit_exceeded");
  const facts = rawFacts.map((item) => parseFact(item, photoIndex));
  if (facts.some((item) => item === null)) {
    throw new Error("schema_fact_invalid");
  }
  const rawSignals = Array.isArray(raw.inspection_signals)
    ? raw.inspection_signals
    : [];
  const signals = rawSignals.map((item, signalIndex) =>
    parseSignal(item, photoIndex, false, signalIndex)
  );
  if (signals.some((item) => item === null)) {
    throw new Error("schema_signal_invalid");
  }
  const sceneInventory = Array.isArray(raw.scene_inventory)
    ? raw.scene_inventory.slice(0, 60).flatMap((item) => {
      if (!isRecord(item)) return [];
      const entityRef = text(item.entity_ref, 120);
      const equipment = text(item.equipment_family, 160);
      const component = text(item.component, 160);
      if (!entityRef || !equipment || !component) return [];
      return [{
        entity_ref: entityRef,
        equipment_family: equipment,
        component,
        visible_condition_summary: sanitizeInventorySummary(
          item.visible_condition_summary,
        ),
      }];
    })
    : [];
  const mandatoryModuleOutcomes = parseMandatoryModuleOutcomes(
    raw.mandatory_module_outcomes,
  );
  const effectiveModuleAudit = rawAudits.length > 0
    ? moduleAudit
    : compactModuleAudits(
      compactScannedModuleIDs(raw),
      facts as HazardFactV3[],
      mandatoryModuleOutcomes,
    );
  return {
    scene_inventory: sceneInventory,
    module_audit: completeModuleAudits(effectiveModuleAudit),
    mandatory_module_outcomes: mandatoryModuleOutcomes,
    sector_context_evidence: parseSectorContextEvidence(
      raw.sector_context_evidence,
    ),
    hazard_facts: facts as HazardFactV3[],
    inspection_signals: signals as InspectionSignalV1[],
  };
}

/**
 * Preserves individually valid facts when an auxiliary audit or a sibling
 * record violates the provider schema. This is deliberately stricter than a
 * generic JSON repair: it never invents evidence, facts or missing audits.
 */
export function parsePhotoAnalysisV3WithSalvage(
  raw: unknown,
  photoIndex: number,
): PhotoAnalysisV3 {
  const savedDiagnostics = isRecord(raw) &&
      isRecord(raw._schema_diagnostics_v1) &&
      raw._schema_diagnostics_v1.salvaged === true
    ? raw._schema_diagnostics_v1 as PhotoAnalysisV3["_schema_diagnostics_v1"]
    : null;
  try {
    const output = parsePhotoAnalysisV3(raw, photoIndex);
    const suppliedModules = suppliedModuleIDs(raw);
    const defaultedModules = MODULE_IDS.filter((id) =>
      !suppliedModules.has(id)
    );
    return {
      ...output,
      _schema_diagnostics_v1: savedDiagnostics ?? {
        salvaged: false,
        strict_error_code: null,
        raw_fact_count: output.hazard_facts.length,
        valid_fact_count: output.hazard_facts.length,
        invalid_fact_count: 0,
        raw_signal_count: output.inspection_signals.length,
        invalid_signal_count: 0,
        missing_module_ids: defaultedModules,
        duplicate_module_ids: [],
        reason_codes: defaultedModules.length > 0
          ? ["module_audit_server_defaulted"]
          : [],
      },
    };
  } catch (strictError) {
    if (!isRecord(raw)) throw strictError;
    const strictErrorCode = strictError instanceof Error
      ? strictError.message.slice(0, 160)
      : "schema_unknown_error";
    const rawAudits = Array.isArray(raw.module_audit) ? raw.module_audit : [];
    const auditsByModule = new Map<
      string,
      PhotoAnalysisV3["module_audit"][number]
    >();
    const duplicateModules = new Set<string>();
    for (const item of rawAudits) {
      if (!isRecord(item)) continue;
      const moduleID = text(item.module_id, 120);
      const status = text(item.status, 80);
      if (
        !ALLOWED_MODULES.has(moduleID) ||
        ![
          "not_applicable",
          "scanned_no_positive_evidence",
          "positive_evidence",
        ].includes(status)
      ) continue;
      if (auditsByModule.has(moduleID)) {
        duplicateModules.add(moduleID);
        continue;
      }
      auditsByModule.set(moduleID, {
        module_id: moduleID as typeof MODULE_IDS[number],
        entity_refs: stringArray(item.entity_refs, 30, 120),
        status: status as
          | "not_applicable"
          | "scanned_no_positive_evidence"
          | "positive_evidence",
      });
    }
    const suppliedModules = suppliedModuleIDs(raw);
    const missingModules = MODULE_IDS.filter((id) => !suppliedModules.has(id));
    const rawFacts = Array.isArray(raw.hazard_facts) ? raw.hazard_facts : [];
    if (rawFacts.length > 50) throw new Error("schema_fact_limit_exceeded");
    const salvageReasonCodes = new Set<string>();
    const validFacts = rawFacts.flatMap((item) => {
      if (isRecord(item)) {
        if (Number(item.photo_index) !== photoIndex) {
          salvageReasonCodes.add("fact_photo_index_rebound");
        }
        const region = isRecord(item.evidence) &&
            isRecord(item.evidence.normalized_region)
          ? item.evidence.normalized_region
          : null;
        if (
          region &&
          (Number(region.x) + Number(region.width) > 1.001 ||
            Number(region.y) + Number(region.height) > 1.001)
        ) {
          salvageReasonCodes.add("evidence_region_clipped");
        }
        if (!isRecord(item.verification)) {
          salvageReasonCodes.add("verification_defaulted_required");
        }
        if (
          !isRecord(item.technical_assessment) ||
          !ALLOWED_ROOT_CAUSE_MODES.has(
            text(
              isRecord(item.technical_assessment)
                ? item.technical_assessment.root_cause_mode
                : null,
              40,
            ),
          )
        ) {
          salvageReasonCodes.add("technical_assessment_defaulted");
        }
        if (
          isRecord(item.entity) &&
          !parseConfidence(item.entity.identity_confidence) &&
          isRecord(item.confidence) && parseConfidence(item.confidence.entity)
        ) {
          salvageReasonCodes.add("identity_confidence_reused");
        }
        if (!ALLOWED_MECHANISM_CODES.has(text(item.mechanism_code, 100))) {
          salvageReasonCodes.add("mechanism_code_inferred");
        }
        if (!ALLOWED_ASSESSMENT_BASES.has(text(item.assessment_basis, 80))) {
          salvageReasonCodes.add("assessment_basis_defaulted");
        }
      }
      const parsed = parseFact(item, photoIndex, true);
      return parsed ? [parsed] : [];
    });
    if (rawFacts.length > 0 && validFacts.length === 0) {
      const first = rawFacts[0];
      let reason = "unknown";
      if (!isRecord(first)) reason = "record";
      else if (
        !isRecord(first.evidence) ||
        !parseRegion(first.evidence.normalized_region, true)
      ) {
        reason = "region";
      } else if (!isRecord(first.entity)) reason = "entity";
      else if (!isRecord(first.confidence)) reason = "confidence";
      else if (!isRecord(first.observed_condition)) reason = "condition";
      else reason = "required_field_or_enum";
      throw new Error(`schema_all_facts_invalid_${reason}`);
    }
    const rawSignals = Array.isArray(raw.inspection_signals)
      ? raw.inspection_signals
      : [];
    const validSignals = rawSignals.flatMap((item, signalIndex) => {
      const parsed = parseSignal(item, photoIndex, true, signalIndex);
      return parsed ? [parsed] : [];
    });
    const sceneInventory = Array.isArray(raw.scene_inventory)
      ? raw.scene_inventory.slice(0, 60).flatMap((item) => {
        if (!isRecord(item)) return [];
        const entityRef = text(item.entity_ref, 120);
        const equipment = text(item.equipment_family, 160);
        const component = text(item.component, 160);
        if (!entityRef || !equipment || !component) return [];
        return [{
          entity_ref: entityRef,
          equipment_family: equipment,
          component,
          visible_condition_summary: sanitizeInventorySummary(
            item.visible_condition_summary,
          ),
        }];
      })
      : [];
    if (sceneInventory.length === 0 && validFacts.length === 0) {
      throw new Error("schema_salvage_empty");
    }
    const invalidFactCount = rawFacts.length - validFacts.length;
    const invalidSignalCount = rawSignals.length - validSignals.length;
    const reasonCodes = [
      "provider_schema_salvaged",
      ...salvageReasonCodes,
    ];
    if (invalidFactCount > 0) reasonCodes.push("invalid_record");
    if (invalidSignalCount > 0) reasonCodes.push("invalid_signal_record");
    if (missingModules.length > 0) {
      reasonCodes.push("module_audit_incomplete");
    }
    if (duplicateModules.size > 0) {
      reasonCodes.push("module_audit_duplicate");
    }
    const mandatoryModuleOutcomes = parseMandatoryModuleOutcomes(
      raw.mandatory_module_outcomes,
    );
    const effectiveAudits = rawAudits.length > 0
      ? [...auditsByModule.values()]
      : compactModuleAudits(
        compactScannedModuleIDs(raw),
        validFacts,
        mandatoryModuleOutcomes,
      );
    return {
      scene_inventory: sceneInventory,
      module_audit: completeModuleAudits(effectiveAudits),
      mandatory_module_outcomes: mandatoryModuleOutcomes,
      sector_context_evidence: parseSectorContextEvidence(
        raw.sector_context_evidence,
      ),
      hazard_facts: validFacts,
      inspection_signals: validSignals,
      _schema_diagnostics_v1: savedDiagnostics ?? {
        salvaged: true,
        strict_error_code: strictErrorCode,
        raw_fact_count: rawFacts.length,
        valid_fact_count: validFacts.length,
        invalid_fact_count: invalidFactCount,
        raw_signal_count: rawSignals.length,
        invalid_signal_count: invalidSignalCount,
        missing_module_ids: missingModules,
        duplicate_module_ids: [...duplicateModules],
        reason_codes: reasonCodes,
      },
    };
  }
}

function normalized(value: string): string {
  // Locale-aware Turkish lowercasing corrupts English enum codes (TRIP ->
  // trıp, PINCH -> pınch). Fold both Turkish prose and English codes to the
  // same ASCII comparison alphabet before applying deterministic policies.
  return value.toLowerCase().normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "").replace(/ı/g, "i")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

// Keep every policy layer on the same canonical vocabulary. A live regression
// used the common Turkish term "etek sacı" while the evidence gate only knew
// "etek tahtası"; the fact was therefore rejected even though the cue also
// described an open edge. These expressions intentionally consume normalized
// ASCII text produced by `normalized`.
const TOE_BOARD_COMPONENT_PATTERN =
  /(?:toe board|toeboard|kick plate|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik)/u;
const MIDRAIL_COMPONENT_PATTERN =
  /(?:midrail|mid rail|intermediate rail|intermediate barrier(?: element)?|ara korkuluk|orta korkuluk|ara bariyer(?: elemani)?|orta bariyer(?: elemani)?|ara elemani)/u;
const GUARDRAIL_COMPONENT_PATTERN =
  /(?:guardrail|railing|korkuluk|midrail|mid rail|intermediate rail|ara korkuluk|orta korkuluk|ara bariyer|orta bariyer|ara elemani|toe board|toeboard|kick plate|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik)/u;
const SAFETY_CRITICAL_HARDWARE_PATTERN =
  /(?:hook|kanca|latch|mandal|retainer|segman|safety pin|emniyet pimi|guard|koruyucu|machine guard|makine koruyucu|guardrail|railing|korkuluk|midrail|mid rail|ara korkuluk|orta korkuluk|toe board|toeboard|kick plate|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik)/u;

function hasExplicitSlopeContext(value: string): boolean {
  const context = normalized(value);
  return /(?:(?:^| )sev(?:ler)?(?:de|den|in|i|e)?(?: |$)|slope|rockfall|kaya dusmesi|excavation face|kazi aynasi|background slope|steep slope|iksa)/u
    .test(context);
}

function hasExcavationContext(value: string): boolean {
  const context = normalized(value);
  return hasExplicitSlopeContext(context) ||
    /(?:excavation|excavat|kazi|kazma|kaziyor|digging|quarry|ocak|bucket|kova|kepce)/u
      .test(context);
}

const ABSENCE_ONLY_PATTERNS = [
  /(?:belge|kayıt|kayit|sertifika|rapor|film|etiket).{0,28}(?:görünmüyor|gorunmuyor|yok|okunmuyor|bilinmiyor)/iu,
  /(?:görsel|goruntu|fotoğraf|fotograf).{0,24}(?:dışında|disinda).{0,28}(?:bilinmiyor|belirsiz|görünmüyor|gorunmuyor)/iu,
  /(?:whether|unknown|unclear).{0,30}(?:record|certificate|inspection|label|outside)/iu,
  /(?:record|certificate|inspection report|label).{0,30}(?:not visible|missing from the photo|cannot be read)/iu,
];

const VISUAL_ABSENCE_PATTERNS = [
  /(?:görünmüyor|gorunmuyor|bulunmuyor|takmaması|takmamasi|takılı değil|takili degil|takılı olmayıp|takili olmayip|yokluğu|yoklugu|\byok\b|eksikliği|eksikligi|\beksik\b)/iu,
  /(?:not visible|not present|not worn|without wearing|cannot be seen|appears missing|\bmissing\b|\babsent\b)/iu,
];

const POSITIVE_ABSENCE_GEOMETRY_PATTERNS = [
  /(?:boş|bos|açık|acik)\s+(?:yuva|delik|kanal|bağlantı noktası|baglanti noktasi|kenar|boşluk|bosluk)/iu,
  /(?:korunmasız|korunmasiz|çıplak|ciplak|açığa çıkmış|aciga cikmis)\s+(?:kenar|iletken|hareketli|temas)/iu,
  /(?:empty|open|unoccupied)\s+(?:hole|slot|groove|mount|edge|opening)/iu,
  /(?:exposed)\s+(?:conductor|moving part|edge|opening)/iu,
  /(?:dışa|disa)\s+kaymış|yerinden\s+çıkmış|yerinden\s+cikmis|displaced|partially\s+withdrawn/iu,
  /(?:pim|pin).{0,32}(?:ucu|end).{0,24}(?:kanal|delik|groove|hole).{0,20}(?:boş|bos|açık|acik|empty|open)/iu,
  /(?:mandal|latch|segman|retainer).{0,32}(?:yuva|yatak|kanal|bağlantı noktası|baglanti noktasi|mount|slot|groove).{0,20}(?:boş|bos|açık|acik|empty|open)/iu,
  /(?:mandal|latch).{0,28}(?:açık konum|acik konum|dışa dönük|disa donuk|open position|swung open)/iu,
];

const STRUCTURED_VISIBLE_BARRIER_CONDITIONS = new Map<
  string,
  HazardMechanismCode
>([
  ["missing_guardrail", "fall_from_height"],
  ["unguarded_open_edge", "fall_from_height"],
  ["missing_mid_rail", "fall_from_height"],
  ["missing_toeboard", "fall_from_height"],
  ["missing_machine_guard", "caught_in_pinch_shear"],
  ["unguarded_moving_parts", "caught_in_pinch_shear"],
]);

function canonicalConditionCode(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function factHasDirectPersonExposure(fact: HazardFactV3): boolean {
  const exposed = normalized(
    `${fact.exposed_entity} ${fact.initiating_event_state} ${
      fact.evidence.affirmative_cues.join(" ")
    }`,
  );
  return /(?:worker|person|personnel|employee|operator|calisan|personel|is arkadasi|bakim ekibi|saha ekibi)/u
    .test(exposed);
}

function factIsOccludedOrOutOfFrame(fact: HazardFactV3): boolean {
  const cues = normalized([
    fact.observed_condition.short_text,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
  return /(?:occluded|obscured|out of frame|not visible|cannot be seen|gorunmuyor|kadraj disi|kapali kaldigi|ortulu)/u
    .test(cues);
}

/**
 * Accepts only a small, structured set of locally visible safety-barrier
 * failures. This is deliberately stricter than free-text absence matching:
 * an enum, direct mechanism, local box, high identity/condition/localization
 * confidence and an exposed person must all agree. Occluded components never
 * pass this gate.
 */
export function hasStructuredVisibleBarrierEvidence(
  fact: HazardFactV3,
): boolean {
  if (
    fact.assessment_basis === "equipment_integrity_verification" ||
    fact.evidence.normalized_region.is_global ||
    fact.confidence.entity !== "high" ||
    fact.confidence.condition !== "high" ||
    fact.confidence.localization !== "high" ||
    fact.confidence.mechanism === "low" ||
    factIsOccludedOrOutOfFrame(fact) ||
    !hasStructuredCriticalBarrierFields(fact)
  ) return false;
  return fact.barrier_state.startsWith("absent_or_failed_");
}

/**
 * Names the conditions a fact failed on the structured barrier gate.
 *
 * The gate is eight conjunctive checks and the ledger only recorded
 * `absence_only_claim`, which says a fact was dropped without saying why. A
 * live construction photo lost its scaffold guardrail finding while the slab
 * edge beside it passed, and the trace could not distinguish a wrong
 * condition_code from a missing person link or a global bounding box. Raw
 * facts are not persisted, so the diagnosis has to travel with the rejection.
 *
 * Diagnostic only: nothing here changes whether a fact is accepted.
 */
export function structuredBarrierGateFailures(fact: HazardFactV3): string[] {
  const failures: string[] = [];
  if (fact.assessment_basis === "equipment_integrity_verification") {
    failures.push("assessment_basis_is_verification");
  }
  if (fact.evidence.normalized_region.is_global) {
    failures.push("region_is_global");
  }
  if (fact.confidence.entity !== "high") failures.push("entity_confidence");
  if (fact.confidence.condition !== "high") {
    failures.push("condition_confidence");
  }
  if (fact.confidence.localization !== "high") {
    failures.push("localization_confidence");
  }
  if (fact.confidence.mechanism === "low") {
    failures.push("mechanism_confidence");
  }
  if (factIsOccludedOrOutOfFrame(fact)) {
    failures.push("occluded_or_out_of_frame");
  }
  const canonical = canonicalConditionCode(
    fact.observed_condition.condition_code,
  );
  const expectedMechanism = STRUCTURED_VISIBLE_BARRIER_CONDITIONS.get(
    canonical,
  );
  if (!expectedMechanism) {
    failures.push(`condition_code_not_whitelisted:${canonical}`);
  } else if (expectedMechanism !== fact.mechanism_code) {
    failures.push(
      `mechanism_mismatch:${canonical}->${fact.mechanism_code}`,
    );
  }
  if (!factHasDirectPersonExposure(fact)) failures.push("no_person_exposure");
  if (!fact.barrier_state.startsWith("absent_or_failed_")) {
    failures.push(`barrier_state:${fact.barrier_state}`);
  }
  return failures;
}

function hasStructuredCriticalBarrierFields(fact: HazardFactV3): boolean {
  const expectedMechanism = STRUCTURED_VISIBLE_BARRIER_CONDITIONS.get(
    canonicalConditionCode(fact.observed_condition.condition_code),
  );
  return expectedMechanism === fact.mechanism_code &&
    fact.evidence.normalized_region.is_global !== true &&
    fact.confidence.entity === "high" &&
    fact.confidence.condition === "high" &&
    fact.confidence.localization === "high" &&
    fact.confidence.mechanism !== "low" &&
    factHasDirectPersonExposure(fact);
}

function isHighConsequencePersonFact(fact: HazardFactV3): boolean {
  return isHighConsequencePersonClaim(fact) &&
    fact.evidence.normalized_region.is_global !== true &&
    fact.confidence.entity === "high" &&
    fact.confidence.condition === "high" &&
    fact.confidence.localization === "high" &&
    fact.confidence.mechanism !== "low" &&
    !factIsOccludedOrOutOfFrame(fact);
}

function isHighConsequencePersonClaim(fact: HazardFactV3): boolean {
  return fact.assessment_basis !== "equipment_integrity_verification" && [
    "permanent_disability",
    "single_fatality",
    "multiple_fatality_major_environmental",
  ].includes(fact.consequence_class) &&
    factHasDirectPersonExposure(fact);
}

function hasVisualAbsenceClaim(value: string): boolean {
  return VISUAL_ABSENCE_PATTERNS.some((pattern) => pattern.test(value));
}

function hasPositiveAbsenceGeometry(fact: HazardFactV3): boolean {
  if (hasStructuredVisibleBarrierEvidence(fact)) return true;
  const visibleCue = fact.evidence.affirmative_cues.join(" ");
  return POSITIVE_ABSENCE_GEOMETRY_PATTERNS.some((pattern) =>
    pattern.test(visibleCue)
  );
}

function hasDirectVisibleSafetyBarrierGeometry(fact: HazardFactV3): boolean {
  if (hasStructuredVisibleBarrierEvidence(fact)) return true;
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code}`,
  );
  const safetyBarrier = GUARDRAIL_COMPONENT_PATTERN.test(context) ||
    /(?:machine guard|makine koruyucu)/u.test(context);
  if (!safetyBarrier) return false;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const missingBarrier = /(?:eksik|yok|missing|absent)/u.test(
    `${context} ${cues}`,
  );
  const positiveBoundaryGeometry =
    /(?:acikta kalan bosluk|acikta kalan kenar|acik bosluk|dusme boslugu|acik kenar|korumasiz bosluk|korkuluk kesintisi|bariyer kesintisi|korkuluk direkleri arasinda bosluk|bariyer direkleri arasinda bosluk|open gap|open edge|unprotected opening|barrier discontinuity|gap between (?:guardrail|barrier) posts)/u
      .test(cues);
  const directlyDescribedMissingElement =
    /(?:ara korkuluk|orta korkuluk|ara bariyer(?: elemani)?|orta bariyer(?: elemani)?|ara elemani|midrail|mid rail|intermediate rail|intermediate barrier(?: element)?|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik|toe board|toeboard|kick plate|machine guard|makine koruyucu).{0,64}(?:eksik|yok|missing|absent).{0,56}(?:acikca|gorul|visible|clearly|bosluk|gap|opening|acik kenar|acikta kalan kenar)/u
      .test(cues);
  return missingBarrier &&
    (positiveBoundaryGeometry || directlyDescribedMissingElement);
}

function genericGuardingHazardRejection(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  if (
    fact.assessment_basis !== "visible_inherent_hazard" ||
    fact.mechanism_code !== "caught_in_pinch_shear" ||
    !/(?:motor|drive|tahrik|agitator|karistirici|rotating|doner|hareketli parca)/u
      .test(structuredContext)
  ) return null;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const namedTransmission =
    /(?:shaft|saft|mil|coupling|kaplin|belt|kayis|pulley|kasnak|gear|disli|chain|zincir|fan|pervane)/u
      .test(cues);
  const guardGeometry =
    /(?:guard|koruyucu).{0,40}(?:kirik|broken|hasar|damag|eksik|missing|yerinden|displaced|acik bosluk|open gap)|(?:kirik|broken|hasar|damag|eksik|missing|yerinden|displaced|acik bosluk|open gap).{0,40}(?:guard|koruyucu)/u
      .test(cues);
  const directExposure =
    /(?:calisan|personel|worker|person|operator|\bel\b|\bhand\b|bakim faaliyeti|maintenance activity|servis erisimi|service access)/u
      .test(cues);
  return namedTransmission || guardGeometry || directExposure
    ? null
    : "generic_guarding_hazard_rejected";
}

function genericHoseRoutingRejection(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  if (
    fact.mechanism_code !== "hydraulic_pneumatic_release" ||
    !/(?:hortum|hose)/u.test(structuredContext)
  ) return null;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const positiveRoutingAnomaly =
    /(?:asinma|asinmis|abrasion|surtunme izi|rubbing mark|temas ediyor|in contact|keskin yuzey|sharp edge|sicak yuzey|hot surface|sizinti|kacak|leak|catlak|crack|takviye teli|reinforcement exposed|ezilmis|crush|kink|burkul|uygunsuz bukul|bend radius)/u
      .test(cues);
  return positiveRoutingAnomaly ? null : "generic_hose_routing_rejected";
}

function genericMobileArticulationRejection(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  if (
    fact.assessment_basis !== "visible_inherent_hazard" ||
    fact.mechanism_code !== "caught_in_pinch_shear" ||
    !/(?:excavator|ekskavator|mobile equipment|heavy equipment|mobil is ekipmani)/u
      .test(structuredContext) ||
    !/(?:mafsal|articulation|articulated joint|boom|bom|bucket|kova|kepce|pinch)/u
      .test(structuredContext)
  ) return null;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const directExposure =
    /(?:calisan|personel|worker|person|operator|\bel\b|\bhand\b|bakim faaliyeti|maintenance activity|servis erisimi|service access).{0,48}(?:mafsal|bom|kova|kepce|sikisma|pinch)|(?:mafsal|bom|kova|kepce|sikisma|pinch).{0,48}(?:calisan|personel|worker|person|operator|\bel\b|\bhand\b|bakim|maintenance)/u
      .test(cues);
  const abnormalCondition =
    /(?:kirik|broken|hasar|damag|deform|eksik|missing|koruyucu boslugu|guard gap|anormal bosluk|abnormal clearance|gevsek|loose)/u
      .test(cues);
  return directExposure || abnormalCondition
    ? null
    : "generic_articulation_hazard_rejected";
}

function ambiguousPipeObjectRejection(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  if (
    fact.mechanism_code !== "falling_object" ||
    !/(?:process piping|proses hatti|pipe|boru|valve|vana|flange|flans)/u
      .test(structuredContext)
  ) return null;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const objectClaim =
    /(?:malzeme|material|nesne|object|parca|piece|ortu|cover|wrap|sargi|torba|poset|bag|plastic bag)/u
      .test(cues);
  if (!objectClaim) return null;
  const separateUnsupportedGeometry =
    /(?:ayri|bagimsiz|separate|distinct).{0,28}(?:nesne|object|parca|piece)|(?:desteksiz|unsupported|sarkiyor|dangling|overhanging|asili|hanging)|(?:boru|pipe).{0,28}(?:uzerinde duran|resting on|ustunde duran).{0,24}(?:ayri|bagimsiz|separate|distinct)/u
      .test(cues);
  return separateUnsupportedGeometry ? null : "ambiguous_pipe_object_rejected";
}

function unsupportedOpenProcessVentClaim(
  structuredContext: string,
  normalizedClaim: string,
): boolean {
  const openVent =
    /(?:open pipe end|open vent|vent pipe|breather|overflow|havalandirma|tasirma|acik boru agzi)/u
      .test(`${structuredContext} ${normalizedClaim}`) &&
    /(?:open pipe end|acik boru agzi|agzi acik|open mouth|uncovered opening|kapaksiz)/u
      .test(`${structuredContext} ${normalizedClaim}`);
  if (!openVent) return false;
  // An open vent/overflow termination may be intentional. It becomes a
  // scored visible condition only when the image also shows a positive
  // anomaly, not merely the absence of a cap or grille.
  return !/(?:tik|blocked|obstruct|kirik|broken|hasar|damage|korozy|corrosion|deform|sizinti|leak|icinde yabanci cisim|foreign object inside|guvensiz tahliye yonu|unsafe discharge)/u
    .test(normalizedClaim);
}

const CONDITION_UNCERTAINTY_PATTERNS = [
  /(?:belirsiz|net\s+(?:değil|degil|olma)|kesin\s+değil|kesin\s+degil|doğrulanam|dogrulanam|ayırt\s+edilem|ayirt\s+edilem|seçilem|secilem)/iu,
  /(?:potansiyel|olabilir|muhtemel|şüpheli|supheli|ihtimali|izlenimi|gibi\s+görün|gibi\s+gorun)/iu,
  /(?:potential|uncertain|unclear|cannot\s+(?:confirm|determine|distinguish)|possibly|may\s+be|appears\s+to\s+be|seems?\s+to|suggests?)/iu,
];

const CONDITION_STATE_TERM =
  "\\b(?:eksik|missing|acik|open|hasarli|hasar|damaged|damage|kirik|broken|gevsek|loose|yerinden cikmis|displaced|takili|installed|yerinde|in place)\\b";
const UNRESOLVED_ALTERNATIVE_STATE_PATTERN = new RegExp(
  `${CONDITION_STATE_TERM}.{0,36}\\b(?:veya|ya da|or|and or)\\b.{0,36}${CONDITION_STATE_TERM}`,
  "u",
);

function factRequiresTargetedConfirmation(fact: HazardFactV3): boolean {
  const conditionClaim = [
    ...fact.evidence.affirmative_cues,
    fact.observed_condition.condition_code,
    fact.observed_condition.short_text,
    fact.verification.reason_code,
  ].join(" ");
  const unresolvedAlternative = UNRESOLVED_ALTERNATIVE_STATE_PATTERN.test(
    normalized(conditionClaim),
  );
  const definitiveVisibleBarrierState =
    hasDirectVisibleSafetyBarrierGeometry(fact) &&
    /(?:^|_)(?:missing|absent)(?:_|$)|(?:eksik|yok)/iu.test(
      fact.observed_condition.condition_code,
    ) &&
    fact.confidence.condition === "high" &&
    fact.confidence.localization === "high";
  return CONDITION_UNCERTAINTY_PATTERNS.some((pattern) =>
    pattern.test(conditionClaim)
  ) || (unresolvedAlternative && !definitiveVisibleBarrierState);
}

function unsupportedSlopeRockfallClaim(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  if (
    fact.assessment_basis !== "visible_inherent_hazard" ||
    ![
      "falling_object",
      "excavation_collapse_rockfall",
    ].includes(fact.mechanism_code) ||
    !hasExplicitSlopeContext(`${structuredContext} ${cues}`)
  ) return null;
  // A rocky, uneven or inclined surface is ordinary scene context. A scored
  // slope/rockfall fact also needs affirmative instability geometry or an
  // active material-fall cue; provider labels such as "loose slope" are not
  // sufficient by themselves.
  const affirmativeInstability =
    /(?:catlak|fracture|fissure|kopma izi|detachment mark|kopmak uzere|kopabilecek|ayrilmis|detached|askida|sarkan|hanging|desteksiz kaya|unsupported rock|oyuk alti|undercut|overhang|dusmekte olan|falling debris|yuvarlanmakta|rolling rock|aktif kaya dusmesi|active rockfall|taze kaya dokuntusu|fresh rockfall debris)/u
      .test(cues);
  return affirmativeInstability ? null : "slope_instability_evidence_missing";
}

function ordinaryExcavationMaterialHandlingRejection(
  fact: HazardFactV3,
  structuredContext: string,
): string | null {
  if (
    fact.assessment_basis !== "visible_inherent_hazard" ||
    fact.mechanism_code !== "falling_object"
  ) return null;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  const context = `${structuredContext} ${cues}`;
  const bucketHandling =
    /(?:excavator|ekskavator|kazi|digging)/u.test(context) &&
    /(?:bucket|kova|kepce)/u.test(context) &&
    /(?:malzeme|material|toprak|soil|kaya|rock)/u.test(context);
  if (!bucketHandling) return null;
  const directExposure =
    /(?:calisan|personel|worker|person|operator|ekipman|equipment).{0,48}(?:altinda|beneath|dusme hatti|fall line|dogrudan|direct)|(?:altinda|beneath|dusme hatti|fall line).{0,48}(?:calisan|personel|worker|person|operator|ekipman|equipment)/u
      .test(cues);
  const abnormalRelease =
    /(?:kontrolsuz sacil|kontrol disi sacil|uncontrolled spill|outside the intended|amaclanan alan disi|kova hasar|damaged bucket|kirik kova|broken bucket|tasarak dokul|overflowing bucket)/u
      .test(cues);
  return directExposure || abnormalRelease
    ? null
    : "ordinary_excavation_material_handling_rejected";
}

export function evidenceRejectionReason(fact: HazardFactV3): string | null {
  if (fact.evidence.affirmative_cues.length === 0) return "evidence_unlinked";
  if (
    fact.confidence.entity === "low" || fact.confidence.condition === "low" ||
    fact.confidence.mechanism === "low"
  ) return "evidence_non_actionable";
  if (!fact.credible_event_path || !fact.hazard_mechanism) {
    return "process_link_invalid";
  }
  // Equipment-assurance facts do not allege that a defect, document gap or
  // failed control is visible. Their affirmative evidence is the reliably
  // identified asset itself, and the record describes the checks required to
  // establish integrity. Applying visual-defect absence rules to this basis
  // would incorrectly discard LOTO, safety-device and inspection guidance.
  if (fact.assessment_basis === "equipment_integrity_verification") {
    return null;
  }
  // A structured, local, high-confidence barrier failure with an exposed
  // person is positive visual evidence. Do not let broad words such as
  // "missing" or "yok" turn it into a document-style absence claim.
  if (hasStructuredVisibleBarrierEvidence(fact)) return null;
  const claim = [
    ...fact.evidence.affirmative_cues,
    fact.observed_condition.short_text,
    fact.credible_event_path,
  ].join(" ");
  const structuredContext = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code}`,
  );
  const normalizedClaim = normalized(claim);
  if (ABSENCE_ONLY_PATTERNS.some((pattern) => pattern.test(claim))) {
    return "absence_only_claim";
  }
  // An unresolved condition is a request for closer inspection, not a scored
  // risk finding. It may only re-enter as a fact after the targeted pass
  // confirms an affirmative physical condition.
  if (factRequiresTargetedConfirmation(fact)) {
    return "uncertain_condition_requires_confirmation";
  }
  if (
    unsupportedOpenProcessVentClaim(structuredContext, normalizedClaim)
  ) {
    return "process_vent_opening_requires_design_basis";
  }
  const deterministicVisualRejection =
    genericGuardingHazardRejection(fact, structuredContext) ??
      genericHoseRoutingRejection(fact, structuredContext) ??
      genericMobileArticulationRejection(fact, structuredContext) ??
      ambiguousPipeObjectRejection(fact, structuredContext) ??
      unsupportedSlopeRockfallClaim(fact, structuredContext) ??
      ordinaryExcavationMaterialHandlingRejection(fact, structuredContext);
  if (deterministicVisualRejection) return deterministicVisualRejection;
  // A bridge-crane trolley is a moving assembly by design. Its mere movement,
  // drum gaps or theoretical pinch zones are not a useful finding unless the
  // image also establishes either a physical guarding defect or a direct
  // worker/maintenance exposure path. Periodic inspection and safety-function
  // assurance are represented separately by the deterministic assurance layer.
  if (
    fact.mechanism_code === "caught_in_pinch_shear" &&
    /(?:overhead crane|bridge crane|kopru vinc|vinc arabasi|crane trolley)/u
      .test(structuredContext)
  ) {
    const physicalDefect =
      /(?:kirik|hasar|eksik|korunmasiz|acikta|deform|gevse|broken|damage|missing|unguarded|exposed)/u
        .test(normalizedClaim);
    const directExposure =
      /(?:calisan|personel|worker|person|elini|hand|bakim calismasi|maintenance activity|servis platformu|service platform)/u
        .test(normalizedClaim);
    if (!physicalDefect && !directExposure) {
      return "generic_inherent_hazard_rejected";
    }
  }
  const ppeContext = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code}`,
  );
  const ppeOnly = /(?:^|\s)(?:ppe|kkd|operator|operatör|insan)(?:\s|$)/iu.test(
    ppeContext,
  ) || /(?:gozluk|gözlük|eldiven|baret|kask|helmet|glove)/iu.test(claim);
  const headProtectionClaim = /(?:baret|kask|helmet|hard\s*hat)/iu.test(claim);
  const cabOccupantContext =
    /(?:kabin|cab|operator compartment|koltuk|konsol)/iu
      .test(claim);
  if (ppeOnly && headProtectionClaim && cabOccupantContext) {
    return "contextual_ppe_rejected";
  }
  // A flattened, single photograph is not a reliable basis for declaring
  // person-worn PPE absent. Visible misuse/damage may still be reported when
  // expressed as an affirmative condition rather than a visibility claim.
  if (ppeOnly && hasVisualAbsenceClaim(claim)) {
    return "contextual_ppe_rejected";
  }
  if (
    ppeOnly && !/(çalış|calis|operat|worker|person|maruziyet|exposure)/iu.test(
      `${fact.exposed_entity} ${fact.initiating_event_state}`,
    )
  ) return "contextual_ppe_rejected";
  // Missing physical hardware is actionable only when the image contains
  // positive geometry (for example, an empty retainer groove or an open edge).
  // Machine-style tags such as `segman_yok` are not evidence by themselves.
  if (
    hasVisualAbsenceClaim(claim) && !hasPositiveAbsenceGeometry(fact) &&
    !hasDirectVisibleSafetyBarrierGeometry(fact)
  ) {
    return "absence_only_claim";
  }
  return null;
}

function targetedEvidenceRejectionReason(
  fact: HazardFactV3,
): string | null {
  const reason = evidenceRejectionReason(fact);
  // Keep the primary pass strict: an absence label alone is never a finding.
  // A targeted crop may confirm safety-critical hardware only through direct,
  // local geometry such as an empty latch pivot/seat. Other rejection reasons
  // and unlocalized "missing/not visible" claims remain rejected.
  return reason === "absence_only_claim" &&
      isCriticalHardwareGeometryCandidate(fact)
    ? null
    : reason;
}

function fingerprint(fact: HazardFactV3): string {
  return [
    fact.entity.equipment_family,
    fact.entity.component,
    fact.observed_condition.condition_code,
    fact.mechanism_code,
  ].map(normalized).join("|");
}

function crossPhotoIdentity(
  fact: AggregatedFact,
  other: HazardFactV3,
): boolean {
  // Assurance findings describe an inspection/control programme rather than
  // a photographed defect. Repeating the same programme for the same asset
  // class on every angle adds report noise, so merge it at analysis level and
  // retain every contributing photo as evidence.
  if (
    fact.assessment_basis === "equipment_integrity_verification" &&
    other.assessment_basis === "equipment_integrity_verification"
  ) {
    return normalized(fact.entity.equipment_family) ===
        normalized(other.entity.equipment_family) &&
      normalized(fact.observed_condition.condition_code) ===
        normalized(other.observed_condition.condition_code);
  }
  return fact.entity.identity_confidence === "high" &&
    other.entity.identity_confidence === "high" &&
    normalized(fact.entity.identity_basis).length >= 8 &&
    normalized(fact.entity.identity_basis) ===
      normalized(other.entity.identity_basis) &&
    fingerprint(fact) === fingerprint(other);
}

function regionsOverlap(
  left: HazardFactV3["evidence"]["normalized_region"],
  right: HazardFactV3["evidence"]["normalized_region"],
): boolean {
  if (left.is_global || right.is_global) return true;
  const width = Math.max(
    0,
    Math.min(left.x + left.width, right.x + right.width) -
      Math.max(left.x, right.x),
  );
  const height = Math.max(
    0,
    Math.min(left.y + left.height, right.y + right.height) -
      Math.max(left.y, right.y),
  );
  const intersection = width * height;
  const smallerArea = Math.min(
    left.width * left.height,
    right.width * right.height,
  );
  return smallerArea > 0 && intersection / smallerArea >= 0.25;
}

function targetedDuplicatesPrimary(
  primary: AggregatedFact,
  targeted: HazardFactV3,
): boolean {
  if (!primary.sourcePhotoIndices.includes(targeted.photo_index)) return false;
  if (primary.mechanism_code !== targeted.mechanism_code) return false;
  const sameEntity = normalized(primary.entity.entity_ref) ===
    normalized(targeted.entity.entity_ref);
  const sameComponent = normalized(primary.entity.equipment_family) ===
      normalized(targeted.entity.equipment_family) &&
    normalized(primary.entity.component) ===
      normalized(targeted.entity.component);
  return (sameEntity || sameComponent) &&
    regionsOverlap(
      primary.evidence.normalized_region,
      targeted.evidence.normalized_region,
    );
}

function samePhotoEquivalentConditionReason(
  existing: AggregatedFact,
  fact: HazardFactV3,
): string | null {
  if (!existing.sourcePhotoIndices.includes(fact.photo_index)) return null;
  if (existing.assessment_basis !== fact.assessment_basis) return null;
  const existingContext = normalized(
    `${existing.entity.equipment_family} ${existing.entity.component}`,
  );
  const factContext = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component}`,
  );
  const sameCondition =
    normalized(existing.observed_condition.condition_code) ===
      normalized(fact.observed_condition.condition_code) &&
    existing.mechanism_code === fact.mechanism_code;
  const conditionContext = normalized(
    `${existing.observed_condition.condition_code} ${existing.observed_condition.short_text} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  if (
    sameCondition &&
    normalized(existing.entity.equipment_family) ===
      normalized(fact.entity.equipment_family) &&
    /(?:hook|kanca)/u.test(conditionContext) &&
    /(?:latch|mandal)/u.test(conditionContext)
  ) return "same_photo_equivalent_hook_latch_condition";
  // Keep independently repairable pins, hooks, guards and electrical points
  // separate. Area/zone fragments of the same condition are one scene-level
  // finding with multiple evidence observations, not multiple risk cards.
  const areaPattern =
    /(?:floor|ground|zemin|walkway|gecis|work area|area|zone|alan|housekeeping|surface)/u;
  const existingConditionContext = normalized(
    `${existing.observed_condition.condition_code} ${existing.observed_condition.short_text} ${existing.hazard_mechanism}`,
  );
  const factConditionContext = normalized(
    `${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${fact.hazard_mechanism}`,
  );
  const housekeepingPattern =
    /(?:housekeeping|clutter|debris|daginik|atik|engel|obstruction|poor equipment|poor material)/u;
  if (
    existing.mechanism_code === "fall_same_level" &&
    fact.mechanism_code === "fall_same_level" &&
    areaPattern.test(existingContext) && areaPattern.test(factContext) &&
    housekeepingPattern.test(existingConditionContext) &&
    housekeepingPattern.test(factConditionContext)
  ) return "same_scene_housekeeping_condition_merged";
  if (
    areaPattern.test(existingContext) && areaPattern.test(factContext) &&
    normalized(existing.observed_condition.condition_code) ===
      normalized(fact.observed_condition.condition_code) &&
    existing.mechanism_code === fact.mechanism_code
  ) return "same_scene_area_condition_merged";
  const sameEntityRef = normalized(existing.entity.entity_ref) !== "" &&
    normalized(existing.entity.entity_ref) ===
      normalized(fact.entity.entity_ref);
  const rackPattern = /(?:rack|raf|storage racking|istif|stack)/u;
  const storageConditionPattern =
    /(?:storage|rack|raf|istif|stack|overhang|overheight|tasma|yukseklik)/u;
  if (
    sameEntityRef &&
    existing.mechanism_code === "falling_object" &&
    fact.mechanism_code === "falling_object" &&
    rackPattern.test(`${existingContext} ${factContext}`) &&
    storageConditionPattern.test(existingConditionContext) &&
    storageConditionPattern.test(factConditionContext) &&
    regionsOverlap(
      existing.evidence.normalized_region,
      fact.evidence.normalized_region,
    )
  ) return "same_rack_region_storage_condition_merged";
  if (fingerprint(existing) !== fingerprint(fact)) return null;
  const context = `${existingContext} ${factContext}`;
  if (
    /(?:vent pipe|vent_pipe|overflow|breather|havalandirma|tasirma)/u.test(
      context,
    )
  ) {
    return "same_photo_equivalent_condition";
  }
  return null;
}

function assuranceOverlapReason(
  existing: AggregatedFact,
  assurance: HazardFactV3,
): string | null {
  if (
    assurance.assessment_basis !== "equipment_integrity_verification" ||
    !existing.sourcePhotoIndices.includes(assurance.photo_index)
  ) return null;
  const assuranceIdentity = normalized(assurance.entity.identity_basis);
  const existingIdentityRefs = [
    existing.entity.entity_ref,
    ...existing.equivalentEntityRefs,
  ].map(normalized).filter(Boolean);
  const existingIdentityBasis = normalized(existing.entity.identity_basis);
  const assuranceRefs = assurance.entity.identity_basis.split(",").map(
    normalized,
  ).filter(Boolean);
  const sharesAssetIdentity =
    existingIdentityRefs.some((ref) => assuranceIdentity.includes(ref)) ||
    assuranceRefs.some((ref) => existingIdentityBasis.includes(ref));
  if (sharesAssetIdentity) {
    return existing.assessment_basis === "equipment_integrity_verification"
      ? "same_asset_assurance_merged"
      : "assurance_absorbed_by_observed_finding";
  }
  if (
    assurance.observed_condition.condition_code !==
      "agitator_drive_assurance" ||
    existing.assessment_basis === "equipment_integrity_verification" ||
    existing.mechanism_code !== "caught_in_pinch_shear"
  ) return null;
  const context = normalized(
    `${existing.entity.equipment_family} ${existing.entity.component} ${existing.observed_condition.condition_code} ${existing.observed_condition.short_text} ${assurance.entity.equipment_family} ${assurance.entity.component}`,
  );
  return /(?:motor|drive|tahrik|agitator|karistirici|coupling|kaplin|shaft|saft|mil)/u
      .test(context)
    ? "assurance_absorbed_by_observed_finding"
    : null;
}

function fkBand(score: number): RiskBand {
  if (score <= 70) return "low";
  if (score <= 200) return "medium";
  if (score <= 400) return "high";
  return "critical";
}

function m5Band(score: number): RiskBand {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 19) return "high";
  return "critical";
}

function m5Probability(p: number): number {
  if (p <= 0.5) return 1;
  if (p === 1) return 2;
  if (p === 3) return 3;
  if (p === 6) return 4;
  return 5;
}

function m5Severity(s: number): number {
  if (s === 1) return 1;
  if (s === 3) return 2;
  if (s === 7) return 3;
  if (s === 15) return 4;
  return 5;
}

function residualProbability(p: number): number {
  // Proposed controls do not change risk until implementation and operating
  // effectiveness have been confirmed. Keep residual equal to current risk.
  return p;
}

function isTurkish(language: string): boolean {
  return language.toLowerCase().startsWith("tr");
}

type ControlCopy = { hierarchy: string; tr: string; en: string };
const CONTROL_CATALOG: Record<string, ControlCopy> = {
  stop_use: {
    hierarchy: "elimination",
    tr:
      "Ekipmanı/işi güvenli durum sağlanana kadar kullanım dışı bırak ve tehlikeli bölgeyi sınırla.",
    en:
      "Stop use until a safe condition is restored and isolate the hazardous area.",
  },
  isolate_energy: {
    hierarchy: "engineering",
    tr:
      "İlgili enerji kaynaklarını doğrulanmış LOTO adımlarıyla izole et ve sıfır enerji durumunu test et.",
    en:
      "Isolate relevant energy sources under verified LOTO and test the zero-energy state.",
  },
  replace_component: {
    hierarchy: "engineering",
    tr:
      "Hasarlı veya eksik bileşeni üretici şartnamesine uygun parça ile değiştir; montaj ve kilitlemeyi doğrula.",
    en:
      "Replace the damaged or missing component to manufacturer specification and verify locking and installation.",
  },
  secure_connection: {
    hierarchy: "engineering",
    tr:
      "Bağlantıyı uygun pim, segman, kilit veya bağlantı elemanıyla sabitle; tork/kilitleme kabulünü kayda al.",
    en:
      "Secure the joint with the specified pin, retainer, lock or fastener and record torque/locking acceptance.",
  },
  restore_barrier: {
    hierarchy: "engineering",
    tr:
      "Korkuluk veya bariyer sürekliliğini geçiş yapan hat çevresinde uygun çerçeveleme, ara korkuluk ve gerekli etek elemanlarıyla yeniden kur; açıklık ölçülerini ve bağlantı rijitliğini sahada doğrula.",
    en:
      "Restore guardrail or barrier continuity around the line penetration using suitable framing, intermediate rail and toe-board elements; verify opening dimensions and joint rigidity in the field.",
  },
  install_guard: {
    hierarchy: "engineering",
    tr:
      "Tehlikeli hareket veya temas bölgesine uygun sabit/interlocklu koruyucu yerleştir ve işlev testini yap.",
    en:
      "Install a suitable fixed/interlocked guard at the hazardous contact zone and function-test it.",
  },
  guard_pinch_point: {
    hierarchy: "engineering",
    tr:
      "Erişilebilir sıkışma/kesilme noktasını uygun sabit veya interlocklu koruyucu ve güvenli mesafe ile ayır; koruma sonrası erişim testini yap.",
    en:
      "Separate the accessible pinch/shear point with a suitable fixed or interlocked guard and safe distance; perform an access test after guarding.",
  },
  restore_hook_latch: {
    hierarchy: "engineering",
    tr:
      "Kancanın emniyet mandalını üretici şartnamesine uygun şekilde onar veya değiştir; mandalın yayıyla kapanmasını ve kanca ağzını tam kapatmasını işlevsel olarak doğrula.",
    en:
      "Repair or replace the hook safety latch to manufacturer specification and functionally verify spring closure and full coverage of the hook opening.",
  },
  lifting_accessory_inspection: {
    hierarchy: "administrative",
    tr:
      "Kanca, mandal, pim ve yük bağlantı elemanlarını yetkin kişiyle kullanım öncesi ve periyodik kontrole al; deformasyon, aşınma, açıklık ve kilitleme kabul kriterlerini kayda bağla.",
    en:
      "Have a competent person inspect the hook, latch, pins and load attachments before use and periodically; document acceptance criteria for deformation, wear, opening and locking.",
  },
  reroute_hose: {
    hierarchy: "engineering",
    tr:
      "Hortum/hat güzergâhını keskin, sıcak veya hareketli yüzeyden ayır; kelepçe, koruyucu kılıf ve bükülme yarıçapını doğrula.",
    en:
      "Reroute the hose/line away from sharp, hot or moving surfaces and verify clamps, sleeve and bend radius.",
  },
  repair_weld: {
    hierarchy: "engineering",
    tr:
      "Kaynak bölgesini yetkin prosedür ve kaynakçıyla onar; onarım öncesi/sonrası yüzey hazırlığı ve kabul kontrolü yap.",
    en:
      "Repair the weld using a qualified procedure and welder, with pre/post repair preparation and acceptance checks.",
  },
  ndt_inspection: {
    hierarchy: "administrative",
    tr:
      "Görünür kusurun mekanizmasına göre VT ve gerektiğinde PT/MT/UT veya radyografik yöntemle yetkin NDT incelemesi yap; kabul kriterini teknik standarda bağla.",
    en:
      "Perform competent VT and, where mechanism-appropriate, PT/MT/UT or radiography; tie acceptance to the applicable technical standard.",
  },
  engineering_inspection: {
    hierarchy: "administrative",
    tr:
      "Hedef bileşeni yetkin kişiyle ölçülü teknik kontrole al; deformasyon, bağlantı bütünlüğü ve işlev için yazılı kabul kriteri uygula.",
    en:
      "Have a competent person inspect the target component using written acceptance criteria for deformation, joint integrity and function.",
  },
  verify_periodic_control_status: {
    hierarchy: "administrative",
    tr:
      "Ekipmanın son geçerli periyodik kontrol kapsamını, rapordaki uygunsuzlukların kapatılmasını ve bir sonraki kontrol tarihini doğrula; kontrol süresi geçmişse veya kritik kapsam eksikse uygunluk sağlanana kadar kullanımı sınırla.",
    en:
      "Verify the scope and validity of the latest periodic inspection, closure of recorded nonconformities and the next due date; restrict use if overdue or if critical scope is missing.",
  },
  verify_chemical_inventory_controls: {
    hierarchy: "administrative",
    tr:
      "Doğrulanmış kimyasal kap ve kullanım alanlarını envanter, etiket-SDS eşleşmesi, uyumluluk ayrımı ve ikincil tutma kapsamında kontrol et; kimliği doğrulanamayan kabı kimyasal olarak sınıflandırma.",
    en:
      "Check confirmed chemical containers and handling areas for inventory, label-to-SDS matching, compatibility segregation and secondary containment; do not classify a container as chemical when its identity is unresolved.",
  },
  verify_electrical_protection_status: {
    hierarchy: "administrative",
    tr:
      "Elektrik panosu veya şalt ekipmanının mahfaza bütünlüğü, koruma düzeni, topraklama, izolasyon ve LOTO test kapsamını doğrula; kritik koruma doğrulanamıyorsa yetkisiz erişimi ve kullanımı sınırla.",
    en:
      "Verify enclosure integrity, protection, earthing, insulation and LOTO test coverage for the confirmed electrical panel or switchgear; restrict unauthorized access and use if a critical protection cannot be confirmed.",
  },
  periodic_crane_inspection: {
    hierarchy: "administrative",
    tr:
      "Köprü vinci yetkin kişiyle periyodik kontrole al; taşıyıcı kirişler, ray ve son durdurucular, halat/tambur, kanca bloğu, frenler, limit kesiciler ve yük sınırlayıcılarını ölçülü ve kayıtlı kabul kriterleriyle kontrol et.",
    en:
      "Have a competent person periodically inspect the overhead crane, covering girders, runway and end stops, rope/drum, hook block, brakes, limit switches and load limiting devices against recorded acceptance criteria.",
  },
  crane_safety_function_test: {
    hierarchy: "engineering",
    tr:
      "Fren, üst-alt limit, acil durdurma, çarpışma/son yaklaşma koruması ile ekipman tasarımı ve risk değerlendirmesinde öngörülen sesli-görsel hareket uyarılarını fonksiyon testine tabi tut; arızalı emniyet fonksiyonuyla çalışmaya izin verme.",
    en:
      "Function-test brakes, upper/lower limits, emergency stop, anti-collision/end-approach protection and any audible/visual travel warning required by the equipment design and risk assessment; do not operate with a failed safety function.",
  },
  process_equipment_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "Tank gövdesi, taşıyıcılar, ankrajlar, nozullar, flanşlar ve bağlı hatları proses koşullarına uygun periyodik bütünlük programına al; korozyon, cidar kaybı, sızdırmazlık, deformasyon ve destek yük aktarımı için kayıtlı kabul kriteri uygula.",
    en:
      "Include vessel shells, supports, anchors, nozzles, flanges and connected lines in a process-specific periodic integrity programme with documented acceptance criteria for corrosion, wall loss, containment, deformation and support load paths.",
  },
  process_safeguard_function_test: {
    hierarchy: "engineering",
    tr:
      "Proses şartlarına uygulanabilir seviye, taşma, basınç/sıcaklık izleme, havalık-tahliye, izolasyon ve acil durdurma fonksiyonlarını tanımlı set değerleri ve test periyotlarıyla doğrula; bağımsız koruma katmanlarının işlev kayıtlarını tut.",
    en:
      "Verify process-applicable level, overfill, pressure/temperature monitoring, vent/relief, isolation and emergency shutdown functions against defined set points and test intervals; retain functional records for independent protection layers.",
  },
  agitator_guard_loto_inspection: {
    hierarchy: "engineering",
    tr:
      "Tank üstü tahrik, kaplin ve döner aktarım elemanlarının koruyucularını; bakım erişimi, elektrik/mekanik enerji izolasyonu ve yeniden çalıştırma önleme adımlarıyla birlikte kontrol et ve işlevsel LOTO doğrulaması yap.",
    en:
      "Inspect guarding of tank-top drives, couplings and rotating transmission parts together with maintenance access, electrical/mechanical isolation and restart prevention; perform a functional LOTO verification.",
  },
  storage_tank_integrity_ndt: {
    hierarchy: "administrative",
    tr:
      "Tankın gerçek tasarım ve servis kapsamını belirle. Kapsama giren atmosferik, dikey, kaynaklı yer üstü tanklarda API 650 tasarım/imalat kayıtlarını ve API 653 hizmet içi muayene yaklaşımını esas al; dış/iç muayene, taban-gövde-çatı/nozul-kaynak değerlendirmesi, oturma, korozyon hızı ve kalan ömür hesabını yap. Muayene planında VT ve UT kalınlık haritalamasını; kusur mekanizmasına ve onarım/kaynak kapsamına göre PT, MT, UT veya radyografiyi yetkin prosedür ve personelle uygula. API 650/653 kapsam dışıysa ekipmanın kendi tasarım standardını kullan.",
    en:
      "Determine the tank's actual design and service scope. For applicable atmospheric vertical welded aboveground tanks, use API 650 design/fabrication records and the API 653 in-service inspection approach; assess shell, bottom, roof, nozzles, welds, settlement, corrosion rate and remaining life. Use VT and UT thickness mapping, with PT, MT, UT or radiography selected by damage mechanism and repair/weld scope through qualified procedures and personnel. If API 650/653 is outside scope, use the equipment's governing design standard.",
  },
  secondary_containment_overfill_control: {
    hierarchy: "engineering",
    tr:
      "Tankın akışkanı, hacmi ve taşma senaryosuna göre sızdırmaz ikincil tutma/taşma havuzu, kontrollü drenaj, yağmur suyu yönetimi, dolum gözetimi ve bağımsız yüksek-yüksek seviye/taşma önleme katmanlarını doğrula; tutma hacmini ve vana/drenaj konumlarını kayıtlı kabul kriterleriyle kontrol et.",
    en:
      "Verify leak-tight secondary containment/bunding, controlled drainage, stormwater management, filling supervision and independent high-high level/overfill prevention based on the stored material, inventory and overfill scenario; check containment capacity and valve/drain positions against documented criteria.",
  },
  lng_cryogenic_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "LNG tank sisteminin gerçek tasarım ve kapasite kapsamını belirle; iç/dış tank, taban-çatı ve penetrasyonlar, temel ve oturma, ankrajlar, izolasyon/annüler alan, kriyojenik vanalar-hatlar, sıcaklık-basınç eğilimleri ve sızdırmazlık sınırını kayıtlı periyodik bütünlük planına al. Kapsama uygunsa API 625 ve ilgili LNG tesis standardını, değilse ekipmanın kendi tasarım standardını kullan; NDT yöntemini malzeme, düşük sıcaklık ve hasar mekanizmasına göre seç.",
    en:
      "Determine the LNG tank system's actual design and capacity scope; place inner/outer tanks, bottom-roof and penetrations, foundation/settlement, anchors, insulation/annular space, cryogenic valves-lines, temperature-pressure trends and containment under a documented periodic integrity plan. Use API 625 and the applicable LNG facility standard only where in scope, otherwise the governing design standard; select NDT for the material, low temperature and damage mechanism.",
  },
  lng_safeguard_emergency_control: {
    hierarchy: "engineering",
    tr:
      "Uygulanabilir bağımsız yüksek-yüksek seviye/taşma önleme, basınç-vakum tahliyesi, boil-off gas yönetimi, yanıcı gaz ile düşük sıcaklık/oksijen algılama, uzaktan ESD ve izolasyon, kriyojenik döküntü tutma ve acil durum senaryolarını tanımlı set değerleriyle periyodik fonksiyon testine tabi tut.",
    en:
      "Periodically function-test applicable independent high-high level/overfill prevention, pressure-vacuum relief, boil-off-gas management, flammable-gas and low-temperature/oxygen detection, remote ESD/isolation, cryogenic spill impoundment and emergency scenarios against defined set points.",
  },
  lpg_installation_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "LPG tankı/basınçlı kabı ile transfer sistemini tasarım basıncı ve sıcaklığına göre periyodik bütünlük kontrolüne al; gövde-kaynak-nozul, destek/ankraj, korozyon ve UT kalınlık eğilimi, uygun yüzey/hacimsel NDT, vana/hat ve emniyet tahliye cihazlarını kayıtlı kabul kriterleriyle doğrula. Yerleşim ve tesis kapsamı uygunsa API 2510'u; hizmet içi muayenede gerçek basınçlı kap ve borulama standardını kullan.",
    en:
      "Periodically inspect the LPG tank/pressure vessel and transfer system against design pressure and temperature, verifying shell-weld-nozzle areas, supports/anchors, corrosion and UT thickness trends, suitable surface/volumetric NDT, valves-lines and relief devices against documented criteria. Use API 2510 where its installation scope fits and the actual pressure-vessel/piping standard for in-service inspection.",
  },
  lpg_safeguard_periodic_test: {
    hierarchy: "engineering",
    tr:
      "Emniyet valfi ve güvenli tahliye yönü, aşırı dolum önleme, gaz algılama, acil durdurma ve uzaktan izolasyon vanaları, transfer hortumu/kopma koruması, topraklama-eşpotansiyel bağlama ve uygulanabilir yangın koruma fonksiyonlarını kayıtlı periyot ve senaryolarla test et.",
    en:
      "Test relief devices and safe discharge routing, overfill prevention, gas detection, emergency shutdown and remote isolation, transfer-hose break protection, earthing/bonding and applicable fire-protection functions at documented intervals and scenarios.",
  },
  hazardous_area_ex_equipment_control: {
    hierarchy: "engineering",
    tr:
      "Sızıntı kaynağı, salım derecesi, gaz özellikleri ve havalandırmaya göre IEC 60079-10-1 yaklaşımıyla tehlikeli bölge sınıflandırmasını ve Patlamadan Korunma Dokümanı'nı güncelle. Zon içindeki elektrikli ve uygulanabilir elektriksiz ekipmanın Ex işareti/sertifikası, gaz grubu, sıcaklık sınıfı, EPL/kategorisi, koruma tipi, kablo-rakor bütünlüğü, topraklama ve statik bağlamasını doğrula; ilk ve periyodik denetimleri IEC 60079-14/17 ile uygulanabilir ATEX ve yerel mevzuata göre yetkin personelle yap.",
    en:
      "Update hazardous-area classification and explosion-protection documentation from release sources, grade of release, gas properties and ventilation using IEC 60079-10-1. Verify Ex marking/certification, gas group, temperature class, EPL/category, protection concept, cable-gland integrity, earthing and static bonding for electrical and applicable non-electrical equipment in the zone; have competent personnel perform initial and periodic inspections under IEC 60079-14/17 and applicable ATEX/local requirements.",
  },
  pressure_equipment_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "Basınçlı ekipmanın tasarım bilgileri ve proses şartlarına göre gövde, kaynak, nozul, flanş, destek ve bağlantıları periyodik kontrole al; VT, UT kalınlık ölçümü ve hasar mekanizmasına uygun PT/MT/UT/RT yöntemlerini yetkin personel ve yazılı kabul kriterleriyle uygula.",
    en:
      "Periodically inspect the pressure boundary, welds, nozzles, flanges, supports and connections against design and process conditions, using VT, UT thickness measurement and damage-mechanism-appropriate PT/MT/UT/RT with qualified personnel and written acceptance criteria.",
  },
  pressure_safety_device_test: {
    hierarchy: "engineering",
    tr:
      "Emniyet valfi/tahliye cihazı set basıncı ve kapasitesini, manometre/limit doğruluğunu, tahliye hattını ve izolasyon konumunu proses şartlarına göre doğrula; kalibrasyon ve fonksiyon testini kayıtlı periyotta yap.",
    en:
      "Verify relief-device set pressure/capacity, gauge/limit accuracy, discharge routing and isolation position against process conditions; calibrate and function-test at documented intervals.",
  },
  mobile_equipment_periodic_inspection: {
    hierarchy: "administrative",
    tr:
      "Üretici limitlerine göre şasi ve ROPS/FOPS, bom-ataşman yük yolu, pim-tutucular, silindir-hortumlar, fren/park sistemi, direksiyon ve lastik/paletleri ölçülü periyodik kontrole al; kusur ve aşınma sınırlarını kayıt altına al.",
    en:
      "Periodically inspect chassis and ROPS/FOPS, boom-attachment load path, pins/retainers, cylinders/hoses, brakes/parking, steering and tyres/tracks against manufacturer limits, documenting defect and wear criteria.",
  },
  mobile_equipment_safety_function_test: {
    hierarchy: "engineering",
    tr:
      "Servis/park freni, direksiyon, korna, geri hareket sesli-görsel ikazı, aydınlatma, kamera/ayna, emniyet kemeri ve uygulanabilir hareket/kapasite limitlerini vardiya öncesi ve kayıtlı periyotlarda fonksiyon testine tabi tut.",
    en:
      "Function-test service/parking brakes, steering, horn, audible/visual reverse warning, lighting, cameras/mirrors, seat belt and applicable travel/capacity limits before use and at documented intervals.",
  },
  industrial_vehicle_safety_inspection: {
    hierarchy: "administrative",
    tr:
      "Aracın fren, direksiyon, lastik, aydınlatma, geri hareket ikazı ve görüş yardımcılarını; üstyapı, damper/mikser/tanker bağlantıları ile hidrolik kaldırma elemanlarını birlikte kontrol et ve yol/saha uygunluk kayıtlarını güncel tut.",
    en:
      "Inspect brakes, steering, tyres, lighting, reversing warnings and visibility aids together with body, tipper/mixer/tanker attachments and hydraulic lifting components, maintaining current road/site fitness records.",
  },
  machine_guarding_function_test: {
    hierarchy: "engineering",
    tr:
      "Ayna/takım/iş mili ve hareket eksenleri için koruyucu, kapı interlocku, acil durdurma, yeniden başlatma önleme, iş parçası bağlama ve talaş/sıvı muhafazasını üretici emniyet fonksiyonlarına göre test et.",
    en:
      "Test guards, door interlocks, emergency stop, restart prevention, workholding and chip/fluid containment for chuck/tool/spindle and motion axes against manufacturer safety functions.",
  },
  machine_loto_maintenance_control: {
    hierarchy: "engineering",
    tr:
      "Bakım, ayar, takım değişimi ve temizlik için elektrik/pnömatik/hidrolik enerji kesme noktalarını kilitlenebilir yap; sıfır enerji testi, düşebilen eksen/başlıkların mekanik blokajı ve kontrollü yeniden devreye alma adımlarını doğrula.",
    en:
      "Provide lockable electrical/pneumatic/hydraulic isolation for maintenance, setup, tool change and cleaning; verify zero energy, mechanical blocking of descending axes/heads and controlled recommissioning.",
  },
  bulk_machine_guard_loto_inspection: {
    hierarchy: "engineering",
    tr:
      "Besleme-boşaltma, rotor, bant-kasnak ve tahrik bölgelerini uygun koruyucularla ayır; acil durdurma, hız/sapma interlockları ve tıkanıklık açma-temizlik için LOTO fonksiyonlarını test et.",
    en:
      "Guard feed/discharge, rotor, belt-pulley and drive zones; test emergency stops, speed/deviation interlocks and LOTO for blockage clearing and cleaning.",
  },
  rotating_equipment_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "Titreşim ve sıcaklık eğilimi, yataklar, hizalama, rotor/elek/astar aşınması, cıvatalı-kaynaklı birleşimler, şase ve temel ankrajları için ölçülü bakım ve kabul kriterleri uygula.",
    en:
      "Apply measured maintenance and acceptance criteria for vibration/temperature trends, bearings, alignment, rotor/screen/liner wear, bolted/welded joints, frame and foundation anchors.",
  },
  pump_integrity_maintenance: {
    hierarchy: "administrative",
    tr:
      "Kaplin koruyucusu, hizalama, yatak titreşimi/sıcaklığı, salmastra-keçe sızıntısı, kavitasyon göstergeleri, temel-ankraj ve emiş/basma bağlantı yüklerini durum izleme ve periyodik bakım planına bağla.",
    en:
      "Include coupling guards, alignment, bearing vibration/temperature, seal leakage, cavitation indicators, foundation/anchors and suction/discharge nozzle loads in condition monitoring and periodic maintenance.",
  },
  process_line_integrity_inspection: {
    hierarchy: "administrative",
    tr:
      "Akışkan ve proses koşuluna göre korozyon/erozyon devrelerini belirle; boru ve dirseklerde UT kalınlık ölçümü, flanş-conta ve vana işlevi, destek yükleri, izolasyon altı korozyon ve sızıntı eğilimlerini yazılı bütünlük planıyla izle.",
    en:
      "Define corrosion/erosion circuits from fluid and process conditions; monitor UT thickness on pipe/elbows, flange/gasket and valve function, support loads, corrosion under insulation and leak trends under a written integrity plan.",
  },
  combustion_safeguard_function_test: {
    hierarchy: "engineering",
    tr:
      "Yakıt kesme, purge, alev gözetimi, hava-yakıt oranı, basınç limitleri, aşırı sıcaklık kesmesi ve acil durdurmayı tanımlı başlatma-durdurma sırasına göre kayıtlı fonksiyon testine tabi tut.",
    en:
      "Function-test fuel shutoff, purge, flame supervision, air-fuel ratio, pressure limits, high-temperature trip and emergency shutdown against the defined start/stop sequence.",
  },
  tire_inflation_safety_control: {
    hierarchy: "engineering",
    tr:
      "Lastik-jant uyumluluğu ve hasarını kontrol et; üretici basınç limitini, kalibre manometreyi, klipsli uzatma hortumunu ve uzaktan şişirmeyi kullan. Çalışanı fırlama hattından çıkar ve gerekli durumda uygun tutma kafesi uygula.",
    en:
      "Check tyre-rim compatibility and damage; use manufacturer pressure limits, a calibrated gauge, clip-on extension hose and remote inflation. Keep personnel out of the trajectory and use a suitable restraint cage where required.",
  },
  chemical_sds_storage_control: {
    hierarchy: "administrative",
    tr:
      "Kimyasal envanteri kap etiketi ve güncel/erişilebilir Türkçe SDS ile eşleştir; uyumsuz kimyasalları ayır, maruziyet-ilk yardım bilgisini erişilebilir tut ve akışkana uygun dolap, havalandırma ve ikincil tutma kullan. Bu kontrol, SDS'nin mevcut veya eksik olduğu yönünde bir uygunluk iddiası içermez.",
    en:
      "Match chemical inventory and container labels to current accessible SDS; segregate incompatibles, keep exposure/first-aid information available and provide fluid-compatible cabinets, ventilation and secondary containment. This control makes no compliance claim about whether an SDS is available or missing.",
  },
  rail_system_safety_inspection: {
    hierarchy: "administrative",
    tr:
      "Ray geometrisi ve bağlantıları, makaslar, tekerlek/aks, fren ve tutma sistemleri, sinyal/iletişim, geçit korumaları ve bakım sırasında hareket-enerji izolasyonunu kayıtlı periyodik kontrole al.",
    en:
      "Periodically inspect track geometry/fastenings, points, wheels/axles, braking/restraint, signalling/communications, crossing protection and motion/energy isolation during maintenance.",
  },
  electrical_periodic_test_program: {
    hierarchy: "administrative",
    tr:
      "Pano/mahfaza bütünlüğü, bağlantı torku ve termal tarama, koruma rölesi/kaçak akım testi, topraklama sürekliliği, izolasyon direnci ve LOTO düzenini gerilim ve ark riskine göre kayıtlı periyodik programa bağla.",
    en:
      "Place enclosure integrity, connection torque/thermal scanning, protection/residual-current testing, earth continuity, insulation resistance and LOTO under a documented programme based on voltage and arc risk.",
  },
  workshop_system_audit: {
    hierarchy: "administrative",
    tr:
      "Ekipman bazlı kontrolleri atölye yerleşimi, güvenli geçiş, ortak LOTO standardı, kaldırma/taşıma, sıcak iş, kimyasal, elektrik, yangın ve acil durum erişimiyle birleştiren periyodik atölye denetimi uygula.",
    en:
      "Apply a periodic workshop audit integrating equipment controls with layout, safe access, common LOTO, lifting/handling, hot work, chemicals, electrical, fire and emergency access.",
  },
  stabilize_structure: {
    hierarchy: "engineering",
    tr:
      "Yapı/ekipmanı tasarıma uygun ankraj, çapraz, destek veya iksa ile stabilize et ve yük aktarma yolunu doğrula.",
    en:
      "Stabilize the structure/equipment with design-compliant anchorage, bracing, support or shoring and verify the load path.",
  },
  install_fall_protection: {
    hierarchy: "engineering",
    tr:
      "Öncelikle toplu düşmeye karşı koruma kur; kişisel sistem gerekiyorsa uygun ankraj, bağlantı ve kurtarma düzenini birlikte doğrula.",
    en:
      "Prioritize collective fall protection; if a personal system is needed, verify anchorage, connection and rescue arrangements together.",
  },
  electrical_isolation: {
    hierarchy: "engineering",
    tr:
      "Enerjiyi kes, gerilimsizliği doğrula ve açık iletken/mahfazayı uygun koruma sınıfıyla kalıcı olarak düzelt.",
    en:
      "De-energize, verify absence of voltage, and permanently correct the exposed conductor/enclosure to the required protection class.",
  },
  leak_control: {
    hierarchy: "engineering",
    tr:
      "Akışı/enerjiyi güvenle izole et, sızıntı kaynağını onar ve yayılımı uygun ikincil tutma ile kontrol et.",
    en:
      "Safely isolate flow/energy, repair the leak source and control spread with suitable secondary containment.",
  },
  restrict_access: {
    hierarchy: "administrative",
    tr:
      "Etkilenen alanı geçici olarak sınırla; güvenli erişim veya ekipman bütünlüğü doğrulanana kadar maruziyeti önle.",
    en:
      "Temporarily restrict the affected area and prevent exposure until safe access or equipment integrity is verified.",
  },
  clear_walkway: {
    hierarchy: "elimination",
    tr:
      "Geçiş alanındaki dağınık malzeme ve atıkları hemen kaldır; zemini temiz, engelsiz ve yürümeye elverişli duruma getir.",
    en:
      "Immediately remove loose materials and waste from the access route and restore a clear, walkable surface.",
  },
  housekeeping_program: {
    hierarchy: "administrative",
    tr:
      "Malzeme yerlerini, atık toplama sıklığını ve vardiya sonu saha kontrolünü tanımlayan düzen ve temizlik standardı uygula; geçiş yollarını periyodik olarak doğrula.",
    en:
      "Implement a housekeeping standard covering storage locations, waste-removal frequency and end-of-shift checks; periodically verify access routes.",
  },
  reorganize_storage: {
    hierarchy: "elimination",
    tr:
      "Dengesiz veya raf sınırı dışına taşan malzemeleri güvenli yöntemle indir; yükleri tabanı kararlı, düşmeye karşı tutulmuş ve raf kapasitesine uygun biçimde yeniden istifle.",
    en:
      "Safely remove unstable or overhanging materials and restack them with a stable base, suitable retention and within the rack capacity.",
  },
  storage_stacking_standard: {
    hierarchy: "administrative",
    tr:
      "Raf gözü kapasitesi, yük yüksekliği, taşma sınırı, ağır malzemenin alt seviyeye yerleştirilmesi ve düşmeye karşı tutma yöntemleri için yazılı istif kabul kriteri uygula; vardiya kontrollerini kayda bağla.",
    en:
      "Apply documented stacking acceptance criteria for bay capacity, load height, overhang, placement of heavy items and load retention; record shift inspections.",
  },
  secure_heavy_floor_component: {
    hierarchy: "engineering",
    tr:
      "Yuvarlanma veya devrilme potansiyeli bulunan ağır parçayı uygun takoz, sehpa, beşik veya mekanik sabitlemeyle kararlı duruma getir; sabitleme tamamlanana kadar çarpma hattını sınırla.",
    en:
      "Stabilize the heavy component against rolling or overturning using suitable chocks, stands, cradles or mechanical restraint; isolate its strike path until restraint is complete.",
  },
  heavy_component_storage_standard: {
    hierarchy: "administrative",
    tr:
      "Tank bombesi, silindirik parça, bobin ve benzeri ağır bileşenler için yük kapasitesi doğrulanmış sehpa/beşik, takozlama, sabitleme ve güvenli taşıma kabul kriterleri uygula; parçaları geçiş ve çalışma alanı dışında depola.",
    en:
      "Apply verified-capacity stands/cradles, chocking, restraint and handling criteria for dished heads, cylindrical parts, coils and similar heavy components; store them outside access and work areas.",
  },
  verify_process_vent_design: {
    hierarchy: "engineering",
    tr:
      "Havalık veya taşma ağzını körleme ya da kapatma; önce tasarım görevini, gerekli serbest kesiti ve güvenli tahliye yönünü doğrula. Gerekliyse akışı kısıtlamayan, servise uygun yabancı cisim koruması kullan.",
    en:
      "Do not blind or cap the vent/overflow opening; first verify its design duty, required free area and safe discharge direction. Where required, use service-compatible foreign-object protection that does not restrict flow.",
  },
  process_vent_function_inspection: {
    hierarchy: "administrative",
    tr:
      "Havalık/taşma hattının boyutunu, tıkanma ve yağmur-yabancı cisim girişine karşı düzenini, tahliye konumunu ve prosesle uyumunu tasarım senaryosuna göre kontrol et; koruma elemanının tahliye kapasitesini düşürmediğini doğrula.",
    en:
      "Inspect vent/overflow sizing, blockage and weather/foreign-object protection, discharge location and process compatibility against the design scenario; verify that any protective element does not reduce relief capacity.",
  },
  repair_insulation: {
    hierarchy: "engineering",
    tr:
      "Hattın proses koşuluna uygun yalıtım ve dış kaplamasını yenile; yüzeyin tamamen kapandığını ve kaplamanın mekanik olarak sabitlendiğini doğrula.",
    en:
      "Renew insulation and cladding to suit the process conditions; verify complete coverage and mechanical security of the cladding.",
  },
  verify_process_condition: {
    hierarchy: "administrative",
    tr:
      "Akışkan türünü, çalışma sıcaklığını/basıncını ve temas riskini proses kayıtlarından doğrula; uygulanacak kabul kriterini bu değerlere göre belirle.",
    en:
      "Verify fluid, operating temperature/pressure and contact risk from process records, then set acceptance criteria from those values.",
  },
  stabilize_ground: {
    hierarchy: "engineering",
    tr:
      "Makinenin çalışma platformunu üretici limitleri ve zemin taşıma kapasitesine göre tesviye edip sıkıştır; palet/ayakların tamamında kararlı ve drenajı yeterli yüzey sağla.",
    en:
      "Level and compact the operating platform to manufacturer limits and ground-bearing capacity; provide stable, adequately drained support under all tracks/outriggers.",
  },
  ground_acceptance: {
    hierarchy: "administrative",
    tr:
      "Çalışma öncesi zemin eğimi, taşıma kapasitesi, kenar yaklaşımı ve yağış sonrası değişimi için yetkin kişi kabul kontrolü ve kayıtlı durdurma kriteri uygula.",
    en:
      "Before work, apply a competent-person acceptance check and documented stop criteria for slope, bearing capacity, edge distance and post-rain changes.",
  },
  safe_access_route: {
    hierarchy: "engineering",
    tr:
      "Ekskavatör çevresindeki yaya erişimini çalışma ve manevra alanından ayır; engebeli yüzeyde işaretli, yeterli genişlikte ve kayma/takılma riski giderilmiş güvenli bir güzergâh oluştur.",
    en:
      "Separate pedestrian access around the excavator from its operating and manoeuvring area; provide a marked, adequately wide route with slip and trip hazards controlled across uneven ground.",
  },
  stabilize_slope: {
    hierarchy: "engineering",
    tr:
      "Şev yüzeyindeki gevşek kaya ve toprak kütlesini yetkin kişi değerlendirmesine göre kontrollü temizleme, kademelendirme, iksa veya uygun tutma yöntemiyle stabilize et; çalışma alanına malzeme düşme yolunu kes.",
    en:
      "Stabilize loose rock and soil on the slope using controlled scaling, benching, shoring or suitable retention based on a competent assessment; interrupt the material-fall path to the work area.",
  },
  clear_loose_material: {
    hierarchy: "elimination",
    tr:
      "Gevşek malzeme düşme hattındaki çalışan ve ekipmanı uzaklaştır; güvenli yöntem belirlendikten sonra kopabilecek kaya ve toprak parçalarını kontrollü olarak temizle.",
    en:
      "Remove people and equipment from the loose-material fall path and, once a safe method is established, scale or remove detachable rock and soil under control.",
  },
  slope_acceptance: {
    hierarchy: "administrative",
    tr:
      "Şev yüksekliği/eğimi, malzeme yapısı, çatlak-kopma izleri, su etkisi ve kazı ilerlemesine göre yetkin kişi kontrolü yap; yağış, titreşim ve her geometrik değişiklik sonrası yeniden kabul kriteri uygula.",
    en:
      "Have a competent person assess slope height/angle, material, cracking or detachment signs, water effects and excavation progress; reapply acceptance criteria after rain, vibration or geometry changes.",
  },
  provide_ppe: {
    hierarchy: "ppe",
    tr:
      "İş ve maruziyet değerlendirmesine uygun KKD'yi işe başlamadan önce sağla ve doğru kullanımını doğrula.",
    en:
      "Provide PPE selected for the task and exposure before work and verify correct use.",
  },
  ppe_program: {
    hierarchy: "administrative",
    tr:
      "KKD seçimi, uygunluk kontrolü, bakım/değişim ve kullanım gözetimini görev bazlı risk değerlendirmesine bağla.",
    en:
      "Tie PPE selection, fit checks, maintenance/replacement and use supervision to the task risk assessment.",
  },
};

type ControlPlan = {
  corrective: string;
  preventive: string[];
  selectionReason: string;
};

function criticalActiveEnergy(fact: HazardFactV3, joined: string): boolean {
  const criticalConsequence = fact.consequence_class === "single_fatality" ||
    fact.consequence_class === "multiple_fatality_major_environmental";
  const directEvent = fact.barrier_state === "absent_or_failed_event_active" ||
    fact.barrier_state === "absent_or_failed_event_direct";
  return criticalConsequence && directEvent &&
    /(?:kaldır|kaldir|lifting|pim|segman|pin|retainer|elektr|voltage|basınç|basinc|pressure|yapı|yapi|structure|stabil|devril|overturn|zemin|ground)/iu
      .test(joined);
}

function inferredControlPlan(fact: HazardFactV3): ControlPlan {
  const joined = normalized(
    `${fact.mechanism_code} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${fact.entity.equipment_family} ${fact.entity.component} ${fact.hazard_mechanism}`,
  );
  const evidence = normalized(fact.evidence.affirmative_cues.join(" "));
  if (fact.assessment_basis === "equipment_integrity_verification") {
    if (/(?:overhead crane|bridge crane|kopru vinc|vinc)/u.test(joined)) {
      return {
        corrective: "verify_periodic_control_status",
        preventive: [
          "periodic_crane_inspection",
          "crane_safety_function_test",
        ],
        selectionReason: "crane_asset_assurance",
      };
    }
    if (/(?:karistirici|agitator|tahrik|drive|coupling|kaplin)/u.test(joined)) {
      return {
        corrective: "verify_periodic_control_status",
        preventive: [
          "agitator_guard_loto_inspection",
          "process_equipment_integrity_inspection",
        ],
        selectionReason: "agitator_asset_assurance",
      };
    }
    if (
      /(?:safeguard|emniyet fonksiyon|seviye|tasma|relief|tahliye)/u.test(
        joined,
      )
    ) {
      return {
        corrective: "verify_periodic_control_status",
        preventive: [
          "process_safeguard_function_test",
          "process_equipment_integrity_inspection",
        ],
        selectionReason: "process_safeguard_assurance",
      };
    }
    return {
      corrective: "verify_periodic_control_status",
      preventive: [
        "process_equipment_integrity_inspection",
        "process_safeguard_function_test",
      ],
      selectionReason: "process_asset_assurance",
    };
  }
  if (
    fact.mechanism_code === "fall_from_height" &&
    /(?:korkuluk|guardrail|midrail|bariyer|barrier|open edge|acik kenar)/u
      .test(joined)
  ) {
    return {
      corrective: "restrict_access",
      preventive: ["restore_barrier", "engineering_inspection"],
      selectionReason: "guard_barrier_condition",
    };
  }
  if (
    fact.mechanism_code === "fall_same_level" &&
    /(?:excavator|ekskavator|quarry|ocak|kazi|excavation|engebe|uneven ground|dengesiz zemin)/u
      .test(joined)
  ) {
    return {
      corrective: "restrict_access",
      preventive: ["safe_access_route", "ground_acceptance"],
      selectionReason: "uneven_ground_access_condition",
    };
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:platform|yuksekte|elevated|asili|hanging|gevsek|loose|torba|bag|malzeme|material)/u
      .test(`${joined} ${evidence}`) &&
    !/(?:raf|rack|istif|stack|dished head|tank head|tank bombesi|metal parca|yuvarlan|rolling|devril)/u
      .test(joined) &&
    !hasExcavationContext(`${joined} ${evidence}`)
  ) {
    return {
      corrective: "clear_loose_material",
      preventive: ["housekeeping_program"],
      selectionReason: "elevated_loose_material_condition",
    };
  }
  if (
    fact.mechanism_code === "fall_same_level" ||
    /(?:housekeeping|daginik|takil|walkway|clutter|obstructed pathway)/u
      .test(joined)
  ) {
    return {
      corrective: "clear_walkway",
      preventive: ["housekeeping_program"],
      selectionReason: "housekeeping_condition",
    };
  }
  if (
    fact.mechanism_code === "excavation_collapse_rockfall" ||
    (
      fact.mechanism_code === "falling_object" &&
      hasExplicitSlopeContext(`${joined} ${evidence}`)
    )
  ) {
    return {
      corrective: "clear_loose_material",
      preventive: ["stabilize_slope", "slope_acceptance"],
      selectionReason: "slope_stability_condition",
    };
  }
  if (
    fact.mechanism_code === "falling_object" &&
    hasExcavationContext(`${joined} ${evidence}`)
  ) {
    return {
      corrective: "clear_loose_material",
      preventive: ["restrict_access"],
      selectionReason: "excavation_falling_material_condition",
    };
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:kanca|hook).*(?:mandal|latch)|(?:mandal|latch).*(?:kanca|hook)/u
      .test(joined)
  ) {
    return {
      corrective: "stop_use",
      preventive: ["restore_hook_latch", "lifting_accessory_inspection"],
      selectionReason: "lifting_hook_latch_condition",
    };
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:raf|rack|istif|stack|stored material)/u.test(joined)
  ) {
    return {
      corrective: "reorganize_storage",
      preventive: ["storage_stacking_standard", "engineering_inspection"],
      selectionReason: "rack_storage_condition",
    };
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:zeminde|floor|dished head|tank head|tank bombesi|metal parca|yuvarlan|rolling|devril)/u
      .test(joined)
  ) {
    return {
      corrective: "secure_heavy_floor_component",
      preventive: [
        "heavy_component_storage_standard",
        "engineering_inspection",
      ],
      selectionReason: "heavy_floor_storage_condition",
    };
  }
  if (fact.mechanism_code === "equipment_overturn") {
    return {
      corrective: criticalActiveEnergy(fact, joined)
        ? "stop_use"
        : "restrict_access",
      preventive: ["stabilize_ground", "ground_acceptance"],
      selectionReason: "ground_stability_condition",
    };
  }
  if (
    fact.mechanism_code === "caught_in_pinch_shear" &&
    /(?:ekskavator|excavator|heavy equipment|mobile equipment)/u.test(joined) &&
    /(?:mafsal|articulated joint|boom|bucket|kova|kepce)/u.test(joined)
  ) {
    return {
      corrective: "restrict_access",
      preventive: ["isolate_energy", "engineering_inspection"],
      selectionReason: "mobile_equipment_articulation_condition",
    };
  }
  if (fact.mechanism_code === "caught_in_pinch_shear") {
    return {
      corrective: "restrict_access",
      preventive: ["guard_pinch_point", "isolate_energy"],
      selectionReason: "accessible_pinch_shear_condition",
    };
  }
  if (
    /housekeeping|dağınık|daginik|takıl|takil|geçiş|gecis|walkway|clutter/.test(
      joined,
    )
  ) {
    return {
      corrective: "clear_walkway",
      preventive: ["housekeeping_program"],
      selectionReason: "housekeeping_condition",
    };
  }
  if (
    /engebe|gevşek zemin|gevsek zemin|zemin stabil|unstable ground|uneven ground|taşıma kapasitesi|tasima kapasitesi/
      .test(joined)
  ) {
    return {
      corrective: criticalActiveEnergy(fact, joined)
        ? "stop_use"
        : "restrict_access",
      preventive: ["stabilize_ground", "ground_acceptance"],
      selectionReason: "ground_stability_condition",
    };
  }
  if (/kaynak|weld/.test(joined)) {
    return {
      corrective: criticalActiveEnergy(fact, joined)
        ? "stop_use"
        : "restrict_access",
      preventive: ["repair_weld", "ndt_inspection"],
      selectionReason: "weld_integrity_condition",
    };
  }
  if (/yalıtım|yalitim|insulation|cladding/.test(joined)) {
    return {
      corrective: "restrict_access",
      preventive: ["repair_insulation", "verify_process_condition"],
      selectionReason: "pipe_insulation_condition",
    };
  }
  if (/(?:sikisma|kesilme|ezilme|pinch|shear|crush)/.test(joined)) {
    return {
      corrective: "restrict_access",
      preventive: ["guard_pinch_point", "isolate_energy"],
      selectionReason: "accessible_pinch_shear_condition",
    };
  }
  if (
    /(?:kanca|hook)/.test(joined) &&
    /(?:mandal|latch|agiz|opening|kilit|lock)/.test(joined)
  ) {
    return {
      corrective: "stop_use",
      preventive: ["restore_hook_latch", "lifting_accessory_inspection"],
      selectionReason: "lifting_hook_latch_condition",
    };
  }
  const visibleRelease =
    /(?:sizinti|kacak|leak|spill|damlama|wet stain|islak iz|akiskan cikisi)/u
      .test(evidence);
  if (
    visibleRelease &&
    [
      "environmental_release",
      "chemical_contact_release",
      "hydraulic_pneumatic_release",
    ].includes(fact.mechanism_code)
  ) {
    return {
      corrective: "isolate_energy",
      preventive: ["leak_control", "engineering_inspection"],
      selectionReason: "release_condition",
    };
  }
  if (
    /(?:flans|flange|fitting|connection|baglanti)/u.test(joined) &&
    /(?:sarili|ortu|kaplama|wrapped|cover|anomaly|supheli)/u.test(joined) &&
    !visibleRelease
  ) {
    return {
      corrective: "restrict_access",
      preventive: ["verify_process_condition", "engineering_inspection"],
      selectionReason: "process_connection_anomaly_condition",
    };
  }
  if (
    /(?:open pipe end|open vent|vent pipe|breather|overflow|havalandirma|tasirma|acik boru agzi)/u
      .test(joined)
  ) {
    return {
      corrective: "verify_process_vent_design",
      preventive: ["process_vent_function_inspection"],
      selectionReason: "process_vent_design_condition",
    };
  }
  if (/hortum|hose|boru|pipe|fitting|flans|flange/.test(joined)) {
    const observedLineDamage =
      /(?:sizinti|kacak|leak|catlak|crack|yirtik|tear|kabarcik|blister|patlak|burst|dis katman.{0,20}(?:asinmis|hasarli)|visible abrasion mark)/
        .test(evidence);
    const hoseRouting = /(?:hortum|hose)/u.test(joined);
    return {
      corrective: "isolate_energy",
      preventive: observedLineDamage
        ? [
          "replace_component",
          ...(hoseRouting ? ["reroute_hose"] : []),
          "engineering_inspection",
        ]
        : [
          ...(hoseRouting ? ["reroute_hose"] : []),
          "engineering_inspection",
        ],
      selectionReason: observedLineDamage
        ? "pressurized_line_damage_condition"
        : "pressurized_line_routing_condition",
    };
  }
  if (/pim|segman|kilit|pin|retainer|bolt|civata/.test(joined)) {
    return {
      corrective: criticalActiveEnergy(fact, joined)
        ? "stop_use"
        : "restrict_access",
      preventive: ["secure_connection", "engineering_inspection"],
      selectionReason: "mechanical_connection_condition",
    };
  }
  if (
    /koruyucu|guard|interlock|korkuluk|midrail|mid rail|bariyer|açık kenar|acik kenar/
      .test(joined)
  ) {
    return {
      corrective: "restrict_access",
      preventive: ["install_guard", "engineering_inspection"],
      selectionReason: "guarding_condition",
    };
  }
  if (/elektr|iletken|kablo|voltage/.test(joined)) {
    return {
      corrective: "restrict_access",
      preventive: ["electrical_isolation", "engineering_inspection"],
      selectionReason: "electrical_condition",
    };
  }
  if (/sizinti|sızıntı|leak|release/.test(joined)) {
    return {
      corrective: "isolate_energy",
      preventive: ["leak_control", "engineering_inspection"],
      selectionReason: "release_condition",
    };
  }
  if (/yuksek|yüksek|kenar|fall/.test(joined)) {
    return {
      corrective: "restrict_access",
      preventive: ["install_fall_protection", "engineering_inspection"],
      selectionReason: "fall_condition",
    };
  }
  if (/raf|yapi|yapı|profil|structure|ankraj|iksa/.test(joined)) {
    return {
      corrective: criticalActiveEnergy(fact, joined)
        ? "stop_use"
        : "restrict_access",
      preventive: ["stabilize_structure", "engineering_inspection"],
      selectionReason: "structural_condition",
    };
  }
  if (/ppe|kkd|gözlük|gozluk|eldiven|baret|helmet|glove/.test(joined)) {
    return {
      corrective: "provide_ppe",
      preventive: ["ppe_program"],
      selectionReason: "ppe_condition",
    };
  }
  return {
    corrective: "restrict_access",
    preventive: ["engineering_inspection"],
    selectionReason: "competent_inspection_fallback",
  };
}

const CONTROL_INTENT_ALIASES: Record<string, string> = {
  clear_obstruction: "clear_walkway",
  establish_exclusion_zone: "restrict_access",
  assess_ground_stability: "ground_acceptance",
};

const DIRECT_CORRECTIVE_CODES = new Set([
  "stop_use",
  "restrict_access",
  "isolate_energy",
  "clear_walkway",
  "provide_ppe",
  "reorganize_storage",
  "secure_heavy_floor_component",
  "verify_process_vent_design",
  "clear_loose_material",
  "verify_periodic_control_status",
  "verify_chemical_inventory_controls",
  "verify_electrical_protection_status",
]);

const ALLOWED_INTENTS_BY_REASON: Record<string, Set<string>> = {
  crane_asset_assurance: new Set([
    "verify_periodic_control_status",
    "periodic_crane_inspection",
    "crane_safety_function_test",
  ]),
  agitator_asset_assurance: new Set([
    "verify_periodic_control_status",
    "agitator_guard_loto_inspection",
    "process_equipment_integrity_inspection",
  ]),
  process_safeguard_assurance: new Set([
    "verify_periodic_control_status",
    "process_safeguard_function_test",
    "process_equipment_integrity_inspection",
  ]),
  process_asset_assurance: new Set([
    "verify_periodic_control_status",
    "process_equipment_integrity_inspection",
    "process_safeguard_function_test",
  ]),
  guard_barrier_condition: new Set([
    "restrict_access",
    "restore_barrier",
    "install_guard",
    "engineering_inspection",
  ]),
  housekeeping_condition: new Set([
    "clear_walkway",
    "housekeeping_program",
  ]),
  elevated_loose_material_condition: new Set([
    "clear_loose_material",
    "housekeeping_program",
    "restrict_access",
  ]),
  lifting_hook_latch_condition: new Set([
    "stop_use",
    "restore_hook_latch",
    "lifting_accessory_inspection",
  ]),
  rack_storage_condition: new Set([
    "restrict_access",
    "reorganize_storage",
    "storage_stacking_standard",
    "engineering_inspection",
  ]),
  heavy_floor_storage_condition: new Set([
    "secure_heavy_floor_component",
    "heavy_component_storage_standard",
    "engineering_inspection",
  ]),
  process_vent_design_condition: new Set([
    "verify_process_vent_design",
    "process_vent_function_inspection",
  ]),
  slope_stability_condition: new Set([
    "restrict_access",
    "clear_loose_material",
    "stabilize_slope",
    "slope_acceptance",
  ]),
  excavation_falling_material_condition: new Set([
    "clear_loose_material",
    "restrict_access",
  ]),
  ground_stability_condition: new Set([
    "stop_use",
    "restrict_access",
    "stabilize_ground",
    "ground_acceptance",
  ]),
  uneven_ground_access_condition: new Set([
    "restrict_access",
    "safe_access_route",
    "ground_acceptance",
  ]),
  accessible_pinch_shear_condition: new Set([
    "restrict_access",
    "guard_pinch_point",
    "isolate_energy",
  ]),
  mobile_equipment_articulation_condition: new Set([
    "restrict_access",
    "isolate_energy",
    "engineering_inspection",
  ]),
  weld_integrity_condition: new Set([
    "stop_use",
    "restrict_access",
    "repair_weld",
    "ndt_inspection",
  ]),
  pipe_insulation_condition: new Set([
    "restrict_access",
    "repair_insulation",
    "verify_process_condition",
  ]),
  pressurized_line_damage_condition: new Set([
    "isolate_energy",
    "replace_component",
    "reroute_hose",
    "engineering_inspection",
  ]),
  pressurized_line_routing_condition: new Set([
    "isolate_energy",
    "reroute_hose",
    "engineering_inspection",
  ]),
  process_connection_anomaly_condition: new Set([
    "restrict_access",
    "verify_process_condition",
    "engineering_inspection",
  ]),
  mechanical_connection_condition: new Set([
    "stop_use",
    "restrict_access",
    "replace_component",
    "secure_connection",
    "engineering_inspection",
  ]),
  guarding_condition: new Set([
    "restrict_access",
    "restore_barrier",
    "install_guard",
    "engineering_inspection",
  ]),
  electrical_condition: new Set([
    "restrict_access",
    "electrical_isolation",
    "engineering_inspection",
  ]),
  release_condition: new Set([
    "isolate_energy",
    "leak_control",
    "engineering_inspection",
  ]),
  structural_condition: new Set([
    "stop_use",
    "restrict_access",
    "stabilize_structure",
    "engineering_inspection",
  ]),
  ppe_condition: new Set(["provide_ppe", "ppe_program"]),
  fall_condition: new Set([
    "restrict_access",
    "restore_barrier",
    "install_fall_protection",
    "engineering_inspection",
  ]),
  competent_inspection_fallback: new Set([
    "restrict_access",
    "engineering_inspection",
  ]),
};

function planWithControlIntents(fact: HazardFactV3): ControlPlan {
  if (fact.assessment_basis === "equipment_integrity_verification") {
    const accepted = [
      ...new Set(
        fact.control_intents.map((intent) =>
          CONTROL_INTENT_ALIASES[intent.action_code] ?? intent.action_code
        ).filter((code) => Boolean(CONTROL_CATALOG[code])),
      ),
    ];
    const corrective = accepted.find((code) =>
      DIRECT_CORRECTIVE_CODES.has(code)
    ) ?? "verify_periodic_control_status";
    const preventive = accepted.filter((code) => code !== corrective);
    return {
      corrective,
      preventive: preventive.length > 0
        ? preventive
        : ["engineering_inspection"],
      selectionReason:
        `asset_assurance_${fact.observed_condition.condition_code}`,
    };
  }
  const base = inferredControlPlan(fact);
  const allowed = ALLOWED_INTENTS_BY_REASON[base.selectionReason] ?? new Set();
  const accepted = fact.control_intents.flatMap((intent) => {
    let code = CONTROL_INTENT_ALIASES[intent.action_code] ??
      intent.action_code;
    if (
      base.selectionReason === "lifting_hook_latch_condition" &&
      code === "replace_component"
    ) {
      code = "restore_hook_latch";
    }
    return CONTROL_CATALOG[code] && allowed.has(code) ? [code] : [];
  });
  const uniqueAccepted = [...new Set(accepted)];
  const corrective =
    uniqueAccepted.find((code) => DIRECT_CORRECTIVE_CODES.has(code)) ??
      base.corrective;
  const preventive = [
    ...new Set([
      ...uniqueAccepted.filter((code) => code !== corrective),
      ...base.preventive,
      ...(
        (fact as AggregatedFact).reasonCodes?.includes(
            "assurance_absorbed_by_observed_finding",
          )
          ? [
            "agitator_guard_loto_inspection",
            "process_equipment_integrity_inspection",
          ]
          : []
      ),
    ]),
  ];
  return {
    corrective,
    preventive,
    selectionReason: uniqueAccepted.length > 0
      ? `${base.selectionReason}_structured_intent`
      : base.selectionReason,
  };
}

const ASSURANCE_CORRECTIVE_COPY: Record<
  string,
  { tr: string; en: string }
> = {
  process_tank_integrity_assurance: {
    tr:
      "Tank gövdesi, taşıyıcıları, ankrajları, nozulları ve bağlantıları için son bütünlük muayenesinin kapsamını, bulguların kapatılmasını ve sonraki kontrol tarihini doğrula; kritik kapsam eksikse kullanımı sınırla.",
    en:
      "Verify the latest integrity inspection scope for the vessel shell, supports, anchors, nozzles and connections, closure of findings and the next due date; restrict use if critical scope is missing.",
  },
  process_safeguard_assurance: {
    tr:
      "Seviye, taşma, basınç/sıcaklık izleme, tahliye, izolasyon ve acil durdurma fonksiyonlarının güncel test kayıtlarını ve set değerlerini doğrula; kritik emniyet fonksiyonu doğrulanamıyorsa prosesi sınırla.",
    en:
      "Verify current test records and set points for level, overfill, pressure/temperature monitoring, relief, isolation and emergency shutdown; restrict the process if a critical safeguard cannot be confirmed.",
  },
  tank_secondary_containment_assurance: {
    tr:
      "İkincil tutma hacmi, drenaj/vana konumu, sızdırmazlık ve taşma önleme düzeninin tank servisine uygunluğunu doğrula; yetersiz veya devre dışı tutma düzeninde dolumu sınırla.",
    en:
      "Verify secondary-containment capacity, drainage/valve position, leak tightness and overfill prevention for the tank service; restrict filling when containment is inadequate or unavailable.",
  },
  agitator_drive_assurance: {
    tr:
      "Tank üstü motor, tahrik, kaplin ve döner aktarım bölgesinde koruyucu kapsamını ve bakım için elektrik/mekanik LOTO noktalarını doğrula; erişilebilir aktarım veya doğrulanmamış izolasyonda ekipmanı sınırla.",
    en:
      "Verify guard coverage and electrical/mechanical LOTO points for the tank-top motor, drive, coupling and rotating transmission; restrict the equipment if transmission parts are accessible or isolation is unverified.",
  },
  process_line_integrity_assurance: {
    tr:
      "Boru hattı, destekler, flanşlar, vanalar ve bağlantılar için güncel mekanik bütünlük ve sızdırmazlık kontrol kapsamını doğrula; aktif kusur veya süresi geçmiş kritik kontrol varsa hattı güvenli duruma al.",
    en:
      "Verify current mechanical-integrity and containment inspection coverage for piping, supports, flanges, valves and joints; place the line in a safe state if an active defect exists or a critical inspection is overdue.",
  },
  crane_periodic_safety_assurance: {
    tr:
      "Köprü vincin taşıyıcı sistemi, halat/tambur ve kanca bloğu ile fren, limit ve yük sınırlama fonksiyonlarının geçerli kontrol/test kapsamını doğrula; kritik kapsam veya fonksiyon eksikse kullanımı durdur.",
    en:
      "Verify valid inspection and test coverage for the crane structure, rope/drum and hook block, brakes, limits and load limiting functions; stop use if critical scope or function is missing.",
  },
  mobile_equipment_periodic_integrity_assurance: {
    tr:
      "Şasi ve ROPS/FOPS, bom-ataşman yük yolu, pim-tutucular, silindir-hortumlar, fren/direksiyon ve palet-lastiklerin güncel periyodik kontrol kapsamını doğrula; kritik mekanik kusur kapanmadan ekipmanı kullanma.",
    en:
      "Verify current periodic inspection coverage for chassis and ROPS/FOPS, boom-attachment load path, pins/retainers, cylinders/hoses, brakes/steering and tracks/tyres; do not use the equipment until critical mechanical defects are closed.",
  },
  mobile_equipment_safety_function_assurance: {
    tr:
      "Servis/park freni, direksiyon, korna, geri hareket ikazı, aydınlatma, görüş yardımcıları ve emniyet kemerinin vardiya öncesi fonksiyon kontrolünü doğrula; arızalı kritik fonksiyonla çalışmaya izin verme.",
    en:
      "Verify pre-use function checks for service/parking brakes, steering, horn, reversing warnings, lighting, visibility aids and seat belt; do not operate with a failed critical function.",
  },
};

function renderedControlTarget(
  fact: HazardFactV3,
  plan: ControlPlan,
  language: string,
): string {
  const tr = isTurkish(language);
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  if (
    plan.selectionReason.startsWith("excavation_falling_material_condition")
  ) {
    return tr
      ? "Kazı alanı ve düşen malzeme hattı"
      : "Excavation area and falling-material path";
  }
  if (plan.selectionReason.startsWith("slope_stability_condition")) {
    return tr ? "Şev yüzeyi ve düşme hattı" : "Slope face and fall path";
  }
  if (GUARDRAIL_COMPONENT_PATTERN.test(context)) {
    return tr ? "Korkuluk sistemi" : "Guardrail system";
  }
  if (/(?:rack|raf|istif|stack)/u.test(context)) {
    return tr ? "Depolama rafı ve istif" : "Storage rack and stack";
  }
  if (/(?:hook|kanca)/u.test(context) && /(?:latch|mandal)/u.test(context)) {
    const grouped = "equivalentEntityRefs" in fact &&
      Array.isArray(fact.equivalentEntityRefs) &&
      fact.equivalentEntityRefs.length > 1;
    return tr
      ? grouped
        ? "Vinç kancaları ve emniyet mandalları"
        : "Vinç kancası ve emniyet mandalı"
      : grouped
      ? "Crane hooks and safety latches"
      : "Crane hook and safety latch";
  }
  if (/(?:hose|hortum)/u.test(context)) {
    return tr ? "Hidrolik hortum" : "Hydraulic hose";
  }
  if (/(?:walking surface|walkway|floor|zemin|gecis)/u.test(context)) {
    return tr ? "Geçiş alanı ve zemin" : "Access route and floor";
  }
  return capitalized(cleanPublicText(fact.entity.component), language);
}

function renderedControlCopy(
  code: string,
  target: string,
  language: string,
): string {
  const tr = isTurkish(language);
  const raw = CONTROL_CATALOG[code][tr ? "tr" : "en"];
  const named = code === "engineering_inspection"
    ? raw.replace(
      tr
        ? /^Hedef bileşeni/u
        : /^Have a competent person inspect the target component/u,
      tr
        ? target
        : `Have a competent person inspect the ${
          target.toLocaleLowerCase("en-US")
        }`,
    )
    : raw;
  return stripDirectImageAddress(named).trim().slice(0, 1_200).trim();
}

function orderBySectorControlPreference(
  codes: string[],
  profile: SectorProfileV2 | null,
  enabled: boolean,
): { codes: string[]; applied: boolean } {
  if (!enabled || !profile || profile.preferredControlIntents.length === 0) {
    return { codes, applied: false };
  }
  const rank = new Map(
    profile.preferredControlIntents.map((code, index) => [code, index]),
  );
  const originalIndex = new Map(codes.map((code, index) => [code, index]));
  const ordered = [...codes].sort((left, right) => {
    const leftRank = rank.get(left) ?? Number.MAX_SAFE_INTEGER;
    const rightRank = rank.get(right) ?? Number.MAX_SAFE_INTEGER;
    if (leftRank !== rightRank) return leftRank - rightRank;
    return (originalIndex.get(left) ?? 0) - (originalIndex.get(right) ?? 0);
  });
  return {
    codes: ordered,
    applied: ordered.some((code, index) => code !== codes[index]),
  };
}

function renderControls(
  fact: HazardFactV3,
  language: string,
  sectorProfile: SectorProfileV2 | null,
  sectorPreferencesEnabled: boolean,
) {
  const plan = planWithControlIntents(fact);
  const corrective = CONTROL_CATALOG[plan.corrective];
  const eligiblePreventiveCodes = [...new Set(plan.preventive)].filter(
    (code) => CONTROL_CATALOG[code],
  );
  const preferred = orderBySectorControlPreference(
    eligiblePreventiveCodes,
    sectorProfile,
    sectorPreferencesEnabled,
  );
  const preventiveCodes = preferred.codes.slice(0, 3);
  const tr = isTurkish(language);
  const target = renderedControlTarget(fact, plan, language);
  const assuranceCorrective = fact.assessment_basis ===
      "equipment_integrity_verification"
    ? ASSURANCE_CORRECTIVE_COPY[
      fact.observed_condition.condition_code.trim().toLowerCase()
    ]
    : undefined;
  const groupedHooks = "equivalentEntityRefs" in fact &&
    Array.isArray(fact.equivalentEntityRefs) &&
    fact.equivalentEntityRefs.length > 1 &&
    /(?:hook|kanca)/u.test(normalized(
      `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.short_text}`,
    ));
  const preventiveText = preventiveCodes.map((code, index) => {
    let copy = renderedControlCopy(code, target, language);
    if (groupedHooks && tr && code === "restore_hook_latch") {
      copy =
        "Kancaların emniyet mandallarını üretici şartnamesine uygun şekilde onar veya değiştir; mandalların yayla kapanmasını ve kanca ağızlarını tam kapatmasını işlevsel olarak doğrula.";
    } else if (groupedHooks && tr && code === "lifting_accessory_inspection") {
      copy =
        "Kancaları, mandalları, pimleri ve yük bağlantı elemanlarını yetkin kişiyle kullanım öncesi ve periyodik kontrole al; deformasyon, aşınma, açıklık ve kilitleme kabul kriterlerini kayda bağla.";
    } else if (groupedHooks && !tr && code === "restore_hook_latch") {
      copy =
        "Repair or replace the hook safety latches to manufacturer specification and functionally verify spring closure and full coverage of each hook opening.";
    } else if (
      groupedHooks && !tr && code === "lifting_accessory_inspection"
    ) {
      copy =
        "Have a competent person inspect the hooks, latches, pins and load attachments before use and periodically; document acceptance criteria for deformation, wear, opening and locking.";
    }
    return preventiveCodes.length === 1 ? copy : `${index + 1}. ${copy}`;
  }).join("\n");
  return [
    {
      kind: "corrective",
      title: tr ? "Acil/geçici kontrol" : "Immediate/interim control",
      text: stripDirectImageAddress(
        assuranceCorrective?.[tr ? "tr" : "en"] ??
          corrective[tr ? "tr" : "en"],
      ).trim().slice(0, 1_200).trim(),
      action_code: plan.corrective,
      action_codes: [plan.corrective],
      control_hierarchy: corrective.hierarchy,
      target,
      selection_reason: preferred.applied
        ? `${plan.selectionReason}_sector_preference`
        : plan.selectionReason,
    },
    {
      kind: "preventive",
      title: tr ? "Kalıcı/önleyici kontrol" : "Permanent/preventive control",
      text: preventiveText,
      action_code: preventiveCodes[0] ?? "engineering_inspection",
      action_codes: preventiveCodes,
      control_hierarchy: preventiveCodes.map((code) =>
        CONTROL_CATALOG[code].hierarchy
      ).join(","),
      target,
      selection_reason: preferred.applied
        ? `${plan.selectionReason}_sector_preference`
        : plan.selectionReason,
    },
  ];
}

function stripDirectImageAddress(value: string): string {
  return value
    .replace(
      /(^|[.!?]\s+)(?:fotoğrafın|fotografin|görselin|gorselin|görüntünün|goruntunun|photo(?:graph)?['’]?s?|image['’]?s?)\s+genelinde\s*[,;:\-]?\s*/giu,
      "$1",
    )
    .replace(
      /(^|[.!?]\s+)(?:fotoğrafta|fotografta|görselde|gorselde|görüntüde|goruntude|in\s+the\s+(?:photo|photograph|image))\s+(?:yer\s+alan|bulunan|görülen|gorulen|gösterilen|gosterilen|shown|visible)?\s*/giu,
      "$1",
    )
    .replace(
      /(^|[.!?]\s+)(?:fotoğraftaki|fotograftaki|görseldeki|gorseldeki|görüntüdeki|goruntudeki)\s+/giu,
      "$1",
    )
    .replace(
      /\b(?:fotoğraf|fotograf|görsel|gorsel|görüntü|goruntu|photo|photograph|image)\s+tek\s+başına\b/giu,
      "Bu gözlem tek başına",
    )
    .replace(
      /\b(?:foto|fotoğraf|fotograf|görsel|gorsel|görüntü|goruntu|photo|photograph|image)[_\s-]*(?:no\.?\s*:?\s*)?#?\s*\d+\s*(?:[’']?(?:de|da|te|ta)|\b(?:in|on))?\s*[,;:\-]?\s*/giu,
      "",
    )
    .replace(
      /\b\d+\s*(?:\.|numaralı|numarali)\s*(?:fotoğrafta|fotografta|görselde|gorselde|görüntüde|goruntude|photo|photograph|image)\s*[,;:\-]?\s*/giu,
      "",
    )
    .replace(
      /(?:birinci|[İi]kinci|[Üü]çüncü|ucuncu|[Dd]ördüncü|dorduncu|[Bb]eşinci|besinci|first|second|third|fourth|fifth)\s+(?:fotoğrafta|fotografta|görselde|gorselde|görüntüde|goruntude|photo|photograph|image)\s*[,;:\-]?\s*/giu,
      "",
    )
    .replace(
      /\b(?:fotoğrafın|fotografin|görselin|gorselin|görüntünün|goruntunun|photo(?:graph)?['’]?s?|image['’]?s?)\s+(?:sağ|sag|sol|üst|ust|alt|orta|merkez)\s+(?:(?:taraf(?:lar)?|k[ıi]s(?:ım|im|m|ımlar|imler)|bölüm(?:ler)?|bolum(?:ler)?)(?:ındaki|indaki|undaki|ündeki|daki|deki|taki|teki|ında|inda|inde|unda|ünde|unde|da|de|ta|te)?|side|part|section)\s*(?:bulunan|yer alan|görülen|gorulen|located|shown)?\s*/giu,
      "",
    )
    .replace(
      /\b(?:fotoğrafta|fotografta|görselde|gorselde|görüntüde|goruntude|photo|image)\s+(?:sağda|sagda|solda|üstte|ustte|altta|on the right|on the left|at the top|at the bottom)\s*/giu,
      "",
    )
    .replace(
      /((?:üst|ust|alt)\s+platform)(?:un|ın|in|ün)\s+(?:sağ|sag|sol)\s+taraf(?:ındaki|indaki)\s+korkulukta\b/giu,
      "$1 korkuluğunda",
    )
    .replace(
      /(?:özellikle\s+|ozellikle\s+)?(?:sağ\s+ve\s+sol|sag\s+ve\s+sol|sol\s+ve\s+sağ|sol\s+ve\s+sag|sağ|sag|sol|üst|ust|alt|orta|merkez)\s+(?:(?:taraf(?:lar)?|k[ıi]s(?:ım|im|m|ımlar|imler)|bölüm(?:ler)?|bolum(?:ler)?)(?:ındaki|indaki|undaki|ündeki|daki|deki|taki|teki|ında|inda|inde|unda|ünde|unde|da|de|ta|te))\s*[,;:\-]?\s*/giu,
      "",
    )
    .replace(
      /(?:özellikle\s+|ozellikle\s+)?(?:sağ\s+ve\s+sol|sag\s+ve\s+sol|sol\s+ve\s+sağ|sol\s+ve\s+sag|sağ|sag|sol|üst|ust|alt|orta|merkez)\s+((?:zemin|alan|bölge|bolge)(?:de|da|te|ta|inde|inda|ünde|unde)?)\s*[,;:\-]?\s*/giu,
      "$1 ",
    )
    .replace(
      /((?:üst|ust|alt)\s+platform)(?:un|ın|in|ün)\s+korkulukta\b/giu,
      "$1 korkuluğunda",
    )
    .replace(
      /\b(?:especially\s+)?(?:on\s+)?(?:the\s+)?(?:right\s+and\s+left|left\s+and\s+right|right|left|upper|lower)\s+(?:side|sides|part|section)s?\s*[,;:\-]?\s*/giu,
      "",
    )
    .replace(
      /\b(?:arka|ön|on)\s+planda(?:ki|da|de)?\s*(?:da|de)?\s*/giu,
      "",
    )
    .replace(/\b(?:in the )?(?:background|foreground)\s*[,;:\-]?\s*/giu, "")
    .trim();
}

function cleanPublicText(value: string, max = 800): string {
  return stripDirectImageAddress(value)
    .replace(/^[\p{L}\p{N}]+(?:_[\p{L}\p{N}]+)+\s*:\s*/u, "")
    .replace(/_/g, " ")
    .replace(/\s*\/\s*/g, " ve ")
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:!?])/g, "$1")
    .replace(/([.!?])(?:\s*\1)+/g, "$1")
    .replace(
      /kötü\s+ev\s+idaresi/giu,
      "çalışma alanındaki düzen ve temizlik yetersizliği",
    )
    .trim().slice(0, max).trim();
}

function withoutTerminalPunctuation(value: string): string {
  return cleanPublicText(value).replace(/[.!?;:,]+$/u, "").trim();
}

function capitalized(value: string, language = "tr"): string {
  const clean = withoutTerminalPunctuation(value);
  const locale = isTurkish(language) ? "tr-TR" : "en-US";
  return clean ? `${clean[0].toLocaleUpperCase(locale)}${clean.slice(1)}` : "";
}

function capitalizeInitial(value: string, language = "tr"): string {
  const clean = value.trim();
  const locale = isTurkish(language) ? "tr-TR" : "en-US";
  return clean ? `${clean[0].toLocaleUpperCase(locale)}${clean.slice(1)}` : "";
}

function capitalizeSentenceStarts(value: string, language = "tr"): string {
  const locale = isTurkish(language) ? "tr-TR" : "en-US";
  return value.replace(
    /(^|[.!?]\s+)(\p{L})/gu,
    (_match, prefix: string, letter: string) =>
      `${prefix}${letter.toLocaleUpperCase(locale)}`,
  );
}

function fallbackTitle(value: string, language: string): string {
  let title = capitalized(value, language);
  if (isTurkish(language)) {
    title = title
      .replace(
        /\s+(?:bulunmaktadır|bulunuyor|mevcuttur|mevcut|görülmektedir|gözlenmektedir|gözleniyor|tespit edilmiştir)$/iu,
        "",
      )
      .replace(/\s+oluşturmaktadır$/iu, "")
      .trim();
  }
  return title;
}

const ASSURANCE_TITLES_TR: Record<string, string> = {
  process_tank_integrity_assurance:
    "Proses tanklarının mekanik bütünlüğü ve periyodik kontrolü",
  process_safeguard_assurance:
    "Proses tanklarında seviye, taşma ve emniyet fonksiyonlarının doğrulanması",
  tank_secondary_containment_assurance:
    "Tanklarda taşma, sızıntı ve ikincil tutma kontrolleri",
  agitator_drive_assurance:
    "Tank üstü tahrik ekipmanında koruyucu ve enerji izolasyonu kontrolü",
  crane_periodic_safety_assurance:
    "Köprü vinçlerin periyodik kontrolü ve emniyet fonksiyonlarının doğrulanması",
  lng_storage_integrity_assurance:
    "LNG tank sisteminde kriyojenik bütünlük ve periyodik muayene",
  lng_process_safeguard_assurance:
    "LNG tesisinde gaz algılama, proses emniyeti ve acil durdurma kontrolleri",
  lpg_storage_integrity_assurance:
    "LPG depolama sisteminde basınç bütünlüğü ve periyodik kontrol",
  lpg_safeguard_assurance:
    "LPG tesisinde emniyet fonksiyonları ve acil durum kontrolleri",
  flammable_gas_ex_area_assurance:
    "LNG/LPG alanında tehlikeli bölge sınıflandırması ve Ex ekipman uygunluğu",
  pressure_equipment_integrity_assurance:
    "Basınçlı ekipmanın mekanik bütünlüğü ve periyodik kontrolü",
  pressure_safety_device_assurance:
    "Basınç emniyet cihazlarının ayar ve fonksiyon doğrulaması",
  mobile_equipment_periodic_integrity_assurance:
    "Mobil iş ekipmanının mekanik bütünlüğü ve periyodik kontrolü",
  mobile_equipment_safety_function_assurance:
    "Mobil iş ekipmanında operasyonel emniyet fonksiyonlarının doğrulanması",
  industrial_vehicle_safety_assurance:
    "Endüstriyel aracın yol ve operasyon emniyeti kontrolleri",
  machine_tool_guarding_assurance:
    "Takım tezgâhında koruyucu ve emniyet fonksiyonlarının doğrulanması",
  machine_tool_loto_maintenance_assurance:
    "Takım tezgâhında bakım, ayar ve LOTO güvenliği",
  bulk_machine_guard_loto_assurance:
    "Proses makinesinde koruyucu, acil durdurma ve LOTO kontrolleri",
  bulk_machine_integrity_assurance:
    "Proses makinesinin mekanik bütünlüğü ve durum izlemesi",
  pump_integrity_assurance:
    "Pompa sisteminde bütünlük ve durum bazlı bakım kontrolleri",
  process_line_integrity_assurance:
    "Proses hattının mekanik bütünlüğü ve sızdırmazlık kontrolü",
  combustion_safeguard_assurance:
    "Fırın yakma ve aşırı sıcaklık emniyet fonksiyonlarının doğrulanması",
  tire_inflation_assurance:
    "Lastik şişirme işleminde basınç ve fırlama güvenliği",
  chemical_information_storage_assurance:
    "Kimyasal envanter, SDS, uyumluluk ve depolama kontrolleri",
  rail_system_integrity_assurance:
    "Raylı sistemde hat, araç ve hareket emniyeti kontrolleri",
  electrical_system_assurance:
    "Elektrik dağıtım ekipmanında koruma ve periyodik test programı",
  workshop_system_assurance:
    "Atölye genelinde makine, enerji ve acil durum denetimi",
};

function turkishTitle(fact: HazardFactV3): string {
  const condition = normalized(
    `${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.entity.identity_basis} ${condition} ${fact.hazard_mechanism} ${
      fact.evidence.affirmative_cues.join(" ")
    }`,
  );
  if (fact.assessment_basis === "equipment_integrity_verification") {
    const exact = ASSURANCE_TITLES_TR[
      fact.observed_condition.condition_code.trim().toLowerCase()
    ];
    if (exact) return exact;
    if (/crane|vinc|kaldirma/u.test(context)) {
      return "Köprü vinçlerin periyodik kontrolü ve emniyet fonksiyonlarının doğrulanması";
    }
    if (/karistirici|agitator|drive|tahrik/u.test(context)) {
      return "Tank üstü tahrik ekipmanında koruyucu ve enerji izolasyonu kontrolü";
    }
    if (
      /secondary containment|ikincil tutma|tasma havuzu|drenaj/u.test(context)
    ) {
      return "Tanklarda taşma, sızıntı ve ikincil tutma kontrolleri";
    }
    if (
      /process line|proses hatti|kimyasal hat|piping|boru hatti/u.test(context)
    ) {
      return "Proses hattının mekanik bütünlüğü ve sızdırmazlık kontrolü";
    }
    if (
      /emniyet fonksiyon|safeguard|tahliye|relief|taşma|tasma|seviye/u.test(
        context,
      )
    ) {
      return "Proses tanklarında seviye, taşma ve emniyet fonksiyonlarının doğrulanması";
    }
    if (/tank|vessel|proses/u.test(context)) {
      return "Proses tanklarının mekanik bütünlüğü ve periyodik kontrolü";
    }
  }
  if (
    hasExplicitSlopeContext(context) &&
    (
      fact.mechanism_code === "excavation_collapse_rockfall" ||
      fact.mechanism_code === "falling_object"
    )
  ) {
    return "Şevdeki gevşek kayaç ve malzemelerin düşme tehlikesi";
  }
  if (
    (fact.mechanism_code === "excavation_collapse_rockfall" ||
      fact.mechanism_code === "falling_object") &&
    hasExcavationContext(context)
  ) {
    return "Kazı alanındaki gevşek malzemelerin düşme tehlikesi";
  }
  if (
    /(?:hortum|hose)/u.test(context) &&
    /(?:guzergah|routing|route)/u.test(context) &&
    /(?:asin|abras|surtun|rubb)/u.test(context)
  ) {
    return "Hidrolik hortum güzergâhında sürtünme ve aşınma riski";
  }
  if (
    /(?:kanca|hook)/u.test(context) &&
    /(?:mandal|latch)/u.test(context)
  ) {
    const hookSubject = /(?:^| )(?:ust|upper|top|main hoist)(?: |$)/u.test(
        context,
      )
      ? "Üst vinç kancasında"
      : /(?:^| )(?:alt|lower|bottom)(?: |$)/u.test(context)
      ? "Alt vinç kancasında"
      : "Vinç kancasında";
    const missing = /(?:eksik|missing)/u.test(condition);
    const open = /(?:acik|open)/u.test(condition);
    const damaged = /(?:hasar|damag|kirik|broken)/u.test(condition);
    if (missing && !open && !damaged) {
      return `${hookSubject} emniyet mandalı eksikliği`;
    }
    if (open && !missing && !damaged) {
      return `${hookSubject} açık emniyet mandalı`;
    }
    if (damaged && !missing && !open) {
      return `${hookSubject} emniyet mandalı hasarı`;
    }
  }
  if (
    /(?:raf|rack)/u.test(context) &&
    /(?:dengesiz|asiri yuk|overload|unstable|istif|stack|storage)/u.test(
      context,
    )
  ) return "Raf üst seviyesindeki dengesiz malzeme istifi";
  if (
    GUARDRAIL_COMPONENT_PATTERN.test(context) &&
    /(?:eksik|missing|acik|open)/u.test(context)
  ) {
    if (TOE_BOARD_COMPONENT_PATTERN.test(context)) {
      return /(?:ust platform|upper platform)/u.test(context)
        ? "Üst platform korkuluğunda etek sacı eksikliği"
        : "Korkuluk sisteminde etek sacı eksikliği";
    }
    return /(?:ust platform|upper platform)/u.test(context)
      ? "Üst platform korkuluğunda ara korkuluk eksikliği"
      : "Korkuluk sisteminde ara korkuluk eksikliği";
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:gevsek|loose|torba|bag|malzeme|material)/u.test(context) &&
    !hasExcavationContext(context)
  ) {
    return "Üst seviyedeki gevşek malzemenin düşme tehlikesi";
  }
  if (
    /(?:housekeeping|daginik|clutter)/u.test(context) &&
    /(?:ust platform|upper platform)/u.test(context)
  ) return "Üst platform geçişindeki dağınık malzemeler";
  if (
    /(?:housekeeping|daginik|clutter)/u.test(context) &&
    /(?:zemin|floor|ground)/u.test(context)
  ) return "Geçiş alanındaki dağınık malzemeler ve takılma riski";
  if (
    /(?:ekskavator|excavator)/u.test(context) &&
    /(?:engebe|dengesiz zemin|uneven ground|unstable ground)/u.test(context)
  ) {
    return fact.mechanism_code === "fall_same_level"
      ? "Ekskavatör çevresindeki engebeli zeminde takılma tehlikesi"
      : "Ekskavatörün engebeli ve dengesiz zeminde çalışması";
  }
  if (
    (hasExplicitSlopeContext(context) || /egimli arazi/u.test(context)) &&
    /(?:stabil|dengesiz|unstable)/u.test(context)
  ) return "Kazı kenarı veya eğimli arazide stabilite riski";
  if (
    /(?:ekskavator|excavator)/u.test(context) &&
    /(?:sikisma|pinch|kesme|shear)/u.test(context)
  ) {
    return "Ekskavatör kolu ve kepçe bağlantılarında sıkışma ve kesilme tehlikesi";
  }
  return fallbackTitle(fact.observed_condition.short_text, "tr");
}

function renderTitle(fact: HazardFactV3, language: string): string {
  const equivalentCount = "equivalentEntityRefs" in fact &&
      Array.isArray(fact.equivalentEntityRefs)
    ? fact.equivalentEntityRefs.length
    : 1;
  const groupedContext = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  if (
    equivalentCount > 1 && /(?:hook|kanca)/u.test(groupedContext) &&
    /(?:latch|mandal)/u.test(groupedContext)
  ) {
    const missing = /(?:missing|absent|eksik)/u.test(groupedContext);
    const damaged = /(?:damage|damaged|broken|hasar|kirik)/u.test(
      groupedContext,
    );
    if (isTurkish(language)) {
      return missing
        ? "Köprü vinç kancalarında emniyet mandalı eksikliği"
        : damaged
        ? "Köprü vinç kancalarında emniyet mandalı hasarı"
        : "Köprü vinç kancalarında emniyet mandallarının açık kalması";
    }
    return missing
      ? "Missing safety latches on overhead-crane hooks"
      : damaged
      ? "Damaged safety latches on overhead-crane hooks"
      : "Open safety latches on overhead-crane hooks";
  }
  const title = isTurkish(language)
    ? turkishTitle(fact)
    : fallbackTitle(fact.observed_condition.short_text, language);
  if (title) return title.slice(0, 220);
  return fallbackTitle(fact.hazard_mechanism, language).slice(0, 220);
}

function entityPositionQualifier(
  fact: AggregatedFact,
  language: string,
): string {
  const context = normalized([
    fact.entity.identity_basis,
    fact.observed_condition.short_text,
    fact.technical_assessment.observation_narrative,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
  const tr = isTurkish(language);
  const positions: Array<[RegExp, string, string]> = [
    [/(?:^| )(?:ust|upper|top)(?: |$)/u, "üst", "upper"],
    [/(?:^| )(?:alt|lower|bottom)(?: |$)/u, "alt", "lower"],
    [/(?:^| )(?:sol|left)(?: |$)/u, "sol", "left"],
    [/(?:^| )(?:sag|right)(?: |$)/u, "sağ", "right"],
    [/(?:^| )(?:on|front)(?: |$)/u, "ön", "front"],
    [/(?:^| )(?:arka|rear)(?: |$)/u, "arka", "rear"],
  ];
  for (const [pattern, trValue, enValue] of positions) {
    if (pattern.test(context)) return tr ? trValue : enValue;
  }
  return "";
}

function disambiguatedTitle(
  fact: AggregatedFact,
  baseTitle: string,
  qualifier: string,
  language: string,
): string {
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  if (
    isTurkish(language) && /(?:kanca|hook)/u.test(context) &&
    /(?:mandal|latch)/u.test(context)
  ) {
    let state = "kusuru";
    if (
      /(?:eksik|missing)/u.test(context) && !/(?:hasar|damag)/u.test(context)
    ) {
      state = "eksikliği";
    } else if (/(?:acik|open)/u.test(context)) {
      state = "açık kalması";
    } else if (/(?:hasar|damag|kirik|broken)/u.test(context)) {
      state = "hasarı";
    }
    return `${
      capitalized(qualifier, language)
    } vinç kancasında emniyet mandalı ${state}`
      .slice(0, 220);
  }
  return `${baseTitle} (${qualifier})`.slice(0, 220);
}

function displayTitles(facts: AggregatedFact[], language: string): string[] {
  const baseTitles = facts.map((fact) => renderTitle(fact, language));
  return facts.map((fact, index) => {
    const title = baseTitles[index];
    const sameTitleSamePhoto = facts.some((other, otherIndex) =>
      otherIndex !== index &&
      normalized(baseTitles[otherIndex]) === normalized(title) &&
      other.sourcePhotoIndices.some((photoIndex) =>
        fact.sourcePhotoIndices.includes(photoIndex)
      )
    );
    if (!sameTitleSamePhoto) return title;
    const qualifier = entityPositionQualifier(fact, language);
    if (!qualifier) return title;
    return disambiguatedTitle(
      fact,
      title,
      qualifier,
      language,
    );
  });
}

function localizedExposedEntity(value: string, language: string): string {
  const clean = withoutTerminalPunctuation(value);
  if (!isTurkish(language)) return capitalized(clean, language);
  const exact: Record<string, string> = {
    person: "çalışan",
    persons: "çalışanlar",
    operator: "operatör",
    operators: "operatörler",
    personnel: "çalışanlar",
    worker: "çalışan",
    workers: "çalışanlar",
    "other personnel": "diğer çalışanlar",
    "nearby personnel": "yakındaki çalışanlar",
    "maintenance personnel": "bakım personeli",
    "ground crew": "saha çalışanları",
    environment: "çevre",
    equipment: "ekipman",
    "mobile equipment": "mobil iş ekipmanı",
    machine: "makine",
    "machine itself": "makinenin kendisi",
  };
  const canonicalClean = clean
    .replace(
      /\bworker[_\s-]*(?:foreground|background)?[_\s-]*\d+\b/giu,
      "worker",
    )
    .replace(/\b(?:person|operator|employee)[_\s-]*\d+\b/giu, "$1");
  const parts = canonicalClean.split(/\s*(?:,|;|\band\b|\bve\b|&)\s*/iu).filter(
    Boolean,
  ).map((part) => exact[normalized(part)] ?? part.toLocaleLowerCase("tr-TR"));
  if (parts.length === 0) return "İlgili çalışanlar";
  if (parts.length === 1) return capitalized(parts[0], "tr");
  return capitalized(
    `${parts.slice(0, -1).join(", ")} ve ${parts.at(-1)}`,
    "tr",
  );
}

function completeObservationSentence(title: string, language: string): string {
  const clean = withoutTerminalPunctuation(title);
  if (!clean) return "";
  return isTurkish(language)
    ? `${capitalized(clean, language)} tespit edilmiştir.`
    : `${capitalized(clean, language)} was observed.`;
}

function completeEventSentence(value: string, language: string): string {
  const clean = capitalized(value, language);
  return clean ? `${clean}.` : "";
}

function cleanNarrative(value: string, max = 1_600): string {
  return cleanPublicText(value, max)
    .replace(
      /^(?:fotoğrafta gözlenen koşul|fotografta gozlenen kosul|açıklama|aciklama|risk mekanizması|risk mekanizmasi|olası olay|olasi olay|observation|risk mechanism|possible event)\s*:\s*/iu,
      "",
    )
    .replace(
      /(?:Fotoğraf tek başına kesin kök nedeni doğrulamadığından\s*)?(?:saha incelemesiyle|sahada)\s+teyit edilmelidir\.?/giu,
      "",
    )
    .replace(/field verification is required\.?/giu, "")
    .replace(/\s+/g, " ")
    .trim();
}

function fallbackObservationNarrative(
  fact: HazardFactV3,
  language: string,
): string {
  const cues = [
    ...new Set(
      fact.evidence.affirmative_cues.map((cue) => cleanNarrative(cue, 450))
        .filter(Boolean),
    ),
  ].slice(0, 3);
  if (cues.length > 0) {
    const joined = cues.map((cue) => completeEventSentence(cue, language))
      .join(" ");
    return joined;
  }
  return completeObservationSentence(renderTitle(fact, language), language);
}

function fallbackTechnicalSignificance(
  fact: HazardFactV3,
  language: string,
): string {
  const mechanism = withoutTerminalPunctuation(fact.hazard_mechanism);
  const eventPath = completeEventSentence(fact.credible_event_path, language);
  if (!mechanism) return eventPath;
  return isTurkish(language)
    ? `${
      capitalized(mechanism, language)
    }, mevcut bariyer veya bütünlük koşulu nedeniyle gelişebilir. ${eventPath}`
    : `${
      capitalized(mechanism, language)
    } may develop under the observed barrier or integrity condition. ${eventPath}`;
}

function sanitizeUnsupportedRiskNarrative(
  fact: HazardFactV3,
  value: string,
): string {
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  if (!/(?:rack|shelf|stack|storage|raf|istif|depo)/u.test(context)) {
    return value;
  }
  const evidence = normalized(fact.evidence.affirmative_cues.join(" "));
  const capacityOrRackStabilityEvidence =
    /(?:readable|okunabilir).{0,24}(?:capacity|kapasite)|(?:rack|raf).{0,40}(?:deform|bukul|egil|tilt|lean|anchor.{0,12}(?:loose|missing)|ankraj.{0,12}(?:gevsek|eksik))/u
      .test(evidence);
  if (capacityOrRackStabilityEvidence) return value;
  return value.split(/(?<=[.!?])\s+/u).filter((sentence) =>
    !/(?:raf|rack).{0,45}(?:taşıma kapasitesini aş|tasima kapasitesini as|kapasite aş|kapasite as|devril|tip(?:ping| over)|collapse)|(?:exceed|overload).{0,35}(?:rack|shelf).{0,20}capacity/u
      .test(normalized(sentence))
  ).join(" ").trim();
}

function sanitizeDefinitiveConditionNarrative(
  fact: HazardFactV3,
  value: string,
): string {
  const conditionCode = normalized(fact.observed_condition.condition_code);
  if (
    !hasDirectVisibleSafetyBarrierGeometry(fact) ||
    !/(?:missing|absent|eksik)/u.test(conditionCode)
  ) return value;
  return value
    .replace(
      /(?:eksik\s+olduğu|eksik).{0,12}(?:veya|ya da).{0,36}(?:ciddi\s+şekilde\s+)?hasar(?:lı|\s+gördüğü|\s+görmüş)?/giu,
      (match) => /olduğu/iu.test(match) ? "eksik olduğu" : "eksik",
    )
    .replace(
      /(?:missing|absent).{0,12}(?:or|and\/or).{0,28}(?:damaged|broken)/giu,
      "missing",
    );
}

function sanitizeFindingNarrative(
  fact: HazardFactV3,
  value: string,
): string {
  return sanitizeDefinitiveConditionNarrative(
    fact,
    sanitizeUnsupportedRiskNarrative(fact, value)
      .replace(
        /(?:iş\s+sağlığı\s+ve\s+güvenliği|is\s+sagligi\s+ve\s+guvenligi|İSG|ISG)\s+standartlarına\s+uygun\s+olmayan\s+(?:bir\s+)?çalışma\s+ortamı/giu,
        "güvenli hareketi zorlaştıran bir çalışma ortamı",
      )
      .replace(
        /(?:non-compliant|not compliant)\s+with\s+(?:occupational\s+)?safety\s+standards/giu,
        "an impediment to safe movement and work",
      )
      .replace(
        /(?:Bu|Söz konusu|Soz konusu)\s+durum[^.!?]{0,220}(?:standart(?:lar)?(?:ına|ina)|mevzuat(?:a)?)[^.!?]*(?:aykırıdır|aykiridir|uygun değildir|uygun degildir)\.?/giu,
        "",
      )
      .replace(
        /(?:This|The)\s+(?:condition|situation)[^.!?]{0,220}(?:violates|is not compliant with|does not comply with)[^.!?]*(?:standards?|regulations?)?\.?/giu,
        "",
      ),
  );
}

function renderDescription(fact: HazardFactV3, language: string): string {
  const equivalentCount = "equivalentEntityRefs" in fact &&
      Array.isArray(fact.equivalentEntityRefs)
    ? fact.equivalentEntityRefs.length
    : 1;
  const groupedContext = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
  );
  const groupedHookObservation = equivalentCount > 1 &&
      /(?:hook|kanca)/u.test(groupedContext) &&
      /(?:latch|mandal)/u.test(groupedContext)
    ? isTurkish(language)
      ? `${equivalentCount} köprü vinç kancasının emniyet mandalı açık konumdadır. Mandalların kapanmaması, yük bağlantısının kanca ağzından istem dışı ayrılmasına karşı korumayı zayıflatır.`
      : `Safety latches are open on ${equivalentCount} overhead-crane hooks. Failure to close weakens protection against unintended separation of the load attachment from the hook opening.`
    : "";
  const rawObservation = groupedHookObservation || cleanNarrative(
    sanitizeFindingNarrative(
      fact,
      fact.technical_assessment.observation_narrative,
    ),
    1_200,
  );
  const observation = capitalizeSentenceStarts(
    rawObservation &&
      !ABSENCE_ONLY_PATTERNS.some((pattern) => pattern.test(rawObservation))
      ? rawObservation
      : fallbackObservationNarrative(fact, language),
    language,
  );
  const rawSignificance = cleanNarrative(
    sanitizeFindingNarrative(
      fact,
      fact.technical_assessment.technical_significance,
    ),
    1_600,
  );
  const significance = capitalizeSentenceStarts(
    rawSignificance &&
      !ABSENCE_ONLY_PATTERNS.some((pattern) => pattern.test(rawSignificance))
      ? rawSignificance
      : fallbackTechnicalSignificance(fact, language),
    language,
  );
  const exposed = localizedExposedEntity(fact.exposed_entity, language);
  return isTurkish(language)
    ? `${observation}\n\n${significance}\n\nEtkilenebilecekler: ${exposed}.`
    : `${observation}\n\n${significance}\n\nPotentially exposed: ${exposed}.`;
}

const NON_VISUAL_ROOT_CAUSE_PATTERNS = [
  /(?:bakım|bakim|kontrol|eğitim|egitim|prosedür|prosedur|standart).{0,30}(?:yapılmam|yapilmam|uygulanmam|verilmem|izlenmem)/iu,
  /(?:kurulum|montaj|bakım|bakim|işletme|isletme|organizasyon|yönetim|yonetim|çalışan|calisan|personel).{0,55}(?:takılmam|takilmam|takmam|kurmam|bırakıl|birakil|bırakm|birakm|kaldırıl|kaldiril|kaldırm|kaldirm|çıkarıl|cikaril|sökül|sokul|sökm|sokm|yerleştirm|yerlestirm|temizlem|sabitlem|depolam)/iu,
  /(?:malzeme|parça|parca|nesne).{0,80}(?:bırakıl|birakil|konul|yerleştiril|yerlestiril|istiflen|depolan|terk edil)/iu,
  /(?:düzen|duzen|temizlik|housekeeping).{0,36}(?:eksik|yetersiz|olmama)/iu,
  /(?:iyi\s+bir\s+)?(?:düzen|duzen).{0,30}(?:temizlik|housekeeping).{0,30}(?:eksik|yetersiz|olmama)/iu,
  /(?:yetersiz|uygunsuz).{0,36}(?:zemin\s+hazırlığı|zemin\s+hazirligi|hazırlık|hazirlik|planlama|uygulama)/iu,
  /(?:maintenance|inspection|training|procedure|standard).{0,30}(?:not performed|not applied|not provided|not followed)/iu,
  /(?:installation|maintenance|operation|management|worker|personnel).{0,45}(?:did not|failed to|removed|left|placed|stored|installed)/iu,
  /(?:material|part|object).{0,30}(?:was left|was placed|was stored|was stacked|was removed)/iu,
  /(?:prosedür|prosedur|standart|eğitim|egitim|bakım|bakim|kontrol|program).{0,55}(?:eksik|yetersiz|uyulm|ihlali|uygulanmam)/iu,
  /(?:çalışan|calisan|personel|operatör|operator|worker).{0,55}(?:uymam|bırak|birak|takm|çıkarm|cikarm|yerleştirm)/iu,
  /(?:uygun\s+olmayan|uygunsuz).{0,36}(?:istifleme|depolama|stacking|storage).{0,24}(?:uygulama|practice)?/iu,
];

const ROOT_CAUSE_STATE_TERMS = new Set([
  "eksik",
  "eksikligi",
  "acik",
  "gevsek",
  "dengesiz",
  "daginik",
  "egimli",
  "hasarli",
  "kirik",
  "missing",
  "open",
  "loose",
  "unstable",
  "damaged",
  "broken",
]);

const ROOT_CAUSE_STOP_WORDS = new Set([
  "olmasi",
  "olmasidir",
  "fiziksel",
  "olarak",
  "durum",
  "mevcut",
  "bulunmasi",
  "ve",
  "veya",
  "ile",
  "the",
  "being",
  "condition",
]);

function rootCauseRestatesCondition(fact: HazardFactV3, raw: string): boolean {
  const rootTokens = normalized(raw).split(" ").filter((token) =>
    token.length >= 4 && !ROOT_CAUSE_STOP_WORDS.has(token)
  );
  const conditionTokens = new Set(
    normalized(
      `${fact.observed_condition.short_text} ${
        fact.evidence.affirmative_cues.join(" ")
      }`,
    ).split(" ").filter((token) => token.length >= 4),
  );
  const shared = rootTokens.filter((token) =>
    [...conditionTokens].some((conditionToken) =>
      conditionToken === token ||
      (
        Math.min(conditionToken.length, token.length) >= 5 &&
        conditionToken.slice(0, 5) === token.slice(0, 5)
      )
    )
  );
  const repeatsState = rootTokens.some((token) =>
    ROOT_CAUSE_STATE_TERMS.has(token)
  );
  return repeatsState && shared.length >= 2 &&
    shared.length / Math.max(rootTokens.length, 1) >= 0.45;
}

function qualifiedRootCause(fact: HazardFactV3, language: string): string {
  const context = normalized(
    `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${fact.mechanism_code}`,
  );
  if (!isTurkish(language)) {
    if (/(?:hook|kanca)/u.test(context) && /(?:latch|mandal)/u.test(context)) {
      return "Possible contributing factors: latch seizure, spring or connection failure, deformation, or another condition preventing full closure.";
    }
    if (/(?:rack|raf|stack|istif)/u.test(context)) {
      return "Possible contributing factors: unstable load placement, failure to maintain rack boundaries, or inadequate restraint of stored material.";
    }
    if (
      fact.mechanism_code === "fall_same_level" &&
      /(?:housekeeping|clutter|debris|poor housekeeping)/u.test(context)
    ) {
      return "Possible contributing factors: ineffective material and waste collection or inadequate control of walking and working areas.";
    }
    if (
      hasExplicitSlopeContext(context) ||
      fact.mechanism_code === "equipment_overturn"
    ) {
      return "Possible contributing factors: incompatibility between ground or slope conditions and the equipment position, load, or movement.";
    }
    return "Possible contributing factors: degradation, incorrect positioning, or loss of function in the relevant barrier or component.";
  }
  if (/(?:hook|kanca)/u.test(context) && /(?:latch|mandal)/u.test(context)) {
    return "Olası temel etkenler: mandal mekanizmasında sıkışma, yay veya bağlantı kusuru, deformasyon ya da tam kapanmayı engelleyen başka bir mekanik durum.";
  }
  if (/(?:rack|raf|stack|istif)/u.test(context)) {
    return "Olası temel etkenler: yüklerin kararsız yerleştirilmesi, raf sınırlarının korunmaması veya istifin düşmeye karşı yeterince tutulmaması.";
  }
  if (GUARDRAIL_COMPONENT_PATTERN.test(context)) {
    return "Olası temel etkenler: korkuluk bileşeninin montaj ve bağlantı bütünlüğü ile bakım durumundaki bozulma.";
  }
  if (
    fact.mechanism_code === "fall_same_level" &&
    /(?:housekeeping|daginik|clutter|debris|atik|gecis)/u.test(context)
  ) {
    return "Olası temel etkenler: malzeme ve atık toplama düzeninin aksaması veya geçiş alanı kontrolünün etkin uygulanmaması.";
  }
  if (
    hasExplicitSlopeContext(context) ||
    fact.mechanism_code === "equipment_overturn"
  ) {
    return "Olası temel etkenler: zemin veya şev koşullarının ekipmanın konumu, yükü ve çalışma hareketiyle uyumsuz hale gelmesi.";
  }
  if (
    /(?:loose material|gevsek malzeme|falling object|falling_object)/u.test(
      context,
    )
  ) {
    return "Olası temel etkenler: malzemenin güvenli sınırlar içinde tutulmaması, sabitlenmemesi veya düşme yolunun yeterince kontrol edilmemesi.";
  }
  return "Olası temel etkenler: ilgili bariyer veya bileşende bozulma, yanlış konumlanma ya da işlev kaybı.";
}

function renderRootCause(fact: HazardFactV3, language: string): string {
  if (fact.assessment_basis === "equipment_integrity_verification") {
    const source = withoutTerminalPunctuation(fact.hazard_mechanism);
    return isTurkish(language)
      ? `Temel doğrulama konusu: ${source.toLocaleLowerCase("tr-TR")}.`
      : `Primary verification subject: ${source.toLocaleLowerCase("en-US")}.`;
  }
  const raw = cleanNarrative(
    sanitizeFindingNarrative(
      fact,
      fact.technical_assessment.root_cause_text,
    ),
    900,
  );
  const nonVisualClaim = NON_VISUAL_ROOT_CAUSE_PATTERNS.some((pattern) =>
    pattern.test(raw)
  );
  if (nonVisualClaim || rootCauseRestatesCondition(fact, raw)) {
    return qualifiedRootCause(fact, language);
  }
  const effectiveMode = fact.technical_assessment.root_cause_mode;
  if (effectiveMode === "not_determinable") {
    return qualifiedRootCause(fact, language);
  }
  if (effectiveMode === "observed_condition" && raw) {
    return capitalizeInitial(raw, language);
  }
  if (effectiveMode === "probable_factor" && raw) {
    const alreadyQualified =
      /^(?:muhtemel|olası|olasi|possible|probable|likely)/iu
        .test(raw);
    if (isTurkish(language)) {
      return alreadyQualified ? raw : `Muhtemel temel etken: ${raw}`;
    }
    return alreadyQualified ? raw : `Probable contributing factor: ${raw}`;
  }
  return raw
    ? capitalizeInitial(raw, language)
    : qualifiedRootCause(fact, language);
}

function renderCategory(fact: HazardFactV3, language: string): string {
  const joined = normalized(
    `${fact.observed_condition.condition_code} ${fact.entity.equipment_family} ${fact.entity.component} ${fact.hazard_mechanism}`,
  );
  const tr = isTurkish(language);
  const equipmentGroup = resolveEquipmentGroupCode(fact);
  if (
    fact.assessment_basis === "equipment_integrity_verification" &&
    equipmentGroup === "electrical_equipment"
  ) {
    return tr
      ? "Elektrik bütünlüğü ve periyodik test"
      : "Electrical integrity and periodic testing";
  }
  if (
    fact.assessment_basis === "equipment_integrity_verification" &&
    equipmentGroup === "chemical_storage"
  ) {
    return tr
      ? "Kimyasal güvenlik ve bilgi yönetimi"
      : "Chemical safety and information management";
  }
  if (
    fact.assessment_basis !== "equipment_integrity_verification" &&
    equipmentGroup === "lifting_equipment"
  ) {
    return tr
      ? "Kaldırma ekipmanları ve yük güvenliği"
      : "Lifting equipment and load safety";
  }
  if (
    fact.assessment_basis !== "equipment_integrity_verification" &&
    equipmentGroup === "storage_system" &&
    /(?:rack|raf|stack|istif)/u.test(joined)
  ) {
    return tr ? "Depolama ve istif güvenliği" : "Storage and stacking safety";
  }
  if (fact.assessment_basis === "equipment_integrity_verification") {
    if (
      /(?:\blng\b|\blpg\b|flammable gas|yanici gaz|patlayici ortam|ex ekipman)/u
        .test(joined)
    ) {
      return tr
        ? "Yanıcı gaz, patlayıcı ortam ve Ex ekipman güvenliği"
        : "Flammable gas, explosive atmosphere and Ex-equipment safety";
    }
    if (/crane|vinc|kaldirma/u.test(joined)) {
      return tr
        ? "Kaldırma ekipmanları ve periyodik kontrol"
        : "Lifting equipment and periodic inspection";
    }
    if (
      /(?:mobile|excavator|ekskavator|forklift|truck|kamyon|vehicle)/u.test(
        joined,
      )
    ) {
      return tr
        ? "Mobil iş ekipmanı ve araç güvenliği"
        : "Mobile equipment and vehicle safety";
    }
    if (/(?:pressure|basinc|cylinder|tup|boiler|kazan)/u.test(joined)) {
      return tr
        ? "Basınçlı ekipman ve mekanik bütünlük"
        : "Pressure equipment and mechanical integrity";
    }
    if (
      /(?:lathe|torna|cnc|machine tool|takim tezgahi|crusher|kirici|screen|elek|mill|degirmen|conveyor|konveyor)/u
        .test(joined)
    ) {
      return tr
        ? "Makine güvenliği, bakım ve LOTO"
        : "Machine safety, maintenance and LOTO";
    }
    if (/(?:furnace|firin|oven|kiln|burner|brulor)/u.test(joined)) {
      return tr
        ? "Fırın, yanma ve termal proses güvenliği"
        : "Furnace, combustion and thermal-process safety";
    }
    if (/(?:chemical|kimyasal|sds|ibc)/u.test(joined)) {
      return tr
        ? "Kimyasal güvenlik ve bilgi yönetimi"
        : "Chemical safety and information management";
    }
    if (/(?:rail|rayli|demiryolu|locomotive|lokomotif)/u.test(joined)) {
      return tr ? "Raylı sistem güvenliği" : "Rail-system safety";
    }
    if (/(?:electrical|elektrik|switchgear|pano|mcc)/u.test(joined)) {
      return tr
        ? "Elektrik bütünlüğü ve periyodik test"
        : "Electrical integrity and periodic testing";
    }
    if (/(?:tire|tyre|lastik|rim|jant)/u.test(joined)) {
      return tr
        ? "Lastik ve basınçlı şişirme güvenliği"
        : "Tyre and inflation safety";
    }
    if (/(?:workshop|atolye)/u.test(joined)) {
      return tr ? "Atölye güvenlik sistemi" : "Workshop safety system";
    }
    return tr
      ? "Proses güvenliği ve ekipman bütünlüğü"
      : "Process safety and equipment integrity";
  }
  if (
    fact.mechanism_code === "excavation_collapse_rockfall" ||
    hasExcavationContext(joined)
  ) {
    return tr ? "Kazı, şev ve zemin güvenliği" : "Excavation and slope safety";
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:gevsek|loose|torba|bag|malzeme|material)/u.test(joined)
  ) {
    return tr
      ? "Düşen cisim ve yüksekte malzeme güvenliği"
      : "Falling-object and elevated-material safety";
  }
  if (/housekeeping|dağınık|daginik|takıl|takil|walkway|clutter/.test(joined)) {
    return tr ? "Düzen ve geçiş güvenliği" : "Housekeeping and access";
  }
  if (
    fact.mechanism_code === "falling_object" &&
    /(?:floor|zemin|storage|depolan|dished head|tank head|tank bombesi|metal parca|rolling|yuvarlan)/u
      .test(joined)
  ) {
    return tr
      ? "Ağır parça depolama ve sabitleme güvenliği"
      : "Heavy-component storage and restraint safety";
  }
  if (
    fact.mechanism_code === "electrical_contact_arc" ||
    /elektr|iletken|kablo|voltage/.test(joined)
  ) {
    return tr ? "Elektrik güvenliği" : "Electrical safety";
  }
  if (/engebe|zemin|ground|stabil|devril|overturn/.test(joined)) {
    return tr
      ? "Mobil ekipman ve zemin stabilitesi"
      : "Mobile equipment and ground stability";
  }
  if (/hortum|hose|boru|pipe|fitting|flans|flange/.test(joined)) {
    return tr
      ? "Boru, hortum ve proses bütünlüğü"
      : "Pipe, hose and process integrity";
  }
  if (/pim|segman|kilit|pin|retainer|bolt|civata/.test(joined)) {
    return tr ? "Mekanik bağlantı bütünlüğü" : "Mechanical joint integrity";
  }
  if (/kaynak|weld|ndt/.test(joined)) {
    return tr ? "Kaynak ve yapısal bütünlük" : "Weld and structural integrity";
  }
  if (/koruyucu|guard|interlock|korkuluk|bariyer|fall|düş|dus/.test(joined)) {
    return tr ? "Düşme ve koruyucu sistemler" : "Fall and guarding systems";
  }
  if (/sizinti|sızıntı|leak|release|kimyasal|chemical/.test(joined)) {
    return tr ? "Proses ve kimyasal güvenliği" : "Process and chemical safety";
  }
  if (/ppe|kkd|gözlük|gozluk|eldiven|baret|helmet|glove/.test(joined)) {
    return tr ? "Kişisel koruyucu donanım" : "Personal protective equipment";
  }
  return capitalized(fact.hazard_mechanism, language).slice(0, 160);
}

function taxonomyContext(fact: HazardFactV3): string {
  return normalized([
    fact.entity.equipment_family,
    fact.entity.component,
    fact.observed_condition.condition_code,
    fact.observed_condition.short_text,
    fact.hazard_mechanism,
    fact.energy_source,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
}

function resolveEquipmentGroupCode(fact: HazardFactV3): EquipmentGroupCode {
  // Equipment grouping is intentionally based on stable structured identity
  // fields, not free-form consequence/control prose that can drift by model or
  // language and accidentally move the same asset between groups.
  const context = normalized([
    fact.entity.equipment_family,
    fact.entity.component,
    fact.observed_condition.condition_code,
  ].join(" "));
  if (
    /(?:ppe|kkd|helmet|baret|glove|eldiven|gozluk|respirator)/u.test(context)
  ) {
    return "ppe";
  }
  if (
    /(?:crane|vinc|hoist|kaldirma|lifting|hook|kanca|sapan|sling|shackle|mapa)/u
      .test(context)
  ) {
    return "lifting_equipment";
  }
  if (
    /(?:excavator|ekskavator|forklift|loader|yukleyici|truck|kamyon|vehicle|mobile equipment|is makinesi|dozer)/u
      .test(context)
  ) {
    return "mobile_equipment";
  }
  if (
    /(?:walkway|yurume yolu|gecis|floor|zemin|ground|terrain|saha|platform|ladder|merdiven|scaffold|iskele|guardrail|korkuluk|railing|midrail|ara korkuluk|orta korkuluk|toe board|toeboard|kick plate|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik|work area|calisma alani)/u
      .test(context)
  ) {
    return "access_work_area";
  }
  if (
    /(?:rail system|rayli sistem|demiryolu|locomotive|lokomotif)/u.test(context)
  ) {
    return "rail_system";
  }
  if (
    /(?:electrical|elektrik|switchgear|pano|mcc|cable|kablo)/u.test(context)
  ) {
    return "electrical_equipment";
  }
  if (
    /(?:pressure|basinc|hydraulic|hidrolik|pneumatic|pnomatik|boiler|kazan|compressor|kompresor|lpg|cylinder|tup)/u
      .test(context)
  ) {
    return "pressure_equipment";
  }
  if (
    /(?:furnace|firin|oven|kiln|burner|brulor|thermal|termal)/u.test(context)
  ) {
    return "thermal_equipment";
  }
  if (
    /(?:chemical storage|chemical material|chemical inventory|kimyasal depolama|kimyasal madde|kimyasal envanter|chemical container|ibc|drum|varil|acid tank|asit tank)/u
      .test(context)
  ) {
    return "chemical_storage";
  }
  if (
    /(?:rack|raf|pallet|palet|stack|istif|storage system|depolama sistemi)/u
      .test(context)
  ) {
    return "storage_system";
  }
  if (
    /(?:lathe|torna|cnc|machine tool|takim tezgahi|crusher|kirici|screen|elek|mill|degirmen|conveyor|konveyor|drive|tahrik|motor|gear|disli)/u
      .test(context)
  ) {
    return "machine_equipment";
  }
  if (
    /(?:process|proses|vessel|tank|boru|pipe|hose|hortum|flange|flans|valve|vana|lng|flammable gas|yanici gaz)/u
      .test(context)
  ) {
    return "process_equipment";
  }
  if (
    /(?:structure|yapi|structural|kolon|column|beam|kiris|weld|kaynak|support|tasiyici)/u
      .test(context)
  ) {
    return "structural_system";
  }
  return "other_equipment";
}

function resolveFindingTaxonomy(fact: HazardFactV3): FindingTaxonomy {
  let equipmentGroupCode = resolveEquipmentGroupCode(fact);
  const context = taxonomyContext(fact);
  const assessmentSection: AssessmentSection = fact.assessment_basis ===
      "equipment_integrity_verification"
    ? "equipment_assurance"
    : "observed_risk";
  let categoryCode: FindingCategoryCode;

  if (
    assessmentSection === "observed_risk" &&
    (
      fact.mechanism_code === "excavation_collapse_rockfall" ||
      hasExcavationContext(context)
    )
  ) {
    equipmentGroupCode = "access_work_area";
  }

  if (assessmentSection === "equipment_assurance") {
    if (
      /(?:flammable gas|yanici gaz|patlayici ortam|ex equipment|ex ekipman)/u
        .test(context)
    ) {
      categoryCode = "fire_explosion_safety";
    } else {
      const assuranceCategoryByGroup: Record<
        EquipmentGroupCode,
        FindingCategoryCode
      > = {
        process_equipment: "environmental_process_safety",
        lifting_equipment: "lifting_safety",
        mobile_equipment: "mobile_equipment_safety",
        access_work_area: "access_housekeeping",
        storage_system: "storage_safety",
        machine_equipment: "machine_mechanical_safety",
        pressure_equipment: "pressure_hydraulic_safety",
        electrical_equipment: "electrical_safety",
        structural_system: "structural_integrity",
        chemical_storage: "chemical_safety",
        rail_system: "mobile_equipment_safety",
        thermal_equipment: "thermal_safety",
        ppe: "ppe_safety",
        other_equipment: "general_physical_safety",
      };
      categoryCode = assuranceCategoryByGroup[equipmentGroupCode];
    }
  } else {
    switch (fact.mechanism_code) {
      case "fall_same_level":
        categoryCode = "access_housekeeping";
        break;
      case "fall_from_height":
        categoryCode = "work_at_height";
        break;
      case "falling_object":
        categoryCode = hasExcavationContext(context)
          ? "excavation_slope_safety"
          : equipmentGroupCode === "lifting_equipment"
          ? "lifting_safety"
          : equipmentGroupCode === "storage_system"
          ? "storage_safety"
          : equipmentGroupCode === "access_work_area" &&
              /(?:toe board|toeboard|kick plate|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik|guardrail|korkuluk|platform|yukseklik)/u
                .test(context)
          ? "work_at_height"
          : "general_physical_safety";
        break;
      case "vehicle_equipment_strike":
      case "equipment_overturn":
        categoryCode = "mobile_equipment_safety";
        break;
      case "caught_in_pinch_shear":
        categoryCode = "machine_mechanical_safety";
        break;
      case "mechanical_separation_release":
        categoryCode = equipmentGroupCode === "lifting_equipment"
          ? "lifting_safety"
          : equipmentGroupCode === "structural_system"
          ? "structural_integrity"
          : "machine_mechanical_safety";
        break;
      case "hydraulic_pneumatic_release":
        categoryCode = "pressure_hydraulic_safety";
        break;
      case "electrical_contact_arc":
        categoryCode = "electrical_safety";
        break;
      case "fire_explosion":
        categoryCode = "fire_explosion_safety";
        break;
      case "structural_collapse":
        categoryCode = "structural_integrity";
        break;
      case "excavation_collapse_rockfall":
        categoryCode = "excavation_slope_safety";
        break;
      case "chemical_contact_release":
        categoryCode = "chemical_safety";
        break;
      case "thermal_contact":
        categoryCode = "thermal_safety";
        break;
      case "ergonomic_overexertion":
        categoryCode = "ergonomic_safety";
        break;
      case "environmental_release":
        categoryCode = "environmental_process_safety";
        break;
      case "sharp_edge_contact":
        categoryCode = "general_physical_safety";
        break;
      case "other_visible_physical":
        categoryCode = equipmentGroupCode === "ppe"
          ? "ppe_safety"
          : equipmentGroupCode === "access_work_area"
          ? "access_housekeeping"
          : "general_physical_safety";
        break;
    }
  }
  return { categoryCode, equipmentGroupCode, assessmentSection };
}

const TR_REGULATIONS = {
  general: "6331 sayılı İş Sağlığı ve Güvenliği Kanunu",
  workEquipment:
    "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
  workplace:
    "İşyeri Bina ve Eklentilerinde Alınacak Sağlık ve Güvenlik Önlemlerine İlişkin Yönetmelik",
  construction: "Yapı İşlerinde İş Sağlığı ve Güvenliği Yönetmeliği",
  ppe:
    "Kişisel Koruyucu Donanımların İşyerlerinde Kullanılması Hakkında Yönetmelik",
  chemical:
    "Kimyasal Maddelerle Çalışmalarda Sağlık ve Güvenlik Önlemleri Hakkında Yönetmelik",
  emergency: "İşyerlerinde Acil Durumlar Hakkında Yönetmelik",
  explosive:
    "Çalışanların Patlayıcı Ortamların Tehlikelerinden Korunması Hakkında Yönetmelik",
  manualHandling: "Elle Taşıma İşleri Yönetmeliği",
} as const;

function renderReferences(
  fact: HazardFactV3,
  language: string,
  plan: string,
  context: EngineReferenceContext,
): string {
  const referencesEnabled = isTurkish(language) &&
    plan.toLocaleLowerCase("tr-TR") !== "free" &&
    context.safetyProfileID === "tr-tr-current-v1" &&
    context.regulatoryReferencePolicy === "tr_current" &&
    context.structuredRegulatoryReferencesEnabled === true;
  if (!referencesEnabled) return "";

  // Regulation selection is deliberately based on the structured semantic
  // contract. Free-text substring matching caused `wrapped` and `upper` to
  // match the token `ppe`, assigning the PPE regulation to process piping and
  // storage-rack findings. An unclassified fact receives the general act only;
  // an unrelated specific regulation is worse than a precise general one.
  const structured = normalized(
    `${fact.observed_condition.condition_code} ${fact.entity.equipment_family} ${fact.entity.component}`,
  );
  const tokens = new Set(structured.split(" ").filter(Boolean));
  const hasAnyToken = (...values: string[]) =>
    values.some((value) => tokens.has(value));
  let specific: string | null = null;

  if (
    hasAnyToken(
      "excavation",
      "kazi",
      "sev",
      "slope",
      "iksa",
      "rockfall",
      "kayalik",
      "kaya",
    )
  ) {
    specific = TR_REGULATIONS.construction;
  } else if (
    hasAnyToken(
      "ppe",
      "kkd",
      "helmet",
      "baret",
      "glove",
      "eldiven",
      "goggle",
      "gozluk",
    )
  ) {
    specific = TR_REGULATIONS.ppe;
  } else {
    switch (fact.mechanism_code) {
      case "fall_same_level":
        specific = TR_REGULATIONS.workplace;
        break;
      case "fall_from_height":
        specific = hasAnyToken("scaffold", "iskele", "excavation", "kazi")
          ? TR_REGULATIONS.construction
          : TR_REGULATIONS.workplace;
        break;
      case "falling_object":
        specific = hasAnyToken("rack", "raf", "shelf", "shelves", "storage")
          ? TR_REGULATIONS.workplace
          : TR_REGULATIONS.workEquipment;
        break;
      case "vehicle_equipment_strike":
      case "caught_in_pinch_shear":
      case "mechanical_separation_release":
      case "hydraulic_pneumatic_release":
      case "equipment_overturn":
        specific = TR_REGULATIONS.workEquipment;
        break;
      case "excavation_collapse_rockfall":
        specific = TR_REGULATIONS.construction;
        break;
      case "chemical_contact_release":
        specific = TR_REGULATIONS.chemical;
        break;
      case "fire_explosion":
        specific = TR_REGULATIONS.explosive;
        break;
      case "ergonomic_overexertion":
        specific = TR_REGULATIONS.manualHandling;
        break;
      case "electrical_contact_arc":
        specific = hasAnyToken("machine", "makine", "equipment", "ekipman")
          ? TR_REGULATIONS.workEquipment
          : TR_REGULATIONS.workplace;
        break;
      case "structural_collapse":
        specific = hasAnyToken("scaffold", "iskele", "excavation", "iksa")
          ? TR_REGULATIONS.construction
          : TR_REGULATIONS.workEquipment;
        break;
      case "environmental_release":
        specific = hasAnyToken("chemical", "kimyasal", "container", "kap")
          ? TR_REGULATIONS.chemical
          : TR_REGULATIONS.workEquipment;
        break;
      default:
        specific = null;
    }
  }
  const technicalReferences: string[] = [];
  switch (normalized(fact.observed_condition.condition_code)) {
    case "process tank integrity assurance":
      technicalReferences.push(
        "API 650 / API 653 (yalnız ekipmanın tasarım ve servis kapsamı uygunsa)",
      );
      break;
    case "lng storage integrity assurance":
      technicalReferences.push(
        "API 625 (yalnız LNG tank tasarımı ve kapasite kapsamı uygunsa)",
      );
      break;
    case "lpg storage integrity assurance":
      technicalReferences.push(
        "API 2510 (yalnız LPG tesis tasarımı ve yerleşim kapsamı uygunsa)",
      );
      break;
  }
  return [
    ...new Set([
      ...(specific ? [specific] : []),
      TR_REGULATIONS.general,
      ...technicalReferences,
    ]),
  ].join("; ");
}

type FrequencyResolution = {
  value: number;
  finalBasis: FrequencyBasis | "sector_prior";
  reasonCode: string | null;
  sectorPriorUsed: boolean;
  sectorDefaultF: number | null;
  modifierCode: string | null;
};

function scorePolicyContext(fact: HazardFactV3): string {
  return normalized([
    fact.mechanism_code,
    fact.observed_condition.condition_code,
    fact.observed_condition.short_text,
    fact.entity.equipment_family,
    fact.entity.component,
    fact.hazard_mechanism,
    fact.energy_source,
    fact.credible_event_path,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
}

type NumericPolicyResolution = {
  value: number;
  reasonCode: string | null;
};

function fieldVerificationReasonCodes(
  fact: HazardFactV3,
  frequency?: FrequencyResolution,
): string[] {
  const reasons: string[] = [];
  if (fact.assessment_basis === "equipment_integrity_verification") {
    reasons.push("equipment_integrity_verification");
  }
  if (fact.verification.model_required) {
    reasons.push("model_requested_verification");
  }
  const context = scorePolicyContext(fact);
  if (
    fact.assessment_basis === "visible_inherent_hazard" &&
    (
      fact.mechanism_code === "equipment_overturn" ||
      fact.mechanism_code === "excavation_collapse_rockfall" ||
      (
        fact.mechanism_code === "falling_object" &&
        hasExcavationContext(context)
      )
    )
  ) {
    reasons.push("site_stability_requires_field_confirmation");
  }
  const confidenceDimensions = [
    ["entity", fact.confidence.entity],
    ["condition", fact.confidence.condition],
    ["localization", fact.confidence.localization],
    ["mechanism", fact.confidence.mechanism],
  ] as const;
  for (const [dimension, confidence] of confidenceDimensions) {
    if (confidence !== "high") {
      reasons.push(`${dimension}_confidence_below_high`);
    }
  }
  if (fact.frequency_basis === "missing_invalid_fallback") {
    reasons.push("frequency_basis_missing");
  }
  if (frequency?.sectorPriorUsed) {
    reasons.push("sector_frequency_prior_unverified");
  }
  return [...new Set(reasons)];
}

function resolveProbability(fact: HazardFactV3): NumericPolicyResolution {
  const raw = P_BY_BARRIER[fact.barrier_state];
  if (fact.assessment_basis === "equipment_integrity_verification") {
    return {
      value: 1,
      reasonCode: raw === 1 ? null : "asset_assurance_probability_capped",
    };
  }
  const context = scorePolicyContext(fact);
  if (
    fact.assessment_basis === "observed_nonconformity" &&
    fact.mechanism_code === "falling_object" &&
    /(?:rack|raf|shelf|storage racking)/u.test(context) &&
    /(?:stack|istif|overhang|tasan|taşan|dengesiz|unstable)/u.test(context)
  ) {
    const directActiveRelease =
      /(?:dusmekte|düşmekte|falling now|actively falling|kopmakta|detaching|calisan.{0,40}(?:altinda|beneath)|worker.{0,40}beneath)/u
        .test(context);
    if (!directActiveRelease && raw > 3) {
      return {
        value: 3,
        reasonCode: "storage_stacking_probability_normalized",
      };
    }
  }
  if (fact.assessment_basis === "visible_inherent_hazard") {
    const cues = normalized(fact.evidence.affirmative_cues.join(" "));
    const directActiveEvidence =
      /(?:calisan|personel|worker|person|operator).{0,48}(?:dogrudan|direct|altinda|beneath|dusme hatti|fall line|temas|contact|erisiyor|reaching)|(?:askidaki yuk|suspended load|aktif sizinti|active leak|akmakta|flowing|dusmekte olan|falling debris|kopmakta|detaching|aktif catlak ilerlemesi|active crack propagation)/u
        .test(cues);
    const cap = directActiveEvidence ? 3 : 1;
    if (raw > cap) {
      return {
        value: cap,
        reasonCode: "inherent_hazard_probability_capped_by_evidence",
      };
    }
  }
  return { value: raw, reasonCode: null };
}

function resolveSeverity(fact: HazardFactV3): NumericPolicyResolution {
  const raw = S_BY_CONSEQUENCE[fact.consequence_class];
  const context = scorePolicyContext(fact);
  const incompleteGuardrailComponent =
    fact.assessment_basis === "observed_nonconformity" &&
    fact.mechanism_code === "fall_from_height" &&
    (MIDRAIL_COMPONENT_PATTERN.test(context) ||
      TOE_BOARD_COMPONENT_PATTERN.test(context)) &&
    /(?:missing|absent|eksik|open gap|acik bosluk)/u.test(context);
  if (incompleteGuardrailComponent && raw > 15) {
    return {
      value: 15,
      reasonCode: "incomplete_guardrail_severity_normalized",
    };
  }
  const maximumByMechanism: Record<HazardMechanismCode, number> = {
    fall_same_level: 7,
    fall_from_height: 40,
    falling_object: 40,
    vehicle_equipment_strike: 40,
    caught_in_pinch_shear: 15,
    mechanical_separation_release: 40,
    hydraulic_pneumatic_release: 15,
    electrical_contact_arc: 15,
    fire_explosion: 100,
    structural_collapse: 100,
    equipment_overturn: 40,
    excavation_collapse_rockfall: 40,
    chemical_contact_release: 15,
    thermal_contact: 15,
    sharp_edge_contact: 7,
    ergonomic_overexertion: 7,
    environmental_release: 15,
    other_visible_physical: 15,
  };
  const cap = maximumByMechanism[fact.mechanism_code];
  return raw > cap
    ? { value: cap, reasonCode: "severity_capped_by_mechanism_policy" }
    : { value: raw, reasonCode: null };
}

function hasActiveSceneEvidence(fact: HazardFactV3): boolean {
  const context = scorePolicyContext(fact);
  return /(?:ekskavator|excavator|palet).*(?:calis|konumlan|operat|operating|positioned)/u
    .test(context) ||
    /(?:ekskavator|excavator|kova|bucket).{0,120}(?:aktif|kazi|kazma|kaziyor|digging|excavat|calis|operat)/u
      .test(context) ||
    /(?:aktif olarak |actively )?(?:kazi|kazma|digging|excavation) (?:islemi|faaliyeti|activity|work)/u
      .test(context) ||
    /(?:aktif sizinti|active leak|asil[iı] yuk|suspended load|calisan gorul|worker visible)/u
      .test(context);
}

function resolveFrequency(
  fact: HazardFactV3,
  profile: SectorProfileV2 | null = null,
  modifier: ReturnType<typeof validSectorModifierEvidence>[number] | null =
    null,
  sectorFrequencyPriorEnabled = false,
): FrequencyResolution {
  if (fact.assessment_basis === "equipment_integrity_verification") {
    return {
      value: 2,
      finalBasis: "sector_scene_proxy",
      reasonCode: fact.frequency_basis === "sector_scene_proxy"
        ? null
        : "asset_assurance_frequency_normalized",
      sectorPriorUsed: false,
      sectorDefaultF: profile?.frequencyPrior.defaultF ?? null,
      modifierCode: null,
    };
  }
  if (fact.frequency_basis === "catalogued_rare") {
    return {
      value: 0.5,
      finalBasis: "catalogued_rare",
      reasonCode: null,
      sectorPriorUsed: false,
      sectorDefaultF: profile?.frequencyPrior.defaultF ?? null,
      modifierCode: null,
    };
  }
  const activeScene = hasActiveSceneEvidence(fact);
  if (sectorFrequencyPriorEnabled && profile) {
    const value = modifier?.f ?? (
      profile.sectorId === "general"
        ? activeScene ? 3 : 1
        : profile.frequencyPrior.defaultF
    );
    if (value !== null) {
      return {
        value,
        finalBasis: "sector_prior",
        reasonCode: modifier
          ? "sector_visible_modifier_applied"
          : "sector_frequency_prior_applied",
        sectorPriorUsed: true,
        sectorDefaultF: profile.frequencyPrior.defaultF,
        modifierCode: modifier?.code ?? null,
      };
    }
  }
  if (fact.frequency_basis === "missing_invalid_fallback") {
    return {
      value: 1,
      finalBasis: "missing_invalid_fallback",
      reasonCode: "fk_frequency_missing_fallback",
      sectorPriorUsed: false,
      sectorDefaultF: profile?.frequencyPrior.defaultF ?? null,
      modifierCode: null,
    };
  }
  const finalBasis: FrequencyBasis = activeScene
    ? "active_single_exposure"
    : "sector_scene_proxy";
  const value = F_BY_BASIS[finalBasis];
  const raw = F_BY_BASIS[fact.frequency_basis];
  return {
    value,
    finalBasis,
    reasonCode: value === raw
      ? null
      : "fk_frequency_normalized_by_scene_policy",
    sectorPriorUsed: false,
    sectorDefaultF: profile?.frequencyPrior.defaultF ?? null,
    modifierCode: null,
  };
}

function confidenceValue(fact: HazardFactV3): number {
  const values = Object.values(fact.confidence).map((level) =>
    CONFIDENCE_VALUE[level]
  );
  return Number(
    (values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(2),
  );
}

function stage(
  name: string,
  total: number,
  byPhoto: Record<string, number>,
  previous?: number,
) {
  return {
    name,
    total,
    by_photo: byPhoto,
    delta_from_previous: previous === undefined ? 0 : total - previous,
  };
}

function countsByPhoto(
  facts: Array<{ sourcePhotoIndices: number[] }>,
  photoCount: number,
) {
  const counts: Record<string, number> = {};
  for (let index = 1; index <= photoCount; index += 1) {
    counts[String(index)] = 0;
  }
  for (const fact of facts) {
    for (const index of fact.sourcePhotoIndices) {
      counts[String(index)] = (counts[String(index)] ?? 0) + 1;
    }
  }
  return counts;
}

const CRITICAL_COMPONENT_CHECKS = [
  {
    check_code: "pin_retainer_joint_integrity",
    mechanismCodes: [
      "mechanical_separation_release",
      "falling_object",
    ] as HazardMechanismCode[],
    inventoryPattern:
      /(?:^| )(?:pim(?:ler[iı]?)?|pins?|segman(?:lar[iı]?)?|retainers?|mafsal(?:lar[iı]?)?|joints?|kanca(?:lar[iı]?)?|hooks?|mandal(?:lar[iı]?)?|latches?)(?: |$)/u,
    outcomePattern:
      /(?:eksik|missing|gevse|loose|displace|yerinden|bos (?:yuva|delik|kanal)|empty (?:slot|hole|groove)|acik (?:agiz|mandal)|open (?:hook|latch)|(?:hook|latch|kanca|mandal).{0,24}(?:open|acik)|deform|asin|wear|kirik|broken|kilitlenm|retainer failure)/u,
  },
  {
    check_code: "hose_line_route_integrity",
    mechanismCodes: [
      "hydraulic_pneumatic_release",
      "thermal_contact",
      "mechanical_separation_release",
      "other_visible_physical",
    ] as HazardMechanismCode[],
    inventoryPattern:
      /(?:^| )(?:hortum(?:lar[iı]?)?|hoses?|hidrolik|hydraulic|boru(?:lar[iı]?)?|pipes?|hat(?:lar[iı]?)?|lines?)(?: |$)/u,
    outcomePattern:
      /(?:asin|abras|surtun|rub|sizinti|kacak|leak|catlak|crack|yirt|tear|bukul|kink|ezil|crush|temas|contact|guzergah|routing|destek|support|kelepce|clamp|sicak yuzey|hot surface|keskin yuzey|sharp surface)/u,
  },
  {
    check_code: "structural_joint_integrity",
    mechanismCodes: [
      "structural_collapse",
      "mechanical_separation_release",
      "falling_object",
      "other_visible_physical",
    ] as HazardMechanismCode[],
    inventoryPattern:
      /(?:^| )(?:civata(?:lar[iı]?)?|bolts?|kaynak(?:lar[iı]?)?|welds?|flans(?:lar[iı]?)?|flanges?)(?: |$)/u,
    outcomePattern:
      /(?:eksik|missing|gevse|loose|catlak|crack|gözenek|gozenek|porosity|alt kesme|undercut|korozy|corrosion|deform|ayril|separation|sizinti|leak)/u,
  },
  {
    check_code: "guard_barrier_integrity",
    mechanismCodes: [
      "fall_from_height",
      "falling_object",
      "caught_in_pinch_shear",
      "other_visible_physical",
    ] as HazardMechanismCode[],
    inventoryPattern:
      /(?:^| )(?:korkuluk(?:lar[iı]?)?|guardrails?|railings?|ara korkuluk|orta korkuluk|midrails?|toe boards?|toeboards?|kick plates?|etek tahtasi|etek saci|etek elemani|topuk levhasi|supurgelik|koruyucu(?:lar[iı]?)?|guards?|interlocks?|bariyer(?:ler[iı]?)?|barriers?)(?: |$)/u,
    outcomePattern:
      /(?:eksik|missing|acik kenar|open edge|bosluk|gap|kirik|broken|hasar|damage|gevse|loose|islevsiz|inoperative|erisilebilir|accessible|korunmasiz|unguarded)/u,
  },
] as const;

type RejectedFactCoverage = {
  fact: HazardFactV3;
  traceID: string;
  reasonCode: string;
};

function componentCoverage(
  photoResult: PhotoResult,
  acceptedFacts: HazardFactV3[],
  rejectedFacts: RejectedFactCoverage[] = [],
) {
  return photoResult.output.scene_inventory.flatMap((item) => {
    const inventoryContext = normalized(
      `${item.equipment_family} ${item.component}`,
    );
    const checks = CRITICAL_COMPONENT_CHECKS.filter((check) =>
      check.inventoryPattern.test(inventoryContext)
    );
    return checks.map((check) => {
      const matchingFacts = acceptedFacts.filter((fact) => {
        const outcomeContext = normalized(
          `${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${fact.hazard_mechanism} ${
            fact.evidence.affirmative_cues.join(" ")
          }`,
        );
        return fact.entity.entity_ref === item.entity_ref &&
          check.mechanismCodes.includes(fact.mechanism_code) &&
          check.outcomePattern.test(outcomeContext);
      });
      const matchingRejectedFacts = rejectedFacts.filter((entry) => {
        const fact = entry.fact;
        const outcomeContext = normalized(
          `${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${fact.hazard_mechanism} ${
            fact.evidence.affirmative_cues.join(" ")
          }`,
        );
        return fact.entity.entity_ref === item.entity_ref &&
          check.mechanismCodes.includes(fact.mechanism_code) &&
          check.outcomePattern.test(outcomeContext);
      });
      // Inventory prose can describe what the model looked at, but it cannot
      // certify a component as safe. Preserve rejected, entity-linked facts in
      // the audit so an evidence-gate rejection is not misreported as if the
      // component had never produced a candidate.
      const status = matchingFacts.length > 0
        ? "accepted_fact"
        : matchingRejectedFacts.length > 0
        ? "rejected_fact"
        : "unresolved_no_candidate";
      return {
        photo_index: photoResult.photoIndex,
        entity_ref: item.entity_ref,
        equipment_family: item.equipment_family,
        component: item.component,
        check_code: check.check_code,
        status,
        fact_ids: matchingFacts.map((fact) => fact.fact_id),
        rejected_fact_trace_ids: matchingRejectedFacts.map((entry) =>
          entry.traceID
        ),
        rejection_reason_codes: [
          ...new Set(matchingRejectedFacts.map((entry) => entry.reasonCode)),
        ],
        reason_code: status === "accepted_fact"
          ? "critical_component_represented_by_entity_linked_fact"
          : status === "rejected_fact"
          ? "critical_component_candidate_rejected_by_evidence_policy"
          : "critical_component_visible_without_candidate_outcome",
      };
    });
  });
}

type SectorModulePolicyResult = {
  moduleAudits: Array<Record<string, unknown>>;
  outcomeTrace: Array<Record<string, unknown>>;
  omissions: Array<Record<string, unknown>>;
};

const MODULE_EVIDENCE_PATTERNS: Partial<Record<ModuleID, RegExp>> = {
  ppe: /(?:ppe|kkd|helmet|baret|glove|eldiven|goggle|gozluk|respirator|maske)/u,
  lifting_operations:
    /(?:lift|lifting|crane|hoist|hook|rope|vinc|kaldirma|kanca|halat)/u,
  machine_safety_loto:
    /(?:machine|guard|drive|motor|press|conveyor|makine|muhafaza|tahrik|pres|konveyor|loto|izolasyon)/u,
  storage_racking: /(?:rack|shelf|stack|storage|raf|istif|depo)/u,
  pressure_process_safety:
    /(?:pressure|vessel|tank|relief|process|basinc|kap|tahliye|proses)/u,
  mobile_equipment_traffic:
    /(?:vehicle|mobile|forklift|excavator|traffic|arac|mobil|ekskavator|trafik)/u,
  access_and_work_at_height:
    /(?:height|platform|guardrail|ladder|fall|yuksek|platform|korkuluk|merdiven|dusme)/u,
  egress_housekeeping:
    /(?:egress|walkway|access|clutter|obstruction|floor|gecis|zemin|daginik|engel)/u,
  electrical_safety:
    /(?:electric|panel|cable|conductor|elektrik|pano|kablo|iletken)/u,
  emergency_equipment:
    /(?:emergency|extinguisher|alarm|eyewash|acil|sondurucu|alarm|goz dusu)/u,
};

function moduleEvidenceMatches(
  moduleID: ModuleID,
  context: string,
): boolean {
  const pattern = MODULE_EVIDENCE_PATTERNS[moduleID];
  return pattern ? pattern.test(normalized(context)) : true;
}

function sectorModulePolicy(
  photoResults: PhotoResult[],
  profile: SectorProfileV2 | null,
  acceptedFacts: HazardFactV3[],
): SectorModulePolicyResult {
  const moduleAudits: Array<Record<string, unknown>> = [];
  const outcomeTrace: Array<Record<string, unknown>> = [];
  const omissions: Array<Record<string, unknown>> = [];
  for (const result of photoResults) {
    const auditByModule = new Map(
      result.output.module_audit.map((audit) => [audit.module_id, audit]),
    );
    if (profile) {
      const inventoryRefs = new Set(
        result.output.scene_inventory.map((item) => item.entity_ref),
      );
      const outcomeByModule = new Map(
        result.output.mandatory_module_outcomes.map((outcome) => [
          outcome.module_id,
          outcome,
        ]),
      );
      for (const moduleID of profile.mandatoryModules) {
        const outcome = outcomeByModule.get(moduleID);
        if (!outcome) {
          omissions.push({
            photo_index: result.photoIndex,
            module_id: moduleID,
            reason_code: "sector_mandatory_module_omitted",
          });
          outcomeTrace.push({
            photo_index: result.photoIndex,
            module_id: moduleID,
            declared_status: null,
            effective_status: null,
            reason_code: "sector_mandatory_module_omitted",
          });
          continue;
        }
        const linkedToFact = acceptedFacts.some((fact) =>
          fact.photo_index === result.photoIndex &&
          outcome.entity_refs.includes(fact.entity.entity_ref) &&
          moduleEvidenceMatches(
            moduleID,
            `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.short_text} ${fact.hazard_mechanism}`,
          )
        );
        const linkedToConcreteSignal = outcome.entity_refs.some((ref) => {
          if (!inventoryRefs.has(ref)) return false;
          const item = result.output.scene_inventory.find((candidate) =>
            candidate.entity_ref === ref
          );
          if (!item) return false;
          return result.output.inspection_signals.some((signal) =>
            moduleEvidenceMatches(
              moduleID,
              `${item.equipment_family} ${item.component} ${
                signal.affirmative_cues.join(" ")
              }`,
            ) && targetedSignalHasConcreteCue(signal)
          );
        });
        const actionableValid = outcome.status !== "actionable" ||
          (outcome.entity_refs.length > 0 &&
            (linkedToFact || linkedToConcreteSignal));
        const effectiveStatus = actionableValid ? outcome.status : "uncertain";
        const mappedStatus = effectiveStatus === "actionable"
          ? "positive_evidence"
          : effectiveStatus === "not_visible"
          ? "not_applicable"
          : "scanned_no_positive_evidence";
        auditByModule.set(moduleID, {
          module_id: moduleID,
          entity_refs: outcome.entity_refs,
          status: mappedStatus,
        });
        outcomeTrace.push({
          photo_index: result.photoIndex,
          module_id: moduleID,
          declared_status: outcome.status,
          effective_status: effectiveStatus,
          legacy_module_audit_status: mappedStatus,
          entity_refs: outcome.entity_refs,
          reason_code: !actionableValid
            ? "sector_actionable_without_accepted_evidence"
            : outcome.status === "checked_no_hazard" &&
                outcome.entity_refs.length === 0
            ? "sector_checked_without_entity_link"
            : null,
        });
      }
    }
    for (
      const audit of MODULE_IDS.map((moduleID) =>
        auditByModule.get(moduleID) ?? {
          module_id: moduleID,
          entity_refs: [],
          status: "not_applicable",
        }
      )
    ) {
      moduleAudits.push({ photo_index: result.photoIndex, ...audit });
    }
  }
  return { moduleAudits, outcomeTrace, omissions };
}

function sectorCriticalEquipmentCoverage(
  photoResults: PhotoResult[],
  acceptedFacts: HazardFactV3[],
  rejectedFacts: RejectedFactCoverage[],
  profile: SectorProfileV2 | null,
): Array<Record<string, unknown>> {
  if (!profile) return [];
  const coverage: Array<Record<string, unknown>> = [];
  for (const result of photoResults) {
    for (const entry of profile.criticalEquipment) {
      const familyItems = result.output.scene_inventory.filter((item) =>
        sectorEquipmentForEntity(
          profile,
          item.equipment_family,
          item.component,
        ).some((candidate) => candidate.familyCode === entry.familyCode)
      );
      if (familyItems.length === 0) continue;
      for (const checkCode of entry.checkCodes) {
        const checkAliases = entry.checkComponentAliases[checkCode] ?? [];
        const factMatchesEntryAndCheck = (fact: HazardFactV3) =>
          fact.photo_index === result.photoIndex &&
          fact.assessment_basis !== "equipment_integrity_verification" &&
          sectorEquipmentForEntity(
            profile,
            fact.entity.equipment_family,
            fact.entity.component,
          ).some((candidate) => candidate.familyCode === entry.familyCode) &&
          checkAliases.some((alias) =>
            normalized(
              `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text} ${
                fact.evidence.affirmative_cues.join(" ")
              }`,
            ).includes(normalized(alias))
          );
        const componentItems = familyItems.filter((item) =>
          sectorCheckCodesForEntity(
            entry,
            item.equipment_family,
            item.component,
          ).includes(checkCode)
        );
        if (componentItems.length === 0) {
          const root = familyItems[0];
          // Providers often inventory a scaffold/platform as the parent asset
          // and attach the visible guardrail/open-edge fact to a child
          // entity_ref. The semantic family + check alias is authoritative for
          // this parent-child coverage link; exact entity_ref equality is not.
          const relatedFacts = acceptedFacts.filter(factMatchesEntryAndCheck);
          const relatedRejected = rejectedFacts.filter((candidate) =>
            factMatchesEntryAndCheck(candidate.fact)
          );
          coverage.push({
            photo_index: result.photoIndex,
            sector_id: profile.sectorId,
            entity_ref: root.entity_ref,
            equipment_family_code: entry.familyCode,
            component: null,
            check_code: checkCode,
            status: relatedFacts.length > 0
              ? "accepted_fact"
              : relatedRejected.length > 0
              ? "unresolved_no_fact"
              : "not_visible",
            fact_ids: relatedFacts.map((fact) => fact.fact_id),
            rejected_fact_trace_ids: relatedRejected.map((candidate) =>
              candidate.traceID
            ),
            rejection_reason_codes: [
              ...new Set(
                relatedRejected.map((candidate) => candidate.reasonCode),
              ),
            ],
            reason_code: relatedFacts.length > 0
              ? "sector_critical_parent_child_has_accepted_fact"
              : relatedRejected.length > 0
              ? "sector_critical_parent_child_candidate_unresolved"
              : "sector_critical_component_not_visible",
            assurance_does_not_close_sector_coverage: true,
            triggers_targeted_reinspection: false,
          });
          continue;
        }
        for (const item of componentItems) {
          const facts = acceptedFacts.filter((fact) =>
            factMatchesEntryAndCheck(fact) &&
            (
              normalized(fact.entity.entity_ref) ===
                normalized(item.entity_ref) ||
              normalized(fact.entity.entity_ref).includes(
                normalized(item.entity_ref),
              ) ||
              normalized(item.entity_ref).includes(
                normalized(fact.entity.entity_ref),
              )
            )
          );
          const rejected = rejectedFacts.filter((entry) => {
            const fact = entry.fact;
            return factMatchesEntryAndCheck(fact) &&
              (
                normalized(fact.entity.entity_ref) ===
                  normalized(item.entity_ref) ||
                normalized(fact.entity.entity_ref).includes(
                  normalized(item.entity_ref),
                ) ||
                normalized(item.entity_ref).includes(
                  normalized(fact.entity.entity_ref),
                )
              );
          });
          const notVisible =
            /(?:görünmüyor|gorunmuyor|not visible|out of frame)/iu
              .test(item.visible_condition_summary);
          const unresolved =
            /(?:net değil|net degil|seçilemiyor|secilemiyor|çözülemiyor|cozulemiyor|unclear|unresolved|not discernible)/iu
              .test(item.visible_condition_summary);
          const status = facts.length > 0
            ? "accepted_fact"
            : rejected.length > 0
            ? "unresolved_no_fact"
            : notVisible
            ? "not_visible"
            : unresolved
            ? "unresolved_no_fact"
            : "scanned_no_hazard";
          coverage.push({
            photo_index: result.photoIndex,
            sector_id: profile.sectorId,
            entity_ref: item.entity_ref,
            equipment_family_code: entry.familyCode,
            component: item.component,
            check_code: checkCode,
            status,
            fact_ids: facts.map((fact) => fact.fact_id),
            rejected_fact_trace_ids: rejected.map((entry) => entry.traceID),
            rejection_reason_codes: [
              ...new Set(rejected.map((entry) => entry.reasonCode)),
            ],
            reason_code: status === "accepted_fact"
              ? "sector_critical_component_has_accepted_fact"
              : rejected.length > 0
              ? "sector_critical_component_candidate_unresolved"
              : status === "not_visible"
              ? "sector_critical_component_not_visible"
              : status === "unresolved_no_fact"
              ? "sector_critical_component_unresolved"
              : "sector_critical_component_scanned_no_hazard",
            assurance_does_not_close_sector_coverage: true,
            triggers_targeted_reinspection: false,
          });
        }
      }
    }
  }
  return coverage;
}

function sectorNegativeRejectionReason(
  fact: HazardFactV3,
  enabled: boolean,
): string | null {
  if (!enabled) return null;
  const core = [
    fact.entity.equipment_family,
    fact.entity.component,
    fact.entity.identity_basis,
    fact.observed_condition.short_text,
    fact.hazard_mechanism,
    fact.energy_source,
    fact.credible_event_path,
    ...fact.evidence.affirmative_cues,
  ].join(" ");
  if (
    /(?:belge|kayıt|kayit|sertifika|eğitim|egitim|yetki|periyodik kontrol|CE).{0,35}(?:yok|eksik|görünmüyor|gorunmuyor|yapılmamış|yapilmamis|bulunmuyor)|(?:missing|absent|not visible).{0,35}(?:document|record|certificate|training|inspection|CE)/iu
      .test(core)
  ) return "sector_negative_missing_document_claim";
  if (
    /\b\d+(?:[.,]\d+)?\s*(?:dB|lux|ppm|mg\/?m3|mg\/?m³|kV|volt|bar|psi|km\/?h|ton|kg)\b/iu
      .test(core)
  ) return "sector_negative_photo_measurement_claim";
  if (
    /(?:psikososyal|psychosocial|stres seviyesi|stress level|gözetim yetersiz|gozetim yetersiz|insufficient supervision)/iu
      .test(core)
  ) {
    return "sector_negative_behavior_or_psychosocial_inference";
  }
  if (
    /(?:kabin|cab|cabin).{0,100}(?:baret|helmet|KKD|PPE).{0,50}(?:yok|takm|eksik|görünm|gorunm|without|missing|not worn)|(?:baret|helmet|KKD|PPE).{0,50}(?:yok|takm|eksik|görünm|gorunm|without|missing|not worn).{0,100}(?:kabin|cab|cabin)/iu
      .test(core)
  ) return "sector_negative_cab_occupant_ppe_claim";
  return null;
}

type SceneInventoryItem = PhotoAnalysisV3["scene_inventory"][number];

function assuranceFact(params: {
  factID: string;
  photoIndex: number;
  entityRef: string;
  equipmentFamily: string;
  component: string;
  identityBasis: string;
  cue: string;
  conditionCode: string;
  conditionText: string;
  mechanismCode: HazardMechanismCode;
  mechanism: string;
  energySource: string;
  eventPath: string;
  exposedEntity: string;
  observation: string;
  significance: string;
  consequence: ConsequenceClass;
  controlIntents: string[];
}): HazardFactV3 {
  return {
    fact_id: params.factID,
    photo_index: params.photoIndex,
    assessment_basis: "equipment_integrity_verification",
    evidence: {
      normalized_region: {
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        is_global: true,
      },
      affirmative_cues: [params.cue],
    },
    entity: {
      entity_ref: params.entityRef,
      equipment_family: params.equipmentFamily,
      component: params.component,
      identity_basis: params.identityBasis,
      identity_confidence: "high",
    },
    observed_condition: {
      condition_code: params.conditionCode,
      short_text: params.conditionText,
    },
    mechanism_code: params.mechanismCode,
    hazard_mechanism: params.mechanism,
    energy_source: params.energySource,
    barrier_state: "visible_effective_event_conditional",
    initiating_event_state: params.mechanism,
    credible_event_path: params.eventPath,
    exposed_entity: params.exposedEntity,
    technical_assessment: {
      observation_narrative: params.observation,
      technical_significance: params.significance,
      root_cause_mode: "not_determinable",
      root_cause_text: "",
    },
    consequence_class: params.consequence,
    frequency_basis: "sector_scene_proxy",
    verification: {
      model_required: true,
      reason_code: "asset_integrity_assurance_from_inventory",
    },
    confidence: {
      entity: "high",
      condition: "high",
      localization: "high",
      mechanism: "medium",
    },
    depth_tags: ["asset_assurance", params.conditionCode],
    control_intents: params.controlIntents.map((actionCode, index) => ({
      action_code: actionCode,
      target: params.component,
      priority: index === 0 ? "immediate" : "planned",
    })),
  };
}

function inventoryContext(item: SceneInventoryItem): string {
  return normalized(`${item.equipment_family} ${item.component}`);
}

function inventoryDetailedContext(item: SceneInventoryItem): string {
  return normalized(
    `${item.equipment_family} ${item.component} ${item.visible_condition_summary}`,
  );
}

type AssetAssuranceIdentityRejection = {
  photo_index: number;
  entity_ref: string;
  equipment_family: string;
  component: string;
  reason_code: string;
};

function assetAssuranceIdentityRejectionReason(
  item: SceneInventoryItem,
): string | null {
  const context = inventoryDetailedContext(item);
  const visibleDetail = normalized(
    `${item.component} ${item.visible_condition_summary}`,
  );
  const alternativeContainerIdentity =
    /(?:kap|container|metal parca|metal object).{0,48}(?:veya|or).{0,48}(?:tank basligi|tank head|vessel head|dished head|bombe|kapak)/u
      .test(context);
  const alternativeElectricalIdentity =
    /(?:elektrik panosu|electrical panel|panel|pano).{0,40}(?:veya|or).{0,40}(?:dolap|cabinet|enclosure)/u
      .test(context);
  if (alternativeContainerIdentity || alternativeElectricalIdentity) {
    return "asset_assurance_ambiguous_equipment_identity";
  }
  const genericUnlabelledBucket = /(?:bucket|pail|kova)/u.test(visibleDetail) &&
    !/(?:ibc|drum|varil|jerrycan|bidon|tank|vessel|readable chemical label|okunabilir kimyasal etiket)/u
      .test(visibleDetail);
  if (genericUnlabelledBucket) {
    return "asset_assurance_unidentified_generic_container";
  }
  if (
    /(?:muhtemel|possibly|probable|suspected|kimligi net degil|identity unclear)/u
      .test(context) &&
    /(?:tank|vessel|chemical container|kimyasal kap|electrical panel|elektrik panosu)/u
      .test(context)
  ) {
    return "asset_assurance_uncertain_equipment_identity";
  }
  return null;
}

type CriticalAssetAssuranceResult = {
  facts: HazardFactV3[];
  identityRejections: AssetAssuranceIdentityRejection[];
};

/**
 * Converts visible critical-asset presence into truthful assurance findings.
 * These are not claims that a record is missing or an inspection is overdue.
 * They preserve the user's all-numeric scoring contract while ensuring the
 * process/crane audit does not disappear merely because a still image cannot
 * prove a functional test result.
 */
function criticalAssetAssuranceFacts(
  photoResults: PhotoResult[],
  acceptedProviderFacts: HazardFactV3[],
  language: string,
): CriticalAssetAssuranceResult {
  const tr = isTurkish(language);
  const facts: HazardFactV3[] = [];
  const identityRejections: AssetAssuranceIdentityRejection[] = [];
  for (const result of photoResults) {
    const photoFactStart = facts.length;
    const inventory = result.output.scene_inventory;
    const identityEligibleInventory = inventory.filter((item) => {
      const reasonCode = assetAssuranceIdentityRejectionReason(item);
      if (!reasonCode) return true;
      identityRejections.push({
        photo_index: result.photoIndex,
        entity_ref: item.entity_ref,
        equipment_family: item.equipment_family,
        component: item.component,
        reason_code: reasonCode,
      });
      return false;
    });
    const tankItems = identityEligibleInventory.filter((item) => {
      const equipmentContext = inventoryContext(item);
      const context = inventoryDetailedContext(item);
      const isTank =
        /(?:process vessel|storage tank|chemical tank|proses tank|depolama tank|kimyasal tank|tank|reactor)/u
          .test(equipmentContext);
      const gasSpecific =
        /(?:\blng\b|\blpg\b|liquefied natural gas|liquefied petroleum gas|sivilastirilmis dogal gaz|sivilastirilmis petrol gazi|cryogenic tank|kriyojenik tank|propane|propan|butane|butan)/u
          .test(context);
      const detachedOrUncertainPart =
        /(?:tank head|vessel head|dished head|dished end|tank basi|tank kapagi|tank bombesi|bombe|end cap|muhtemel|possibly|probable|suspected)/u
          .test(context);
      return isTank && !gasSpecific && !detachedOrUncertainPart;
    });
    const craneItems = identityEligibleInventory.filter((item) =>
      /(?:overhead crane|bridge crane|kopru vinc)/u.test(inventoryContext(item))
    );
    const containmentItems = identityEligibleInventory.filter((item) =>
      /(?:secondary containment|containment bund|bund wall|bunding|dyke|dike|spill basin|catch basin|ikincil tutma|taşma havuzu|tasma havuzu|sedd|drenaj havuzu)/u
        .test(inventoryDetailedContext(item))
    );
    const driveItems = identityEligibleInventory.filter((item) =>
      /(?:agitator|karistirici|motor|tahrik|process equipment)/u
        .test(inventoryContext(item))
    );
    const alreadyCovered = (conditionCode: string) =>
      acceptedProviderFacts.some((fact) =>
        fact.photo_index === result.photoIndex &&
        fact.assessment_basis === "equipment_integrity_verification" &&
        normalized(fact.observed_condition.condition_code) ===
          normalized(conditionCode)
      );

    if (
      tankItems.length > 0 &&
      !alreadyCovered("process_tank_integrity_assurance")
    ) {
      const count = tankItems.length;
      facts.push(assuranceFact({
        factID: "assurance-process-tank-integrity",
        photoIndex: result.photoIndex,
        entityRef: `process-tank-bank-p${result.photoIndex}`,
        equipmentFamily: tr ? "Proses tankları" : "Process vessels",
        component: tr
          ? "Tank gövdeleri, taşıyıcılar, ankrajlar, nozullar ve bağlantılar"
          : "Vessel shells, supports, anchors, nozzles and connections",
        identityBasis: tankItems.map((item) => item.entity_ref).join(", "),
        cue: tr
          ? `Fotoğrafta ${count} proses tankı ile tankların taşıyıcı yapıları ve bağlı ekipmanları görülmektedir.`
          : `${count} process vessels with their support structures and connected equipment are visible.`,
        conditionCode: "process_tank_integrity_assurance",
        conditionText: tr
          ? "Proses tanklarının mekanik bütünlük ve periyodik kontrol gereklilikleri"
          : "Mechanical integrity and periodic inspection of process vessels",
        mechanismCode: "environmental_release",
        mechanism: tr
          ? "Tank veya bağlantı bütünlüğünün bozulmasıyla proses akışkanının kontrol dışı salımı"
          : "Loss of containment following degradation of vessel or connection integrity",
        energySource: tr
          ? "Proses envanteri, sıvı kolonu ve varsa basınç/sıcaklık"
          : "Process inventory, liquid head and any pressure or temperature",
        eventPath: tr
          ? "Gövde, destek, nozul veya bağlantı bütünlüğündeki bozulma sızdırmazlık kaybına ve çalışanların ya da çevrenin proses akışkanına maruz kalmasına yol açabilir."
          : "Degradation of the shell, supports, nozzles or connections can cause loss of containment and expose personnel or the environment to process material.",
        exposedEntity: tr
          ? "Çalışanlar, tesis ve çevre"
          : "Personnel, plant and environment",
        observation: tr
          ? "Fotoğrafta birden fazla proses tankı, bunları taşıyan çelik yapı ve bağlı proses hatları birlikte görülmektedir. Bu ekipman grubu, tek bir bileşen yerine gövde-bağlantı-destek yük yoluyla birlikte ele alınmalıdır."
          : "Multiple process vessels, their steel support structure and connected process lines are visible. The equipment group should be assessed as a shell-connection-support load path rather than as isolated components.",
        significance: tr
          ? "Tank bütünlüğü yalnız dış yüzey görünümüne bağlı değildir; gövde/cidar, taban, çatı, kaynak, nozul, flanş, destek, ankraj, oturma ve sızdırmazlık birlikte değerlendirilir. Tasarım ve servis kapsamı uygunsa API 650 imalat/tasarım kayıtları ile API 653 hizmet içi muayene yaklaşımı kullanılmalı; VT ve UT kalınlık haritalaması temel alınarak hasar mekanizmasına ve onarım/kaynak kapsamına göre PT, MT, UT veya radyografi seçilmelidir. API kapsam dışıysa ekipmanın gerçek tasarım standardı esas alınır."
          : "Tank integrity cannot be established from external appearance alone; shell, bottom, roof, welds, nozzles, flanges, supports, anchors, settlement and containment must be assessed together. Where design/service scope fits, use API 650 fabrication/design records and the API 653 in-service inspection approach, with VT and UT thickness mapping plus PT, MT, UT or radiography selected by damage mechanism and repair/weld scope. Otherwise use the actual governing design standard.",
        consequence: "permanent_disability",
        controlIntents: [
          "verify_periodic_control_status",
          "process_equipment_integrity_inspection",
          "storage_tank_integrity_ndt",
        ],
      }));
    }

    if (
      tankItems.length > 0 && !alreadyCovered("process_safeguard_assurance")
    ) {
      facts.push(assuranceFact({
        factID: "assurance-process-safeguards",
        photoIndex: result.photoIndex,
        entityRef: `process-safeguards-p${result.photoIndex}`,
        equipmentFamily: tr ? "Proses tankları" : "Process vessels",
        component: tr
          ? "Seviye, taşma, havalık-tahliye, izolasyon ve acil durdurma fonksiyonları"
          : "Level, overfill, vent/relief, isolation and emergency shutdown functions",
        identityBasis: tankItems.map((item) => item.entity_ref).join(", "),
        cue: tr
          ? "Fotoğrafta proses envanteri içeren tank grubu ve bunlara bağlı proses ekipmanları görülmektedir."
          : "A group of process-inventory vessels and connected process equipment is visible.",
        conditionCode: "process_safeguard_assurance",
        conditionText: tr
          ? "Proses tanklarında seviye, taşma ve emniyet fonksiyonlarının doğrulanması"
          : "Verification of level, overfill and safety functions for process vessels",
        mechanismCode: "environmental_release",
        mechanism: tr
          ? "Proses sapmasının bağımsız emniyet fonksiyonlarıyla sınırlandırılamaması"
          : "Failure to contain a process deviation through independent safety functions",
        energySource: tr
          ? "Proses envanteri ve işletme koşulları"
          : "Process inventory and operating conditions",
        eventPath: tr
          ? "Seviye, taşma, basınç/sıcaklık, havalık-tahliye veya izolasyon fonksiyonlarından uygulanabilir olanların talep anında çalışmaması taşma, aşırı basınç ya da kontrolsüz salıma dönüşebilir."
          : "Failure on demand of applicable level, overfill, pressure/temperature, vent/relief or isolation functions can develop into overfill, overpressure or uncontrolled release.",
        exposedEntity: tr
          ? "Operatörler, bakım çalışanları ve çevre"
          : "Operators, maintenance personnel and environment",
        observation: tr
          ? "Görüntüdeki tank grubu, proses envanterinin depolandığı veya işlendiği bir ekipman sistemi oluşturmaktadır. Bu nedenle yalnız mekanik yüzey değil, prosese uygulanabilir izleme, tahliye, izolasyon ve durdurma katmanları da ekipman bütünlüğünün parçasıdır."
          : "The visible vessels form an equipment system in which process inventory is stored or handled. Applicable monitoring, relief, isolation and shutdown layers are therefore part of integrity alongside the mechanical envelope.",
        significance: tr
          ? "Emniyet fonksiyonları normal işletme göstergelerinden bağımsız olarak tanımlı set değerlerinde ve periyotlarda fonksiyon testine tabi tutulmalıdır. Test kapsamı, tankın gerçek akışkanı, çalışma basıncı/sıcaklığı, dolum-boşaltım yolu ve taşma senaryosuna göre belirlenmelidir."
          : "Safety functions should be function-tested at defined set points and intervals independently of normal operating indications. Scope should be based on the vessel contents, pressure/temperature, filling/emptying route and overfill scenario.",
        consequence: "permanent_disability",
        controlIntents: [
          "verify_periodic_control_status",
          "process_safeguard_function_test",
        ],
      }));
    }

    if (
      tankItems.length > 0 && containmentItems.length > 0 &&
      !alreadyCovered("tank_secondary_containment_assurance")
    ) {
      facts.push(assuranceFact({
        factID: "assurance-tank-secondary-containment",
        photoIndex: result.photoIndex,
        entityRef: `tank-containment-p${result.photoIndex}`,
        equipmentFamily: tr
          ? "Proses/depolama tankları"
          : "Process/storage tanks",
        component: tr
          ? "İkincil tutma, taşma havuzu, drenaj ve dolum-taşma kontrolü"
          : "Secondary containment, bunding, drainage and filling/overfill control",
        identityBasis: tankItems.map((item) => item.entity_ref).join(", "),
        cue: tr
          ? "Fotoğrafta proses veya depolama envanteri içerebilen tank grubu görülmektedir."
          : "A group of tanks capable of containing process or storage inventory is visible.",
        conditionCode: "tank_secondary_containment_assurance",
        conditionText: tr
          ? "Tanklarda taşma, sızıntı ve ikincil tutma kontrolleri"
          : "Overfill, leak and secondary-containment controls for tanks",
        mechanismCode: "environmental_release",
        mechanism: tr
          ? "Tanktan sızan veya taşan akışkanın kontrolsüz yayılması"
          : "Uncontrolled spread of leaked or overfilled tank contents",
        energySource: tr
          ? "Tank envanteri, sıvı kolonu ve dolum akışı"
          : "Tank inventory, liquid head and filling flow",
        eventPath: tr
          ? "Gövde/bağlantı sızıntısı veya dolum sırasında taşma; yeterli tutma, drenaj ve durdurma katmanı yoksa çalışan maruziyetine, tesis hasarına ve çevresel yayılıma dönüşebilir."
          : "Shell/connection leakage or overfill during filling can develop into personnel exposure, plant damage and environmental spread without adequate containment, drainage and shutdown layers.",
        exposedEntity: tr
          ? "Operatörler, acil müdahale çalışanları, tesis ve çevre"
          : "Operators, emergency responders, plant and environment",
        observation: tr
          ? "Tankların güvenliği yalnız gövde bütünlüğüyle sınırlı değildir; olası sızıntı ve taşmanın tank çevresinde nasıl tutulacağı, algılanacağı ve güvenli biçimde yönetileceği de kontrol sınırının parçasıdır."
          : "Tank safety is not limited to shell integrity; how a potential leak or overfill is contained, detected and safely managed around the tank is also part of the control boundary.",
        significance: tr
          ? "Akışkan özelliği, tank hacmi, dolum-boşaltım senaryosu ve drenaj bağlantıları belirlenerek ikincil tutma/taşma havuzu kapasitesi ve sızdırmazlığı, yağmur suyu yönetimi, yüksek-yüksek seviye veya bağımsız taşma önleme, dolum gözetimi ve acil izolasyon birlikte doğrulanmalıdır."
          : "Based on fluid properties, tank inventory, filling/emptying scenario and drains, verify capacity/tightness of secondary containment, stormwater management, independent high-high level or overfill prevention, filling supervision and emergency isolation together.",
        consequence: "permanent_disability",
        controlIntents: [
          "verify_periodic_control_status",
          "secondary_containment_overfill_control",
        ],
      }));
    }

    if (
      tankItems.length > 0 && driveItems.length > 0 &&
      !alreadyCovered("agitator_drive_assurance")
    ) {
      facts.push(assuranceFact({
        factID: "assurance-agitator-drive",
        photoIndex: result.photoIndex,
        entityRef: `tank-top-drive-p${result.photoIndex}`,
        equipmentFamily: tr
          ? "Tank üstü tahrik ekipmanı"
          : "Tank-top drive equipment",
        component: tr
          ? "Motor, kaplin/aktarma, koruyucu ve enerji izolasyonu"
          : "Motor, coupling/transmission, guarding and energy isolation",
        identityBasis: driveItems.map((item) => item.entity_ref).join(", "),
        cue: tr
          ? "Fotoğrafta tank üst seviyesinde motor veya tahrik ekipmanı görülmektedir."
          : "Motor or drive equipment is visible at the top level of the vessels.",
        conditionCode: "agitator_drive_assurance",
        conditionText: tr
          ? "Tank üstü tahrik ekipmanında koruyucu ve enerji izolasyonu kontrolü"
          : "Guarding and energy-isolation checks for tank-top drive equipment",
        mechanismCode: "caught_in_pinch_shear",
        mechanism: tr
          ? "Döner aktarma elemanına temas veya bakım sırasında beklenmeyen çalıştırma"
          : "Contact with rotating transmission parts or unexpected startup during maintenance",
        energySource: tr
          ? "Elektrik ve döner mekanik enerji"
          : "Electrical and rotating mechanical energy",
        eventPath: tr
          ? "Koruyucu, durdurma veya enerji izolasyonu işlevindeki bozulma, işletme ya da bakım sırasında döner parçayla temas ve sıkışma-kesilme yaralanmasına yol açabilir."
          : "Degradation of guarding, stopping or energy isolation can expose personnel to rotating parts and cause caught-in or shear injuries during operation or maintenance.",
        exposedEntity: tr
          ? "Operatörler ve bakım çalışanları"
          : "Operators and maintenance personnel",
        observation: tr
          ? "Tankların üst seviyesinde proses ekipmanına bağlı motor/tahrik grubu görülmektedir. Döner aktarım elemanlarının koruyucuları ile bakım erişimindeki izolasyon noktaları bu ekipmanın kritik kontrol sınırını oluşturur."
          : "A motor/drive group associated with process equipment is visible above the vessels. Guarding of rotating transmission parts and isolation points for maintenance define the critical control boundary.",
        significance: tr
          ? "Koruyucu bütünlüğü, acil durdurma ve LOTO yalnız ekipmanın varlığına bakılarak değerlendirilemez; fonksiyon ve sıfır enerji doğrulaması birlikte yapılmalıdır. Periyodik bakım, kaplin/şaft koruyucusu, bağlantılar, titreşim ve yeniden çalıştırma önleme adımlarını kapsamalıdır."
          : "Guard integrity, emergency stopping and LOTO cannot be established from equipment presence alone; functional and zero-energy verification are both required. Periodic maintenance should cover coupling/shaft guards, connections, vibration and restart prevention.",
        consequence: "permanent_disability",
        controlIntents: [
          "verify_periodic_control_status",
          "agitator_guard_loto_inspection",
        ],
      }));
    }

    if (
      craneItems.length > 0 &&
      !alreadyCovered("crane_periodic_safety_assurance")
    ) {
      const uniqueCranes = new Set(
        craneItems.map((item) =>
          item.entity_ref.replace(
            /_(?:(?:MAIN|BRIDGE)_)?(?:GIRDER|BEAM|BRIDGE|TROLLEY|HOIST|WIRE_ROPE|ROPE|DRUM|HOOK_BLOCK|HOOK|STRUCTURE)$/iu,
            "",
          )
        ),
      );
      facts.push(assuranceFact({
        factID: "assurance-crane-periodic-safety",
        photoIndex: result.photoIndex,
        entityRef: `overhead-crane-group-p${result.photoIndex}`,
        equipmentFamily: tr ? "Köprü vinçler" : "Overhead cranes",
        component: tr
          ? "Taşıyıcı sistem, kaldırma mekanizması ve emniyet fonksiyonları"
          : "Structural system, hoisting mechanism and safety functions",
        identityBasis: craneItems.map((item) => item.entity_ref).join(", "),
        cue: tr
          ? `Fotoğrafta ${uniqueCranes.size} köprü vinç; vinç arabaları, halat/tambur ve kanca bloklarıyla birlikte görülmektedir.`
          : `${uniqueCranes.size} overhead cranes are visible with their trolleys, ropes/drums and hook blocks.`,
        conditionCode: "crane_periodic_safety_assurance",
        conditionText: tr
          ? "Köprü vinçlerin periyodik kontrolü ve emniyet fonksiyonlarının doğrulanması"
          : "Periodic inspection and safety-function verification of overhead cranes",
        mechanismCode: "falling_object",
        mechanism: tr
          ? "Kaldırma veya hareket emniyet fonksiyonunun bozulmasıyla yükün ya da ekipman parçasının kontrolsüz hareketi"
          : "Uncontrolled load or component movement following degradation of a lifting or travel safety function",
        energySource: tr
          ? "Yerçekimi, kaldırma ve hareket enerjisi"
          : "Gravity, hoisting and travel energy",
        eventPath: tr
          ? "Halat, tambur, kanca, fren, limit veya taşıyıcı sistem bütünlüğündeki bozulma yükün düşmesine ya da vincin kontrolsüz hareketine ve çalışanların ezilmesine/çarpılmasına yol açabilir."
          : "Degradation of rope, drum, hook, brake, limit or structural integrity can lead to a dropped load or uncontrolled crane movement and strike/crush personnel.",
        exposedEntity: tr
          ? "Kaldırma alanındaki çalışanlar"
          : "Personnel in the lifting area",
        observation: tr
          ? "Fotoğrafta köprü vinçlerin taşıyıcı kirişleri, hareketli arabaları, halat/tambur düzenleri ve kanca blokları birlikte görülmektedir. Bu düzeneklerin güvenliği, normal hareketli parça varlığından çok kaldırma bütünlüğü ve emniyet fonksiyonlarının sürekliliğine bağlıdır."
          : "The crane girders, travelling trolleys, rope/drum arrangements and hook blocks are visible together. Safety depends on lifting integrity and continuity of safety functions rather than on the mere presence of moving parts.",
        significance: tr
          ? "Periyodik kontrol; taşıyıcı sistem ve raylardan halat, tambur, kanca, fren, limit kesici, yük sınırlayıcı ve son durduruculara kadar yük yolunu kapsamalıdır. Ekipman tasarımı ve risk değerlendirmesinde öngörülen sesli-görsel hareket uyarıları ile acil durdurma ve çarpışma korumaları ayrıca fonksiyon testine tabi tutulmalıdır."
          : "Periodic inspection should cover the load path from structure and runway through rope, drum, hook, brakes, limit switches, load limiting devices and end stops. Audible/visual travel warnings required by design/risk assessment, emergency stop and collision protection should also be function-tested.",
        consequence: "single_fatality",
        controlIntents: [
          "verify_periodic_control_status",
          "periodic_crane_inspection",
          "crane_safety_function_test",
        ],
      }));
    }

    // Specific asset profiles are ordered by safety importance and capped per
    // photo. This prevents a busy workshop from being padded with generic
    // records while still surfacing knowledge the user could not derive from
    // the image alone. Tank/crane rules above consume the same cap first.
    const generalProfiles = resolveAssetAssuranceProfiles(
      identityEligibleInventory,
    );
    const maxAssuranceFindingsPerPhoto = 8;
    for (const { profile, items } of generalProfiles) {
      // A tank-top agitator is already covered by the specific drive/LOTO
      // finding above. Repeating the generic crusher/mixer profile here would
      // inflate the count without adding a distinct control boundary.
      if (
        profile.profileID === "bulk_process_machine" && tankItems.length > 0
      ) {
        continue;
      }
      for (const template of profile.templates) {
        if (facts.length - photoFactStart >= maxAssuranceFindingsPerPhoto) {
          break;
        }
        if (alreadyCovered(template.conditionCode)) continue;
        const itemNames = [
          ...new Set(
            items.map((item) =>
              `${item.equipment_family}/${item.component}`.replace(/_/g, " ")
            ),
          ),
        ].slice(0, 5);
        const created = assuranceFact({
          factID: `assurance-${profile.profileID}-${template.conditionCode}`,
          photoIndex: result.photoIndex,
          entityRef: `${profile.profileID}-p${result.photoIndex}`,
          equipmentFamily: tr
            ? profile.equipmentFamily.tr
            : profile.equipmentFamily.en,
          component: tr ? template.component.tr : template.component.en,
          identityBasis: items.map((item) => item.entity_ref).join(", "),
          cue: tr
            ? `Fotoğrafta ${
              profile.equipmentFamily.tr.toLocaleLowerCase("tr-TR")
            } sınıfında ekipman/bileşen görülmektedir: ${itemNames.join(", ")}.`
            : `Visible equipment/components match the ${profile.equipmentFamily.en.toLowerCase()} class: ${
              itemNames.join(", ")
            }.`,
          conditionCode: template.conditionCode,
          conditionText: tr
            ? template.conditionText.tr
            : template.conditionText.en,
          mechanismCode: template.mechanismCode,
          mechanism: tr ? template.mechanism.tr : template.mechanism.en,
          energySource: tr
            ? template.energySource.tr
            : template.energySource.en,
          eventPath: tr ? template.eventPath.tr : template.eventPath.en,
          exposedEntity: tr
            ? template.exposedEntity.tr
            : template.exposedEntity.en,
          observation: tr ? template.observation.tr : template.observation.en,
          significance: tr
            ? template.significance.tr
            : template.significance.en,
          consequence: template.consequence,
          controlIntents: template.controlIntents,
        });
        created.depth_tags.push(
          ASSET_ASSURANCE_CATALOG_VERSION,
          profile.profileID,
        );
        facts.push(created);
      }
      if (facts.length - photoFactStart >= maxAssuranceFindingsPerPhoto) break;
    }
  }
  return { facts, identityRejections };
}

export function buildEngineProduct(
  photoResults: PhotoResult[],
  language: string,
  plan: string,
  targetedConfirmedFacts: HazardFactV3[] = [],
  referenceContext: EngineReferenceContext = {},
  sectorContext: EngineSectorContext = {},
): EngineProduct {
  const sectorProfile = sectorContext.profileEnabled === false
    ? null
    : getSectorProfile(sectorContext.sectorID);
  const sectorFrequencyPriorEnabled = Boolean(sectorProfile) &&
    sectorContext.frequencyPriorEnabled !== false;
  const sectorNegativeRulesEnabled = Boolean(sectorProfile) &&
    sectorContext.negativeRulesEnabled !== false;
  const rejectionLedger: Array<Record<string, unknown>> = [];
  const rejectedFactCoverage: RejectedFactCoverage[] = [];
  const mergeLedger: Array<Record<string, unknown>> = [];
  for (const result of photoResults) {
    const invalidCount = result.output._schema_diagnostics_v1
      ?.invalid_fact_count ?? 0;
    for (let index = 0; index < invalidCount; index += 1) {
      rejectionLedger.push({
        fact_trace_id: `p${result.photoIndex}:schema-invalid-${index + 1}`,
        photo_index: result.photoIndex,
        reason_code: "invalid_record",
      });
    }
  }
  const parsedFacts = photoResults.flatMap((result) =>
    result.output.hazard_facts
  );
  const evidenceValid: HazardFactV3[] = [];
  const acceptedTargetedFacts: HazardFactV3[] = [];
  const acceptedCandidates: Array<{
    fact: HazardFactV3;
    traceID: string;
    source: "primary" | "targeted" | "assurance";
  }> = [];
  const traceOccurrences = new Map<string, number>();
  const allocateTraceID = (
    source: "primary" | "targeted" | "assurance",
    fact: HazardFactV3,
  ): string => {
    // fact_id is provider-authored and is not guaranteed unique. Keep it for
    // diagnosis, but namespace targeted facts and deterministically suffix
    // duplicate IDs before they reach the DB uniqueness boundary.
    const prefix = source === "targeted"
      ? "targeted:"
      : source === "assurance"
      ? "assurance:"
      : "";
    const base = `${prefix}p${fact.photo_index}:${fact.fact_id}`;
    const occurrence = (traceOccurrences.get(base) ?? 0) + 1;
    traceOccurrences.set(base, occurrence);
    return occurrence === 1 ? base : `${base}#${occurrence}`;
  };
  for (const fact of parsedFacts) {
    const traceID = allocateTraceID("primary", fact);
    const commonReason = evidenceRejectionReason(fact);
    const sectorReason = sectorNegativeRejectionReason(
      fact,
      sectorNegativeRulesEnabled,
    );
    const reason = sectorReason ?? commonReason;
    if (reason) {
      rejectedFactCoverage.push({ fact, traceID, reasonCode: reason });
      rejectionLedger.push({
        fact_trace_id: traceID,
        photo_index: fact.photo_index,
        reason_code: reason,
        reason_codes: [
          ...new Set([sectorReason, commonReason].filter(Boolean)),
        ],
        // Only for absence rejections, and only when the fact was aiming at a
        // safety barrier: says which gate condition it missed.
        ...(commonReason === "absence_only_claim" &&
            SAFETY_CRITICAL_HARDWARE_PATTERN.test(
              normalized(
                `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code}`,
              ),
            )
          ? { structured_gate_failures: structuredBarrierGateFailures(fact) }
          : {}),
      });
    } else {
      evidenceValid.push(fact);
      acceptedCandidates.push({ fact, traceID, source: "primary" });
    }
  }

  const assuranceResult = criticalAssetAssuranceFacts(
    photoResults,
    evidenceValid,
    language,
  );
  const assuranceFacts = assuranceResult.facts;
  for (const fact of assuranceFacts) {
    const traceID = allocateTraceID("assurance", fact);
    const reason = evidenceRejectionReason(fact);
    if (reason) {
      rejectionLedger.push({
        fact_trace_id: traceID,
        photo_index: fact.photo_index,
        reason_code: "asset_assurance_rejected",
        policy_reason_code: reason,
      });
    } else {
      acceptedCandidates.push({ fact, traceID, source: "assurance" });
    }
  }

  for (const fact of targetedConfirmedFacts) {
    const traceID = allocateTraceID("targeted", fact);
    const commonReason = targetedEvidenceRejectionReason(fact);
    const sectorReason = sectorNegativeRejectionReason(
      fact,
      sectorNegativeRulesEnabled,
    );
    const reason = sectorReason ?? commonReason;
    if (reason) {
      rejectionLedger.push({
        fact_trace_id: traceID,
        photo_index: fact.photo_index,
        reason_code: "targeted_not_confirmed",
        policy_reason_code: reason,
        reason_codes: [
          ...new Set([sectorReason, commonReason].filter(Boolean)),
        ],
      });
    } else {
      acceptedTargetedFacts.push(fact);
      acceptedCandidates.push({ fact, traceID, source: "targeted" });
    }
  }
  const rejectedHighConsequenceFacts = rejectedFactCoverage.filter((entry) =>
    isHighConsequencePersonClaim(entry.fact) &&
    !acceptedTargetedFacts.some((confirmed) =>
      confirmed.photo_index === entry.fact.photo_index &&
      confirmed.mechanism_code === entry.fact.mechanism_code &&
      (
        normalized(confirmed.entity.entity_ref) ===
          normalized(entry.fact.entity.entity_ref) ||
        regionsOverlap(
          confirmed.evidence.normalized_region,
          entry.fact.evidence.normalized_region,
        )
      )
    )
  );
  const evidenceRejectionRatio = parsedFacts.length === 0
    ? 0
    : rejectedFactCoverage.length / parsedFacts.length;
  const evidenceRejectionAlert = {
    parsed_fact_count: parsedFacts.length,
    accepted_primary_fact_count: evidenceValid.length,
    rejected_primary_fact_count: rejectedFactCoverage.length,
    rejection_ratio: Number(evidenceRejectionRatio.toFixed(4)),
    alert_threshold: 0.5,
    triggered: evidenceRejectionRatio > 0.5,
    reason_code: evidenceRejectionRatio > 0.5
      ? "evidence_rejection_ratio_above_threshold"
      : null,
  };
  const aggregated: AggregatedFact[] = [];
  const samePhotoKeys = new Set<string>();
  for (const candidate of acceptedCandidates) {
    const { fact, traceID, source } = candidate;
    if (source === "targeted") {
      const existingPrimary = aggregated.find((item) =>
        !item.traceID.startsWith("targeted:") &&
        targetedDuplicatesPrimary(item, fact)
      );
      if (existingPrimary) {
        rejectionLedger.push({
          fact_trace_id: traceID,
          photo_index: fact.photo_index,
          reason_code: "targeted_duplicate_primary",
          duplicate_of_fact_trace_id: existingPrimary.traceID,
        });
        continue;
      }
    }
    if (source === "assurance") {
      const overlap = aggregated.map((item) => ({
        item,
        reason: assuranceOverlapReason(item, fact),
      })).find((candidate) => candidate.reason !== null);
      if (overlap?.reason) {
        overlap.item.evidenceRegions.push({
          photo_index: fact.photo_index,
          region: fact.evidence.normalized_region,
          cues: fact.evidence.affirmative_cues,
        });
        overlap.item.equivalentEntityRefs.push(fact.entity.entity_ref);
        overlap.item.equivalentEntityRefs.push(
          ...fact.entity.identity_basis.split(",").map((value) => value.trim())
            .filter(Boolean),
        );
        overlap.item.equivalentEntityRefs = [
          ...new Set(overlap.item.equivalentEntityRefs),
        ];
        overlap.item.control_intents = [
          ...overlap.item.control_intents,
          ...fact.control_intents,
        ].filter((intent, index, all) =>
          all.findIndex((candidate) =>
            candidate.action_code === intent.action_code
          ) === index
        );
        overlap.item.reasonCodes.push(overlap.reason);
        mergeLedger.push({
          into_fact_trace_id: overlap.item.traceID,
          merged_fact_trace_id: traceID,
          reason_code: overlap.reason,
          merged_entity_ref: fact.entity.entity_ref,
        });
        continue;
      }
    }
    // Repeated text on two different physical components is not a duplicate.
    // Keep the stable entity identity in same-photo dedup so four hooks, pins
    // or floor zones cannot silently collapse into one finding.
    const exactKey = `${fact.photo_index}|${
      normalized(fact.entity.entity_ref)
    }|${fingerprint(fact)}`;
    if (samePhotoKeys.has(exactKey)) {
      rejectionLedger.push({
        fact_trace_id: traceID,
        photo_index: fact.photo_index,
        reason_code: "duplicate_exact",
      });
      continue;
    }
    samePhotoKeys.add(exactKey);
    const equivalentSamePhoto = aggregated.map((item) => ({
      item,
      reason: samePhotoEquivalentConditionReason(item, fact),
    })).find((candidate) => candidate.reason !== null);
    if (equivalentSamePhoto?.reason) {
      equivalentSamePhoto.item.evidenceRegions.push({
        photo_index: fact.photo_index,
        region: fact.evidence.normalized_region,
        cues: fact.evidence.affirmative_cues,
      });
      equivalentSamePhoto.item.equivalentEntityRefs.push(
        fact.entity.entity_ref,
      );
      equivalentSamePhoto.item.control_intents = [
        ...equivalentSamePhoto.item.control_intents,
        ...fact.control_intents,
      ].filter((intent, index, all) =>
        all.findIndex((candidate) =>
          candidate.action_code === intent.action_code
        ) === index
      );
      equivalentSamePhoto.item.reasonCodes.push(equivalentSamePhoto.reason);
      mergeLedger.push({
        into_fact_trace_id: equivalentSamePhoto.item.traceID,
        merged_fact_trace_id: traceID,
        reason_code: equivalentSamePhoto.reason,
        merged_entity_ref: fact.entity.entity_ref,
      });
      continue;
    }
    const existing = aggregated.find((candidate) =>
      !candidate.sourcePhotoIndices.includes(fact.photo_index) &&
      crossPhotoIdentity(candidate, fact)
    );
    if (existing) {
      existing.sourcePhotoIndices.push(fact.photo_index);
      existing.evidenceRegions.push({
        photo_index: fact.photo_index,
        region: fact.evidence.normalized_region,
        cues: fact.evidence.affirmative_cues,
      });
      existing.reasonCodes.push("cross_photo_duplicate");
      existing.equivalentEntityRefs.push(
        fact.entity.entity_ref,
        ...(
          fact.assessment_basis === "equipment_integrity_verification"
            ? fact.entity.identity_basis.split(",").map((value) => value.trim())
              .filter(Boolean)
            : []
        ),
      );
      existing.equivalentEntityRefs = [
        ...new Set(existing.equivalentEntityRefs),
      ];
      existing.control_intents = [
        ...existing.control_intents,
        ...fact.control_intents,
      ].filter((intent, index, all) =>
        all.findIndex((candidate) =>
          candidate.action_code === intent.action_code
        ) === index
      );
      mergeLedger.push({
        into_fact_trace_id: existing.traceID,
        merged_fact_trace_id: traceID,
        reason_code: "cross_photo_duplicate",
      });
      continue;
    }
    aggregated.push({
      ...fact,
      traceID,
      sourcePhotoIndices: [fact.photo_index],
      equivalentEntityRefs: [
        fact.entity.entity_ref,
        ...(
          source === "assurance"
            ? fact.entity.identity_basis.split(",").map((value) => value.trim())
              .filter(Boolean)
            : []
        ),
      ],
      evidenceRegions: [{
        photo_index: fact.photo_index,
        region: fact.evidence.normalized_region,
        cues: fact.evidence.affirmative_cues,
      }],
      reasonCodes: source === "assurance" ? ["asset_assurance_added"] : [],
    });
  }

  // Targeted confirmation is still an observed risk. Keep every observed
  // finding ahead of inventory-derived assurance records while preserving the
  // provider order within each section.
  aggregated.sort((left, right) => {
    const leftAssurance = left.assessment_basis ===
      "equipment_integrity_verification";
    const rightAssurance = right.assessment_basis ===
      "equipment_integrity_verification";
    return Number(leftAssurance) - Number(rightAssurance);
  });

  let totalFK = 0;
  let totalM5 = 0;
  let assuranceTotalFK = 0;
  let assuranceTotalM5 = 0;
  let activeFindingCount = 0;
  let assuranceFindingCount = 0;
  let highestFK: RiskBand = "low";
  let highestM5: RiskBand = "low";
  const rank: Record<RiskBand, number> = {
    low: 1,
    medium: 2,
    high: 3,
    critical: 4,
  };
  const lineage: Array<Record<string, unknown>> = [];
  const modifierByPhoto = new Map(
    photoResults.map((result) => [
      result.photoIndex,
      sectorProfile
        ? validSectorModifierEvidence(sectorProfile, result.output)[0] ?? null
        : null,
    ]),
  );
  const titles = displayTitles(aggregated, language);
  const findings = aggregated.map((fact, index): FinalFindingV3 => {
    const probability = resolveProbability(fact);
    const frequency = resolveFrequency(
      fact,
      sectorProfile,
      modifierByPhoto.get(fact.photo_index) ?? null,
      sectorFrequencyPriorEnabled,
    );
    const severity = resolveSeverity(fact);
    const p = probability.value;
    const f = frequency.value;
    const s = severity.value;
    const m5p = m5Probability(p);
    const m5s = m5Severity(s);
    const score = p * f * s;
    const m5score = m5p * m5s;
    const fkB = fkBand(score);
    const m5B = m5Band(m5score);
    const assurance = fact.assessment_basis ===
      "equipment_integrity_verification";
    if (assurance) {
      assuranceTotalFK += score;
      assuranceTotalM5 += m5score;
      assuranceFindingCount += 1;
    } else {
      totalFK += score;
      totalM5 += m5score;
      activeFindingCount += 1;
      if (rank[fkB] > rank[highestFK]) highestFK = fkB;
      if (rank[m5B] > rank[highestM5]) highestM5 = m5B;
    }
    const mutations: Array<Record<string, unknown>> = [];
    const reasonCodes = [...fact.reasonCodes];
    if (probability.reasonCode) {
      mutations.push({
        field: "fk_probability",
        before: P_BY_BARRIER[fact.barrier_state],
        after: p,
        reason_code: probability.reasonCode,
      });
      reasonCodes.push(probability.reasonCode);
    }
    if (frequency.reasonCode) {
      mutations.push({
        field: "fk_frequency",
        before: F_BY_BASIS[fact.frequency_basis],
        after: frequency.value,
        reason_code: frequency.reasonCode,
      });
      reasonCodes.push(frequency.reasonCode);
    }
    if (severity.reasonCode) {
      mutations.push({
        field: "fk_severity",
        before: S_BY_CONSEQUENCE[fact.consequence_class],
        after: s,
        reason_code: severity.reasonCode,
      });
      reasonCodes.push(severity.reasonCode);
    }
    const scorePolicyReasonCodes = [
      probability.reasonCode,
      frequency.reasonCode,
      severity.reasonCode,
    ].filter((reason): reason is string => reason !== null);
    const scorePolicyAdjusted = scorePolicyReasonCodes.length > 0;
    const verificationReasonCodes = fieldVerificationReasonCodes(
      fact,
      frequency,
    );
    const needsVerification = verificationReasonCodes.length > 0;
    reasonCodes.push(...verificationReasonCodes);
    if (needsVerification && !fact.verification.model_required) {
      mutations.push({
        field: "needs_field_verification",
        before: false,
        after: true,
        reason_code: "verification_required_by_evidence_policy",
      });
      reasonCodes.push("verification_required_by_evidence_policy");
    }
    const residualP = residualProbability(p);
    reasonCodes.push("residual_not_reduced_without_control_confirmation");
    const measures = renderControls(
      fact,
      language,
      sectorProfile,
      sectorContext.controlPreferencesEnabled !== false,
    );
    const ordinal = index + 1;
    const confidence = confidenceValue(fact);
    const taxonomy = resolveFindingTaxonomy(fact);
    lineage.push({
      fact_trace_id: fact.traceID,
      final_ordinal: ordinal,
      source_photo_indices: fact.sourcePhotoIndices,
      evidence_regions: fact.evidenceRegions,
      semantic_inputs: {
        assessment_basis: fact.assessment_basis,
        mechanism_code: fact.mechanism_code,
        barrier_state: fact.barrier_state,
        frequency_basis: fact.frequency_basis,
        consequence_class: fact.consequence_class,
        model_barrier_state: fact.barrier_state,
        model_frequency_basis: fact.frequency_basis,
        scoring_frequency_basis: frequency.finalBasis,
        sector_id: sectorProfile?.sectorId ?? null,
        sector_profile_version: sectorProfile ? SECTOR_PROFILE_VERSION : null,
        sector_default_frequency: frequency.sectorDefaultF,
        sector_modifier_code: frequency.modifierCode,
        model_consequence_class: fact.consequence_class,
        credible_event_path: fact.credible_event_path,
        taxonomy_version: FINDING_TAXONOMY_VERSION,
        category_code: taxonomy.categoryCode,
        equipment_group_code: taxonomy.equipmentGroupCode,
        assessment_section: taxonomy.assessmentSection,
        model_verification_required: fact.verification.model_required,
        model_verification_reason_code: fact.verification.reason_code || null,
      },
      score_output: {
        fk_probability: p,
        fk_frequency: f,
        fk_severity: s,
        fk_score: score,
        m5_probability: m5p,
        m5_severity: m5s,
        m5_score: m5score,
        residual_fk_probability: residualP,
        residual_fk_frequency: f,
        residual_fk_severity: s,
        needs_field_verification: needsVerification,
        field_verification_reason_codes: verificationReasonCodes,
        score_policy_adjusted: scorePolicyAdjusted,
        score_policy_reason_codes: scorePolicyReasonCodes,
      },
      mutations,
      reason_codes: [...new Set(reasonCodes)],
    });
    const sourceObservations = fact.evidenceRegions.map((item) => ({
      photo_index: item.photo_index,
      observation: stripDirectImageAddress(item.cues.join("; ")).slice(0, 600),
    }));
    return {
      ordinal,
      title: titles[index],
      category: renderCategory(fact, language),
      description: renderDescription(fact, language),
      recommended_action: String(measures[0]?.text ?? ""),
      recommended_measures: measures,
      references_text: renderReferences(
        fact,
        language,
        plan,
        referenceContext,
      ),
      root_cause_text: renderRootCause(fact, language),
      confidence,
      needs_field_verification: needsVerification,
      field_verification_reason_codes: verificationReasonCodes,
      score_policy_adjusted: scorePolicyAdjusted,
      score_policy_reason_codes: scorePolicyReasonCodes,
      taxonomy_version: FINDING_TAXONOMY_VERSION,
      category_code: taxonomy.categoryCode,
      equipment_group_code: taxonomy.equipmentGroupCode,
      assessment_section: taxonomy.assessmentSection,
      ai_original_snapshot: {
        schema_version: SCHEMA_VERSION,
        fact_trace_id: fact.traceID,
        semantic_inputs: {
          assessment_basis: fact.assessment_basis,
          mechanism_code: fact.mechanism_code,
          barrier_state: fact.barrier_state,
          frequency_basis: fact.frequency_basis,
          consequence_class: fact.consequence_class,
          model_barrier_state: fact.barrier_state,
          model_frequency_basis: fact.frequency_basis,
          scoring_frequency_basis: frequency.finalBasis,
          sector_id: sectorProfile?.sectorId ?? null,
          sector_profile_version: sectorProfile ? SECTOR_PROFILE_VERSION : null,
          sector_default_frequency: frequency.sectorDefaultF,
          sector_modifier_code: frequency.modifierCode,
          model_consequence_class: fact.consequence_class,
          model_verification_required: fact.verification.model_required,
          model_verification_reason_code: fact.verification.reason_code || null,
        },
        score_output: {
          p,
          f,
          s,
          m5p,
          m5s,
          needs_field_verification: needsVerification,
          field_verification_reason_codes: verificationReasonCodes,
          score_policy_adjusted: scorePolicyAdjusted,
          score_policy_reason_codes: scorePolicyReasonCodes,
        },
        taxonomy: {
          version: FINDING_TAXONOMY_VERSION,
          category_code: taxonomy.categoryCode,
          equipment_group_code: taxonomy.equipmentGroupCode,
          assessment_section: taxonomy.assessmentSection,
        },
        mutations,
        reason_codes: [...new Set(reasonCodes)],
      },
      display_group: taxonomy.equipmentGroupCode,
      display_order: ordinal,
      source_photo_indices: fact.sourcePhotoIndices,
      source_photo_observations: sourceObservations,
      finding_budget_policy: {
        engine: "vnext",
        minimum_pressure: false,
        final_limit: null,
      },
      ai_confidence: confidence,
      fk_probability: p,
      fk_frequency: f,
      fk_severity: s,
      fk_band: fkB,
      m5_probability: m5p,
      m5_severity: m5s,
      m5_band: m5B,
      residual_fk_probability: residualP,
      residual_fk_frequency: f,
      residual_fk_severity: s,
      residual_m5_probability: m5Probability(residualP),
      residual_m5_severity: m5s,
      bounding_box: (() => {
        const region = fact.evidenceRegions[0]?.region as
          | { x: number; y: number; width: number; height: number }
          | undefined;
        return region
          ? { x: region.x, y: region.y, w: region.width, h: region.height }
          : null;
      })(),
    };
  });

  const photoCount = photoResults.length;
  const rawByPhoto: Record<string, number> = {};
  const validByPhoto: Record<string, number> = {};
  for (const result of photoResults) {
    rawByPhoto[String(result.photoIndex)] = result.output._schema_diagnostics_v1
      ?.raw_fact_count ?? result.output.hazard_facts.length;
    validByPhoto[String(result.photoIndex)] = evidenceValid.filter((fact) =>
      fact.photo_index === result.photoIndex
    ).length;
  }
  const rawFactCount = Object.values(rawByPhoto).reduce(
    (sum, count) => sum + count,
    0,
  );
  const primaryAggregated = aggregated.filter((fact) =>
    !fact.traceID.startsWith("targeted:")
  );
  const targetedAggregated = aggregated.filter((fact) =>
    fact.traceID.startsWith("targeted:")
  );
  const crossPhotoMergeCount =
    mergeLedger.filter((entry) =>
      entry.reason_code === "cross_photo_duplicate" &&
      !String(entry.merged_fact_trace_id ?? "").startsWith("targeted:")
    ).length;
  const primaryAggByPhoto = countsByPhoto(primaryAggregated, photoCount);
  const aggByPhoto = countsByPhoto(aggregated, photoCount);
  const stages = [
    stage("provider_parsed_fact", rawFactCount, rawByPhoto),
    stage(
      "schema_valid_fact",
      parsedFacts.length,
      Object.fromEntries(photoResults.map((result) => [
        String(result.photoIndex),
        result.output.hazard_facts.length,
      ])),
      rawFactCount,
    ),
    stage(
      "evidence_valid_fact",
      evidenceValid.length,
      validByPhoto,
      parsedFacts.length,
    ),
    stage(
      "asset_assurance_added_fact",
      evidenceValid.length + assuranceFacts.length,
      Object.fromEntries(photoResults.map((result) => [
        String(result.photoIndex),
        (validByPhoto[String(result.photoIndex)] ?? 0) +
        assuranceFacts.filter((fact) => fact.photo_index === result.photoIndex)
          .length,
      ])),
      evidenceValid.length,
    ),
    stage(
      "atomic_fact",
      evidenceValid.length + assuranceFacts.length,
      Object.fromEntries(photoResults.map((result) => [
        String(result.photoIndex),
        (validByPhoto[String(result.photoIndex)] ?? 0) +
        assuranceFacts.filter((fact) => fact.photo_index === result.photoIndex)
          .length,
      ])),
      evidenceValid.length + assuranceFacts.length,
    ),
    stage(
      "within_photo_dedup",
      primaryAggregated.length + crossPhotoMergeCount,
      primaryAggByPhoto,
      evidenceValid.length + assuranceFacts.length,
    ),
    stage(
      "cross_photo_pre_dedup",
      primaryAggregated.length + crossPhotoMergeCount,
      primaryAggByPhoto,
      primaryAggregated.length + crossPhotoMergeCount,
    ),
    stage(
      "cross_photo_post_dedup",
      primaryAggregated.length,
      primaryAggByPhoto,
      primaryAggregated.length + crossPhotoMergeCount,
    ),
    stage(
      "targeted_added_fact",
      primaryAggregated.length + targetedAggregated.length,
      aggByPhoto,
      primaryAggregated.length,
    ),
    stage("scored_fact", findings.length, aggByPhoto, aggregated.length),
    stage("persistence_final", findings.length, aggByPhoto, findings.length),
  ];
  const sectorModuleResult = sectorModulePolicy(
    photoResults,
    sectorProfile,
    aggregated.filter((fact) =>
      fact.assessment_basis !== "equipment_integrity_verification"
    ),
  );
  const moduleAudits = sectorModuleResult.moduleAudits;
  const signals = photoResults.flatMap((result) =>
    result.output.inspection_signals.map((signal, signalIndex) => ({
      ...signal,
      signal_id: canonicalInspectionSignalID(
        signal.signal_id,
        result.photoIndex,
        signalIndex,
      ),
      status: "internal",
    }))
  );
  const componentCoverageAudit = photoResults.flatMap((result) =>
    componentCoverage(
      result,
      aggregated.filter((fact) => fact.photo_index === result.photoIndex),
      rejectedFactCoverage.filter((entry) =>
        entry.fact.photo_index === result.photoIndex
      ),
    )
  );
  const sectorComponentCoverageAudit = sectorCriticalEquipmentCoverage(
    photoResults,
    aggregated,
    rejectedFactCoverage,
    sectorProfile,
  );
  const photoSummaries = photoResults.map((result) => {
    const finalCount = findings.filter((finding) =>
      finding.source_photo_indices.includes(result.photoIndex)
    ).length;
    return {
      photo_id: result.photoID,
      photo_sequence_index: result.photoIndex,
      scene_summary: result.output.scene_inventory.map((item) =>
        `${item.equipment_family}/${item.component}`
      ).slice(0, 12).join(", "),
      candidate_findings_count: result.output.hazard_facts.length,
      generated_findings_count: finalCount,
      highest_risk_level: null,
      ai_confidence: null,
      coverage_status: finalCount > 0 ? "covered" : "no_positive_evidence",
      coverage_gap_reason: finalCount > 0
        ? null
        : "no_accepted_affirmative_cue",
      target_findings_min: null,
      target_findings_max: null,
      raw_summary: {
        engine: "vnext",
        inventory_count: result.output.scene_inventory.length,
        module_count: result.output.module_audit.length,
        schema_diagnostics: result.output._schema_diagnostics_v1 ?? null,
        component_coverage: componentCoverage(
          result,
          aggregated.filter((fact) =>
            fact.photo_index === result.photoIndex
          ),
          rejectedFactCoverage.filter((entry) =>
            entry.fact.photo_index === result.photoIndex
          ),
        ),
        provider: result.provider,
        model: result.model,
        raw_fact_count: result.output._schema_diagnostics_v1?.raw_fact_count ??
          result.output.hazard_facts.length,
        schema_valid_fact_count: result.output.hazard_facts.length,
        final_fact_count: finalCount,
      },
    };
  });
  const qualityTrace = {
    trace_version: 3,
    engine: "vnext",
    quality_policy_versions: {
      structured_visible_barrier_evidence: 1,
      high_consequence_rejection_guard: 1,
      evidence_rejection_ratio_alert: 1,
      asset_assurance_single_asset: 1,
      crane_taxonomy: 1,
      scaffold_entity_relationship: 1,
      high_hazard_critical_coverage: 2,
      provider_json_syntax_repair: 1,
      provider_retry_checkpoint: 1,
      public_copy_renderer: 10,
      quality_trace_stage: 19,
    },
    asset_assurance_catalog_version: ASSET_ASSURANCE_CATALOG_VERSION,
    asset_assurance_identity_rejections: assuranceResult.identityRejections,
    finding_taxonomy_version: FINDING_TAXONOMY_VERSION,
    stages,
    rejection_ledger: rejectionLedger,
    merge_ledger: mergeLedger,
    schema_diagnostics: photoResults.map((result) => ({
      photo_index: result.photoIndex,
      provider: result.provider,
      model: result.model,
      diagnostics: result.output._schema_diagnostics_v1 ?? null,
    })),
    component_coverage: componentCoverageAudit,
    evidence_rejection_alert: evidenceRejectionAlert,
    high_consequence_rejection_guard: {
      unresolved_count: rejectedHighConsequenceFacts.length,
      report_note_emitted: rejectedHighConsequenceFacts.length > 0,
      reason_code: rejectedHighConsequenceFacts.length > 0
        ? "high_consequence_candidates_require_field_confirmation"
        : null,
      facts: rejectedHighConsequenceFacts.map((entry) => ({
        fact_trace_id: entry.traceID,
        photo_index: entry.fact.photo_index,
        mechanism_code: entry.fact.mechanism_code,
        consequence_class: entry.fact.consequence_class,
        rejection_reason_code: entry.reasonCode,
      })),
    },
    sector_profile: {
      active_sector: sectorProfile?.sectorId ?? null,
      sector_source: sectorContext.source ?? "none",
      profile_version: sectorProfile ? SECTOR_PROFILE_VERSION : null,
      request_database_mismatch: sectorContext.requestMismatch === true,
      mismatch_reason_code: sectorContext.requestMismatch === true
        ? "analysis_sector_request_database_mismatch"
        : null,
      feature_flags: {
        profile_enabled: sectorContext.profileEnabled !== false,
        frequency_prior_enabled: sectorFrequencyPriorEnabled,
        control_preferences_enabled: Boolean(sectorProfile) &&
          sectorContext.controlPreferencesEnabled !== false,
        negative_rules_enabled: sectorNegativeRulesEnabled,
        regulation_anchors_enabled: Boolean(sectorProfile) &&
          sectorContext.regulationAnchorsEnabled === true,
      },
      regulation_anchors_rendered: false,
      regulation_anchor_reason_code: "sector_regulation_anchors_disabled",
      mandatory_module_outcomes: sectorModuleResult.outcomeTrace,
      mandatory_module_omissions: sectorModuleResult.omissions,
      priority_module_outcomes: photoResults.flatMap((result) =>
        (sectorProfile?.priorityModules ?? []).map((moduleID) => {
          const omitted = result.output._schema_diagnostics_v1
            ?.missing_module_ids.includes(moduleID) === true;
          return {
            photo_index: result.photoIndex,
            module_id: moduleID,
            legacy_module_audit_status: omitted
              ? null
              : result.output.module_audit.find((audit) =>
                audit.module_id === moduleID
              )?.status ?? "not_applicable",
            omitted,
            reason_code: omitted ? "sector_priority_module_omitted" : null,
          };
        })
      ),
      priority_module_omissions: photoResults.flatMap((result) =>
        (sectorProfile?.priorityModules ?? []).filter((moduleID) =>
          result.output._schema_diagnostics_v1?.missing_module_ids.includes(
            moduleID,
          ) === true
        ).map((moduleID) => ({
          photo_index: result.photoIndex,
          module_id: moduleID,
          reason_code: "sector_priority_module_omitted",
        }))
      ),
      frequency_evidence: photoResults.map((result) => ({
        photo_index: result.photoIndex,
        model_frequency_bases: [
          ...new Set(
            result.output.hazard_facts.map((fact) => fact.frequency_basis),
          ),
        ],
        sector_default_f: sectorProfile?.frequencyPrior.defaultF ?? null,
        accepted_modifier: modifierByPhoto.get(result.photoIndex) ?? null,
        submitted_sector_context_evidence:
          result.output.sector_context_evidence,
      })),
      critical_equipment_coverage: sectorComponentCoverageAudit,
      triggered_negative_rule_codes: [
        ...new Set(rejectionLedger.flatMap((entry) => {
          const codes = [
            entry.reason_code,
            ...(Array.isArray(entry.reason_codes) ? entry.reason_codes : []),
          ].map(String);
          return codes.filter((code) => code.startsWith("sector_negative_"));
        })),
      ],
    },
    score_totals: {
      active_fk: totalFK,
      active_m5: totalM5,
      assurance_fk: assuranceTotalFK,
      assurance_m5: assuranceTotalM5,
      active_count: activeFindingCount,
      assurance_count: assuranceFindingCount,
      assurance_excluded_from_analysis_total: true,
    },
    verification_summary: {
      total: findings.length,
      required_count:
        findings.filter((finding) => finding.needs_field_verification === true)
          .length,
      active_required_count:
        findings.filter((finding) =>
          finding.assessment_section === "observed_risk" &&
          finding.needs_field_verification === true
        ).length,
      assurance_required_count:
        findings.filter((finding) =>
          finding.assessment_section === "equipment_assurance" &&
          finding.needs_field_verification === true
        ).length,
      score_policy_adjusted_count:
        findings.filter((finding) => finding.score_policy_adjusted === true)
          .length,
    },
    final_count: findings.length,
  };
  const tr = isTurkish(language);
  return {
    findings,
    analysisResult: {
      status_message: tr ? "Analiz tamamlandı." : "Analysis completed.",
      ai_summary: tr
        ? `${photoCount} fotoğrafta ${activeFindingCount} kanıtlı risk bulgusu ve ${assuranceFindingCount} ekipman güvence maddesi oluşturuldu.${
          rejectedHighConsequenceFacts.length > 0
            ? ` Ayrıca ${rejectedHighConsequenceFacts.length} yüksek sonuçlu aday görüntüden kesinleştirilemedi; saha teyidiyle öncelikli olarak kontrol edilmelidir.`
            : ""
        }`
        : `${activeFindingCount} evidence-backed risk findings and ${assuranceFindingCount} equipment-assurance items were produced across ${photoCount} photos.${
          rejectedHighConsequenceFacts.length > 0
            ? ` In addition, ${rejectedHighConsequenceFacts.length} high-consequence candidate(s) could not be resolved from the image and require priority field verification.`
            : ""
        }`,
      total_score_fk: totalFK,
      total_score_m5: totalM5,
      highest_band_fk: highestFK,
      highest_band_m5: highestM5,
      hidden_or_rejected_findings_count: rejectionLedger.length,
      max_findings_per_photo: 50,
      max_findings_total: null,
      consume_analysis_quota: true,
      ai_models_used: [...new Set(photoResults.map((result) => result.model))],
      raw_ai_response: {
        _engine: "vnext-v3",
        _quality_trace_v3: qualityTrace,
        _input_audit: {
          visual_input_mode: "legacy_flattened_1536",
          plan,
          user_extra_questions: false,
          mixed_provider: new Set(
            photoResults.map((result) => `${result.provider}/${result.model}`),
          ).size > 1,
          photo_provider_routes: photoResults.map((result) => ({
            photo_index: result.photoIndex,
            provider: result.provider,
            model: result.model,
          })),
        },
      },
    },
    photoSummaries,
    factLineage: lineage,
    moduleAudits,
    inspectionSignals: signals,
    qualityTrace,
  };
}

export function selectTargetedSignal(
  photoResults: PhotoResult[],
  sectorID: SectorID | null = null,
  multiPhotoHighHazardCoverageEnabled = true,
): InspectionSignalV1 | null {
  return selectTargetedDecision(
    photoResults,
    sectorID,
    multiPhotoHighHazardCoverageEnabled,
  ).signal;
}

export type TargetedSelectionDecision = {
  status: "selected" | "not_needed";
  signal: InspectionSignalV1 | null;
  candidate_count: number;
  candidates: Array<Record<string, unknown>>;
  screened_facts: Array<Record<string, unknown>>;
};

const HIGH_HAZARD_GUARDRAIL_COVERAGE_REASON =
  "high_hazard_guardrail_critical_coverage";

function highHazardGuardrailCoverageCandidate(
  photoResults: PhotoResult[],
  profile: SectorProfileV2 | null,
): InspectionSignalV1 | null {
  if (
    photoResults.length < 1 || !profile ||
    !["very_hazardous", "hazardous_or_very_hazardous"].includes(
      profile.typicalHazardClass,
    )
  ) return null;

  const visibleGuardrails = photoResults.flatMap((result) =>
    result.output.scene_inventory.flatMap((item) => {
      const context = normalized(
        `${item.equipment_family} ${item.component} ${item.visible_condition_summary}`,
      );
      if (!GUARDRAIL_COMPONENT_PATTERN.test(context)) return [];
      const wholeComponentNotVisible =
        /(?:korkuluk|guardrail|railing).{0,36}(?:gorunmuyor|not visible|out of frame)/u
          .test(context);
      if (wholeComponentNotVisible) return [];
      const linkedGuardrailFacts = result.output.hazard_facts.filter((fact) =>
        fact.entity.entity_ref === item.entity_ref &&
        GUARDRAIL_COMPONENT_PATTERN.test(normalized(
          `${fact.entity.equipment_family} ${fact.entity.component} ${fact.observed_condition.condition_code} ${fact.observed_condition.short_text}`,
        ))
      );
      const anomalyOrUnresolved =
        /(?:eksik|yok|missing|absent|acik kenar|open edge|bosluk|gap|net degil|unclear|secilemiyor|unresolved|gorunmuyor|not visible)/u
          .test(context);
      const unresolvedLinkedFact = linkedGuardrailFacts.some((fact) =>
        evidenceRejectionReason(fact) !== null
      );
      const concreteGuardrailSignal = result.output.inspection_signals.some(
        (signal) =>
          GUARDRAIL_COMPONENT_PATTERN.test(
            normalized(signal.affirmative_cues.join(" ")),
          ) && targetedSignalHasConcreteCue(signal),
      );
      const actionableHeightModule = result.output.mandatory_module_outcomes
        .some((outcome) =>
          outcome.status === "actionable" &&
          /(?:height|fall|work_access|structural)/u.test(
            normalized(outcome.module_id),
          )
        );
      if (
        !anomalyOrUnresolved && !unresolvedLinkedFact &&
        !concreteGuardrailSignal && !actionableHeightModule
      ) return [];
      return [{
        result,
        item,
        score: (unresolvedLinkedFact ? 30 : 0) +
          (anomalyOrUnresolved ? 20 : 0),
      }];
    })
  ).sort((a, b) => b.score - a.score);
  const selected = visibleGuardrails[0];
  if (!selected) return null;

  return {
    signal_id:
      `critical-coverage:guardrail:${selected.result.photoIndex}:${selected.item.entity_ref}`,
    photo_index: selected.result.photoIndex,
    // Scene inventory has no trustworthy region. Keep the provider call
    // bounded by component family instead: it may scan only guardrails in the
    // selected photo and every returned fact must still be locally boxed.
    evidence_region: {
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      is_global: true,
    },
    affirmative_cues: [
      `${selected.item.equipment_family} ${selected.item.component}: ${selected.item.visible_condition_summary}`,
    ],
    potential_consequence_class: "permanent_disability",
    reason_code: HIGH_HAZARD_GUARDRAIL_COVERAGE_REASON,
  };
}

export function selectTargetedDecision(
  photoResults: PhotoResult[],
  sectorID: SectorID | null = null,
  multiPhotoHighHazardCoverageEnabled = true,
): TargetedSelectionDecision {
  const sectorProfile = getSectorProfile(sectorID);
  const severity: Record<ConsequenceClass, number> = {
    negligible: 1,
    first_aid: 2,
    serious_reversible: 3,
    permanent_disability: 4,
    single_fatality: 5,
    multiple_fatality_major_environmental: 6,
  };
  const candidates: Array<{
    signal: InspectionSignalV1;
    priority: number;
    sectorCritical: boolean;
  }> = [];
  const screenedFacts: Array<Record<string, unknown>> = [];
  for (const result of photoResults) {
    const noPrimaryFacts = result.output.hazard_facts.every((fact) =>
      evidenceRejectionReason(fact) !== null
    );
    for (const signal of result.output.inspection_signals) {
      const consequenceRank = severity[signal.potential_consequence_class];
      const whitelistedAnomaly = targetedSignalHasPositiveAnomaly(signal);
      const zeroFactConcreteSignal = noPrimaryFacts &&
        targetedSignalHasConcreteCue(signal);
      const signalContext = signal.affirmative_cues.join(" ");
      const sectorCritical = Boolean(sectorProfile) &&
        result.output.scene_inventory.some((item) =>
          sectorEquipmentForEntity(
            sectorProfile!,
            item.equipment_family,
            item.component,
          ).some((equipment) =>
            sectorCheckCodesForEntity(
              equipment,
              signalContext,
              signalContext,
            ).length > 0
          )
        );
      if (!zeroFactConcreteSignal && consequenceRank < 3) continue;
      if (!whitelistedAnomaly && !zeroFactConcreteSignal && !sectorCritical) {
        continue;
      }
      candidates.push({
        signal,
        // A photo that otherwise produced no fact receives first access to
        // the single targeted call. This catches serious visible detail gaps
        // without creating a second general analysis.
        priority: (sectorCritical ? 240 : zeroFactConcreteSignal ? 200 : 0) +
          Math.max(consequenceRank, 3),
        sectorCritical,
      });
    }
    for (const fact of result.output.hazard_facts) {
      const consequenceRank = severity[fact.consequence_class];
      const rejectionReason = evidenceRejectionReason(fact);
      const targetedReason =
        rejectionReason && hasStructuredCriticalBarrierFields(fact) &&
          factIsOccludedOrOutOfFrame(fact)
          ? "critical_barrier_visibility_requires_confirmation"
          : rejectionReason === "uncertain_condition_requires_confirmation" &&
              factMayBenefitFromTargetedConfirmation(fact)
          ? "uncertain_condition_requires_confirmation"
          : rejectionReason === "absence_only_claim" &&
              (
                isCriticalHardwareGeometryCandidate(fact) ||
                isCriticalSafetyHardwareAbsenceCandidate(fact)
              )
          ? "critical_hardware_absence_requires_geometry_confirmation"
          : rejectionReason && isHighConsequencePersonFact(fact) &&
              targetedSignalHasPositiveAnomaly({
                signal_id: `rejected-high-consequence:${fact.fact_id}`,
                photo_index: fact.photo_index,
                evidence_region: fact.evidence.normalized_region,
                affirmative_cues: fact.evidence.affirmative_cues,
                potential_consequence_class: fact.consequence_class,
                reason_code:
                  "rejected_high_consequence_fact_requires_confirmation",
              })
          ? "rejected_high_consequence_fact_requires_confirmation"
          : null;
      if (rejectionReason) {
        screenedFacts.push({
          photo_index: fact.photo_index,
          fact_id: fact.fact_id,
          rejection_reason_code: rejectionReason,
          targeted_eligible: consequenceRank >= 3 && Boolean(targetedReason),
          targeted_reason_code: targetedReason,
        });
      }
      if (consequenceRank < 3 || !targetedReason) continue;
      const sectorCritical = Boolean(sectorProfile) &&
        sectorEquipmentForEntity(
            sectorProfile!,
            fact.entity.equipment_family,
            fact.entity.component,
          ).length > 0;
      candidates.push({
        signal: {
          signal_id: `uncertain-fact:${fact.fact_id}`,
          photo_index: fact.photo_index,
          evidence_region: fact.evidence.normalized_region,
          affirmative_cues: fact.evidence.affirmative_cues,
          potential_consequence_class: fact.consequence_class,
          reason_code: targetedReason,
        },
        priority: (targetedReason ===
              "rejected_high_consequence_fact_requires_confirmation" ||
            targetedReason ===
              "critical_barrier_visibility_requires_confirmation"
          ? 210
          : targetedReason ===
              "critical_hardware_absence_requires_geometry_confirmation"
          ? 120
          : 100) + (sectorCritical ? 80 : 0) + consequenceRank,
        sectorCritical,
      });
    }
  }
  const guardrailCoverage = multiPhotoHighHazardCoverageEnabled
    ? highHazardGuardrailCoverageCandidate(photoResults, sectorProfile)
    : null;
  if (guardrailCoverage) {
    candidates.push({
      signal: guardrailCoverage,
      // Concrete sector-critical signals still win (>=243). This bounded
      // coverage pass wins over generic uncertainty when the primary calls
      // otherwise leave an elevated barrier family incompletely resolved.
      priority: 230,
      sectorCritical: true,
    });
  }
  const ranked = candidates.sort((a, b) => b.priority - a.priority);
  const signal = ranked[0]?.signal ?? null;
  return {
    status: signal ? "selected" : "not_needed",
    signal,
    candidate_count: ranked.length,
    candidates: ranked.map((candidate) => ({
      signal_id: candidate.signal.signal_id,
      photo_index: candidate.signal.photo_index,
      reason_code: candidate.signal.reason_code,
      priority: candidate.priority,
      sector_critical_component: candidate.sectorCritical,
    })),
    screened_facts: screenedFacts,
  };
}

export function targetedSourceFacts(
  photoResults: PhotoResult[],
  signal: InspectionSignalV1,
): HazardFactV3[] {
  if (!signal.signal_id.startsWith("uncertain-fact:")) return [];
  const factID = signal.signal_id.slice("uncertain-fact:".length);
  const source = photoResults.find((result) =>
    result.photoIndex === signal.photo_index
  );
  const primary = source?.output.hazard_facts.find((fact) =>
    fact.fact_id === factID
  );
  if (!primary) return [];
  if (
    signal.reason_code !==
      "critical_hardware_absence_requires_geometry_confirmation"
  ) return [primary];
  const siblings = (source?.output.hazard_facts ?? []).filter((fact) =>
    fact.fact_id !== primary.fact_id &&
    evidenceRejectionReason(fact) === "absence_only_claim" &&
    (
      isCriticalHardwareGeometryCandidate(fact) ||
      isCriticalSafetyHardwareAbsenceCandidate(fact)
    ) &&
    normalized(fact.entity.equipment_family) ===
      normalized(primary.entity.equipment_family) &&
    normalized(fact.entity.component) ===
      normalized(primary.entity.component) &&
    fact.mechanism_code === primary.mechanism_code
  );
  return [primary, ...siblings].slice(0, 2);
}

function targetedSignalComponentFamily(
  signal: InspectionSignalV1,
): string | null {
  const context = normalized(signal.affirmative_cues.join(" "));
  if (/(?:hook|kanca)/u.test(context) && /(?:latch|mandal)/u.test(context)) {
    return "hook_latch";
  }
  if (/(?:pin|pim)/u.test(context) && /(?:retainer|segman)/u.test(context)) {
    return "pin_retainer";
  }
  return null;
}

export function targetedSourceSignals(
  photoResults: PhotoResult[],
  signal: InspectionSignalV1,
): InspectionSignalV1[] {
  const family = targetedSignalComponentFamily(signal);
  if (!family) return [signal];
  const source = photoResults.find((result) =>
    result.photoIndex === signal.photo_index
  );
  const siblings = (source?.output.inspection_signals ?? []).filter((item) =>
    item.signal_id !== signal.signal_id &&
    item.photo_index === signal.photo_index &&
    targetedSignalComponentFamily(item) === family
  );
  // One bounded targeted image call may inspect at most two independently
  // localized sibling components. This closes the two-hook signal path
  // without turning the pass into a second general analysis.
  return [signal, ...siblings].slice(0, 2);
}

export function constrainTargetedFacts(
  photoResults: PhotoResult[],
  signal: InspectionSignalV1,
  facts: HazardFactV3[],
): HazardFactV3[] {
  return constrainTargetedFactsWithTrace(photoResults, signal, facts).facts;
}

export type TargetedFactRejection = {
  fact_id: string;
  photo_index: number;
  reason_code: string;
};

export function constrainTargetedFactsWithTrace(
  photoResults: PhotoResult[],
  signal: InspectionSignalV1,
  facts: HazardFactV3[],
): { facts: HazardFactV3[]; rejections: TargetedFactRejection[] } {
  const sourceFacts = targetedSourceFacts(photoResults, signal);
  const sourceSignals = targetedSourceSignals(photoResults, signal);
  const guardrailCoverage = signal.reason_code ===
    HIGH_HAZARD_GUARDRAIL_COVERAGE_REASON;
  const accepted: HazardFactV3[] = [];
  const rejections: TargetedFactRejection[] = [];
  for (const fact of facts) {
    let rejectionReason: string | null = null;
    if (fact.photo_index !== signal.photo_index) {
      rejectionReason = "targeted_photo_scope_mismatch";
    }
    const evidenceReason = targetedEvidenceRejectionReason(fact);
    if (!rejectionReason && evidenceReason !== null) {
      rejectionReason = evidenceReason;
    }
    if (!rejectionReason && guardrailCoverage) {
      const context = normalized([
        fact.entity.equipment_family,
        fact.entity.component,
        fact.observed_condition.condition_code,
        fact.observed_condition.short_text,
        ...fact.evidence.affirmative_cues,
      ].join(" "));
      const locallyConfirmedGuardrail =
        fact.assessment_basis === "observed_nonconformity" &&
        !fact.evidence.normalized_region.is_global &&
        GUARDRAIL_COMPONENT_PATTERN.test(context) &&
        ["fall_from_height", "falling_object"].includes(
          fact.mechanism_code,
        ) &&
        fact.confidence.entity === "high" &&
        fact.confidence.condition === "high" &&
        fact.confidence.localization === "high";
      if (!locallyConfirmedGuardrail) {
        rejectionReason = "targeted_guardrail_coverage_scope_mismatch";
      }
    }
    if (sourceFacts.length > 0) {
      const sourceMatch = sourceFacts.some((sourceFact) => {
        if (
          !regionsOverlap(
            sourceFact.evidence.normalized_region,
            fact.evidence.normalized_region,
          )
        ) return false;
        const sameEntity = normalized(sourceFact.entity.entity_ref) ===
          normalized(fact.entity.entity_ref);
        const sameComponent = normalized(
              sourceFact.entity.equipment_family,
            ) === normalized(fact.entity.equipment_family) &&
          normalized(sourceFact.entity.component) ===
            normalized(fact.entity.component);
        return (sameEntity || sameComponent) &&
          sourceFact.mechanism_code === fact.mechanism_code;
      });
      if (!rejectionReason && !sourceMatch) {
        rejectionReason = "targeted_source_fact_scope_mismatch";
      }
    } else if (
      !sourceSignals.some((sourceSignal) =>
        regionsOverlap(
          sourceSignal.evidence_region,
          fact.evidence.normalized_region,
        )
      )
    ) {
      if (!rejectionReason) {
        rejectionReason = "targeted_signal_region_mismatch";
      }
    } else if (
      !targetedSignalHasPositiveAnomaly({
        ...signal,
        affirmative_cues: fact.evidence.affirmative_cues,
      })
    ) {
      if (!rejectionReason) {
        rejectionReason = "targeted_positive_anomaly_not_confirmed";
      }
    }
    if (rejectionReason) {
      rejections.push({
        fact_id: fact.fact_id,
        photo_index: fact.photo_index,
        reason_code: rejectionReason,
      });
    } else {
      accepted.push(fact);
    }
  }
  return { facts: accepted, rejections };
}

const TARGETED_POSITIVE_ANOMALY_PATTERNS = [
  /(?:catlak|kiril|yirtil|kesik|crack|fracture|tear)/u,
  /(?:asin|surtun|abras|rubb|wear)/u,
  /(?:sizinti|kacak|dokuntu|leak|spill)/u,
  /(?:deform|bukul|ezil|corrosion|korozy|paslan)/u,
  /(?:gevse|bosluk|yerinden cik|displace|loose|shifted)/u,
  /(?:acik kenar|acikta kalan kenar|bos yuva|bos delik|acik delik|empty slot|open edge|open hole)/u,
  /(?:korunmasiz hareketli|acik iletken|exposed conductor|unguarded moving)/u,
  /(?:daginik|engel|clutter|obstruction)/u,
  /(?:dengesiz|stabilite|unstable|instability)/u,
  /(?:hareketli.{0,24}yak.n|yak.n.{0,24}hareketli|guzergah.{0,24}(?:surtun|temas)|routing.{0,24}(?:moving|rub|contact))/u,
  /(?:(?:keskin|sicak).{0,20}temas|contact.{0,20}(?:sharp|hot)\s+surface)/u,
  /(?:yanik|is lekesi|scorch|burn mark)/u,
];

function targetedSignalHasPositiveAnomaly(signal: InspectionSignalV1): boolean {
  const cues = normalized(signal.affirmative_cues.join(" "));
  if (!cues) return false;
  return TARGETED_POSITIVE_ANOMALY_PATTERNS.some((pattern) =>
    pattern.test(cues)
  );
}

function targetedSignalHasConcreteCue(signal: InspectionSignalV1): boolean {
  return signal.affirmative_cues.some((cue) => {
    if (!normalized(cue)) return false;
    const uncertaintyOnly = CONDITION_UNCERTAINTY_PATTERNS.some((pattern) =>
      pattern.test(cue)
    );
    const missingOnly = ABSENCE_ONLY_PATTERNS.some((pattern) =>
      pattern.test(cue)
    ) || hasVisualAbsenceClaim(cue);
    return !uncertaintyOnly && !missingOnly;
  });
}

function isCriticalHardwareGeometryCandidate(fact: HazardFactV3): boolean {
  const hardwareContext = normalized([
    fact.entity.equipment_family,
    fact.entity.component,
    fact.observed_condition.condition_code,
    fact.observed_condition.short_text,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
  const safetyCriticalHardware = SAFETY_CRITICAL_HARDWARE_PATTERN.test(
    hardwareContext,
  );
  if (!safetyCriticalHardware) return false;
  const cues = normalized(fact.evidence.affirmative_cues.join(" "));
  if (
    !cues ||
    CONDITION_UNCERTAINTY_PATTERNS.some((pattern) =>
      pattern.test(fact.evidence.affirmative_cues.join(" "))
    )
  ) {
    return false;
  }
  const criticalMount =
    /(?:pivot|latch seat|mandal yatagi|mandal yuvasi|baglanti noktasi|mount|mounting point|retainer groove|segman kanali)/u;
  const visiblyEmpty = /(?:bos|empty|unoccupied|acik|open)/u;
  return (
    new RegExp(`${criticalMount.source}.{0,48}${visiblyEmpty.source}`, "u")
      .test(cues) ||
    new RegExp(`${visiblyEmpty.source}.{0,48}${criticalMount.source}`, "u")
      .test(cues)
  );
}

function isCriticalSafetyHardwareAbsenceCandidate(
  fact: HazardFactV3,
): boolean {
  if (
    fact.assessment_basis === "equipment_integrity_verification" ||
    fact.evidence.normalized_region.is_global ||
    fact.confidence.entity !== "high" ||
    fact.confidence.condition !== "high" ||
    fact.confidence.localization !== "high" ||
    fact.confidence.mechanism === "low"
  ) return false;
  const context = normalized([
    fact.entity.equipment_family,
    fact.entity.component,
    fact.observed_condition.condition_code,
    fact.observed_condition.short_text,
    ...fact.evidence.affirmative_cues,
  ].join(" "));
  const safetyCriticalHardware = SAFETY_CRITICAL_HARDWARE_PATTERN.test(context);
  const structuredAbsence =
    /(?:missing|absent|eksik|yok|bulunmuyor|not present)/u.test(context);
  const localizableGeometryCue =
    /(?:hook mouth|hook opening|kanca agzi|pivot|yatak|yuva|mount|baglanti noktasi|pin end|pim ucu|retainer groove|segman kanali|open gap|open edge|acik kenar|acikta kalan bosluk|acikta kalan kenar|korkuluk kesintisi|bariyer kesintisi)/u
      .test(normalized(fact.evidence.affirmative_cues.join(" ")));
  const excludedContext =
    /(?:ppe|kkd|helmet|baret|glove|eldiven|document|record|belge|kayit|etiket|label|certificate|sertifika)/u
      .test(context);
  return safetyCriticalHardware && structuredAbsence &&
    localizableGeometryCue && !excludedContext;
}

function factMayBenefitFromTargetedConfirmation(fact: HazardFactV3): boolean {
  if (!factRequiresTargetedConfirmation(fact)) return false;
  return targetedSignalHasPositiveAnomaly({
    signal_id: `uncertain-fact:${fact.fact_id}`,
    photo_index: fact.photo_index,
    evidence_region: fact.evidence.normalized_region,
    affirmative_cues: fact.evidence.affirmative_cues,
    potential_consequence_class: fact.consequence_class,
    reason_code: "uncertain_condition_requires_confirmation",
  });
}
