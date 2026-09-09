type FindingRecord = Record<string, unknown>;

export const ANALYSIS_QUALITY_TRACE_VERSION = 1;

export const QUALITY_TRACE_REASON_CODES = [
  "invalid_record",
  "finding_budget_exceeded",
  "duplicate_exact",
  "duplicate_fuzzy",
  "evidence_unlinked",
  "evidence_non_actionable",
  "process_link_invalid",
  "contextual_ppe_rejected",
  "repair_duplicate",
  "repair_unsupported",
  "final_limit_applied",
] as const;

export type QualityTraceReasonCode =
  | typeof QUALITY_TRACE_REASON_CODES[number]
  | "confidence_below_threshold";

export type ScoreMutationReasonCode =
  | "fk_value_clamped_to_allowed_scale"
  | "fk_frequency_missing_fallback"
  | "height_fatality_minimum_severity"
  | "m5_value_clamped"
  | "confidence_clamped_to_unit_interval"
  | "verification_derived_from_confidence"
  | "reference_removed_by_plan"
  | "reference_removed_by_safety_profile";

const QUALITY_TRACE_IDS = Symbol("analysis-quality-trace-ids-v1");

type TracedFinding = FindingRecord & {
  [QUALITY_TRACE_IDS]?: string[];
};

type StageSnapshot = {
  name: string;
  total: number;
  by_photo: Array<{ photo_index: number; count: number }>;
  delta_from_previous: number | null;
};

type RejectionSummary = {
  reason_code: QualityTraceReasonCode;
  count: number;
  by_photo: Array<{ photo_index: number; count: number }>;
  finding_trace_ids: string[];
};

export type QualityScoreValues = {
  fk_probability: number | null;
  fk_frequency: number | null;
  fk_severity: number | null;
  m5_probability: number | null;
  m5_severity: number | null;
  confidence: number | null;
  needs_field_verification: boolean | null;
};

export type QualityScoreMutation = {
  field: keyof QualityScoreValues | "references";
  before: number | boolean | string | null;
  after: number | boolean | string | null;
  reason_code: ScoreMutationReasonCode;
};

export type QualityScoreTrace = {
  finding_trace_id: string;
  source_photo_indices: number[];
  lineage_trace_ids: string[];
  model_raw: QualityScoreValues;
  server_final: QualityScoreValues;
  mutations: QualityScoreMutation[];
};

const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

function nearestAllowed(value: number, allowed: number[]): number {
  return allowed.reduce((previous, current) =>
    Math.abs(current - value) < Math.abs(previous - value) ? current : previous
  );
}

type PreviousQualityTrace = {
  stages?: unknown;
  rejections?: unknown;
  score_traces?: unknown;
  first_pass?: unknown;
};

function safePositiveInteger(value: unknown): number | null {
  try {
    const parsed = Math.round(Number(value));
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  } catch {
    return null;
  }
}

