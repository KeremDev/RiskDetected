type FindingRecord = Record<string, unknown>;

function text(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value).trim();
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
