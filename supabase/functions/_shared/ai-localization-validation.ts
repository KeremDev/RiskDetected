import type { LocalizationSnapshot } from "./localization-contract.ts";
import {
  requireSafetyProfile,
  type SafetyProfile,
} from "./safety-profile-manifest.ts";

export const OUTPUT_LANGUAGE_CONTRACT_FAILED =
  "OUTPUT_LANGUAGE_CONTRACT_FAILED" as const;

export const AI_OUTPUT_VALIDATION_LAYER_IDS = [
  "json_schema",
  "output_language",
  "safety_profile_terminology",
  "forbidden_claim",
  "regulatory_reference",
  "photo_evidence",
] as const;

export type AIOutputValidationLayerID =
  (typeof AI_OUTPUT_VALIDATION_LAYER_IDS)[number];

/**
 * Which user-visible field tripped a layer, plus a short excerpt of it.
 *
 * Carried so the single repair attempt can name the exact offending text
 * instead of asking the model to guess, and so a failed analysis records why
 * it failed. Layers that cannot attribute a failure to one field omit it.
 */
export type AIOutputValidationFailureDetail = {
  code: string;
  field?: string;
  path?: string;
  excerpt?: string;
};

export type AIOutputValidationLayerResult = {
  id: AIOutputValidationLayerID;
  ok: boolean;
  code: string | null;
  field?: string;
  path?: string;
  excerpt?: string;
  violations?: AIOutputValidationFailureDetail[];
};

export type AIOutputValidationResult = {
  ok: boolean;
  code: string | null;
  failedLayer: AIOutputValidationLayerID | null;
  failedField: string | null;
  failedPath: string | null;
  failedExcerpt: string | null;
  violations: AIOutputValidationFailureDetail[];
  layers: AIOutputValidationLayerResult[];
};

export type AIOutputValidationOptions = {
  allowedUserAuthoredValues?: readonly string[];
  certaintyPolicy?: "legacy" | "v2";
};

export type AIOutputRepairIntegrityResult = {
  ok: boolean;
  code: string | null;
  path: string | null;
  removedFindingsCount: number;
};

export type DeterministicFallbackCopy = {
  summary: string;
  zeroFindingsSummary: string;
  zeroFindingsLimitation: string;
  cautiousRootCause: string;
  coverageGapReason: string;
};

export type DeterministicFallbackResult = {
  result: Record<string, unknown>;
  codes: string[];
  paths: string[];
  removedFindingsCount: number;
  zeroFindings: boolean;
};

export type ValidatedAIOutput = {
  result: Record<string, unknown>;
  status: "passed" | "repaired" | "fallback";
  attempts: 1 | 2;
  code: string | null;
  initialValidation: AIOutputValidationResult;
  finalValidation: AIOutputValidationResult;
  repairIntegrity: AIOutputRepairIntegrityResult | null;
  deterministicFallback: DeterministicFallbackResult | null;
};

export class OutputLanguageContractError extends Error {
  readonly code = OUTPUT_LANGUAGE_CONTRACT_FAILED;
  readonly status = 502;
  readonly expectedLanguage: "tr" | "en";
  readonly validationCode: string;
  readonly attempts: 2;
  readonly failedLayer: AIOutputValidationLayerID | null;
  readonly validation: AIOutputValidationResult | null;
  readonly initialValidation: AIOutputValidationResult | null;
  readonly finalValidationStatus: "failed" | "not_run";
  readonly repairTransportFailed: boolean;
  readonly repairTransportErrorClass: string | null;
  readonly repairIntegrity: AIOutputRepairIntegrityResult | null;

  constructor(
    expectedLanguage: "tr" | "en",
    validationCode: string,
    validation: AIOutputValidationResult | null = null,
    options: {
      initialValidation?: AIOutputValidationResult | null;
      finalValidationStatus?: "failed" | "not_run";
      repairTransportFailed?: boolean;
      repairTransportErrorClass?: string | null;
      repairIntegrity?: AIOutputRepairIntegrityResult | null;
    } = {},
  ) {
    super(OUTPUT_LANGUAGE_CONTRACT_FAILED);
    this.name = "OutputLanguageContractError";
    this.expectedLanguage = expectedLanguage;
    this.validationCode = validationCode;
    this.failedLayer = validation?.failedLayer ?? null;
    this.validation = validation;
    this.initialValidation = options.initialValidation ?? null;
    this.finalValidationStatus = options.finalValidationStatus ?? "failed";
    this.repairTransportFailed = options.repairTransportFailed ?? false;
    this.repairTransportErrorClass = options.repairTransportErrorClass ?? null;
    this.repairIntegrity = options.repairIntegrity ?? null;
    this.attempts = 2;
  }
}

const USER_VISIBLE_FIELDS = new Set([
  "title",
  "category",
  "observed_evidence",
  "description",
  "root_cause",
  "corrective_action",
  "preventive_control",
  "references",
  "observation",
  "scene_summary",
  "coverage_gap_reason",
  "coverage_conclusion",
  "visual_evidence",
  "ai_summary",
  "limitations",
  "text",
]);

/**
 * Fields that assert something about the scene, so a certainty adverb in them
 * is a claim about evidence.
 *
 * Deliberately narrower than USER_VISIBLE_FIELDS. `limitations`,
 * `coverage_gap_reason` and `coverage_conclusion` exist to *express*
 * uncertainty, and the photo-evidence prompt tells the model to state what it
 * could not confirm there; in Turkish that is "kesin olarak
 * belirlenememistir", which the certainty pattern would read as the opposite
 * of what it is. `corrective_action` and `preventive_control` are imperative
 * safety copy where "kesinlikle kullanilmalidir" is a recommendation, not an
 * evidence claim. Scanning those fields made the validator contradict the
 * contract the same prompt hands the model.
 */
const LEGACY_EVIDENCE_CLAIM_FIELDS = new Set([
  "observed_evidence",
  "description",
  "root_cause",
  "visual_evidence",
  "observation",
]);

const V2_EVIDENCE_CLAIM_FIELDS = new Set(
  [...USER_VISIBLE_FIELDS].filter((field) => field !== "references"),
);

