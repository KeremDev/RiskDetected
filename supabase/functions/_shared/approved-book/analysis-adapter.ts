// v4 analysis items -> canonical BookSourceItem.
//
// v4 only, deliberately. The v3 engine (analyze-vnext) has no condition code, no
// evidence tier and no per-axis confidence, so a v3 adapter could only recover
// those by reading the model's sentences -- which is the one thing this engine
// exists to avoid. v3 analyses keep the v2 notebook projection instead.
//
// An item with no `internal_priority.book_source` block is not adapted. That is
// the correct outcome for module-coverage records ("bu modül sahada kontrol
// edilmeli"), which the plan's writability matrix rejects anyway: they name no
// asset and no concrete verification, so there is nothing to write a book
// sentence about.

import type {
  BookSourceClass,
  BookSourceItem,
  Criticality,
  EvidenceTier,
} from "./contracts.ts";

const BOOK_CLASSES: BookSourceClass[] = [
  "observed_finding",
  "assurance_requirement",
  "verification_request",
];

const EVIDENCE_TIERS: EvidenceTier[] = ["E0", "E1", "E2", "E3", "E4", "E5"];
const CRITICALITIES: Criticality[] = [
  "fatal",
  "permanent",
  "serious",
  "ordinary",
];

export type V4ItemRow = {
  public_finding_id?: string | null;
  criticality?: string | null;
  canonical_payload?: Record<string, unknown> | null;
  internal_priority?: Record<string, unknown> | null;
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function text(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : fallback;
}

function unitInterval(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.min(1, parsed));
}

function codeList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((entry) => text(entry)).filter(Boolean).sort();
}

function photoIndices(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  const parsed = value
    .map((entry) => Number(entry))
    .filter((entry) => Number.isInteger(entry) && entry >= 1);
  return [...new Set(parsed)].sort((left, right) => left - right);
}

/**
 * One item, or null when it carries no canonical codes.
 *
 * Null is a routine answer, not a failure: positive controls, not-assessable
 * records and coverage-derived field checks all land here and all of them are
 * correctly excluded from the book.
 */
export function adaptV4Item(row: V4ItemRow): BookSourceItem | null {
  const sourceItemId = text(row.public_finding_id);
  if (!sourceItemId) return null;

  const internal = record(row.internal_priority);
  const book = record(internal.book_source);
  if (text(book.schema) !== "book-source-v1") return null;

  const itemClass = text(book.item_class) as BookSourceClass;
  if (!BOOK_CLASSES.includes(itemClass)) return null;

  const moduleId = text(book.module_id);
  const conditionCode = text(book.condition_code);
  if (!moduleId || !conditionCode) return null;

  const evidenceRaw = text(book.evidence_level, "E0") as EvidenceTier;
  const evidenceTier = EVIDENCE_TIERS.includes(evidenceRaw) ? evidenceRaw : "E0";

  const criticalityRaw = text(
    book.criticality,
    text(row.criticality, "ordinary"),
  ) as Criticality;
  const criticality = CRITICALITIES.includes(criticalityRaw)
    ? criticalityRaw
    : "ordinary";

  const confidence = record(book.confidence);
  const payload = record(row.canonical_payload);

  return {
    sourceItemId,
    itemClass,
    moduleId,
    conditionCode,
    mechanismCode: text(book.mechanism_code) || null,
    assuranceTopicId: text(book.assurance_topic_id) || null,
    assetFamily: text(book.asset_family, moduleId),
    assetRef: text(book.asset_ref) || null,
    barrierComponentsAbsent: codeList(book.barrier_components_absent),
    evidenceTier,
    criticality,
    occlusion: text(book.occlusion, "unknown"),
    confidence: {
      visibility: unitInterval(confidence.visibility),
      localization: unitInterval(confidence.localization),
      mechanism: unitInterval(confidence.mechanism),
    },
    visuallyResolvable: book.visually_resolvable === true,
    requiresDocumentOrMeasurement:
      book.requires_document_or_measurement === true,
    accessibleEventPath: book.accessible_event_path === true,
    peopleVisible: Math.max(0, Math.trunc(Number(book.people_visible) || 0)),
    photoIndices: photoIndices(payload.source_photo_indices),
    needsFieldVerification: payload.needs_field_verification === true,
    rawForReview: undefined,
  };
}

export function adaptV4Items(rows: V4ItemRow[]): BookSourceItem[] {
  const adapted: BookSourceItem[] = [];
  for (const row of rows) {
    const item = adaptV4Item(row);
    if (item) adapted.push(item);
  }
  // Stable order so the same analysis always clusters identically.
  return adapted.sort((left, right) =>
    left.sourceItemId.localeCompare(right.sourceItemId)
  );
}
