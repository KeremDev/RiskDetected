import {
  type InspectionLayerKey,
  normalizeInspectionLayerKeys,
} from "./inspection-layer-audit.ts";

export const EXPERT_DEPTH_POLICY_VERSION = 1;
export const PROCESS_SAFETY_POLICY_VERSION = 1;

export const EQUIPMENT_DEPTH_GROUPS = [
  "pressure_equipment",
  "lifting_conveying",
  "electrical_installations",
  "machine_tools",
  "industrial_racks_doors",
  "construction_machinery",
  "other_complex_equipment",
] as const;

export const PROCESS_SAFETY_SCOPES = [
  "not_applicable",
  "applicable",
  "uncertain_equipment_identity",
] as const;

export const PROCESS_SAFETY_CHECK_STATUSES = [
  "not_applicable",
  "not_visible",
  "checked_no_hazard",
  "actionable",
  "uncertain",
] as const;

export const PROCESS_SAFETY_CHECK_KEYS = [
  "equipment_process_identity",
  "containment_integrity",
  "pressure_vacuum_integrity",
  "overpressure_relief_path",
  "instrumentation_indication",
  "isolation_energy_release",
  "transfer_connections_hoses",
  "ignition_static_explosion_controls",
  "secondary_containment_drainage",
  "supports_anchorage_impact_protection",
  "material_compatibility_reaction",
  "emergency_access_discharge",
] as const;

export type EquipmentDepthGroup = typeof EQUIPMENT_DEPTH_GROUPS[number];
export type ProcessSafetyScope = typeof PROCESS_SAFETY_SCOPES[number];
export type ProcessSafetyCheckStatus =
  typeof PROCESS_SAFETY_CHECK_STATUSES[number];
export type ProcessSafetyCheckKey = typeof PROCESS_SAFETY_CHECK_KEYS[number];

export type NormalizedEquipmentDepthScan = {
  equipment_instance_key: string;
  equipment_group_code: EquipmentDepthGroup;
  localized_equipment_name: string;
  recognition_confidence: number;
  visible_cues: string[];
  source_photo_indices: number[];
  fk_probability: number;
  fk_frequency: number;
  fk_severity: number;
  m5_probability: number;
  m5_severity: number;
};

export type NormalizedProcessSafetyCheck = {
  check_key: ProcessSafetyCheckKey;
  status: ProcessSafetyCheckStatus;
  visual_evidence: string;
  linked_layer_keys: InspectionLayerKey[];
  equipment_instance_key: string;
};

export type NormalizedProcessSafetyAudit = {
  scope: ProcessSafetyScope;
  checks: NormalizedProcessSafetyCheck[];
  complete: boolean;
  missing_check_keys: ProcessSafetyCheckKey[];
  duplicate_check_keys: ProcessSafetyCheckKey[];
  invalid_check_keys_count: number;
  invalid_check_statuses_count: number;
};

export type ProcessSafetyEvidenceGuardResult = {
  findings: Array<Record<string, unknown>>;
  applied: boolean;
  rejected_invalid_process_link_count: number;
  rejected_non_actionable_process_count: number;
  marked_uncertain_process_count: number;
};

export type EquipmentDepthSalvageResult = {
  scans: NormalizedEquipmentDepthScan[];
  salvaged_groups: EquipmentDepthGroup[];
};

export type ProcessSafetyCompletionResult = {
  audit: NormalizedProcessSafetyAudit;
  completed: boolean;
  inserted_check_count: number;
};

export const PROCESS_SAFETY_LAYER_MAP: Record<
  ProcessSafetyCheckKey,
  readonly InspectionLayerKey[]
> = {
  equipment_process_identity: ["machinery_equipment", "chemicals"],
  containment_integrity: ["chemicals", "machinery_equipment"],
  pressure_vacuum_integrity: ["machinery_equipment", "fire_explosion"],
  overpressure_relief_path: [
    "machinery_equipment",
    "fire_explosion",
    "physical_environment",
  ],
  instrumentation_indication: [
    "machinery_equipment",
    "physical_environment",
  ],
  isolation_energy_release: [
    "electrical_energy",
    "machinery_equipment",
    "excavation_confined_special_work",
  ],
  transfer_connections_hoses: ["chemicals", "machinery_equipment"],
  ignition_static_explosion_controls: [
    "fire_explosion",
    "electrical_energy",
  ],
  secondary_containment_drainage: [
    "chemicals",
    "environment_emergency_signage_competence",
  ],
  supports_anchorage_impact_protection: [
    "machinery_equipment",
    "lifting_handling_storage",
  ],
  material_compatibility_reaction: ["chemicals", "fire_explosion"],
  emergency_access_discharge: [
    "physical_environment",
    "environment_emergency_signage_competence",
  ],
};

