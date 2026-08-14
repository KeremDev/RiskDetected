export type CoverageContractOutcome =
  | "not_applicable"
  | "complete"
  | "normalized_contract_violation"
  | "missing_records";

export type PhotoCoverageContract = {
  expected_indices: number[];
  expected_records: number;
  returned_records: number;
  valid_indices: number[];
  missing_indices: number[];
  duplicate_indices: number[];
  invalid_indices: Array<number | null>;
  normalized_records: number;
  outcome: CoverageContractOutcome;
};

export function coverageRecordRequiresRepair(input: {
  recordMissing: boolean;
  coverageStatus: string;
  findingCount: number;
  targetMin: number;
}): boolean {
  return input.recordMissing ||
    (input.coverageStatus === "actionable" &&
      input.findingCount < input.targetMin);
}

export function normalizeExpectedPhotoIndices(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => Math.round(Number(item)))
        .filter((item) => Number.isFinite(item) && item > 0),
    ),
  ].sort((a, b) => a - b);
}

export function exactCoverageSchemaConstraints(input: {
  schemaVersion: unknown;
  originalPhotoCount: unknown;
  expectedPhotoIndices: unknown;
}): {
  enabled: boolean;
  minItems?: number;
  maxItems?: number;
  photoIndexEnum?: string[];
} {
  const expectedPhotoIndices = normalizeExpectedPhotoIndices(
    input.expectedPhotoIndices,
  );
  const enabled = Number(input.schemaVersion) === 2 &&
    Number(input.originalPhotoCount) > 1 && expectedPhotoIndices.length > 0;
  return enabled
    ? {
      enabled: true,
      minItems: expectedPhotoIndices.length,
      maxItems: expectedPhotoIndices.length,
      // generateContent's OpenAPI-compatible Schema protobuf represents enum
      // members as strings even when the declared field type is INTEGER. The
      // model still emits JSON numbers because photo_index remains INTEGER.
      photoIndexEnum: expectedPhotoIndices.map(String),
    }
    : { enabled: false };
}

export function inspectPhotoCoverageContract(
  rawPhotoFindings: unknown,
  rawExpectedIndices: unknown,
): PhotoCoverageContract {
  const expectedIndices = normalizeExpectedPhotoIndices(rawExpectedIndices);
  if (expectedIndices.length === 0) {
    return {
      expected_indices: [],
      expected_records: 0,
      returned_records: Array.isArray(rawPhotoFindings)
        ? rawPhotoFindings.length
        : 0,
      valid_indices: [],
      missing_indices: [],
      duplicate_indices: [],
      invalid_indices: [],
      normalized_records: 0,
      outcome: "not_applicable",
    };
  }

  const expected = new Set(expectedIndices);
  const seen = new Map<number, number>();
  const invalidIndices: Array<number | null> = [];
  const records = Array.isArray(rawPhotoFindings) ? rawPhotoFindings : [];

  for (const item of records) {
    if (!item || typeof item !== "object") {
      invalidIndices.push(null);
      continue;
    }
    const rawIndex = (item as Record<string, unknown>).photo_index;
    const numeric = Number(rawIndex);
    const photoIndex = Math.round(numeric);
    if (!Number.isFinite(numeric) || !expected.has(photoIndex)) {
      invalidIndices.push(Number.isFinite(numeric) ? photoIndex : null);
      continue;
    }
    seen.set(photoIndex, (seen.get(photoIndex) ?? 0) + 1);
  }

  const validIndices = [...seen.keys()].sort((a, b) => a - b);
  const missingIndices = expectedIndices.filter((index) => !seen.has(index));
  const duplicateIndices = [...seen.entries()]
    .filter(([, count]) => count > 1)
    .map(([index]) => index)
    .sort((a, b) => a - b);
  const outcome: CoverageContractOutcome = missingIndices.length > 0
    ? "missing_records"
    : duplicateIndices.length > 0 || invalidIndices.length > 0 ||
        records.length !== expectedIndices.length
    ? "normalized_contract_violation"
    : "complete";

  return {
    expected_indices: expectedIndices,
    expected_records: expectedIndices.length,
    returned_records: records.length,
    valid_indices: validIndices,
    missing_indices: missingIndices,
    duplicate_indices: duplicateIndices,
    invalid_indices: invalidIndices,
    normalized_records: validIndices.length,
    outcome,
  };
}
