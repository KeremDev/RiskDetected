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

export type AIOutputValidationLayerResult = {
  id: AIOutputValidationLayerID;
  ok: boolean;
  code: string | null;
};

export type AIOutputValidationResult = {
  ok: boolean;
  code: string | null;
  failedLayer: AIOutputValidationLayerID | null;
  layers: AIOutputValidationLayerResult[];
};

export type AIOutputValidationOptions = {
  allowedUserAuthoredValues?: readonly string[];
};

export type ValidatedAIOutput = {
  result: Record<string, unknown>;
  status: "passed" | "repaired";
  attempts: 1 | 2;
  code: string | null;
  initialValidation: AIOutputValidationResult;
  finalValidation: AIOutputValidationResult;
};

export class OutputLanguageContractError extends Error {
  readonly code = OUTPUT_LANGUAGE_CONTRACT_FAILED;
  readonly status = 502;
  readonly expectedLanguage: "tr" | "en";
  readonly validationCode: string;
  readonly attempts: 2;
  readonly failedLayer: AIOutputValidationLayerID | null;
  readonly validation: AIOutputValidationResult | null;

  constructor(
    expectedLanguage: "tr" | "en",
    validationCode: string,
    validation: AIOutputValidationResult | null = null,
  ) {
    super(OUTPUT_LANGUAGE_CONTRACT_FAILED);
    this.name = "OutputLanguageContractError";
    this.expectedLanguage = expectedLanguage;
    this.validationCode = validationCode;
    this.failedLayer = validation?.failedLayer ?? null;
    this.validation = validation;
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

function collectVisibleText(
  value: unknown,
  key = "",
  output: string[] = [],
): string[] {
  if (typeof value === "string") {
    if (USER_VISIBLE_FIELDS.has(key) && value.trim()) output.push(value.trim());
    return output;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectVisibleText(item, key, output);
    return output;
  }
  if (!value || typeof value !== "object") return output;
  for (const [childKey, childValue] of Object.entries(value)) {
    collectVisibleText(childValue, childKey, output);
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

function photoEvidenceCode(value: unknown): string | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const findings = findingsFrom(value as Record<string, unknown>) ?? [];
    for (const finding of findings) {
      if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
        continue;
      }
      const item = finding as Record<string, unknown>;
      const findingText = collectVisibleText(item).join("\n");
      if (
        MEASUREMENT_VALUE_PATTERN.test(findingText) &&
        item.needs_field_verification !== true
      ) {
        return "PHOTO_EVIDENCE_MEASUREMENT_REQUIRES_VERIFICATION";
      }
      const rootCause = typeof item.root_cause === "string"
        ? item.root_cause
        : "";
      if (
        DEFINITIVE_ROOT_CAUSE_PATTERNS.some((pattern) =>
          pattern.test(rootCause)
        )
      ) {
        return "PHOTO_EVIDENCE_DEFINITIVE_ROOT_CAUSE";
      }
      if (UNSUPPORTED_UNSEEN_FACT_PATTERN.test(findingText)) {
        return "PHOTO_EVIDENCE_UNSEEN_FACT";
      }
    }
  }
  const text = collectVisibleText(value).join("\n");
  if (
    /\b(?:definitely|certainly|guaranteed|without doubt|kesinlikle|kesin olarak|şüphesiz)\b/iu
      .test(text)
  ) {
    return "PHOTO_EVIDENCE_UNSUPPORTED_CERTAINTY";
  }
  return null;
}

function layer(
  id: AIOutputValidationLayerID,
  code: string | null,
): AIOutputValidationLayerResult {
  return { id, ok: code === null, code };
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
    layer("photo_evidence", photoEvidenceCode(value)),
  ];
  const failed = layers.find((result) => !result.ok) ?? null;
  return {
    ok: failed === null,
    code: failed?.code ?? null,
    failedLayer: failed?.id ?? null,
    layers,
  };
}

export async function validateAIOutputWithSingleRepair(params: {
  initialResult: unknown;
  snapshot: LocalizationSnapshot;
  allowedUserAuthoredValues?: readonly string[];
  repair: (
    validation: AIOutputValidationResult,
  ) => Promise<Record<string, unknown>>;
}): Promise<ValidatedAIOutput> {
  const initialValidation = validateAIOutputContract(
    params.initialResult,
    params.snapshot,
    { allowedUserAuthoredValues: params.allowedUserAuthoredValues },
  );
  if (initialValidation.ok) {
    return {
      result: params.initialResult as Record<string, unknown>,
      status: "passed",
      attempts: 1,
      code: null,
      initialValidation,
      finalValidation: initialValidation,
    };
  }

  const repairedResult = await params.repair(initialValidation);
  const finalValidation = validateAIOutputContract(
    repairedResult,
    params.snapshot,
    { allowedUserAuthoredValues: params.allowedUserAuthoredValues },
  );
  if (!finalValidation.ok) {
    throw new OutputLanguageContractError(
      params.snapshot.output_language,
      finalValidation.code ?? OUTPUT_LANGUAGE_CONTRACT_FAILED,
      finalValidation,
    );
  }
  return {
    result: repairedResult,
    status: "repaired",
    attempts: 2,
    code: initialValidation.code,
    initialValidation,
    finalValidation,
  };
}
