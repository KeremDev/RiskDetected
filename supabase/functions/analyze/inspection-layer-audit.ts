export const INSPECTION_LAYER_KEYS = [
  "ground_housekeeping",
  "ppe",
  "work_at_height",
  "electrical_energy",
  "machinery_equipment",
  "lifting_handling_storage",
  "chemicals",
  "fire_explosion",
  "physical_environment",
  "ergonomics_manual_handling",
  "excavation_confined_special_work",
  "environment_emergency_signage_competence",
] as const;

export const INSPECTION_LAYER_STATUSES = [
  "not_visible",
  "checked_no_hazard",
  "actionable",
  "uncertain",
] as const;

export type InspectionLayerKey = typeof INSPECTION_LAYER_KEYS[number];
export type InspectionLayerStatus = typeof INSPECTION_LAYER_STATUSES[number];

export type NormalizedInspectionLayer = {
  layer_key: InspectionLayerKey;
  status: InspectionLayerStatus;
  visual_evidence: string;
};

export type InspectionLayerEvidenceGuardResult = {
  findings: Array<Record<string, unknown>>;
  applied: boolean;
  rejected_unlinked_count: number;
  rejected_non_actionable_count: number;
  marked_uncertain_count: number;
};

const INSPECTION_LAYER_KEY_ALIASES: Record<string, InspectionLayerKey> = {
  zemin_saha_duzeni_duzen_tertip: "ground_housekeeping",
  calisan_kkd: "ppe",
  yuksekte_calisma: "work_at_height",
  elektrik_enerji: "electrical_energy",
  makine_ekipman_is_ekipmani: "machinery_equipment",
  kaldirma_tasima_istifleme: "lifting_handling_storage",
  kimyasal_tehlikeli_madde: "chemicals",
  yangin_patlama: "fire_explosion",
  fiziksel_ortam_etkenleri: "physical_environment",
  ergonomi_elle_tasima: "ergonomics_manual_handling",
  kazi_kapali_alan_ozel_isler: "excavation_confined_special_work",
  cevre_acil_durum_isaretleme_yetkinlik:
    "environment_emergency_signage_competence",
};

function text(value: unknown): string {
  return value == null ? "" : String(value).trim();
}

function normalizeInspectionLayerKey(
  value: unknown,
): InspectionLayerKey | null {
  const raw = text(value).toLowerCase();
  const allowed = new Set<string>(INSPECTION_LAYER_KEYS);
  if (allowed.has(raw)) return raw as InspectionLayerKey;
  return INSPECTION_LAYER_KEY_ALIASES[raw] ?? null;
}

function isImageLimitedNonObservation(value: string): boolean {
  const normalized = value.toLocaleLowerCase("tr-TR");
  const mentionsImage = /fotoğraf|görsel|görüntü|kadraj|netlik|çözünürlük/.test(
    normalized,
  );
  const mentionsImageLimitation =
    /bulanık|bulanıklık|net değil|net olm|düşük çözünürlük|görüntü kalitesi|kadraj dışında/
      .test(
        normalized,
      );
  const reportsNonObservation =
    /görünm|tespit edilem|değerlendirilem|seçilem|ayırt edilem/.test(
      normalized,
    );
  return mentionsImage && mentionsImageLimitation && reportsNonObservation;
}

export function normalizeInspectionLayerKeys(
  value: unknown,
): InspectionLayerKey[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.map(normalizeInspectionLayerKey).filter(
        (item): item is InspectionLayerKey => item !== null,
      ),
    ),
  ];
}

export function invalidInspectionLayerKeyCount(value: unknown): number {
  if (!Array.isArray(value)) return 0;
  return value.reduce(
    (count, item) => count + (normalizeInspectionLayerKey(item) ? 0 : 1),
    0,
  );
}