function safeNumber(value: unknown): number | null {
  try {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function sourcePhotoIndices(
  finding: FindingRecord,
  photoCount: number,
  fallbackPhotoIndex?: number,
): number[] {
  const values = Array.isArray(finding.source_photo_indices)
    ? finding.source_photo_indices
    : [];
  const normalized = [
    ...new Set(
      values.map(safePositiveInteger).filter(
        (value): value is number =>
          value !== null && value <= Math.max(1, photoCount),
      ),
    ),
  ].sort((left, right) => left - right);
  if (normalized.length > 0) return normalized;
  return fallbackPhotoIndex && fallbackPhotoIndex <= photoCount
    ? [fallbackPhotoIndex]
    : photoCount === 1
    ? [1]
    : [];
}

function findingRecords(value: unknown): FindingRecord[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is FindingRecord =>
    !!item && typeof item === "object" && !Array.isArray(item)
  );
}

function isPhysicalFinding(finding: FindingRecord): boolean {
  return finding.verification_reason_code !== "periodic_inspection_status" &&
    finding.display_group !== "field_verification";
}

export function qualityTraceIDs(value: unknown): string[] {
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const ids = (value as TracedFinding)[QUALITY_TRACE_IDS];
  return Array.isArray(ids) ? [...new Set(ids)].filter(Boolean) : [];
}

export function assignQualityTraceIDs(
  finding: FindingRecord,
  ids: string[],
): FindingRecord {
  try {
    Object.defineProperty(finding, QUALITY_TRACE_IDS, {
      configurable: true,
      enumerable: true,
      writable: true,
      value: [...new Set(ids)].filter(Boolean),
    });
  } catch {
    // Observability is fail-open. A frozen fixture/provider object keeps its
    // production value even when an internal lineage id cannot be attached.
  }
  return finding;
}

export function mergeQualityTraceIDs(
  target: FindingRecord,
  ...sources: FindingRecord[]
): FindingRecord {
  return assignQualityTraceIDs(
    target,
    sources.flatMap((source) => qualityTraceIDs(source)),
  );
}

export function primaryQualityTraceID(
  finding: FindingRecord,
  fallback: string,
): string {
  return qualityTraceIDs(finding)[0] ?? fallback;
}

function stageFromFindings(
  name: string,
  findings: FindingRecord[],
  photoCount: number,
): Omit<StageSnapshot, "delta_from_previous"> {
  const counts = Array.from({ length: photoCount }, (_, index) => ({
    photo_index: index + 1,
    count: 0,
  }));
  for (const finding of findings) {
    for (const photoIndex of sourcePhotoIndices(finding, photoCount)) {
      counts[photoIndex - 1].count += 1;
    }
  }
  return { name, total: findings.length, by_photo: counts };
}

function parsePreviousArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? value as T[] : [];
}

export class AnalysisQualityTraceCollector {
  readonly photoCount: number;
  readonly pass: "analysis" | "repair";
  private readonly stages = new Map<
    string,
    Omit<StageSnapshot, "delta_from_previous">
  >();
  private readonly rejections = new Map<
    QualityTraceReasonCode,
    { ids: Set<string>; photoCounts: Map<number, number>; anonymous: number }
  >();
  private readonly scoreTraces: QualityScoreTrace[] = [];
  private readonly previous: PreviousQualityTrace | null;
  private providerSequence = 0;

  constructor(
    photoCount: number,
    pass: "analysis" | "repair",
    previousTrace?: unknown,
  ) {
    this.photoCount = Math.max(0, Math.round(photoCount));
    this.pass = pass;
    this.previous = previousTrace && typeof previousTrace === "object" &&
        !Array.isArray(previousTrace)
      ? previousTrace as PreviousQualityTrace
      : null;
  }