type FieldTextEntry = {
  field: string;
  path: string;
  text: string;
};

function collectFieldText(
  value: unknown,
  fields: ReadonlySet<string>,
  key = "",
  path = "",
  output: FieldTextEntry[] = [],
): FieldTextEntry[] {
  if (typeof value === "string") {
    if (fields.has(key) && value.trim()) {
      output.push({ field: key, path, text: value.trim() });
    }
    return output;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => {
      collectFieldText(item, fields, key, `${path}[${index}]`, output);
    });
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [childKey, childValue] of Object.entries(value)) {
    collectFieldText(
      childValue,
      fields,
      childKey,
      path ? `${path}.${childKey}` : childKey,
      output,
    );
  }
  return output;
}

function collectVisibleText(
  value: unknown,
  key = "",
  output: string[] = [],
): string[] {
  for (
    const entry of collectFieldText(value, USER_VISIBLE_FIELDS, key, key)
  ) {
    output.push(entry.text);
  }
  return output;
}

function collectLanguageContractText(
  value: unknown,
  key = "",
  output: string[] = [],
): string[] {
  if (typeof value === "string") {
    if (USER_VISIBLE_FIELDS.has(key) && value.trim()) {
      const systemText = key === "observed_evidence" || key === "observation"
        ? value.replace(/"[^"\n]{1,240}"|“[^”\n]{1,240}”/gu, " ")
        : value;
      output.push(systemText.trim());
    }
    return output;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectLanguageContractText(item, key, output);
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [childKey, childValue] of Object.entries(value)) {
    collectLanguageContractText(childValue, childKey, output);
  }
  return output;
}

function findingsFrom(value: Record<string, unknown>): unknown[] | null {
  if (Array.isArray(value.hazards)) return value.hazards;
  if (!Array.isArray(value.photo_findings)) return null;
  const findings: unknown[] = [];
  for (const photoFinding of value.photo_findings) {
    if (!photoFinding || typeof photoFinding !== "object") return null;
    const records = (photoFinding as Record<string, unknown>).findings;
    if (!Array.isArray(records)) return null;
    findings.push(...records);
  }
  return findings;
}

function validateSchema(value: unknown): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return "AI_SCHEMA_ROOT_INVALID";
  }
  const record = value as Record<string, unknown>;
  if (typeof record.ai_summary !== "string") {
    return "AI_SCHEMA_SUMMARY_MISSING";
  }
  const findings = findingsFrom(record);
  if (!findings) return "AI_SCHEMA_FINDINGS_MISSING";
  const requiredStrings = [
    "title",
    "category",
    "observed_evidence",
    "description",
    "root_cause",
    "corrective_action",
    "preventive_control",
  ];
  const requiredNumbers = [
    "confidence",
    "fk_probability",
    "fk_frequency",
    "fk_severity",
    "m5_probability",
    "m5_severity",
  ];
  for (const finding of findings) {
    if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
      return "AI_SCHEMA_FINDING_INVALID";
    }
    const item = finding as Record<string, unknown>;
    if (
      requiredStrings.some((field) =>
        typeof item[field] !== "string" || !String(item[field]).trim()
      )
    ) {
      return "AI_SCHEMA_REQUIRED_TEXT_INVALID";
    }
    if (
      requiredNumbers.some((field) =>
        typeof item[field] !== "number" || !Number.isFinite(item[field])
      )
    ) {
      return "AI_SCHEMA_REQUIRED_SCORE_INVALID";
    }
    if (typeof item.needs_field_verification !== "boolean") {
      return "AI_SCHEMA_VERIFICATION_FLAG_INVALID";
    }
  }
  return null;
}

const TURKISH_LEXEMES =
  /\b(?:tehlike|bulgu|düzelt|önle|çalış|güvenli|uygunsuz|mevzuat|yüksek|yangın|elektrik|görsel|fotoğraf|saha)\p{L}*\b/giu;
const ENGLISH_LEXEMES =
  /\b(?:a|an|the|and|or|to|of|in|on|for|from|with|without|is|are|was|were|be|been|being|as|at|by|this|that|these|those|could|may|might|should|must|can|will|not|no|only|one|visible|visibly|requires?|needs?|appears?|hazards?|findings?|corrective|preventive|workers?|safety|controls?|evidence|workplace|inspection|equipment|electrical|fire|height|photo|risk|assessment|guard|machine|action|condition|cause|contact|install|effective|measure)\b/giu;
const LETTER_TOKEN_PATTERN = /\p{L}+(?:['’\-]\p{L}+)?/gu;

function languageSignals(text: string): {
  tokenCount: number;
  englishSignalCount: number;
} {
  return {
    tokenCount: (text.match(LETTER_TOKEN_PATTERN) ?? []).length,
    englishSignalCount: (text.match(ENGLISH_LEXEMES) ?? []).length,
  };
}

function languageCode(
  segments: readonly string[],
  expectedLanguage: "tr" | "en",
  options: AIOutputValidationOptions,
): string | null {
  const userValues = (options.allowedUserAuthoredValues ?? [])
    .filter((value) => typeof value === "string")
    .map((value) => value.normalize("NFC").trim().slice(0, 160))
    .filter((value) => value.length >= 2)
    .sort((left, right) => right.length - left.length)
    .slice(0, 8);
  const systemSegments = segments.map((segment) => {
    let systemSegment = segment.normalize("NFC");
    for (const userValue of userValues) {
      systemSegment = systemSegment.split(userValue).join(" ");
    }
    return systemSegment;
  }).filter((segment) => segment.trim().length > 0);
  const systemText = systemSegments.join("\n");
  if (!systemText.trim()) return null;
  const turkishCharacters = (systemText.match(/[çğıöşüİı]/gu) ?? []).length;
  const turkishWords = (systemText.match(TURKISH_LEXEMES) ?? []).length;
  const englishWords = (systemText.match(ENGLISH_LEXEMES) ?? []).length;
  if (
    expectedLanguage === "en" &&
    (turkishWords >= 2 || turkishCharacters >= 8)
  ) {
    return "OUTPUT_LANGUAGE_TURKISH_LEAK";
  }
  if (expectedLanguage === "en") {
    const aggregate = languageSignals(systemText);
    const letterCount = (systemText.match(/\p{L}/gu) ?? []).length;
    const incompatibleScriptLetters = (
      systemText.match(
        /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Cyrillic}\p{Script=Arabic}]/gu,
      ) ?? []
    ).length;
    const requiredSignals = Math.max(
      4,
      Math.ceil(aggregate.tokenCount * 0.12),
    );
    const hasNonEnglishSubstantiveSegment = systemSegments.some((segment) => {
      const signals = languageSignals(segment);
      return signals.tokenCount >= 6 && signals.englishSignalCount === 0;
    });
    if (
      incompatibleScriptLetters >= 4 ||
      (
        (aggregate.tokenCount >= 10 || letterCount >= 40) &&
        (
          aggregate.englishSignalCount < requiredSignals ||
          hasNonEnglishSubstantiveSegment
        )
      )
    ) {
      return "OUTPUT_LANGUAGE_ENGLISH_REQUIRED";
    }
  }
  if (
    expectedLanguage === "tr" &&
    systemText.length >= 80 &&
    englishWords >= 4 &&
    turkishWords === 0 &&
    turkishCharacters === 0
  ) {
    return "OUTPUT_LANGUAGE_ENGLISH_LEAK";
  }
  return null;
}