const PERIODIC_INSPECTION_GROUPS = new Set<EquipmentDepthGroup>([
  "pressure_equipment",
  "lifting_conveying",
  "electrical_installations",
  "machine_tools",
  "industrial_racks_doors",
  "construction_machinery",
]);

const EQUIPMENT_SCENE_PATTERNS: ReadonlyArray<{
  group: EquipmentDepthGroup;
  pattern: RegExp;
}> = [
  {
    group: "pressure_equipment",
    pattern:
      /(?:^|\s)(?:tank|basincli kap|basinc tank|kazan|tup|reaktor|silo|pressure vessel|process vessel|boiler|cylinder|reactor)(?:\w*\s|\w*$)/u,
  },
  {
    group: "lifting_conveying",
    pattern:
      /(?:^|\s)(?:tavan vinc|portal vinc|vinc|kaldirma kanca|forklift|overhead crane|gantry crane|crane|hoist)(?:\w*\s|\w*$)/u,
  },
  {
    group: "construction_machinery",
    pattern:
      /(?:^|\s)(?:ekskavator|is makine|yukleyici|dozer|kepce|excavator|loader|bulldozer|backhoe)(?:\w*\s|\w*$)/u,
  },
  {
    group: "electrical_installations",
    pattern:
      /(?:^|\s)(?:trafo|jenerator|elektrik pano|transformer|generator|switchgear|substation)(?:\w*\s|\w*$)/u,
  },
  {
    group: "machine_tools",
    pattern:
      /(?:^|\s)(?:torna|freze|pres makine|cnc|lathe|milling machine|press machine|machine tool)(?:\w*\s|\w*$)/u,
  },
  {
    group: "other_complex_equipment",
    pattern:
      /(?:^|\s)(?:boru hat|proses boru|pompa|vana|flans|manifold|manometre|emniyet ventil|proses hortum|pipeline|process piping|pump|valve|flange|pressure gauge|relief valve|process hose)(?:\w*\s|\w*$)/u,
  },
  {
    group: "industrial_racks_doors",
    pattern:
      /(?:^|\s)(?:endustriyel raf|raf sistem|depo raf|industrial rack|storage rack|industrial door|sectional door)(?:\w*\s|\w*$)/u,
  },
];

function text(value: unknown): string {
  return value == null ? "" : String(value).normalize("NFC").trim();
}

function boundedConfidence(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : 0;
}