export function normalizeInspectionLayers(
  value: unknown,
  cleanEvidence: (value: unknown) => string = text,
): {
  layers: NormalizedInspectionLayer[];
  missing: InspectionLayerKey[];
  duplicates: InspectionLayerKey[];
  invalidKeyCount: number;
  invalidStatusCount: number;
} {
  const allowedStatuses = new Set<string>(INSPECTION_LAYER_STATUSES);
  const layers: NormalizedInspectionLayer[] = [];
  const seen = new Set<InspectionLayerKey>();
  const duplicates = new Set<InspectionLayerKey>();
  let invalidKeyCount = 0;
  let invalidStatusCount = 0;

  for (const item of Array.isArray(value) ? value : []) {
    if (!item || typeof item !== "object") {
      invalidKeyCount += 1;
      continue;
    }
    const record = item as Record<string, unknown>;
    const typedKey = normalizeInspectionLayerKey(record.layer_key);
    if (!typedKey) {
      invalidKeyCount += 1;
      continue;
    }
    if (seen.has(typedKey)) {
      duplicates.add(typedKey);
      continue;
    }
    seen.add(typedKey);
    const rawStatus = text(record.status);
    const visualEvidence = cleanEvidence(record.visual_evidence).slice(0, 300);
    const parsedStatus = allowedStatuses.has(rawStatus)
      ? rawStatus as InspectionLayerStatus
      : "uncertain";
    const status =
      (parsedStatus === "actionable" || parsedStatus === "uncertain") &&
        isImageLimitedNonObservation(visualEvidence)
        ? "not_visible"
        : parsedStatus;
    if (!allowedStatuses.has(rawStatus)) invalidStatusCount += 1;
    layers.push({
      layer_key: typedKey,
      status,
      visual_evidence: visualEvidence,
    });
  }

  return {
    layers,
    missing: INSPECTION_LAYER_KEYS.filter((key) => !seen.has(key)),
    duplicates: [...duplicates],
    invalidKeyCount,
    invalidStatusCount,
  };
}

export function hasCompleteInspectionLayerContract(
  normalized: ReturnType<typeof normalizeInspectionLayers>,
): boolean {
  return normalized.layers.length === INSPECTION_LAYER_KEYS.length &&
    normalized.missing.length === 0 &&
    normalized.duplicates.length === 0 &&
    normalized.invalidKeyCount === 0 &&
    normalized.invalidStatusCount === 0;
}

export function applyInspectionLayerEvidenceGuard(
  findings: Array<Record<string, unknown>>,
  normalized: ReturnType<typeof normalizeInspectionLayers>,
  enabled: boolean,
): InspectionLayerEvidenceGuardResult {
  if (!enabled || !hasCompleteInspectionLayerContract(normalized)) {
    return {
      findings,
      applied: false,
      rejected_unlinked_count: 0,
      rejected_non_actionable_count: 0,
      marked_uncertain_count: 0,
    };
  }

  const statusByLayer = new Map(
    normalized.layers.map((layer) => [layer.layer_key, layer.status] as const),
  );
  const accepted: Array<Record<string, unknown>> = [];
  let rejectedUnlinkedCount = 0;
  let rejectedNonActionableCount = 0;
  let markedUncertainCount = 0;

  for (const finding of findings) {
    const layerKeys = normalizeInspectionLayerKeys(
      finding.inspection_layer_keys,
    );
    if (layerKeys.length === 0) {
      rejectedUnlinkedCount += 1;
      continue;
    }

    const statuses = layerKeys
      .map((key) => statusByLayer.get(key))
      .filter((status): status is InspectionLayerStatus => Boolean(status));
    if (statuses.includes("actionable")) {
      accepted.push({ ...finding, inspection_layer_keys: layerKeys });
      continue;
    }

    if (statuses.includes("uncertain")) {
      const rawConfidence = Number(finding.confidence);
      const confidence = Number.isFinite(rawConfidence)
        ? Math.max(0, Math.min(0.69, rawConfidence))
        : 0;
      accepted.push({
        ...finding,
        inspection_layer_keys: layerKeys,
        confidence,
        needs_field_verification: true,
      });
      markedUncertainCount += 1;
      continue;
    }

    rejectedNonActionableCount += 1;
  }

  return {
    findings: accepted,
    applied: true,
    rejected_unlinked_count: rejectedUnlinkedCount,
    rejected_non_actionable_count: rejectedNonActionableCount,
    marked_uncertain_count: markedUncertainCount,
  };
}
