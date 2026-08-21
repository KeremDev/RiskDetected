type FindingRecord = Record<string, unknown>;

export const COVERAGE_QUALITY_POLICY_VERSION = 2;

export const COVERAGE_QUALITY_NO_ADDITIONAL_REASON_CODES = [
  "no_distinct_additional_hazard",
  "insufficient_visual_evidence",
  "existing_findings_cover_scene",
] as const;

export type CoverageQualityNoAdditionalReasonCode =
  typeof COVERAGE_QUALITY_NO_ADDITIONAL_REASON_CODES[number];

export type CoverageQualityTriggerReason =
  | "low_finding_count"
  | "candidate_gap"
  | "multi_layer_finding"
  | "unrepresented_actionable_layer"
  | "evidence_guard_rejection"
  | "evidence_guard_uncertain"
  | "record_incomplete";

export type CoverageQualityRecordInput = {
  photo_index: number;
  coverage_status: string;
  candidate_findings_count: number;
  findings: FindingRecord[];
  record_missing: boolean;
  inspection_layers: Array<{
    layer_key: string;
    status: string;
  }>;
  layer_audit: {
    missing_layer_keys: string[];
    duplicate_layer_keys: string[];
    invalid_layer_keys_count: number;
    invalid_layer_statuses_count: number;
  };
  evidence_guard: {
    rejected_unlinked_count: number;
    rejected_non_actionable_count: number;
    marked_uncertain_count: number;
  };
};

export type CoverageQualityEvaluation = {
  photo_index: number;
  eligible: boolean;
  should_repair: boolean;
  trigger_reasons: CoverageQualityTriggerReason[];
  candidate_semantics_evaluable: boolean;
  initial_candidate_findings_count: number;
  initial_generated_findings_count: number;
  actionable_layer_count: number;
  represented_actionable_layer_count: number;
  unrepresented_actionable_layers: string[];
};

function text(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value).trim();
}

function safeNonNegativeCount(value: unknown): number {
  const count = Math.round(Number(value));
  return Number.isFinite(count) && count > 0 ? count : 0;
}

function findingLayerKeys(finding: FindingRecord): string[] {
  if (!Array.isArray(finding.inspection_layer_keys)) return [];
  return [
    ...new Set(
      finding.inspection_layer_keys
        .map((value) => text(value).toLowerCase())
        .filter(Boolean),
    ),
  ];
}

export function normalizeCoverageQualityNoAdditionalReasonCode(
  value: unknown,
): CoverageQualityNoAdditionalReasonCode | null {
  const normalized = text(value);
  return COVERAGE_QUALITY_NO_ADDITIONAL_REASON_CODES.includes(
      normalized as CoverageQualityNoAdditionalReasonCode,
    )
    ? normalized as CoverageQualityNoAdditionalReasonCode
    : null;
}

export function evaluateCoverageQualityRecord(
  record: CoverageQualityRecordInput,
  options: { candidateSemanticsV2: boolean },
): CoverageQualityEvaluation {
  const findings = Array.isArray(record.findings) ? record.findings : [];
  const actionableLayers = record.inspection_layers
    .filter((layer) => layer.status === "actionable")
    .map((layer) => layer.layer_key);
  const representedLayers = new Set(
    findings.flatMap((finding) => findingLayerKeys(finding)),
  );
  const unrepresentedActionableLayers = actionableLayers.filter((layer) =>
    !representedLayers.has(layer)
  );
  const eligible = record.coverage_status === "actionable";
  const triggerReasons: CoverageQualityTriggerReason[] = [];

  if (eligible) {
    if (findings.length <= 1) triggerReasons.push("low_finding_count");
    if (
      options.candidateSemanticsV2 &&
      safeNonNegativeCount(record.candidate_findings_count) > findings.length
    ) {
      triggerReasons.push("candidate_gap");
    }
    if (findings.some((finding) => findingLayerKeys(finding).length > 1)) {
      triggerReasons.push("multi_layer_finding");
    }
    if (unrepresentedActionableLayers.length > 0) {
      triggerReasons.push("unrepresented_actionable_layer");
    }
    if (
      safeNonNegativeCount(record.evidence_guard.rejected_unlinked_count) > 0 ||
      safeNonNegativeCount(
          record.evidence_guard.rejected_non_actionable_count,
        ) > 0
    ) {
      triggerReasons.push("evidence_guard_rejection");
    }
    if (
      safeNonNegativeCount(record.evidence_guard.marked_uncertain_count) > 0
    ) {
      triggerReasons.push("evidence_guard_uncertain");
    }
    if (
      record.record_missing ||
      record.layer_audit.missing_layer_keys.length > 0 ||
      record.layer_audit.duplicate_layer_keys.length > 0 ||
      safeNonNegativeCount(record.layer_audit.invalid_layer_keys_count) > 0 ||
      safeNonNegativeCount(record.layer_audit.invalid_layer_statuses_count) > 0
    ) {
      triggerReasons.push("record_incomplete");
    }
  }

  return {
    photo_index: record.photo_index,
    eligible,
    should_repair: eligible && triggerReasons.length > 0,
    trigger_reasons: triggerReasons,
    candidate_semantics_evaluable: options.candidateSemanticsV2,
    initial_candidate_findings_count: safeNonNegativeCount(
      record.candidate_findings_count,
    ),
    initial_generated_findings_count: findings.length,
    actionable_layer_count: actionableLayers.length,
    represented_actionable_layer_count:
      actionableLayers.filter((layer) => representedLayers.has(layer)).length,
    unrepresented_actionable_layers: unrepresentedActionableLayers,
  };
}