function searchableSceneText(value: unknown): string {
  return text(value).toLocaleLowerCase("tr-TR")
    .replace(/ı/gu, "i")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .replace(/[^a-z0-9]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

function salvagedRiskInputs(group: EquipmentDepthGroup): Pick<
  NormalizedEquipmentDepthScan,
  | "fk_probability"
  | "fk_frequency"
  | "fk_severity"
  | "m5_probability"
  | "m5_severity"
> {
  const majorConsequence = group === "pressure_equipment" ||
    group === "lifting_conveying" ||
    group === "electrical_installations" ||
    group === "construction_machinery";
  return {
    fk_probability: 0.5,
    fk_frequency: 1,
    fk_severity: majorConsequence ? 40 : 15,
    m5_probability: 1,
    m5_severity: majorConsequence ? 5 : 4,
  };
}

/**
 * Recovers only equipment classes that the model already named explicitly in
 * its structured scene description. This does not infer hidden equipment or a
 * defect; it prevents an empty or partial equipment_depth_scan from erasing a
 * visible crane, tank or machine before periodic-verification handling runs.
 */
export function salvageEquipmentDepthScanFromScene(
  existing: NormalizedEquipmentDepthScan[],
  sceneElements: unknown,
  sceneSummary: unknown,
  photoIndex: number,
): EquipmentDepthSalvageResult {
  const cues = [
    ...(Array.isArray(sceneElements) ? sceneElements : []),
    sceneSummary,
  ].map((value) => text(value)).filter(Boolean);
  const scans: NormalizedEquipmentDepthScan[] = [...existing];
  const seen = new Set<EquipmentDepthGroup>(
    existing.map((scan) => scan.equipment_group_code),
  );
  const salvagedGroups: EquipmentDepthGroup[] = [];
  for (const cue of cues) {
    const searchableCue = searchableSceneText(cue);
    for (const matcher of EQUIPMENT_SCENE_PATTERNS) {
      if (seen.has(matcher.group) || !matcher.pattern.test(searchableCue)) {
        continue;
      }
      seen.add(matcher.group);
      salvagedGroups.push(matcher.group);
      scans.push({
        equipment_instance_key: `scene_${matcher.group}_photo_${photoIndex}`,
        equipment_group_code: matcher.group,
        localized_equipment_name: cue.slice(0, 120),
        recognition_confidence: 0.88,
        visible_cues: [cue.slice(0, 180)],
        source_photo_indices: [photoIndex],
        ...salvagedRiskInputs(matcher.group),
      });
    }
  }
  return { scans: scans.slice(0, 8), salvaged_groups: salvagedGroups };
}

/**
 * An applicable process audit may fail open for normal findings, but it must
 * not remain structurally incomplete. Missing controls are completed as
 * not_visible, which cannot create findings, using an explicitly recognised
 * equipment instance as the anchor.
 */
export function completeApplicableProcessSafetyAudit(
  audit: NormalizedProcessSafetyAudit,
  equipmentScans: NormalizedEquipmentDepthScan[],
  notVisibleEvidence: string,
): ProcessSafetyCompletionResult {
  if (audit.scope !== "applicable" || audit.complete) {
    return { audit, completed: false, inserted_check_count: 0 };
  }
  const equipment =
    equipmentScans.find((scan) =>
      scan.equipment_group_code === "pressure_equipment"
    ) ?? equipmentScans[0];
  if (!equipment || !notVisibleEvidence.trim()) {
    return { audit, completed: false, inserted_check_count: 0 };
  }
  const existingByKey = new Map(
    audit.checks.filter((check) =>
      check.visual_evidence.length > 0 &&
      check.linked_layer_keys.length > 0 &&
      check.equipment_instance_key.length > 0
    ).map((check) => [check.check_key, check] as const),
  );
  let insertedCheckCount = 0;
  const completedChecks = PROCESS_SAFETY_CHECK_KEYS.map((checkKey) => {
    const existing = existingByKey.get(checkKey);
    if (existing) return existing;
    insertedCheckCount += 1;
    return {
      check_key: checkKey,
      status: "not_visible" as const,
      visual_evidence: notVisibleEvidence.slice(0, 300),
      linked_layer_keys: [...PROCESS_SAFETY_LAYER_MAP[checkKey]],
      equipment_instance_key: equipment.equipment_instance_key,
    };
  });
  const completedAudit = normalizeProcessSafetyAudit(
    "applicable",
    completedChecks,
  );
  return {
    audit: completedAudit,
    completed: completedAudit.complete,
    inserted_check_count: completedAudit.complete ? insertedCheckCount : 0,
  };
}

function normalizedInstanceKey(value: unknown): string {
  return text(value).toLocaleLowerCase("tr-TR")
    .replace(/ı/gu, "i")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/gu, "")
    .replace(/[^a-z0-9_-]+/gu, "_")
    .replace(/^_+|_+$/gu, "")
    .slice(0, 80);
}

function normalizedPhotoIndices(value: unknown, photoCount: number): number[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.map((item) => Math.round(Number(item))).filter((item) =>
        Number.isFinite(item) && item >= 1 && item <= photoCount
      ),
    ),
  ].sort((left, right) => left - right);
}

export function normalizeEquipmentDepthScan(
  value: unknown,
  photoIndex: number,
  photoCount: number,
  cleanText: (value: unknown) => string = text,
): NormalizedEquipmentDepthScan[] {
  if (!Array.isArray(value)) return [];
  const groups = new Set<string>(EQUIPMENT_DEPTH_GROUPS);
  const byInstance = new Map<string, NormalizedEquipmentDepthScan>();
  for (const item of value.slice(0, 8)) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const record = item as Record<string, unknown>;
    const equipmentGroup = text(record.equipment_group_code);
    const instanceKey = normalizedInstanceKey(record.equipment_instance_key);
    if (!groups.has(equipmentGroup) || !instanceKey) continue;
    const sourcePhotoIndices = normalizedPhotoIndices(
      record.source_photo_indices,
      photoCount,
    ).filter((index) => index === photoIndex);
    const normalized: NormalizedEquipmentDepthScan = {
      equipment_instance_key: instanceKey,
      equipment_group_code: equipmentGroup as EquipmentDepthGroup,
      localized_equipment_name: cleanText(record.localized_equipment_name)
        .slice(0, 120),
      recognition_confidence: boundedConfidence(
        record.recognition_confidence,
      ),
      visible_cues:
        (Array.isArray(record.visible_cues) ? record.visible_cues : []).map((
          cue,
        ) => cleanText(cue).slice(0, 180)).filter(Boolean).slice(
          0,
          6,
        ),
      source_photo_indices: sourcePhotoIndices.length > 0
        ? sourcePhotoIndices
        : [photoIndex],
      fk_probability: Number(record.fk_probability),
      fk_frequency: Number(record.fk_frequency),
      fk_severity: Number(record.fk_severity),
      m5_probability: Number(record.m5_probability),
      m5_severity: Number(record.m5_severity),
    };
    const existing = byInstance.get(instanceKey);
    if (
      !existing ||
      normalized.recognition_confidence > existing.recognition_confidence
    ) {
      byInstance.set(instanceKey, normalized);
    }
  }
  return [...byInstance.values()];
}

