export const ENGINE_VERSION = "vnext-v3";
export const SCHEMA_VERSION = "hazard-fact-v3.5";
export const PROMPT_VERSION = "vnext-photo-expert-v30";
export const POLICY_VERSION = "semantic-risk-v29";
export const PROMPT_BUNDLE_POLICY_VERSION = "prompt-bundle-sha256-v1";
// Updated only together with PROMPT_VERSION. prompt_integrity_test.ts computes
// the canonical primary/targeted/schema bundle and fails when prompt-bearing
// content changes under the same version.
export const PROMPT_BUNDLE_SHA256 =
  "e064c5c6b0da56fba6f7c1e53a715cdfdf8b798981e88d394dacecd9a5ef080b";
export const CONTROL_CATALOG_VERSION = "controls-v19";

export const MODULE_IDS = [
  "access_and_work_at_height",
  "scaffold_and_ladder",
  "excavation_slope_shoring",
  "lifting_operations",
  "mobile_equipment_traffic",
  "machine_safety_loto",
  "storage_racking",
  "pressure_process_safety",
  "pipe_hose_connections",
  "structural_mechanical_integrity",
  "electrical_safety",
  "hot_work_fire_explosion",
  "chemical_risk",
  "egress_housekeeping",
  "ppe",
  "ergonomics",
  "welding_ndt",
  "emergency_equipment",
  "environmental_release_leak",
  "sector_specific",
] as const;

export type ModuleID = typeof MODULE_IDS[number];
export type ConfidenceLevel = "low" | "medium" | "high";
export type ConsequenceClass =
  | "negligible"
  | "first_aid"
  | "serious_reversible"
  | "permanent_disability"
  | "single_fatality"
  | "multiple_fatality_major_environmental";
export type FrequencyBasis =
  | "continuous_visible_work"
  | "daily_repeated_workstation"
  | "active_single_exposure"
  | "sector_scene_proxy"
  | "missing_invalid_fallback"
  | "catalogued_rare";
export type BarrierState =
  | "absent_or_failed_event_active"
  | "absent_or_failed_event_direct"
  | "partial_event_direct_or_conditional"
  | "visible_effective_event_conditional"
  | "multiple_independent_visible_barriers";
export type RootCauseMode =
  | "observed_condition"
  | "probable_factor"
  | "not_determinable";
export type AssessmentBasis =
  | "observed_nonconformity"
  | "visible_inherent_hazard"
  | "equipment_integrity_verification";

export const HAZARD_MECHANISM_CODES = [
  "fall_same_level",
  "fall_from_height",
  "falling_object",
  "vehicle_equipment_strike",
  "caught_in_pinch_shear",
  "mechanical_separation_release",
  "hydraulic_pneumatic_release",
  "electrical_contact_arc",
  "fire_explosion",
  "structural_collapse",
  "equipment_overturn",
  "excavation_collapse_rockfall",
  "chemical_contact_release",
  "thermal_contact",
  "sharp_edge_contact",
  "ergonomic_overexertion",
  "environmental_release",
  "other_visible_physical",
] as const;

export type HazardMechanismCode = typeof HAZARD_MECHANISM_CODES[number];

export type NormalizedRegion = {
  x: number;
  y: number;
  width: number;
  height: number;
  is_global: boolean;
};

export type HazardFactV3 = {
  fact_id: string;
  photo_index: number;
  assessment_basis: AssessmentBasis;
  evidence: {
    normalized_region: NormalizedRegion;
    affirmative_cues: string[];
  };
  entity: {
    entity_ref: string;
    equipment_family: string;
    component: string;
    identity_basis: string;
    identity_confidence: ConfidenceLevel;
  };
  observed_condition: {
    condition_code: string;
    short_text: string;
  };
  mechanism_code: HazardMechanismCode;
  hazard_mechanism: string;
  energy_source: string;
  barrier_state: BarrierState;
  initiating_event_state: string;
  credible_event_path: string;
  exposed_entity: string;
  technical_assessment: {
    observation_narrative: string;
    technical_significance: string;
    root_cause_mode: RootCauseMode;
    root_cause_text: string;
  };
  consequence_class: ConsequenceClass;
  frequency_basis: FrequencyBasis;
  verification: {
    model_required: boolean;
    reason_code: string;
  };
  confidence: {
    entity: ConfidenceLevel;
    condition: ConfidenceLevel;
    localization: ConfidenceLevel;
    mechanism: ConfidenceLevel;
  };
  depth_tags: string[];
  control_intents: Array<{
    action_code: string;
    target: string;
    priority: "immediate" | "planned" | "monitor";
  }>;
};