  restoreInitialProviderTraceIDs(response: unknown): void {
    if (
      this.pass !== "repair" || !response || typeof response !== "object" ||
      Array.isArray(response)
    ) return;
    const result = response as FindingRecord;
    const records = Array.isArray(result.photo_findings)
      ? result.photo_findings
      : [];
    let restored = 0;
    records.forEach((item, recordIndex) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) return;
      const record = item as FindingRecord;
      const photoIndex = safePositiveInteger(record.photo_index);
      const rawFindings = Array.isArray(record.findings) ? record.findings : [];
      rawFindings.forEach((finding, findingIndex) => {
        if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
          return;
        }
        const typedFinding = finding as FindingRecord;
        if (!isPhysicalFinding(typedFinding)) return;
        assignQualityTraceIDs(typedFinding, [
          `i:p${photoIndex ?? "x"}:f${findingIndex + 1}:r${recordIndex + 1}`,
        ]);
        restored += 1;
      });
    });
    if (restored > 0) return;
    findingRecords(result.hazards).forEach((finding, index) => {
      if (!isPhysicalFinding(finding)) return;
      const photos = sourcePhotoIndices(finding, this.photoCount);
      assignQualityTraceIDs(finding, [
        `i:p${photos[0] ?? "x"}:h${index + 1}`,
      ]);
    });
  }

  attachCurrentResultTraceIDs(response: unknown): void {
    if (!response || typeof response !== "object" || Array.isArray(response)) {
      return;
    }
    const result = response as FindingRecord;
    const prefix = this.pass === "repair" ? "r" : "i";
    const records = Array.isArray(result.photo_findings)
      ? result.photo_findings
      : [];
    let attached = 0;
    records.forEach((item, recordIndex) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) return;
      const record = item as FindingRecord;
      const photoIndex = safePositiveInteger(record.photo_index);
      const rawFindings = Array.isArray(record.findings) ? record.findings : [];
      rawFindings.forEach((finding, findingIndex) => {
        if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
          return;
        }
        const typedFinding = finding as FindingRecord;
        if (!isPhysicalFinding(typedFinding)) return;
        if (qualityTraceIDs(typedFinding).length > 0) {
          attached += 1;
          return;
        }
        assignQualityTraceIDs(typedFinding, [
          `${prefix}:p${photoIndex ?? "x"}:f${findingIndex + 1}:r${
            recordIndex + 1
          }`,
        ]);
        attached += 1;
      });
    });
    if (attached > 0) return;
    findingRecords(result.hazards).forEach((finding, index) => {
      if (!isPhysicalFinding(finding)) return;
      if (qualityTraceIDs(finding).length > 0) return;
      const photos = sourcePhotoIndices(finding, this.photoCount);
      assignQualityTraceIDs(finding, [
        `${prefix}:p${photos[0] ?? "x"}:h${index + 1}`,
      ]);
    });
  }

  observeProviderResponse(response: unknown): void {
    if (!response || typeof response !== "object" || Array.isArray(response)) {
      return;
    }
    const result = response as FindingRecord;
    const all: FindingRecord[] = [];
    const records = Array.isArray(result.photo_findings)
      ? result.photo_findings
      : [];
    records.forEach((item, recordIndex) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        this.reject("invalid_record", [], null, 1);
        return;
      }
      const record = item as FindingRecord;
      const photoIndex = safePositiveInteger(record.photo_index);
      if (!photoIndex || photoIndex > this.photoCount) {
        this.reject("invalid_record", [], null, 1);
      }
      const rawFindings = Array.isArray(record.findings) ? record.findings : [];
      rawFindings.forEach((finding, findingIndex) => {
        if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
          this.reject("invalid_record", [], photoIndex, 1);
          return;
        }
        const typedFinding = finding as FindingRecord;
        if (!isPhysicalFinding(typedFinding)) return;
        const traceID = `${this.pass === "repair" ? "r" : "i"}:p${
          photoIndex ?? "x"
        }:f${findingIndex + 1}:r${recordIndex + 1}`;
        assignQualityTraceIDs(typedFinding, [traceID]);
        all.push(typedFinding);
      });
    });

    if (all.length === 0) {
      findingRecords(result.hazards).forEach((finding) => {
        if (!isPhysicalFinding(finding)) return;
        this.providerSequence += 1;
        const photos = sourcePhotoIndices(finding, this.photoCount);
        const traceID = `${this.pass === "repair" ? "r" : "i"}:p${
          photos[0] ?? "x"
        }:h${this.providerSequence}`;
        assignQualityTraceIDs(finding, [traceID]);
        all.push(finding);
      });
    }

    this.capture(
      this.pass === "repair" ? "repair_provider_parsed" : "provider_parsed",
      all,
    );
  }

  capture(name: string, findings: FindingRecord[]): void {
    this.stages.set(
      name,
      stageFromFindings(name, findings, this.photoCount),
    );
  }

  capturePhoto(
    name: string,
    photoIndex: number,
    findings: FindingRecord[],
  ): void {
    const existing = this.stages.get(name) ?? {
      name,
      total: 0,
      by_photo: Array.from({ length: this.photoCount }, (_, index) => ({
        photo_index: index + 1,
        count: 0,
      })),
    };
    if (existing.by_photo[photoIndex - 1]) {
      existing.by_photo[photoIndex - 1].count += findings.length;
    }
    existing.total += findings.length;
    this.stages.set(name, existing);
  }

  reject(
    reason: QualityTraceReasonCode,
    findings: FindingRecord[] = [],
    fallbackPhotoIndex: number | null = null,
    anonymousCount = 0,
  ): void {
    const summary = this.rejections.get(reason) ?? {
      ids: new Set<string>(),
      photoCounts: new Map<number, number>(),
      anonymous: 0,
    };
    for (const finding of findings) {
      const ids = qualityTraceIDs(finding);
      ids.forEach((id) => summary.ids.add(id));
      const photos = sourcePhotoIndices(
        finding,
        this.photoCount,
        fallbackPhotoIndex ?? undefined,
      );
      photos.forEach((photoIndex) =>
        summary.photoCounts.set(
          photoIndex,
          (summary.photoCounts.get(photoIndex) ?? 0) + 1,
        )
      );
      if (ids.length === 0 && photos.length === 0) summary.anonymous += 1;
    }
    if (anonymousCount > 0) {
      summary.anonymous += anonymousCount;
      if (fallbackPhotoIndex) {
        summary.photoCounts.set(
          fallbackPhotoIndex,
          (summary.photoCounts.get(fallbackPhotoIndex) ?? 0) + anonymousCount,
        );
      }
    }
    this.rejections.set(reason, summary);
  }

  rejectedBetween(
    reason: QualityTraceReasonCode,
    before: FindingRecord[],
    after: FindingRecord[],
    fallbackPhotoIndex: number | null = null,
  ): FindingRecord[] {
    const acceptedIDs = new Set(after.flatMap(qualityTraceIDs));
    const removed = before.filter((finding) => {
      const ids = qualityTraceIDs(finding);
      return ids.length === 0 || ids.every((id) => !acceptedIDs.has(id));
    });
    this.reject(reason, removed, fallbackPhotoIndex);
    return removed;
  }

  addScoreTrace(trace: QualityScoreTrace): void {
    this.scoreTraces.push(trace);
  }

  build(params: {
    lifecycleState?: "completed" | "repair_pending";
    promptVersion: string | null;
    policyVersion: string | null;
    model: string;
    provider: string;
    plan: string;
    outputLanguage: string;
    schemaFallbackUsed: boolean;
    repairCandidatePhotoIndices: number[];
    repairAddedCount: number;
    repairCalled: boolean;
    persistenceFindings: FindingRecord[];
    totalDurationMs: number;
    providerRequestCount: number;
    tokens: {
      input: number;
      output: number;
      cached: number;
      thoughts: number;
      total: number;
    };
  }): Record<string, unknown> {
    if (params.lifecycleState !== "repair_pending") {
      this.capture("persistence_submitted", params.persistenceFindings);
      // Both persistence paths write findings before, or atomically with, this
      // trace. If persistence fails the completed response is never stored.
      this.capture("database_final", params.persistenceFindings);
    }

    const preferredOrder = [
      "provider_parsed",
      "normalization",
      "evidence_process_guard",
      "finding_budget",
      "dedup",
      "first_pass_final_candidates",
      "repair_provider_parsed",
      "repair_merged",
      "persistence_submitted",
      "database_final",
    ];
    const previousStages = parsePreviousArray<StageSnapshot>(
      this.previous?.stages,
    );
    const combined = new Map<
      string,
      Omit<StageSnapshot, "delta_from_previous">
    >();
    previousStages.forEach((stage) => {
      if (!stage || typeof stage.name !== "string") return;
      combined.set(stage.name, {
        name: stage.name,
        total: Math.max(0, Math.round(Number(stage.total)) || 0),
        by_photo: Array.isArray(stage.by_photo) ? stage.by_photo : [],
      });
    });
    this.stages.forEach((stage, name) => combined.set(name, stage));
    let priorTotal: number | null = null;
    const stages: StageSnapshot[] = preferredOrder
      .filter((name) => combined.has(name))
      .map((name) => {
        const stage = combined.get(name)!;
        const result = {
          ...stage,
          delta_from_previous: priorTotal === null
            ? null
            : stage.total - priorTotal,
        };
        priorTotal = stage.total;
        return result;
      });

    const previousRejections = parsePreviousArray<RejectionSummary>(
      this.previous?.rejections,
    );
    const rejections = new Map<string, RejectionSummary>();
    previousRejections.forEach((item) => {
      if (!item || typeof item.reason_code !== "string") return;
      rejections.set(item.reason_code, item);
    });
    this.rejections.forEach((summary, reason) => {
      const prior = rejections.get(reason);
      const priorIDs = new Set(prior?.finding_trace_ids ?? []);
      const newIDs = [...summary.ids].filter((id) => !priorIDs.has(id));
      const ids = [
        ...new Set([
          ...(prior?.finding_trace_ids ?? []),
          ...summary.ids,
        ]),
      ];
      const byPhoto = Array.from({ length: this.photoCount }, (_, index) => {
        const photoIndex = index + 1;
        const priorCount = prior?.by_photo?.find((item) =>
          item.photo_index === photoIndex
        )?.count ?? 0;
        return {
          photo_index: photoIndex,
          count: priorCount + (summary.photoCounts.get(photoIndex) ?? 0),
        };
      });
      rejections.set(reason, {
        reason_code: reason,
        count: (prior?.count ?? 0) + newIDs.length + summary.anonymous,
        by_photo: byPhoto,
        finding_trace_ids: ids,
      });
    });

    const scoreTraces = this.scoreTraces.length > 0
      ? this.scoreTraces
      : parsePreviousArray<QualityScoreTrace>(this.previous?.score_traces);
    const stageTotal = (name: string): number =>
      stages.find((stage) => stage.name === name)?.total ?? 0;
    const zeroFindingPhotos = stages
      .find((stage) => stage.name === "database_final")?.by_photo
      .filter((item) => item.count === 0).length ?? this.photoCount;

    return {
      version: ANALYSIS_QUALITY_TRACE_VERSION,
      trace_mode: "full_trace",
      lifecycle_state: params.lifecycleState ?? "completed",
      execution_order: preferredOrder,
      cohort: {
        prompt_version: params.promptVersion,
        policy_version: params.policyVersion,
        model: params.model,
        provider: params.provider,
        plan: params.plan,
        output_language: params.outputLanguage,
        photo_count: this.photoCount,
        photo_mode: this.photoCount > 1 ? "multi_photo" : "single_photo",
      },
      stages,
      rejections: [...rejections.values()].sort((left, right) =>
        left.reason_code.localeCompare(right.reason_code)
      ),
      score_traces: scoreTraces,
      repair: {
        called: params.repairCalled,
        candidate_photo_indices: params.repairCandidatePhotoIndices,
        added_count: params.repairAddedCount,
        yield: params.repairCalled
          ? params.repairAddedCount /
            Math.max(1, stageTotal("repair_provider_parsed"))
          : 0,
      },
      provider: {
        request_count: params.providerRequestCount,
        duration_ms: params.totalDurationMs,
        schema_fallback_used: params.schemaFallbackUsed,
        tokens: params.tokens,
      },
      summary: {
        raw_findings: stageTotal("provider_parsed"),
        final_findings: stageTotal("database_final"),
        zero_finding_photos: zeroFindingPhotos,
        raw_to_final_retention: stageTotal("provider_parsed") > 0
          ? stageTotal("database_final") / stageTotal("provider_parsed")
          : null,
        repair_added_findings: params.repairAddedCount,
        score_mutation_count: scoreTraces.reduce(
          (total, trace) => total + trace.mutations.length,
          0,
        ),
      },
    };
  }
}