export function normalizeProcessSafetyCheckKeys(
  value: unknown,
): ProcessSafetyCheckKey[] {
  if (!Array.isArray(value)) return [];
  const allowed = new Set<string>(PROCESS_SAFETY_CHECK_KEYS);
  return [
    ...new Set(
      value.map((item) => text(item)).filter((item) =>
        allowed.has(item)
      ) as ProcessSafetyCheckKey[],
    ),
  ];
}

export function normalizeProcessSafetyAudit(
  rawScope: unknown,
  rawChecks: unknown,
  cleanText: (value: unknown) => string = text,
): NormalizedProcessSafetyAudit {
  const allowedScopes = new Set<string>(PROCESS_SAFETY_SCOPES);
  const rawScopeText = text(rawScope);
  const scopeValid = allowedScopes.has(rawScopeText);
  const scope = scopeValid
    ? rawScopeText as ProcessSafetyScope
    : "not_applicable";
  const allowedStatuses = new Set<string>(PROCESS_SAFETY_CHECK_STATUSES);
  const allowedChecks = new Set<string>(PROCESS_SAFETY_CHECK_KEYS);
  const checks: NormalizedProcessSafetyCheck[] = [];
  const seen = new Set<ProcessSafetyCheckKey>();
  const duplicates = new Set<ProcessSafetyCheckKey>();
  let invalidCheckKeysCount = 0;
  let invalidCheckStatusesCount = 0;

  for (const item of Array.isArray(rawChecks) ? rawChecks : []) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      invalidCheckKeysCount += 1;
      continue;
    }
    const record = item as Record<string, unknown>;
    const rawKey = text(record.check_key);
    if (!allowedChecks.has(rawKey)) {
      invalidCheckKeysCount += 1;
      continue;
    }
    const checkKey = rawKey as ProcessSafetyCheckKey;
    if (seen.has(checkKey)) {
      duplicates.add(checkKey);
      continue;
    }
    seen.add(checkKey);
    const rawStatus = text(record.status);
    if (!allowedStatuses.has(rawStatus)) invalidCheckStatusesCount += 1;
    const status = allowedStatuses.has(rawStatus)
      ? rawStatus as ProcessSafetyCheckStatus
      : "uncertain";
    const allowedLayers = new Set<InspectionLayerKey>(
      PROCESS_SAFETY_LAYER_MAP[checkKey],
    );
    checks.push({
      check_key: checkKey,
      status,
      visual_evidence: cleanText(record.visual_evidence).slice(0, 300),
      linked_layer_keys: normalizeInspectionLayerKeys(
        record.linked_layer_keys,
      ).filter((layer) => allowedLayers.has(layer)),
      equipment_instance_key: normalizedInstanceKey(
        record.equipment_instance_key,
      ),
    });
  }

  const missing = scope === "applicable"
    ? PROCESS_SAFETY_CHECK_KEYS.filter((key) => !seen.has(key))
    : [];
  const validCheckCollection = duplicates.size === 0 &&
    invalidCheckKeysCount === 0 && invalidCheckStatusesCount === 0 &&
    checks.every((check) =>
      check.linked_layer_keys.length > 0 &&
      check.visual_evidence.length > 0 &&
      check.equipment_instance_key.length > 0
    );
  const complete = scopeValid &&
    (scope === "applicable"
      ? checks.length === PROCESS_SAFETY_CHECK_KEYS.length &&
        missing.length === 0 && duplicates.size === 0 &&
        validCheckCollection
      : scope === "not_applicable"
      ? checks.length === 0 && validCheckCollection
      : validCheckCollection);
  return {
    scope,
    checks,
    complete,
    missing_check_keys: [...missing],
    duplicate_check_keys: [...duplicates],
    invalid_check_keys_count: invalidCheckKeysCount,
    invalid_check_statuses_count: invalidCheckStatusesCount,
  };
}

