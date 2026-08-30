// What the nineteen layers mean to the rest of the system.
//
// The free engine deliberately has no mechanism taxonomy, no coverage matrix
// and no module vocabulary -- that machinery is what published nine lines of
// "biyogüvenlik konusu yoktur" to a reader who wanted three findings. But two
// downstream engines were built on those codes and went silent when the codes
// stopped arriving: the training catalogue returned an empty list for every
// analysis, and the Uzman Görüşü section had nothing to show.
//
// The layers are the replacement spine. They are already a fixed, schema-
// enforced taxonomy -- nineteen numbers, the same on every photograph, in every
// run -- which is exactly the property the old module ids had and the model's
// free prose does not. Mapping them costs no tokens and no prompt text, and it
// constrains nothing the model says: the hazard, the severity and the control
// stay entirely its own.
//
// The map is coarser than mechanism codes were. That is the honest trade: a
// training card recommended from "layer 3 saw a hazard" is a recommendation
// about working at height, which is true, and it never claims to know which of
// the six fall mechanisms applied.

import type { V4ModuleID } from "./contracts.ts";

export type V5LayerBookCodes = {
  moduleID: V4ModuleID;
  /** The training catalogue's own vocabulary, or null where none applies. */
  mechanismCode: string | null;
  assuranceTopicID: string | null;
};

/**
 * Layer 19 is absent on purpose.
 *
 * It asks about an equipment's *record*, not its condition, so it is not a
 * statement about what anyone needs to be taught. It feeds the expert section
 * instead, through EXPERT_ASSET_FAMILIES.
 */
export const V5_LAYER_BOOK_CODES: Record<number, V5LayerBookCodes> = {
  1: {
    moduleID: "people_exposure",
    mechanismCode: null,
    assuranceTopicID: null,
  },
  2: {
    moduleID: "housekeeping_physical_contact",
    mechanismCode: "fall_same_level",
    assuranceTopicID: null,
  },
  3: {
    moduleID: "work_at_height",
    mechanismCode: "fall_from_height",
    assuranceTopicID: "working_at_height_access",
  },
  4: {
    moduleID: "falls_falling_objects",
    mechanismCode: "falling_object",
    assuranceTopicID: null,
  },
  5: {
    moduleID: "electrical",
    mechanismCode: "electrical_contact_arc",
    assuranceTopicID: "electrical_internal_integrity",
  },
  6: {
    moduleID: "machinery",
    mechanismCode: "caught_in_pinch_shear",
    assuranceTopicID: "machine_protective_systems",
  },
  7: {
    moduleID: "lifting",
    mechanismCode: "falling_object",
    assuranceTopicID: "lifting_inspection",
  },
  8: {
    moduleID: "vehicles_mobile_equipment",
    mechanismCode: "vehicle_equipment_strike",
    assuranceTopicID: "mobile_equipment_controls",
  },
  9: {
    moduleID: "housekeeping_physical_contact",
    mechanismCode: "falling_object",
    assuranceTopicID: null,
  },
  10: {
    moduleID: "chemical",
    mechanismCode: "chemical_contact_release",
    assuranceTopicID: "chemical_identity_and_exposure",
  },
  11: {
    moduleID: "process_integrity",
    mechanismCode: "mechanical_separation_release",
    assuranceTopicID: "process_containment_integrity",
  },
  12: {
    moduleID: "process_integrity",
    mechanismCode: "hydraulic_pneumatic_release",
    assuranceTopicID: "process_containment_integrity",
  },
  13: {
    moduleID: "hot_work",
    mechanismCode: "thermal_contact",
    assuranceTopicID: "hot_work_controls",
  },
  14: {
    moduleID: "process_integrity",
    mechanismCode: "mechanical_separation_release",
    assuranceTopicID: "process_containment_integrity",
  },
  15: {
    moduleID: "confined_space",
    mechanismCode: "confined_space_atmosphere_entrapment",
    assuranceTopicID: "confined_space_controls",
  },
  // Was chemical_contact_release/chemical_identity_and_exposure -- the same
  // pair layer 10 uses. That made a noise or dust hazard fire the chemical-spill
  // training card, or nothing, depending on which finding got there first. The
  // operator's revision gives layer 16 its own vocabulary rather than sharing
  // layer 10's, so TRN-HYG-001 (added for noise/vibration/dust) can be matched
  // without also matching a leak.
  16: {
    moduleID: "chemical",
    mechanismCode: "noise_vibration_dust_exposure",
    assuranceTopicID: "occupational_hygiene_controls",
  },
  17: {
    moduleID: "people_exposure",
    mechanismCode: "manual_handling_overexertion",
    assuranceTopicID: "ergonomic_risk_controls",
  },
  18: {
    moduleID: "fire_explosion_release",
    mechanismCode: null,
    assuranceTopicID: "fire_emergency_readiness",
  },
};

/** The records layer, which answers to the expert section rather than training. */
export const V5_RECORDS_LAYER = 19;

/**
 * What the model is allowed to say it saw.
 *
 * A closed list, because this is the one thing the expert section cannot infer
 * and cannot guess at. "Bu tankın API 653 kapsamında et kalınlık ölçümü
 * bulunmalıdır" is a sentence about a specific asset class; getting the class
 * from Turkish prose is how a man carrying a timber became a slewing radius.
 *
 * This asks the model a perception question -- what equipment is in frame --
 * and nothing else. It does not touch the hazard, the severity, the control or
 * the wording of any finding. The standards, the intervals and the measurement
 * requirements are ours; the model never supplies them.
 */
export const EXPERT_ASSET_FAMILIES = [
  "overhead_crane",
  "mobile_crane",
  "hoist",
  "lifting_accessory",
  "forklift",
  "mewp",
  "earthmoving_equipment",
  "storage_tank",
  "pressure_vessel",
  "process_piping",
  "boiler",
  "compressor",
  "gas_cylinder",
  "electrical_panel",
  "earthing_system",
  "welding_machine",
  "machine_tool",
  "fire_equipment",
  "ventilation_system",
  "scaffold",
  "ladder",
  "conveyor",
] as const;

export type ExpertAssetFamily = typeof EXPERT_ASSET_FAMILIES[number];

export function isExpertAssetFamily(value: unknown): value is ExpertAssetFamily {
  return typeof value === "string" &&
    (EXPERT_ASSET_FAMILIES as readonly string[]).includes(value);
}