export function evaluateCoverageQualityRecords(
  records: CoverageQualityRecordInput[],
  options: { candidateSemanticsV2: boolean },
): CoverageQualityEvaluation[] {
  return records.map((record) =>
    evaluateCoverageQualityRecord(record, options)
  );
}

export function normalizedTextTokens(value: unknown): string[] {
  const stopwords = new Set([
    "acil",
    "alan",
    "asansor",
    "asansorde",
    "asansorun",
    "bir",
    "bu",
    "durum",
    "durumda",
    "durumlarda",
    "gibi",
    "icin",
    "ile",
    "olan",
    "olarak",
    "veya",
  ]);
  return text(value)
    .toLocaleLowerCase("tr-TR")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/[^a-z0-9çğıöşü\s]/giu, " ")
    .split(/\s+/)
    .map((item) => item.trim())
    .filter((item) => item.length > 2 && !stopwords.has(item));
}

export function normalizedTextKey(value: unknown): string {
  return normalizedTextTokens(value).join(" ");
}

export function tokenOverlapRatio(left: unknown, right: unknown): number {
  const leftTokens = new Set(normalizedTextTokens(left));
  const rightTokens = new Set(normalizedTextTokens(right));
  if (leftTokens.size === 0 || rightTokens.size === 0) return 0;
  let intersection = 0;
  for (const token of leftTokens) {
    if (rightTokens.has(token)) intersection += 1;
  }
  return intersection / Math.min(leftTokens.size, rightTokens.size);
}

export function tokenJaccardSimilarity(
  left: unknown,
  right: unknown,
): number {
  const leftTokens = new Set(normalizedTextTokens(left));
  const rightTokens = new Set(normalizedTextTokens(right));
  if (leftTokens.size === 0 || rightTokens.size === 0) return 0;
  let intersection = 0;
  for (const token of leftTokens) {
    if (rightTokens.has(token)) intersection += 1;
  }
  const union = new Set([...leftTokens, ...rightTokens]).size;
  return union === 0 ? 0 : intersection / union;
}

export function coverageFindingKey(hazard: FindingRecord): string {
  const title = normalizedTextKey(hazard.title);
  const evidence = normalizedTextKey(hazard.observed_evidence);
  if (title && evidence) {
    return `title-evidence|${title}|${evidence}`;
  }

  const corrective = normalizedTextKey(hazard.corrective_action);
  if (evidence && corrective) {
    return `evidence-action|${evidence}|${corrective}`;
  }
  if (evidence && normalizedTextTokens(evidence).length >= 6) {
    return `evidence|${evidence}`;
  }

  return [
    hazard.title,
    hazard.corrective_action,
    hazard.preventive_control,
    hazard.root_cause,
  ]
    .map(normalizedTextKey)
    .filter((item) => item.length > 0)
    .join("|");
}

export function areLikelyDuplicateCoverageFindings(
  left: FindingRecord,
  right: FindingRecord,
): boolean {
  const leftKey = coverageFindingKey(left);
  const rightKey = coverageFindingKey(right);
  if (leftKey && leftKey === rightKey) return true;

  const leftEvidence = normalizedTextKey(left.observed_evidence);
  const rightEvidence = normalizedTextKey(right.observed_evidence);
  const evidenceHasDetail = normalizedTextTokens(leftEvidence).length >= 5 &&
    normalizedTextTokens(rightEvidence).length >= 5;
  if (!evidenceHasDetail) return false;

  const leftTitle = normalizedTextKey(left.title);
  const rightTitle = normalizedTextKey(right.title);
  const titleSimilarity = tokenJaccardSimilarity(leftTitle, rightTitle);
  const evidenceSimilarity = tokenJaccardSimilarity(
    leftEvidence,
    rightEvidence,
  );

  if (leftTitle && leftTitle === rightTitle && evidenceSimilarity >= 0.65) {
    return true;
  }
  if (titleSimilarity >= 0.7 && evidenceSimilarity >= 0.72) return true;

  const correctiveSimilarity = tokenJaccardSimilarity(
    left.corrective_action,
    right.corrective_action,
  );
  const rootCauseSimilarity = tokenJaccardSimilarity(
    left.root_cause,
    right.root_cause,
  );

  return evidenceSimilarity >= 0.8 &&
    correctiveSimilarity >= 0.72 && rootCauseSimilarity >= 0.72;
}

