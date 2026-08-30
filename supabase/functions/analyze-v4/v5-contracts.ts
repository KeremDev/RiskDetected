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
export const V5_PROMPT_VERSION = "v7-free-core-multidisciplinary-v9";

/** Fine-Kinney scales. The arithmetic stays deterministic; the values do not. */
export const FK_PROBABILITY = [0.2, 0.5, 1, 3, 6, 10] as const;
export const FK_FREQUENCY = [0.5, 1, 2, 3, 6, 10] as const;
export const FK_SEVERITY = [1, 3, 7, 15, 40, 100] as const;

/**
 * A runaway guard, not a budget.
 *
 * The prompt used to cap the model at eight, and that is the model deciding
 * which hazards a reader is allowed to know about. It now writes every hazard
 * it has evidence for; this bound only exists so a malformed response cannot
 * put a thousand rows through the finalize RPC.
 */
export const V5_MAX_FINDINGS = 24;
export const V5_MAX_POSITIVE_CONTROLS = 4;

export type V5Finding = {
  finding_key: string;
  /**
   * Every scan layer this finding discharges, 1-18.
   *
   * Plural because one hazard belongs to several layers and a single number
   * made the audit read a covered hazard as an uncovered one. In analysis
   * 0e48c1c8 the worker on the tank answered layer 3, and layer 1 -- the same
   * worker, "güvensiz pozisyonda kaynak" -- was reported unanswered beside two
   * layers that genuinely were. The oldest engine had inspection_layer_keys
   * plural for this reason.
   *
   * This binding, not the array order, is what fixes a hazard recorded in the
   * scan and never written as a finding. layer_scan is emitted first again so
   * the sweep can act as the checklist the findings discharge.
   */
  layers: number[];
  title: string;
  category: string;
  description: string;
  /** "Kaynak → temas, arıza veya tetikleyici → sonuç", as one line. */
  event_path: string;
  root_cause: string;
  /** One to four entries, each "Mevzuat — ..." or "Standart/... — ...". */
  regulatory_references: string[];
  fine_kinney: {
    /** Turkish keys, because the operator's contract is written in Turkish. */
    olasılık: number;
    frekans: number;
    şiddet: number;
    gerekçe: string;
  };
  immediate_control: string;
  corrective_steps: string[];
  preventive_measure: string;
  training_recommendation?: string;
  ppe_recommendation?: string;
  /** Corner box, converted to x/y/width/height before it is stored. */
  evidence_region?: {
    x_min: number;
    y_min: number;
    x_max: number;
    y_max: number;
  };
  confidence: number;
  needs_field_verification: boolean;
};

export type V5PositiveControl = {
  title: string;
  description: string;
};

/**
 * One line per scan layer, for the model rather than the reader.
 *
 * "Tara" is a suggestion a model can silently skip, and in analyses 6f72a303
 * and 5e90f22d it did: two foreground findings out of eighteen layers, with
 * work at height (layer 3) and water-plus-electricity (layer 5) untouched on a
 * photograph where every earlier version had scored the fall as fatal.
 *
 * The oldest engine forced the walk by making the layer array a required part
 * of the response, and that is what worked. The difference here is where it
 * goes: v4 published those rows and a report spent nine of fourteen items
 * saying a construction site could not be assessed for biosecurity. This array
 * never becomes an item. It lands in the quality trace, where it makes the
 * traversal auditable and nothing else.
 */
export type V5LayerScan = {
  layer: number;
  result: "tehlike_var" | "tehlike_yok" | "kadrajda_yok";
  note: string;
};

/** Which scan layer the finding answers, so the coupling can be audited. */

export type V5PhotoOutput = {
  scene_summary: string;
  findings: V5Finding[];
  positive_controls: V5PositiveControl[];
  layer_scan: V5LayerScan[];
};

export const V5_SCAN_LAYER_COUNT = 19;

const regionSchema = {
  type: "object",
  properties: {
    x_min: { type: "number" },
    y_min: { type: "number" },
    x_max: { type: "number" },
    y_max: { type: "number" },
  },
  required: ["x_min", "y_min", "x_max", "y_max"],
};

export const V5_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    scene_summary: { type: "string" },
    layer_scan: {
      type: "array",
      items: {
        type: "object",
        properties: {
          layer: { type: "number" },
          result: {
            type: "string",
            enum: ["tehlike_var", "tehlike_yok", "kadrajda_yok"],
          },
          note: { type: "string" },
        },
        required: ["layer", "result", "note"],
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
    findings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          finding_key: { type: "string" },
          layers: { type: "array", items: { type: "number" } },
          title: { type: "string" },
          category: { type: "string" },
          description: { type: "string" },
          event_path: { type: "string" },
          root_cause: { type: "string" },
          regulatory_references: { type: "array", items: { type: "string" } },
          fine_kinney: {
            type: "object",
            properties: {
              "olasılık": { type: "number" },
              frekans: { type: "number" },
              "şiddet": { type: "number" },
              "gerekçe": { type: "string" },
            },
            required: ["olasılık", "frekans", "şiddet", "gerekçe"],
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
          "layers",
          "title",
          "category",
          "description",
          "event_path",
          "root_cause",
          "regulatory_references",
          "fine_kinney",
          "immediate_control",
          "corrective_steps",
          "preventive_measure",
          "confidence",
          "needs_field_verification",
        ],
      },
    },
  },
  required: ["scene_summary", "layer_scan", "findings", "positive_controls"],
};