export function applyProcessSafetyEvidenceGuard(
  findings: Array<Record<string, unknown>>,
  audit: NormalizedProcessSafetyAudit,
  enabled: boolean,
): ProcessSafetyEvidenceGuardResult {
  if (!enabled) {
    return {
      findings,
      applied: false,
      rejected_invalid_process_link_count: 0,
      rejected_non_actionable_process_count: 0,
      marked_uncertain_process_count: 0,
    };
  }
  if (!audit.complete || audit.scope === "not_applicable") {
    const accepted = findings.filter((finding) =>
      !Array.isArray(finding.process_safety_check_keys) ||
      finding.process_safety_check_keys.length === 0
    );
    return {
      findings: accepted,
      applied: true,
      rejected_invalid_process_link_count: findings.length - accepted.length,
      rejected_non_actionable_process_count: 0,
      marked_uncertain_process_count: 0,
    };
  }
  const statusByKey = new Map(
    audit.checks.map((check) => [check.check_key, check.status] as const),
  );
  const accepted: Array<Record<string, unknown>> = [];
  let rejectedInvalid = 0;
  let rejectedNonActionable = 0;
  let markedUncertain = 0;
  for (const finding of findings) {
    const rawKeys = Array.isArray(finding.process_safety_check_keys)
      ? finding.process_safety_check_keys
      : [];
    const keys = normalizeProcessSafetyCheckKeys(rawKeys);
    if (rawKeys.length === 0) {
      accepted.push(finding);
      continue;
    }
    if (keys.length !== rawKeys.length) {
      rejectedInvalid += 1;
      continue;
    }
    const statuses = keys.map((key) => statusByKey.get(key)).filter(
      (status): status is ProcessSafetyCheckStatus => Boolean(status),
    );
    if (statuses.length !== keys.length) {
      rejectedInvalid += 1;
      continue;
    }
    const supportedKeys = keys.filter((key) => {
      const status = statusByKey.get(key);
      return status === "actionable" || status === "uncertain";
    });
    if (statuses.includes("actionable")) {
      accepted.push({
        ...finding,
        process_safety_check_keys: supportedKeys,
      });
      continue;
    }
    if (statuses.includes("uncertain")) {
      const rawConfidence = Number(finding.confidence);
      accepted.push({
        ...finding,
        process_safety_check_keys: supportedKeys,
        confidence: Number.isFinite(rawConfidence)
          ? Math.max(0, Math.min(0.69, rawConfidence))
          : 0.5,
        needs_field_verification: true,
      });
      markedUncertain += 1;
      continue;
    }
    rejectedNonActionable += 1;
  }
  return {
    findings: accepted,
    applied: true,
    rejected_invalid_process_link_count: rejectedInvalid,
    rejected_non_actionable_process_count: rejectedNonActionable,
    marked_uncertain_process_count: markedUncertain,
  };
}

export function isFieldVerificationFinding(
  finding: Record<string, unknown>,
): boolean {
  return finding.verification_reason_code === "periodic_inspection_status" ||
    finding.display_group === "field_verification";
}

export function physicalFindings(
  findings: Array<Record<string, unknown>>,
): Array<Record<string, unknown>> {
  return findings.filter((finding) => !isFieldVerificationFinding(finding));
}

export function periodicInspectionEligible(
  scan: NormalizedEquipmentDepthScan,
): boolean {
  return scan.recognition_confidence >= 0.8 &&
    scan.visible_cues.length > 0 &&
    PERIODIC_INSPECTION_GROUPS.has(scan.equipment_group_code);
}

export function unrepresentedActionableProcessChecks(
  audit: NormalizedProcessSafetyAudit,
  findings: Array<Record<string, unknown>>,
): ProcessSafetyCheckKey[] {
  if (audit.scope !== "applicable" || !audit.complete) return [];
  const represented = new Set(
    physicalFindings(findings).flatMap((finding) =>
      normalizeProcessSafetyCheckKeys(finding.process_safety_check_keys)
    ),
  );
  return audit.checks
    .filter((check) => check.status === "actionable")
    .map((check) => check.check_key)
    .filter((key) => !represented.has(key));
}