const CROSS_PROFILE_PATTERNS: Record<string, RegExp[]> = {
  "en-intl-generic-v1": [
    /\bOSHA\b/iu,
    /\bHSE\b/iu,
    /\bHSENI\b/iu,
    /\bWHS\b/iu,
    /\bCanadian OHS\b/iu,
  ],
  "en-gb-generic-v1": [
    /\bOSHA\b/iu,
    /\bWHS\b/iu,
    /\bCanadian OHS\b/iu,
  ],
  "en-us-generic-v1": [
    /\bHSE\b/iu,
    /\bHSENI\b/iu,
    /\bWHS\b/iu,
    /\bCanadian OHS\b/iu,
  ],
  "en-au-generic-v1": [
    /\bOSHA\b/iu,
    /\bHSE\b/iu,
    /\bHSENI\b/iu,
    /\bCanadian OHS\b/iu,
  ],
  "en-ca-generic-v1": [
    /\bOSHA\b/iu,
    /\bHSE\b/iu,
    /\bHSENI\b/iu,
    /\bWHS Act\b/iu,
  ],
};

function terminologyCode(
  text: string,
  profile: SafetyProfile,
): string | null {
  if (
    profile.language === "en" &&
    /\b(?:İSG|OSGB|ÇSGB|6331)\b/iu.test(text)
  ) {
    return "SAFETY_PROFILE_TURKEY_TERMINOLOGY_LEAK";
  }
  const crossProfile = CROSS_PROFILE_PATTERNS[profile.id] ?? [];
  if (crossProfile.some((pattern) => pattern.test(text))) {
    return "SAFETY_PROFILE_CROSS_TERMINOLOGY_LEAK";
  }
  if (
    profile.language === "en" &&
    !text.toLocaleLowerCase("en-US").includes(
      profile.primary_domain_term.toLocaleLowerCase("en-US"),
    )
  ) {
    return "SAFETY_PROFILE_REQUIRED_TERMINOLOGY_MISSING";
  }
  return null;
}

function forbiddenClaimCode(
  text: string,
  profile: SafetyProfile,
): string | null {
  const lower = text.toLocaleLowerCase("en-US");
  if (
    profile.forbidden_terms.some((term) =>
      lower.includes(term.toLocaleLowerCase("en-US"))
    )
  ) {
    return "FORBIDDEN_PROFILE_CLAIM";
  }
  if (
    /\b(?:is|are|fully|legally|globally)\s+(?:osha\s+|hse\s+|whs\s+|ohs\s+)?compliant\b/iu
      .test(text) ||
    /\b(?:certified|approved)\s+by\s+(?:osha|hse|hseni|a regulator)\b/iu
      .test(text) ||
    /\b(?:mevzuata|hukuka)\s+(?:tam\s+)?uygundur\b/iu.test(text)
  ) {
    return "FORBIDDEN_COMPLIANCE_CLAIM";
  }
  return null;
}

function collectReferences(value: unknown, key = "", output: string[] = []) {
  if (key === "references") {
    if (typeof value === "string") output.push(value.trim());
    else if (value !== null && value !== undefined) output.push(String(value));
    return output;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectReferences(item, key, output);
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [childKey, childValue] of Object.entries(value)) {
    collectReferences(childValue, childKey, output);
  }
  return output;
}

function regulatoryCode(
  value: unknown,
  text: string,
  snapshot: LocalizationSnapshot,
): string | null {
  if (snapshot.structured_regulatory_references_enabled) return null;
  if (collectReferences(value).some((reference) => reference.length > 0)) {
    return "REGULATORY_REFERENCE_NOT_ALLOWED";
  }
  if (
    /\b(?:6331|OSHA|HSE|HSENI|WHS Act|Canada Labour Code|official citation|statutory compliance)\b/iu
      .test(text)
  ) {
    return "REGULATORY_JURISDICTION_CLAIM_NOT_ALLOWED";
  }
  return null;
}

const MEASUREMENT_VALUE_PATTERN =
  /\b\d+(?:[.,]\d+)?\s*(?:dB(?:\(A\)|A)?|ppm|ppb|lux|mg\/m(?:3|³)|m\/s(?:2|²)|°[CF]|%RH)\b/iu;
const UNSUPPORTED_UNSEEN_FACT_PATTERN =
  /\b(?:(?:worker|operator|employee|staff member)s?\s+(?:is|are|was|were|has|have)\s+(?:untrained|not trained|incompetent|not competent)|(?:no|missing|absent)\s+(?:training|procedure|maintenance record|inspection record|competence record)|(?:çalışan|operatör|personel)(?:ın|in|un|ün)?\s+(?:eğitimsiz|yetkin değil|eğitim almamış)|(?:eğitim|prosedür|bakım kaydı|kontrol kaydı)\s+(?:yok|bulunmuyor|eksik))\b/iu;