export type InspectionSignalV1 = {
  signal_id: string;
  photo_index: number;
  evidence_region: NormalizedRegion;
  affirmative_cues: string[];
  potential_consequence_class: ConsequenceClass;
  reason_code: string;
};

export type SchemaDiagnosticsV1 = {
  salvaged: boolean;
  strict_error_code: string | null;
  raw_fact_count: number;
  valid_fact_count: number;
  invalid_fact_count: number;
  raw_signal_count: number;
  invalid_signal_count: number;
  missing_module_ids: string[];
  duplicate_module_ids: string[];
  reason_codes: string[];
};

export type PhotoAnalysisV3 = {
  scene_inventory: Array<{
    entity_ref: string;
    equipment_family: string;
    component: string;
    visible_condition_summary: string;
  }>;
  module_audit: Array<{
    module_id: ModuleID;
    entity_refs: string[];
    status:
      | "not_applicable"
      | "scanned_no_positive_evidence"
      | "positive_evidence";
  }>;
  mandatory_module_outcomes: Array<{
    module_id: ModuleID;
    entity_refs: string[];
    status:
      | "actionable"
      | "checked_no_hazard"
      | "not_visible"
      | "uncertain";
  }>;
  sector_context_evidence: Array<{
    code:
      | "visible_active_work"
      | "maintenance_state_visible"
      | "underground_production_face"
      | "manned_control_area"
      | "continuous_traffic_visible"
      | "continuous_line_operation"
      | "daily_animal_care";
    entity_refs: string[];
    affirmative_cues: string[];
  }>;
  hazard_facts: HazardFactV3[];
  inspection_signals: InspectionSignalV1[];
  /** Added by the server after tolerant parsing; never requested from models. */
  _schema_diagnostics_v1?: SchemaDiagnosticsV1;
};

const confidenceSchema = {
  type: "string",
  enum: ["low", "medium", "high"],
} as const;

const consequenceSchema = {
  type: "string",
  enum: [
    "negligible",
    "first_aid",
    "serious_reversible",
    "permanent_disability",
    "single_fatality",
    "multiple_fatality_major_environmental",
  ],
} as const;

const regionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["x", "y", "width", "height", "is_global"],
  properties: {
    x: { type: "number", minimum: 0, maximum: 1 },
    y: { type: "number", minimum: 0, maximum: 1 },
    width: { type: "number", minimum: 0, maximum: 1 },
    height: { type: "number", minimum: 0, maximum: 1 },
    is_global: { type: "boolean" },
  },
} as const;

/**
 * Reorders a schema's `properties` to match its declared generation order.
 *
 * `propertyOrdering` alone was not enough: the two disagreed on the wire, with
 * propertyOrdering asking for hazard_facts second while the properties object
 * still listed it fourth. Serialized JSON follows insertion order, so the model
 * kept seeing the old layout and raw fact production did not move. Both are
 * built from one list now, and a test asserts they cannot drift apart again.
 */
function orderedProperties<T extends Record<string, unknown>>(
  properties: T,
  ordering: readonly string[],
): T {
  const ordered: Record<string, unknown> = {};
  for (const key of ordering) {
    if (key in properties) ordered[key] = properties[key];
  }
  for (const [key, value] of Object.entries(properties)) {
    if (!(key in ordered)) ordered[key] = value;
  }
  return ordered as T;
}

const PHOTO_ANALYSIS_FIELD_ORDER = [
  "scene_inventory",
  "hazard_facts",
  "inspection_signals",
  "module_audit",
  "mandatory_module_outcomes",
  "sector_context_evidence",
] as const;

