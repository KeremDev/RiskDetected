// The free engine.
//
// v4 is a contract engine: the model reports visual candidates, and the server
// decides what they mean. Nineteen modules, a coverage matrix, an evidence
// ladder, a mechanism taxonomy, a control playbook, an assurance catalog and a
// router that has been through thirty-seven versions. It was built for
// gemini-2.5-flash, which invented five different guardrail claims across five
// runs of one photograph, and most of that machinery exists to stop it.
//
// gemini-3.5-flash-lite has fabricated nothing in any run of this work. The
// contract now costs more than it saves: it demoted the most important hazard
// in a photograph because the workers were far away, published nine lines of
// module bookkeeping to a reader who wanted three findings, and compressed a
// man carrying a timber into vehicle_person_interface so the report told him to
// keep pedestrians out of a slewing radius. Every fix so far has been a rule
// fitted to the photograph in front of us, which is precisely the thing that
// will not generalise to whatever a user uploads next.
//
// So this engine asks the model to do the safety assessment -- hazards,
// severity, controls, training, PPE -- and keeps only the rules that are about
// honesty rather than method:
//
//   1. Report what is visible; do not assert what the photograph cannot show.
//   2. Do not cite regulation, standard or article numbers.
//   3. Turkish, with Turkish letters.
//
// Everything else is the model's judgement. The server validates ranges,
// computes the arithmetic, and writes to the same tables as v4 -- so the app,
// the report and the score totals are untouched, and the switch back is one
// config key.

export const V5_ENGINE_MODE = "free";
export const V5_PROMPT_VERSION = "v5-free-core-v5";

/** Fine-Kinney scales. The arithmetic stays deterministic; the values do not. */
export const FK_PROBABILITY = [0.2, 0.5, 1, 3, 6, 10] as const;
export const FK_FREQUENCY = [0.5, 1, 2, 3, 6, 10] as const;
export const FK_SEVERITY = [1, 3, 7, 15, 40, 100] as const;

/** Above this the report stops being read. v4's own budget is eight. */
export const V5_MAX_FINDINGS = 8;
export const V5_MAX_POSITIVE_CONTROLS = 4;

export type V5Finding = {
  finding_key: string;
  title: string;
  /** Hazard family in the model's own words; the report's section label. */
  category: string;
  description: string;
  event_path: {
    source: string;
    contact_or_failure: string;
    consequence: string;
  };
  root_cause: string;
  fine_kinney: {
    probability: number;
    frequency: number;
    severity: number;
    rationale: string;
  };
  immediate_control: string;
  corrective_steps: string[];
  preventive_measure: string;
  training_recommendation?: string;
  ppe_recommendation?: string;
  evidence_region?: {
    x: number;
    y: number;
    width: number;
    height: number;
    description?: string;
  };
  confidence: number;
  needs_field_verification: boolean;
};

export type V5PositiveControl = {
  title: string;
  description: string;
};

export type V5PhotoOutput = {
  scene_summary: string;
  findings: V5Finding[];
  positive_controls: V5PositiveControl[];
};

const regionSchema = {
  type: "object",
  properties: {
    x: { type: "number" },
    y: { type: "number" },
    width: { type: "number" },
    height: { type: "number" },
    description: { type: "string" },
  },
  required: ["x", "y", "width", "height"],
};

export const V5_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    scene_summary: { type: "string" },
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          finding_key: { type: "string" },
          title: { type: "string" },
          category: { type: "string" },
          description: { type: "string" },
          event_path: {
            type: "object",
            properties: {
              source: { type: "string" },
              contact_or_failure: { type: "string" },
              consequence: { type: "string" },
            },
            required: ["source", "contact_or_failure", "consequence"],
          },
          root_cause: { type: "string" },
          fine_kinney: {
            type: "object",
            properties: {
              probability: { type: "number" },
              frequency: { type: "number" },
              severity: { type: "number" },
              rationale: { type: "string" },
            },
            required: ["probability", "frequency", "severity", "rationale"],
          },
          immediate_control: { type: "string" },
          corrective_steps: { type: "array", items: { type: "string" } },
          preventive_measure: { type: "string" },
          training_recommendation: { type: "string" },
          ppe_recommendation: { type: "string" },
          evidence_region: regionSchema,
          confidence: { type: "number" },
          needs_field_verification: { type: "boolean" },
        },
        required: [
          "finding_key",
          "title",
          "category",
          "description",
          "event_path",
          "root_cause",
          "fine_kinney",
          "immediate_control",
          "corrective_steps",
          "preventive_measure",
          "confidence",
          "needs_field_verification",
        ],
      },
    },
    positive_controls: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          description: { type: "string" },
        },
        required: ["title", "description"],
      },
    },
  },
  required: ["scene_summary", "findings", "positive_controls"],
};