const DEFINITIVE_ROOT_CAUSE_PATTERNS = [
  /\b(?:the\s+)?root cause\s+(?:is|was)\b/iu,
  /\b(?:is|are|was|were)\s+caused by\b/iu,
  /^\s*(?:due to|because of)\b/iu,
  /\bkök neden(?:i)?\s+(?:budur|şudur|dır|dir|dur|olarak)\b/iu,
  /\b(?:sebebi|nedeni)\s+(?:kesin olarak\s+)?\b/iu,
];

/**
 * `\b` is ASCII-only even under the `u` flag, so a word starting with a
 * non-ASCII letter never forms a boundary against a preceding space. Wrapping
 * the Turkish alternatives in `\b` therefore failed to match them standalone
 * while still matching them glued onto an ASCII stem. They are anchored on a
 * non-letter lookaround instead; the ASCII alternatives keep `\b`.
 */
const UNSUPPORTED_CERTAINTY_PATTERN =
  /\b(?:definitely|certainly|guaranteed|without doubt|with certainty)\b|(?<![\p{L}\p{N}_])(?:kesinlikle|kesin olarak|şüphesiz)(?![\p{L}\p{N}_])/iu;

const TURKISH_NEGATIVE_DETERMINATION_PATTERN =
  /(?:belirlen|belirtil|tespit\s+edil|ifade\s+edil|s\u{f6}ylen|do\u{11f}rulan|de\u{11f}erlendiril|anla\u{15f}\u{131}l|saptan|g\u{f6}zlemlen|\u{f6}l\u{e7}\u{fc}l|teyit\s+edil)(?:[ae])?m(?:[ae]z|[ae]|iyor|\u{131}yor|uyor|\u{fc}yor)\p{L}*/iu;
const ENGLISH_NEGATIVE_DETERMINATION_PATTERN =
  /\b(?:cannot|can['’]t|could\s+not|couldn['’]t|is\s+not|are\s+not|was\s+not|were\s+not)\s+(?:reliably\s+)?(?:be\s+)?(?:determined|verified|confirmed|assessed|established|observed|measured)\b/iu;
const TURKISH_NORMATIVE_ACTION_PATTERN =
  /\p{L}*m(?:al\u{131}|eli)(?:d\u{131}r|dir|dur|d\u{fc}r|t\u{131}r|tir|tur|t\u{fc}r)?(?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])(?:gerekir|zorunludur)(?![\p{L}\p{N}_])/iu;
const ENGLISH_NORMATIVE_ACTION_PATTERN =
  /\b(?:must|should|(?:is|are)\s+(?:(?:definitely|certainly)\s+)?required)\b/iu;
const CLAUSE_SEPARATOR_PATTERN =
  /(?:[.!?;\n]+|,\s+|\s+(?:ve|ama|ancak|fakat|\u{e7}\u{fc}nk\u{fc}|zira|and|but|however|because|although|though|since|yet)\s+)/iu;

const ACTION_FIELDS = new Set(["corrective_action", "preventive_control"]);

function matchesTouchOrOverlap(
  left: RegExpExecArray,
  right: RegExpExecArray,
  text: string,
): boolean {
  const leftEnd = left.index + left[0].length;
  const rightEnd = right.index + right[0].length;
  if (left.index <= rightEnd && right.index <= leftEnd) return true;
  const between = leftEnd <= right.index
    ? text.slice(leftEnd, right.index)
    : text.slice(rightEnd, left.index);
  return between.trim().length === 0;
}

function certaintyViolationInText(
  entry: FieldTextEntry,
  certaintyPolicy: "legacy" | "v2",
): AIOutputValidationFailureDetail | null {
  const clauses = certaintyPolicy === "v2"
    ? entry.text.split(CLAUSE_SEPARATOR_PATTERN)
    : [entry.text];
  for (const rawClause of clauses) {
    const clause = rawClause.trim();
    const certaintyMatch = UNSUPPORTED_CERTAINTY_PATTERN.exec(clause);
    if (!clause || !certaintyMatch) continue;
    const turkishHedgeMatch = TURKISH_NEGATIVE_DETERMINATION_PATTERN.exec(
      clause,
    );
    const englishHedgeMatch = ENGLISH_NEGATIVE_DETERMINATION_PATTERN.exec(
      clause,
    );
    const isClosedHedge = Boolean(
      (turkishHedgeMatch &&
        certaintyMatch.index <= turkishHedgeMatch.index &&
        matchesTouchOrOverlap(certaintyMatch, turkishHedgeMatch, clause)) ||
        (englishHedgeMatch &&
          matchesTouchOrOverlap(certaintyMatch, englishHedgeMatch, clause)),
    );
    if (certaintyPolicy === "v2" && isClosedHedge) continue;
    const actionMatch = TURKISH_NORMATIVE_ACTION_PATTERN.exec(clause) ??
      ENGLISH_NORMATIVE_ACTION_PATTERN.exec(clause);
    const isActionClause = ACTION_FIELDS.has(entry.field) && actionMatch &&
      matchesTouchOrOverlap(certaintyMatch, actionMatch, clause);
    if (certaintyPolicy === "v2" && isActionClause) continue;
    return {
      code: "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY",
      field: entry.field,
      path: entry.path,
      excerpt: excerptAround(clause, UNSUPPORTED_CERTAINTY_PATTERN),
    };
  }
  return null;
}

function excerptAround(text: string, pattern: RegExp): string {
  const match = pattern.exec(text);
  if (!match) return text.slice(0, 160);
  const start = Math.max(0, match.index - 60);
  const end = Math.min(text.length, match.index + match[0].length + 60);
  return `${start > 0 ? "…" : ""}${text.slice(start, end).trim()}${
    end < text.length ? "…" : ""
  }`;
}

type FindingLocation = {
  item: Record<string, unknown>;
  path: string;
  containerPath: string;
  index: number;
};

