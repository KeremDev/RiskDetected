export const V4_ENGINE_VERSION = "vnext-v4";
export const V4_PROVIDER_CONTRACT_VERSION = "visual-claim-candidate-v1";
export const V4_DOMAIN_SCHEMA_VERSION = "safety-claim-v4.0";
export const V4_PROMPT_VERSION = "v4-vision-core-v10";
export const V4_ROUTER_VERSION = "claim-routing-v30";
export const V4_COVERAGE_VERSION = "critical-coverage-v3";
export const V4_ASSURANCE_VERSION = "assurance-topic-v2";
export const V4_STANDARDS_VERSION = "standards-registry-v1";
export const V4_QUALITY_TRACE_VERSION = "quality-trace-v4";
export const V4_REPORT_PROJECTION_VERSION = "compatibility-report-v4";

export const CORE_MODULE_IDS = [
  "people_exposure",
  "falls_falling_objects",
  "energy",
  "vehicles_mobile_equipment",
  "access_egress",
  "fire_explosion_release",
  "housekeeping_physical_contact",
] as const;

export const DYNAMIC_MODULE_IDS = [
  "work_at_height",
  "process_integrity",
  "lifting",
  "machinery",
  "logistics",
  "electrical",
  "confined_space",
  "hot_work",
  "excavation",
  "chemical",
  "combustible_dust",
  "biosecurity",
] as const;

export const MODULE_OUTCOMES = [
  "finding_present",
  "positive_control_present",
  "no_actionable_issue_visible",
  "unresolved_requires_verification",
  "not_assessable_due_to_image",
  "module_activation_false_positive",
] as const;

export type V4ModuleID =
  | typeof CORE_MODULE_IDS[number]
  | typeof DYNAMIC_MODULE_IDS[number];
export type ModuleOutcome = typeof MODULE_OUTCOMES[number];
export type EvidenceLevel = "E0" | "E1" | "E2" | "E3" | "E4" | "E5";
export type Criticality = "ordinary" | "serious" | "permanent" | "fatal";
export type SafetyItemClass =
  | "observed_finding"
  | "assurance_requirement"
  | "verification_request"
  | "positive_control"
  | "not_assessable";

export type EvidenceRegion = {
  x: number;
  y: number;
  width: number;
  height: number;
  is_global?: boolean;
  description?: string;
};

export type SceneEntity = {
  id: string;
  kind: string;
  label: string;
  visible: boolean;
  accessible?: boolean;
  region?: EvidenceRegion;
  cues?: string[];
};

export type ProviderCandidate = {
  candidate_key: string;
  module_id: V4ModuleID;
  raw_label: string;
  asset_ref?: string;
  person_ref?: string;
  affirmative_cues: string[];
  counter_cues: string[];
  evidence_region?: EvidenceRegion;
  occlusion: "none" | "partial" | "substantial" | "unknown";
  event_path: {
    source: string;
    contact_or_failure: string;
    consequence: string;
  };
  potential_consequence: Criticality;
  visually_resolvable: boolean;
  requires_document_or_measurement: boolean;
  confidence: {
    visibility: number;
    localization: number;
    mechanism: number;
  };
};

export type ModuleCoverage = {
  module_id: V4ModuleID;
  activated_by: string[];
  outcome: ModuleOutcome;
  entity_refs: string[];
  candidate_keys: string[];
  note?: string;
};

export type ProviderPhotoOutput = {
  contract_version: typeof V4_PROVIDER_CONTRACT_VERSION;
  scene_summary: string;
  scene_entities: SceneEntity[];
  people: SceneEntity[];
  accessible_regions: SceneEntity[];
  energy_sources: SceneEntity[];
  candidates: ProviderCandidate[];
  positive_controls: Array<{
    control_key: string;
    module_id: V4ModuleID;
    asset_ref?: string;
    description: string;
    affirmative_cues: string[];
    evidence_region?: EvidenceRegion;
  }>;
  module_coverage: ModuleCoverage[];
  untrusted_embedded_text: string[];
};

export type NormalizedCandidate = ProviderCandidate & {
  id: string;
  photo_index: number;
  evidence_level: EvidenceLevel;
  criticality: Criticality;
  condition_code: string;
  normalized_label: string;
  accessible_event_path: boolean;
  assurance_topic_id?: string;
  hard_reject_reason?: string;
  /**
   * Set when the single-photo verification pass positively contradicted this
   * absence claim. The router demotes it to a field check rather than dropping
   * it: two independent looks disagreeing is exactly what "verify on site"
   * is for.
   */
  verification_disputed?: string;
};

export type RoutedItem = {
  id: string;
  candidate_id?: string;
  item_class: SafetyItemClass;
  is_scored: boolean;
  criticality: Criticality;
  ordinal: number;
  title: string;
  category: string;
  description: string;
  recommended_action: string;
  recommended_measures: Array<{
    kind: "corrective" | "preventive";
    title: string;
    text: string;
  }>;
  references_text: string;
  root_cause_text: string;
  confidence: number;
  ai_confidence: number;
  needs_field_verification: boolean;
  source_photo_indices: number[];
  display_group: string;
  display_order: number;
  score_payload?: Record<string, unknown>;
  fk_probability?: number;
  fk_frequency?: number;
  fk_severity?: number;
  fk_band?: "critical" | "high" | "medium" | "low" | "unknown";
  m5_probability?: number;
  m5_severity?: number;
  m5_band?: "critical" | "high" | "medium" | "low" | "unknown";
  internal_priority: Record<string, unknown>;
};