const COVERAGE_SUBFINDING_GENERIC_TOKENS = new Set([
  "belirgin",
  "and",
  "condition",
  "durum",
  "fiziksel",
  "from",
  "gorulen",
  "gorulmektedir",
  "guvenli",
  "hazard",
  "immediately",
  "into",
  "mevcut",
  "observed",
  "risk",
  "riski",
  "safety",
  "sahada",
  "sekilde",
  "should",
  "that",
  "tehlike",
  "tehlikesi",
  "the",
  "this",
  "unsafe",
  "uygunsuz",
  "visible",
  "with",
]);

function informativeCoverageTokens(value: unknown): string[] {
  return normalizedTextTokens(value).filter((token) =>
    !COVERAGE_SUBFINDING_GENERIC_TOKENS.has(token)
  );
}

function coverageTokensMatch(left: string, right: string): boolean {
  if (left === right) return true;
  const shorterLength = Math.min(left.length, right.length);
  if (shorterLength < 4) return false;

  let commonPrefixLength = 0;
  while (
    commonPrefixLength < shorterLength &&
    left[commonPrefixLength] === right[commonPrefixLength]
  ) {
    commonPrefixLength += 1;
  }

  return commonPrefixLength >= Math.min(5, shorterLength) &&
    commonPrefixLength / shorterLength >= 0.7;
}

function asymmetricCoverageMatch(
  needle: unknown,
  haystack: unknown,
): { matched: number; total: number; ratio: number } {
  const needleTokens = [...new Set(informativeCoverageTokens(needle))];
  const haystackTokens = [...new Set(normalizedTextTokens(haystack))];
  if (needleTokens.length === 0 || haystackTokens.length === 0) {
    return { matched: 0, total: needleTokens.length, ratio: 0 };
  }

  const matched =
    needleTokens.filter((needleToken) =>
      haystackTokens.some((haystackToken) =>
        coverageTokensMatch(needleToken, haystackToken)
      )
    ).length;
  return {
    matched,
    total: needleTokens.length,
    ratio: matched / needleTokens.length,
  };
}

/**
 * Detects the asymmetric case where a quality-repair candidate is already
 * described inside a broader, compound first-pass finding. This deliberately
 * stays separate from the general duplicate detector: only the repair merge
 * may use it, with same-photo scope supplied by the caller.
 */
export function isCoverageRepairSubfindingAlreadyCovered(
  existing: FindingRecord,
  incoming: FindingRecord,
): boolean {
  const existingNarrativeScope = [
    existing.title,
    existing.observed_evidence,
    existing.description,
  ].map(text).filter(Boolean).join(" ");
  const existingControlScope = [
    existing.corrective_action,
    existing.preventive_control,
  ].map(text).filter(Boolean).join(" ");
  const existingFullScope = [
    existingNarrativeScope,
    existing.root_cause,
    existingControlScope,
  ].map(text).filter(Boolean).join(" ");
  if (!existingNarrativeScope || !existingControlScope) return false;

  const titleCoverage = asymmetricCoverageMatch(
    incoming.title,
    existingFullScope,
  );
  const evidenceCoverage = asymmetricCoverageMatch(
    incoming.observed_evidence,
    existingNarrativeScope,
  );
  const actionCoverage = asymmetricCoverageMatch(
    incoming.corrective_action,
    existingControlScope,
  );

  return titleCoverage.total >= 3 &&
    titleCoverage.matched >= 3 && titleCoverage.ratio >= 0.6 &&
    evidenceCoverage.total >= 5 &&
    evidenceCoverage.matched >= 4 && evidenceCoverage.ratio >= 0.45 &&
    actionCoverage.total >= 3 &&
    // Repair actions often enumerate safe alternatives (remove, cut, bend,
    // cap), so the same hazard can be covered with a longer action sentence.
    // Title and narrative evidence remain the stronger identity gates.
    actionCoverage.matched >= 3 && actionCoverage.ratio >= 0.30;
}

export function findingQualityScore(finding: FindingRecord): number {
  const confidence = Number(finding.confidence);
  const safeConfidence = Number.isFinite(confidence)
    ? Math.max(0, Math.min(1, confidence))
    : 0;
  const qualityFields = [
    finding.title,
    finding.observed_evidence,
    finding.description,
    finding.root_cause,
    finding.corrective_action,
    finding.preventive_control,
  ];
  const populatedFields = qualityFields.filter((value) => text(value)).length;
  const uniqueTokens = new Set(
    qualityFields.flatMap((value) => normalizedTextTokens(value)),
  ).size;

  return safeConfidence * 60 + populatedFields * 5 +
    Math.min(uniqueTokens, 80) * 0.125;
}

export function preferredCoverageFinding(
  left: FindingRecord,
  right: FindingRecord,
): FindingRecord {
  return findingQualityScore(right) > findingQualityScore(left) ? right : left;
}