function findingLocations(value: unknown): FindingLocation[] {
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const record = value as Record<string, unknown>;
  if (Array.isArray(record.hazards)) {
    return record.hazards.flatMap((item, index) =>
      item && typeof item === "object" && !Array.isArray(item)
        ? [{
          item: item as Record<string, unknown>,
          path: `hazards[${index}]`,
          containerPath: "hazards",
          index,
        }]
        : []
    );
  }
  if (!Array.isArray(record.photo_findings)) return [];
  return record.photo_findings.flatMap((photoFinding, photoIndex) => {
    if (
      !photoFinding || typeof photoFinding !== "object" ||
      Array.isArray(photoFinding)
    ) return [];
    const findings = (photoFinding as Record<string, unknown>).findings;
    if (!Array.isArray(findings)) return [];
    const containerPath = `photo_findings[${photoIndex}].findings`;
    return findings.flatMap((item, findingIndex) =>
      item && typeof item === "object" && !Array.isArray(item)
        ? [{
          item: item as Record<string, unknown>,
          path: `${containerPath}[${findingIndex}]`,
          containerPath,
          index: findingIndex,
        }]
        : []
    );
  });
}

function deduplicateViolations(
  violations: AIOutputValidationFailureDetail[],
): AIOutputValidationFailureDetail[] {
  const seen = new Set<string>();
  return violations.filter((violation) => {
    const key = `${violation.code}\u0000${violation.path ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function photoEvidenceViolations(
  value: unknown,
  certaintyPolicy: "legacy" | "v2",
): AIOutputValidationFailureDetail[] {
  const violations: AIOutputValidationFailureDetail[] = [];
  for (const finding of findingLocations(value)) {
    const entries = collectFieldText(
      finding.item,
      USER_VISIBLE_FIELDS,
      "",
      finding.path,
    );
    for (const entry of entries) {
      if (
        MEASUREMENT_VALUE_PATTERN.test(entry.text) &&
        finding.item.needs_field_verification !== true
      ) {
        violations.push({
          code: "PHOTO_EVIDENCE_MEASUREMENT_REQUIRES_VERIFICATION",
          field: entry.field,
          path: entry.path,
          excerpt: excerptAround(entry.text, MEASUREMENT_VALUE_PATTERN),
        });
      }
      if (UNSUPPORTED_UNSEEN_FACT_PATTERN.test(entry.text)) {
        violations.push({
          code: "PHOTO_EVIDENCE_UNSEEN_FACT",
          field: entry.field,
          path: entry.path,
          excerpt: excerptAround(entry.text, UNSUPPORTED_UNSEEN_FACT_PATTERN),
        });
      }
    }
    const rootCause = typeof finding.item.root_cause === "string"
      ? finding.item.root_cause
      : "";
    if (
      DEFINITIVE_ROOT_CAUSE_PATTERNS.some((pattern) => pattern.test(rootCause))
    ) {
      violations.push({
        code: "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE",
        field: "root_cause",
        path: `${finding.path}.root_cause`,
        excerpt: rootCause.slice(0, 160),
      });
    }
  }
  const certaintyFields = certaintyPolicy === "v2"
    ? V2_EVIDENCE_CLAIM_FIELDS
    : LEGACY_EVIDENCE_CLAIM_FIELDS;
  for (const entry of collectFieldText(value, certaintyFields)) {
    const violation = certaintyViolationInText(entry, certaintyPolicy);
    if (violation) violations.push(violation);
  }
  return deduplicateViolations(violations).slice(0, 32);
}

function layer(
  id: AIOutputValidationLayerID,
  outcome:
    | string
    | AIOutputValidationFailureDetail
    | AIOutputValidationFailureDetail[]
    | null,
): AIOutputValidationLayerResult {
  if (outcome === null || (Array.isArray(outcome) && outcome.length === 0)) {
    return { id, ok: true, code: null };
  }
  if (typeof outcome === "string") return { id, ok: false, code: outcome };
  const violations = Array.isArray(outcome) ? outcome : [outcome];
  const first = violations[0];
  return {
    id,
    ok: false,
    code: first.code,
    ...(first.field ? { field: first.field } : {}),
    ...(first.path ? { path: first.path } : {}),
    ...(first.excerpt ? { excerpt: first.excerpt } : {}),
    violations,
  };
}

export function validateAIOutputContract(
  value: unknown,
  snapshot: LocalizationSnapshot,
  options: AIOutputValidationOptions = {},
): AIOutputValidationResult {
  const profile = requireSafetyProfile(snapshot.safety_profile_id);
  const visibleText = collectVisibleText(value).join("\n");
  const languageContractSegments = collectLanguageContractText(value);
  const layers = [
    layer("json_schema", validateSchema(value)),
    layer(
      "output_language",
      languageCode(
        languageContractSegments,
        snapshot.output_language,
        options,
      ),
    ),
    layer(
      "safety_profile_terminology",
      terminologyCode(visibleText, profile),
    ),
    layer(
      "forbidden_claim",
      forbiddenClaimCode(visibleText, profile),
    ),
    layer(
      "regulatory_reference",
      regulatoryCode(value, visibleText, snapshot),
    ),
    layer(
      "photo_evidence",
      photoEvidenceViolations(value, options.certaintyPolicy ?? "legacy"),
    ),
  ];
  const failed = layers.find((result) => !result.ok) ?? null;
  const violations = failed?.violations ?? (failed?.code
    ? [{
      code: failed.code,
      ...(failed.field ? { field: failed.field } : {}),
      ...(failed.path ? { path: failed.path } : {}),
      ...(failed.excerpt ? { excerpt: failed.excerpt } : {}),
    }]
    : []);
  return {
    ok: failed === null,
    code: failed?.code ?? null,
    failedLayer: failed?.id ?? null,
    failedField: failed?.field ?? null,
    failedPath: failed?.path ?? null,
    failedExcerpt: failed?.excerpt ?? null,
    violations,
    layers,
  };
}

function jsonClone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function deepEqual(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) return true;
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) return false;
    return left.length === right.length &&
      left.every((value, index) => deepEqual(value, right[index]));
  }
  if (
    !left || !right || typeof left !== "object" || typeof right !== "object"
  ) return false;
  const leftRecord = left as Record<string, unknown>;
  const rightRecord = right as Record<string, unknown>;
  const keys = [
    ...new Set([
      ...Object.keys(leftRecord),
      ...Object.keys(rightRecord),
    ]),
  ].sort();
  return keys.every((key) =>
    Object.hasOwn(leftRecord, key) === Object.hasOwn(rightRecord, key) &&
    deepEqual(leftRecord[key], rightRecord[key])
  );
}

function differencePaths(
  left: unknown,
  right: unknown,
  path = "",
  output: string[] = [],
): string[] {
  if (deepEqual(left, right)) return output;
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right)) {
      output.push(path);
      return output;
    }
    if (left.length !== right.length) output.push(path);
    const length = Math.min(left.length, right.length);
    for (let index = 0; index < length; index += 1) {
      differencePaths(
        left[index],
        right[index],
        `${path}[${index}]`,
        output,
      );
    }
    return output;
  }
  if (
    !left || !right || typeof left !== "object" || typeof right !== "object"
  ) {
    output.push(path);
    return output;
  }
  const leftRecord = left as Record<string, unknown>;
  const rightRecord = right as Record<string, unknown>;
  const keys = [
    ...new Set([
      ...Object.keys(leftRecord),
      ...Object.keys(rightRecord),
    ]),
  ].sort();
  for (const key of keys) {
    const childPath = path ? `${path}.${key}` : key;
    if (
      !Object.hasOwn(leftRecord, key) || !Object.hasOwn(rightRecord, key)
    ) {
      output.push(childPath);
      continue;
    }
    differencePaths(leftRecord[key], rightRecord[key], childPath, output);
  }
  return output;
}

function pathTokens(path: string): Array<string | number> {
  const tokens: Array<string | number> = [];
  for (const match of path.matchAll(/([^.\[\]]+)|\[(\d+)\]/gu)) {
    tokens.push(match[2] === undefined ? match[1] : Number(match[2]));
  }
  return tokens;
}

function valueAtPath(value: unknown, path: string): unknown {
  let current = value;
  for (const token of pathTokens(path)) {
    if (!current || typeof current !== "object") return undefined;
    current = (current as Record<string | number, unknown>)[token];
  }
  return current;
}

function setValueAtPath(value: unknown, path: string, replacement: unknown) {
  const tokens = pathTokens(path);
  if (tokens.length === 0) return;
  let current = value;
  for (const token of tokens.slice(0, -1)) {
    if (!current || typeof current !== "object") return;
    current = (current as Record<string | number, unknown>)[token];
  }
  if (!current || typeof current !== "object") return;
  (current as Record<string | number, unknown>)[tokens.at(-1)!] = replacement;
}

function findingBasePath(path: string | undefined): string | null {
  if (!path) return null;
  return path.match(
    /^(?:hazards\[\d+\]|photo_findings\[\d+\]\.findings\[\d+\])/u,
  )?.[0] ?? null;
}

function findingContainers(
  value: Record<string, unknown>,
): Array<{ path: string; findings: unknown[] }> {
  if (Array.isArray(value.hazards)) {
    return [{ path: "hazards", findings: value.hazards }];
  }
  if (!Array.isArray(value.photo_findings)) return [];
  return value.photo_findings.flatMap((photoFinding, index) => {
    if (
      !photoFinding || typeof photoFinding !== "object" ||
      Array.isArray(photoFinding) ||
      !Array.isArray((photoFinding as Record<string, unknown>).findings)
    ) return [];
    return [{
      path: `photo_findings[${index}].findings`,
      findings: (photoFinding as Record<string, unknown>).findings as unknown[],
    }];
  });
}

function allowedFindingDifferencePaths(
  findingPath: string,
  validation: AIOutputValidationResult,
): Set<string> {
  const allowed = new Set<string>(["needs_field_verification"]);
  for (const violation of validation.violations) {
    if (findingBasePath(violation.path) !== findingPath || !violation.path) {
      continue;
    }
    allowed.add(violation.path.slice(findingPath.length + 1));
  }
  return allowed;
}

function isUserVisibleDifferencePath(path: string): boolean {
  const lastStringToken = pathTokens(path).filter((token) =>
    typeof token === "string"
  ).at(-1);
  return typeof lastStringToken === "string" &&
    USER_VISIBLE_FIELDS.has(lastStringToken);
}

export function validateAIOutputRepairIntegrity(
  initialValue: unknown,
  repairedValue: unknown,
  validation: AIOutputValidationResult,
): AIOutputRepairIntegrityResult {
  const fail = (
    code: string,
    path: string | null,
    removedFindingsCount = 0,
  ): AIOutputRepairIntegrityResult => ({
    ok: false,
    code,
    path,
    removedFindingsCount,
  });
  if (
    !initialValue || !repairedValue || typeof initialValue !== "object" ||
    typeof repairedValue !== "object" || Array.isArray(initialValue) ||
    Array.isArray(repairedValue)
  ) return fail("REPAIR_INTEGRITY_ROOT_CHANGED", null);

  const initial = initialValue as Record<string, unknown>;
  const repaired = repairedValue as Record<string, unknown>;
  const initialContainers = findingContainers(initial);
  const repairedContainers = findingContainers(repaired);
  if (
    initialContainers.length !== repairedContainers.length ||
    initialContainers.some((container, index) =>
      container.path !== repairedContainers[index]?.path
    )
  ) return fail("REPAIR_INTEGRITY_FINDING_CONTAINERS_CHANGED", null);

  const offendingFindingPaths = new Set(
    validation.violations.map((violation) => findingBasePath(violation.path))
      .filter((path): path is string => Boolean(path)),
  );
  const evidenceRepair = validation.failedLayer === "photo_evidence";
  let removedFindingsCount = 0;
  for (
    let containerIndex = 0;
    containerIndex < initialContainers.length;
    containerIndex += 1
  ) {
    const initialContainer = initialContainers[containerIndex];
    const repairedContainer = repairedContainers[containerIndex];
    if (repairedContainer.findings.length > initialContainer.findings.length) {
      return fail("REPAIR_INTEGRITY_FINDING_ADDED", initialContainer.path);
    }
    if (
      !evidenceRepair &&
      repairedContainer.findings.length < initialContainer.findings.length
    ) {
      return fail("REPAIR_INTEGRITY_FINDING_REMOVED", initialContainer.path);
    }
    let repairedIndex = 0;
    for (
      let initialIndex = 0;
      initialIndex < initialContainer.findings.length;
      initialIndex += 1
    ) {
      const initialFinding = initialContainer.findings[initialIndex];
      const repairedFinding = repairedContainer.findings[repairedIndex];
      const initialFindingPath = `${initialContainer.path}[${initialIndex}]`;
      if (!evidenceRepair) {
        const differences = differencePaths(initialFinding, repairedFinding);
        const disallowedPath = differences.find((path) =>
          !isUserVisibleDifferencePath(path)
        );
        if (repairedFinding === undefined || disallowedPath) {
          return fail(
            "REPAIR_INTEGRITY_UNRELATED_PATH_CHANGED",
            disallowedPath
              ? `${initialFindingPath}.${disallowedPath}`
              : initialFindingPath,
            removedFindingsCount,
          );
        }
        repairedIndex += 1;
        continue;
      }
      if (!offendingFindingPaths.has(initialFindingPath)) {
        if (!deepEqual(initialFinding, repairedFinding)) {
          return fail(
            "REPAIR_INTEGRITY_UNAFFECTED_FINDING_CHANGED",
            initialFindingPath,
            removedFindingsCount,
          );
        }
        repairedIndex += 1;
        continue;
      }
      const allowedPaths = allowedFindingDifferencePaths(
        initialFindingPath,
        validation,
      );
      const differences = differencePaths(initialFinding, repairedFinding);
      if (
        repairedFinding !== undefined &&
        differences.every((path) => allowedPaths.has(path))
      ) {
        repairedIndex += 1;
      } else {
        removedFindingsCount += 1;
      }
    }
    if (repairedIndex !== repairedContainer.findings.length) {
      return fail(
        "REPAIR_INTEGRITY_FINDING_ADDED",
        repairedContainer.path,
        removedFindingsCount,
      );
    }
  }

  const initialWithoutFindings = jsonClone(initial);
  const repairedWithoutFindings = jsonClone(repaired);
  for (const container of initialContainers) {
    setValueAtPath(initialWithoutFindings, container.path, []);
    setValueAtPath(repairedWithoutFindings, container.path, []);
  }
  const allowedGlobalPaths = new Set(
    validation.violations.flatMap((violation) => {
      if (!violation.path || findingBasePath(violation.path)) return [];
      return [violation.path];
    }),
  );
  if (!evidenceRepair) {
    for (
      const path of differencePaths(
        initialWithoutFindings,
        repairedWithoutFindings,
      )
    ) {
      if (isUserVisibleDifferencePath(path)) allowedGlobalPaths.add(path);
    }
  }
  if (removedFindingsCount > 0) allowedGlobalPaths.add("ai_summary");
  const globalDifferences = differencePaths(
    initialWithoutFindings,
    repairedWithoutFindings,
  );
  const disallowedGlobalPath = globalDifferences.find((path) =>
    !allowedGlobalPaths.has(path)
  );
  if (disallowedGlobalPath) {
    return fail(
      "REPAIR_INTEGRITY_UNRELATED_PATH_CHANGED",
      disallowedGlobalPath,
      removedFindingsCount,
    );
  }
  return {
    ok: true,
    code: null,
    path: null,
    removedFindingsCount,
  };
}

const DETERMINISTIC_FALLBACK_CODES = new Set([
  "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY",
  "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE",
  "PHOTO_EVIDENCE_MEASUREMENT_REQUIRES_VERIFICATION",
  "PHOTO_EVIDENCE_UNSEEN_FACT",
]);

export function applyDeterministicAIOutputFallback(
  value: unknown,
  validation: AIOutputValidationResult,
  copy: DeterministicFallbackCopy,
): DeterministicFallbackResult | null {
  if (
    validation.failedLayer !== "photo_evidence" ||
    validation.violations.length === 0 ||
    validation.violations.some((violation) =>
      !DETERMINISTIC_FALLBACK_CODES.has(violation.code) || !violation.path
    ) ||
    !value || typeof value !== "object" || Array.isArray(value)
  ) return null;
  const candidate = jsonClone(value as Record<string, unknown>);
  const dropLocations = new Map<string, Set<number>>();
  const cautiousRootCausePaths = new Set(
    validation.violations.filter((violation) =>
      violation.code === "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE"
    ).map((violation) => violation.path),
  );
  let summaryWasOffending = false;
  for (const violation of validation.violations) {
    const path = violation.path!;
    const basePath = findingBasePath(path);
    if (
      violation.code ===
        "PHOTO_EVIDENCE_MEASUREMENT_REQUIRES_VERIFICATION" && basePath
    ) {
      const finding = valueAtPath(candidate, basePath);
      if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
        return null;
      }
      (finding as Record<string, unknown>).needs_field_verification = true;
      continue;
    }
    if (
      violation.code === "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE" && basePath
    ) {
      setValueAtPath(candidate, path, copy.cautiousRootCause);
      const finding = valueAtPath(candidate, basePath);
      if (finding && typeof finding === "object" && !Array.isArray(finding)) {
        (finding as Record<string, unknown>).needs_field_verification = true;
      }
      continue;
    }
    if (
      violation.code === "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY" &&
      cautiousRootCausePaths.has(path)
    ) continue;
    if (!basePath) {
      if (path === "ai_summary") {
        summaryWasOffending = true;
        continue;
      }
      if (path === "limitations") {
        setValueAtPath(candidate, path, copy.zeroFindingsLimitation);
        continue;
      }
      if (
        violation.field &&
        new Set([
          "scene_summary",
          "coverage_gap_reason",
          "coverage_conclusion",
          "visual_evidence",
          "observation",
          "text",
        ]).has(violation.field)
      ) {
        setValueAtPath(candidate, path, copy.coverageGapReason);
        continue;
      }
      return null;
    }
    const match = basePath.match(/^(.*)\[(\d+)\]$/u);
    if (!match) return null;
    const indices = dropLocations.get(match[1]) ?? new Set<number>();
    indices.add(Number(match[2]));
    dropLocations.set(match[1], indices);
  }
  const beforeCount = findingLocations(candidate).length;
  for (const [containerPath, indices] of dropLocations) {
    const findings = valueAtPath(candidate, containerPath);
    if (!Array.isArray(findings)) return null;
    for (const index of [...indices].sort((left, right) => right - left)) {
      findings.splice(index, 1);
    }
  }
  const afterCount = findingLocations(candidate).length;
  const removedFindingsCount = Math.max(0, beforeCount - afterCount);
  const zeroFindings = afterCount === 0;
  if (zeroFindings) {
    candidate.ai_summary = copy.zeroFindingsSummary;
    candidate.limitations = copy.zeroFindingsLimitation;
  } else if (removedFindingsCount > 0 || summaryWasOffending) {
    candidate.ai_summary = copy.summary.replaceAll(
      "{{count}}",
      String(afterCount),
    );
  }
  if (Array.isArray(candidate.photo_findings)) {
    for (const photoFinding of candidate.photo_findings) {
      if (
        !photoFinding || typeof photoFinding !== "object" ||
        Array.isArray(photoFinding)
      ) continue;
      const record = photoFinding as Record<string, unknown>;
      if (Array.isArray(record.findings) && record.findings.length === 0) {
        record.coverage_status = "no_actionable_hazard";
        record.coverage_gap_reason = copy.coverageGapReason;
        if (Object.hasOwn(record, "coverage_conclusion")) {
          record.coverage_conclusion = copy.coverageGapReason;
        }
      }
    }
  }
  return {
    result: candidate,
    codes: [...new Set(validation.violations.map((item) => item.code))],
    paths: [...new Set(validation.violations.map((item) => item.path!))],
    removedFindingsCount,
    zeroFindings,
  };
}

export async function validateAIOutputWithSingleRepair(params: {
  initialResult: unknown;
  snapshot: LocalizationSnapshot;
  allowedUserAuthoredValues?: readonly string[];
  certaintyPolicy?: "legacy" | "v2";
  enforceRepairIntegrity?: boolean;
  deterministicFallbackCopy?: DeterministicFallbackCopy;
  repair: (
    validation: AIOutputValidationResult,
  ) => Promise<Record<string, unknown>>;
}): Promise<ValidatedAIOutput> {
  const initialValidation = validateAIOutputContract(
    params.initialResult,
    params.snapshot,
    {
      allowedUserAuthoredValues: params.allowedUserAuthoredValues,
      certaintyPolicy: params.certaintyPolicy,
    },
  );
  if (initialValidation.ok) {
    return {
      result: params.initialResult as Record<string, unknown>,
      status: "passed",
      attempts: 1,
      code: null,
      initialValidation,
      finalValidation: initialValidation,
      repairIntegrity: null,
      deterministicFallback: null,
    };
  }

  const validatedDeterministicFallback = (
    value: unknown,
    validation: AIOutputValidationResult,
    repairIntegrity: AIOutputRepairIntegrityResult | null,
  ): ValidatedAIOutput | null => {
    const fallback = params.deterministicFallbackCopy
      ? applyDeterministicAIOutputFallback(
        value,
        validation,
        params.deterministicFallbackCopy,
      )
      : null;
    if (!fallback) return null;
    const fallbackValidation = validateAIOutputContract(
      fallback.result,
      params.snapshot,
      {
        allowedUserAuthoredValues: params.allowedUserAuthoredValues,
        certaintyPolicy: params.certaintyPolicy,
      },
    );
    if (!fallbackValidation.ok) return null;
    return {
      result: fallback.result,
      status: "fallback",
      attempts: 2,
      code: initialValidation.code,
      initialValidation,
      finalValidation: fallbackValidation,
      repairIntegrity,
      deterministicFallback: fallback,
    };
  };

  let repairedResult: Record<string, unknown>;
  try {
    repairedResult = await params.repair(initialValidation);
  } catch (error) {
    throw new OutputLanguageContractError(
      params.snapshot.output_language,
      "LANGUAGE_CONTRACT_REPAIR_TRANSPORT_FAILED",
      null,
      {
        initialValidation,
        finalValidationStatus: "not_run",
        repairTransportFailed: true,
        repairTransportErrorClass: error instanceof Error
          ? error.name
          : typeof error,
      },
    );
  }
  const repairIntegrity = params.enforceRepairIntegrity &&
      initialValidation.failedLayer !== "json_schema"
    ? validateAIOutputRepairIntegrity(
      params.initialResult,
      repairedResult,
      initialValidation,
    )
    : null;
  if (repairIntegrity && !repairIntegrity.ok) {
    const fallback = validatedDeterministicFallback(
      params.initialResult,
      initialValidation,
      repairIntegrity,
    );
    if (fallback) return fallback;
    throw new OutputLanguageContractError(
      params.snapshot.output_language,
      repairIntegrity.code ?? "REPAIR_INTEGRITY_FAILED",
      null,
      { initialValidation, repairIntegrity },
    );
  }
  const finalValidation = validateAIOutputContract(
    repairedResult,
    params.snapshot,
    {
      allowedUserAuthoredValues: params.allowedUserAuthoredValues,
      certaintyPolicy: params.certaintyPolicy,
    },
  );
  if (!finalValidation.ok) {
    const fallback = validatedDeterministicFallback(
      repairedResult,
      finalValidation,
      repairIntegrity,
    );
    if (fallback) return fallback;
    throw new OutputLanguageContractError(
      params.snapshot.output_language,
      finalValidation.code ?? OUTPUT_LANGUAGE_CONTRACT_FAILED,
      finalValidation,
      { initialValidation, repairIntegrity },
    );
  }
  return {
    result: repairedResult,
    status: "repaired",
    attempts: 2,
    code: initialValidation.code,
    initialValidation,
    finalValidation,
    repairIntegrity,
    deterministicFallback: null,
  };
}