export type RoutingLedgerEntry = {
  candidate_id?: string;
  from_state: string;
  to_state: SafetyItemClass | "hard_reject";
  reason_code: string;
  evidence_level?: EvidenceLevel;
  details?: Record<string, unknown>;
};

export type HardRejection = {
  candidate_id: string;
  reason_code: string;
  criticality: Criticality;
  evidence_snapshot: Record<string, unknown>;
};

export type V4RunBundle = {
  candidates: NormalizedCandidate[];
  items: RoutedItem[];
  routing_ledger: RoutingLedgerEntry[];
  hard_rejections: HardRejection[];
  quality_trace: Record<string, unknown>;
  analysis_result: Record<string, unknown>;
};

const regionSchema = {
  type: "object",
  properties: {
    x: { type: "number" },
    y: { type: "number" },
    width: { type: "number" },
    height: { type: "number" },
    is_global: { type: "boolean" },
    description: { type: "string" },
  },
  required: ["x", "y", "width", "height"],
};

const entitySchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    kind: { type: "string" },
    label: { type: "string" },
    visible: { type: "boolean" },
    accessible: { type: "boolean" },
    region: regionSchema,
    cues: { type: "array", items: { type: "string" } },
  },
  required: ["id", "kind", "label", "visible"],
};

export const V4_PROVIDER_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    contract_version: { type: "string", enum: [V4_PROVIDER_CONTRACT_VERSION] },
    scene_summary: { type: "string" },
    scene_entities: { type: "array", items: entitySchema },
    people: { type: "array", items: entitySchema },
    accessible_regions: { type: "array", items: entitySchema },
    energy_sources: { type: "array", items: entitySchema },
    candidates: {
      type: "array",
      items: {
        type: "object",
        properties: {
          candidate_key: { type: "string" },
          module_id: {
            type: "string",
            enum: [...CORE_MODULE_IDS, ...DYNAMIC_MODULE_IDS],
          },
          raw_label: { type: "string" },
          asset_ref: { type: "string" },
          person_ref: { type: "string" },
          affirmative_cues: { type: "array", items: { type: "string" } },
          counter_cues: { type: "array", items: { type: "string" } },
          evidence_region: regionSchema,
          occlusion: {
            type: "string",
            enum: ["none", "partial", "substantial", "unknown"],
          },
          event_path: {
            type: "object",
            properties: {
              source: { type: "string" },
              contact_or_failure: { type: "string" },
              consequence: { type: "string" },
            },
            required: ["source", "contact_or_failure", "consequence"],
          },
          potential_consequence: {
            type: "string",
            enum: ["ordinary", "serious", "permanent", "fatal"],
          },
          visually_resolvable: { type: "boolean" },
          requires_document_or_measurement: { type: "boolean" },
          confidence: {
            type: "object",
            properties: {
              visibility: { type: "number" },
              localization: { type: "number" },
              mechanism: { type: "number" },
            },
            required: ["visibility", "localization", "mechanism"],
          },
        },
        required: [
          "candidate_key",
          "module_id",
          "raw_label",
          "affirmative_cues",
          "counter_cues",
          "occlusion",
          "event_path",
          "potential_consequence",
          "visually_resolvable",
          "requires_document_or_measurement",
          "confidence",
        ],
      },
    },
    positive_controls: {
      type: "array",
      items: {
        type: "object",
        properties: {
          control_key: { type: "string" },
          module_id: { type: "string" },
          asset_ref: { type: "string" },
          description: { type: "string" },
          affirmative_cues: { type: "array", items: { type: "string" } },
          evidence_region: regionSchema,
        },
        required: [
          "control_key",
          "module_id",
          "description",
          "affirmative_cues",
        ],
      },
    },
    module_coverage: {
      type: "array",
      items: {
        type: "object",
        properties: {
          module_id: {
            type: "string",
            enum: [...CORE_MODULE_IDS, ...DYNAMIC_MODULE_IDS],
          },
          activated_by: { type: "array", items: { type: "string" } },
          outcome: { type: "string", enum: [...MODULE_OUTCOMES] },
          entity_refs: { type: "array", items: { type: "string" } },
          candidate_keys: { type: "array", items: { type: "string" } },
          note: { type: "string" },
        },
        required: [
          "module_id",
          "activated_by",
          "outcome",
          "entity_refs",
          "candidate_keys",
        ],
      },
    },
    untrusted_embedded_text: { type: "array", items: { type: "string" } },
  },
  required: [
    "contract_version",
    "scene_summary",
    "scene_entities",
    "people",
    "accessible_regions",
    "energy_sources",
    "candidates",
    "positive_controls",
    "module_coverage",
    "untrusted_embedded_text",
  ],
};