const COMPACT_PHOTO_ANALYSIS_FIELD_ORDER = [
  "scene_inventory",
  "hazard_facts",
  "inspection_signals",
  "scanned_module_ids",
  "mandatory_module_outcomes",
  "sector_context_evidence",
] as const;

/**
 * `hazard_facts` is emitted second, not fifth.
 *
 * Gemini generates structured output in schema order. With the module audit,
 * mandatory outcomes and sector evidence ahead of it, the findings were written
 * last out of an 8192-token budget and production settled at three facts per
 * photo regardless of what the photograph contained. The same ordering caused
 * the v173 regression in the previous engine, where two of three photos came
 * back with zero findings.
 *
 * `scene_inventory` stays first because facts reference its entity_refs. The
 * module sweep still happens -- the prompt asks for it during reasoning, which
 * is a separate budget -- but its record is written after the findings it was
 * meant to produce.
 */
export const PHOTO_ANALYSIS_JSON_SCHEMA_V3_4 = {
  type: "object",
  additionalProperties: false,
  propertyOrdering: [...PHOTO_ANALYSIS_FIELD_ORDER],
  required: [...PHOTO_ANALYSIS_FIELD_ORDER],
  properties: orderedProperties({
    scene_inventory: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "entity_ref",
          "equipment_family",
          "component",
          "visible_condition_summary",
        ],
        properties: {
          entity_ref: { type: "string" },
          equipment_family: { type: "string" },
          component: { type: "string" },
          visible_condition_summary: { type: "string" },
        },
      },
    },
    module_audit: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["module_id", "entity_refs", "status"],
        properties: {
          module_id: { type: "string", enum: [...MODULE_IDS] },
          entity_refs: { type: "array", items: { type: "string" } },
          status: {
            type: "string",
            enum: [
              "not_applicable",
              "scanned_no_positive_evidence",
              "positive_evidence",
            ],
          },
        },
      },
    },
    mandatory_module_outcomes: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["module_id", "entity_refs", "status"],
        properties: {
          module_id: { type: "string", enum: [...MODULE_IDS] },
          entity_refs: { type: "array", items: { type: "string" } },
          status: {
            type: "string",
            enum: [
              "actionable",
              "checked_no_hazard",
              "not_visible",
              "uncertain",
            ],
          },
        },
      },
    },
    sector_context_evidence: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["code", "entity_refs", "affirmative_cues"],
        properties: {
          code: {
            type: "string",
            enum: [
              "visible_active_work",
              "maintenance_state_visible",
              "underground_production_face",
              "manned_control_area",
              "continuous_traffic_visible",
              "continuous_line_operation",
              "daily_animal_care",
            ],
          },
          entity_refs: { type: "array", items: { type: "string" } },
          affirmative_cues: { type: "array", items: { type: "string" } },
        },
      },
    },
    hazard_facts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "fact_id",
          "photo_index",
          "assessment_basis",
          "evidence",
          "entity",
          "observed_condition",
          "mechanism_code",
          "hazard_mechanism",
          "energy_source",
          "barrier_state",
          "initiating_event_state",
          "credible_event_path",
          "exposed_entity",
          "technical_assessment",
          "consequence_class",
          "frequency_basis",
          "verification",
          "confidence",
          "depth_tags",
          "control_intents",
        ],
        properties: {
          fact_id: { type: "string" },
          photo_index: { type: "integer", minimum: 1, maximum: 3 },
          assessment_basis: {
            type: "string",
            enum: [
              "observed_nonconformity",
              "visible_inherent_hazard",
              "equipment_integrity_verification",
            ],
          },
          evidence: {
            type: "object",
            additionalProperties: false,
            required: ["normalized_region", "affirmative_cues"],
            properties: {
              normalized_region: regionSchema,
              affirmative_cues: {
                type: "array",
                items: { type: "string" },
              },
            },
          },
          entity: {
            type: "object",
            additionalProperties: false,
            required: [
              "entity_ref",
              "equipment_family",
              "component",
              "identity_basis",
              "identity_confidence",
            ],
            properties: {
              entity_ref: { type: "string" },
              equipment_family: { type: "string" },
              component: { type: "string" },
              identity_basis: { type: "string" },
              identity_confidence: confidenceSchema,
            },
          },
          observed_condition: {
            type: "object",
            additionalProperties: false,
            required: ["condition_code", "short_text"],
            properties: {
              condition_code: { type: "string" },
              short_text: { type: "string" },
            },
          },
          mechanism_code: {
            type: "string",
            enum: [...HAZARD_MECHANISM_CODES],
          },
          hazard_mechanism: { type: "string" },
          energy_source: { type: "string" },
          barrier_state: {
            type: "string",
            enum: [
              "absent_or_failed_event_active",
              "absent_or_failed_event_direct",
              "partial_event_direct_or_conditional",
              "visible_effective_event_conditional",
              "multiple_independent_visible_barriers",
            ],
          },
          initiating_event_state: { type: "string" },
          credible_event_path: { type: "string" },
          exposed_entity: { type: "string" },
          technical_assessment: {
            type: "object",
            additionalProperties: false,
            required: [
              "observation_narrative",
              "technical_significance",
              "root_cause_mode",
              "root_cause_text",
            ],
            properties: {
              observation_narrative: { type: "string" },
              technical_significance: { type: "string" },
              root_cause_mode: {
                type: "string",
                enum: [
                  "observed_condition",
                  "probable_factor",
                  "not_determinable",
                ],
              },
              root_cause_text: { type: "string" },
            },
          },
          consequence_class: consequenceSchema,
          frequency_basis: {
            type: "string",
            enum: [
              "active_single_exposure",
              "sector_scene_proxy",
              "missing_invalid_fallback",
              "catalogued_rare",
            ],
          },
          verification: {
            type: "object",
            additionalProperties: false,
            required: ["model_required", "reason_code"],
            properties: {
              model_required: { type: "boolean" },
              reason_code: { type: "string" },
            },
          },
          confidence: {
            type: "object",
            additionalProperties: false,
            required: ["entity", "condition", "localization", "mechanism"],
            properties: {
              entity: confidenceSchema,
              condition: confidenceSchema,
              localization: confidenceSchema,
              mechanism: confidenceSchema,
            },
          },
          depth_tags: { type: "array", items: { type: "string" } },
          control_intents: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["action_code", "target", "priority"],
              properties: {
                action_code: { type: "string" },
                target: { type: "string" },
                priority: {
                  type: "string",
                  enum: ["immediate", "planned", "monitor"],
                },
              },
            },
          },
        },
      },
    },
    inspection_signals: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "signal_id",
          "photo_index",
          "evidence_region",
          "affirmative_cues",
          "potential_consequence_class",
          "reason_code",
        ],
        properties: {
          signal_id: { type: "string" },
          photo_index: { type: "integer", minimum: 1, maximum: 3 },
          evidence_region: regionSchema,
          affirmative_cues: { type: "array", items: { type: "string" } },
          potential_consequence_class: consequenceSchema,
          reason_code: { type: "string" },
        },
      },
    },
  }, PHOTO_ANALYSIS_FIELD_ORDER),
} as const;

const {
  module_audit: _legacyModuleAuditSchema,
  ...compactPhotoAnalysisProperties
} = PHOTO_ANALYSIS_JSON_SCHEMA_V3_4.properties;

/**
 * v3.5 keeps the normalized server contract unchanged while removing the
 * verbose per-module status objects from provider output. The parser derives
 * the legacy module_audit deterministically and continues to accept v3.4
 * responses for checkpoint/deploy rollback compatibility.
 */
export const PHOTO_ANALYSIS_JSON_SCHEMA = {
  ...PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
  propertyOrdering: [...COMPACT_PHOTO_ANALYSIS_FIELD_ORDER],
  required: [...COMPACT_PHOTO_ANALYSIS_FIELD_ORDER],
  properties: orderedProperties({
    ...compactPhotoAnalysisProperties,
    scanned_module_ids: {
      type: "array",
      items: { type: "string", enum: [...MODULE_IDS] },
    },
  }, COMPACT_PHOTO_ANALYSIS_FIELD_ORDER),
} as const;