export function rawQualityScoreValues(
  hazard: FindingRecord,
): QualityScoreValues {
  return {
    fk_probability: safeNumber(hazard.fk_probability),
    fk_frequency: safeNumber(hazard.fk_frequency),
    fk_severity: safeNumber(hazard.fk_severity),
    m5_probability: safeNumber(hazard.m5_probability),
    m5_severity: safeNumber(hazard.m5_severity),
    confidence: safeNumber(hazard.confidence),
    needs_field_verification:
      typeof hazard.needs_field_verification === "boolean"
        ? hazard.needs_field_verification
        : null,
  };
}

export function buildQualityScoreMutationTrace(
  hazard: FindingRecord,
  final: {
    fkP: number;
    fkF: number;
    fkS: number;
    m5P: number;
    m5S: number;
    confidence: number;
    needsFieldVerification: boolean;
  },
  referencesRemovedReason:
    | "reference_removed_by_plan"
    | "reference_removed_by_safety_profile"
    | null,
): {
  modelRaw: QualityScoreValues;
  serverFinal: QualityScoreValues;
  mutations: QualityScoreMutation[];
} {
  const modelRaw = rawQualityScoreValues(hazard);
  const mutations: QualityScoreMutation[] = [];
  const add = (
    field: QualityScoreMutation["field"],
    before: QualityScoreMutation["before"],
    after: QualityScoreMutation["after"],
    reason_code: QualityScoreMutation["reason_code"],
  ) => mutations.push({ field, before, after, reason_code });

  if (modelRaw.fk_probability !== final.fkP) {
    add(
      "fk_probability",
      modelRaw.fk_probability,
      final.fkP,
      "fk_value_clamped_to_allowed_scale",
    );
  }
  if (modelRaw.fk_frequency === null) {
    add(
      "fk_frequency",
      null,
      final.fkF,
      "fk_frequency_missing_fallback",
    );
  } else if (modelRaw.fk_frequency !== final.fkF) {
    add(
      "fk_frequency",
      modelRaw.fk_frequency,
      final.fkF,
      "fk_value_clamped_to_allowed_scale",
    );
  }
  const clampedSeverity = nearestAllowed(
    Number(hazard.fk_severity),
    FK_SEVERITY_VALUES,
  );
  if (modelRaw.fk_severity !== clampedSeverity) {
    add(
      "fk_severity",
      modelRaw.fk_severity,
      clampedSeverity,
      "fk_value_clamped_to_allowed_scale",
    );
  }
  if (clampedSeverity !== final.fkS) {
    add(
      "fk_severity",
      clampedSeverity,
      final.fkS,
      "height_fatality_minimum_severity",
    );
  }
  if (modelRaw.m5_probability !== final.m5P) {
    add(
      "m5_probability",
      modelRaw.m5_probability,
      final.m5P,
      "m5_value_clamped",
    );
  }
  const roundedM5Severity = Math.max(
    1,
    Math.min(5, Math.round(Number(hazard.m5_severity))),
  );
  if (modelRaw.m5_severity !== roundedM5Severity) {
    add(
      "m5_severity",
      modelRaw.m5_severity,
      roundedM5Severity,
      "m5_value_clamped",
    );
  }
  if (roundedM5Severity !== final.m5S) {
    add(
      "m5_severity",
      roundedM5Severity,
      final.m5S,
      "height_fatality_minimum_severity",
    );
  }
  if (modelRaw.confidence !== final.confidence) {
    add(
      "confidence",
      modelRaw.confidence,
      final.confidence,
      "confidence_clamped_to_unit_interval",
    );
  }
  if (modelRaw.needs_field_verification !== final.needsFieldVerification) {
    add(
      "needs_field_verification",
      modelRaw.needs_field_verification,
      final.needsFieldVerification,
      "verification_derived_from_confidence",
    );
  }
  if (
    referencesRemovedReason && hazard.references !== null &&
    hazard.references !== undefined && String(hazard.references).trim()
  ) {
    add("references", "present", "removed", referencesRemovedReason);
  }

  return {
    modelRaw,
    serverFinal: {
      fk_probability: final.fkP,
      fk_frequency: final.fkF,
      fk_severity: final.fkS,
      m5_probability: final.m5P,
      m5_severity: final.m5S,
      confidence: final.confidence,
      needs_field_verification: final.needsFieldVerification,
    },
    mutations,
  };
}
