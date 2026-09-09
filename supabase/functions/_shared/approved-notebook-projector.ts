import {
  type ApprovedNotebookItemClass,
  isStrictTurkishNotebookAdvisory,
  notebookAdvisoryFallback,
} from "./approved-notebook-advisory-language.ts";

export const APPROVED_NOTEBOOK_PROJECTION_VERSION =
  "approved-notebook-projection-v2";
export const APPROVED_NOTEBOOK_TEMPLATE_TR = "approved-notebook-tr-v3-advisory";
export const SAFETY_LOG_TEMPLATE_EN = "safety-log-en-v2";

export type ResultHubLanguage = "tr" | "en";

export type ProjectorFinding = {
  id: string;
  item_class?: string | null;
  is_scored?: boolean | null;
  title?: string | null;
  category?: string | null;
  description?: string | null;
  recommended_action?: string | null;
  recommended_measures?:
    | Array<{
      kind?: string | null;
      title?: string | null;
      text?: string | null;
    }>
    | null;
  needs_field_verification?: boolean | null;
  source_photo_indices?: number[] | null;
  display_order?: number | null;
  fk_band?: string | null;
  m5_band?: string | null;
  fk_score?: number | null;
  m5_score?: number | null;
};

export type V4ResultMetadata = {
  public_finding_id?: string | null;
  criticality?: string | null;
  canonical_payload?: Record<string, unknown> | null;
  internal_priority?: Record<string, unknown> | null;
  asset_ref?: string | null;
  candidate_key?: string | null;
  evidence_region?: Record<string, unknown> | null;
  verified_references?: string[] | null;
};

export type ApprovedNotebookProjection = {
  id: string;
  grouping_key: string;
  source_finding_ids: string[];
  source_hash: string;
  finding_text: string;
  recommendation_text: string;
  reference_text: string | null;
  display_order: number;
};

export type ApprovedNotebookAdvisory = {
  source_finding_id: string;
  advisory_text: string;
};

type Group = {
  key: string;
  rows: ProjectorFinding[];
  metadata: V4ResultMetadata[];
  priority: number;
};

const PHOTO_ADDRESS_PATTERNS = [
  /\b(?:fotoğraf|foto|görsel|resim)\s*[-–—#]?\s*\d+\s*(?:['’]?(?:de|da|te|ta|den|dan|ten|tan))?\s*(?:üzerinde|içinde|itibarıyla)?\s*[:,\-–—]?\s*/giu,
  /\b\d+\s*\.?\s*(?:numaralı|nolu|no\.?\s*)?\s*(?:alan|bölge|ekipman|fotoğraf|görsel)(?:['’]?(?:de|da|te|ta|den|dan|ten|tan))?\s*[:,\-–—]?\s*/giu,
  /\b(?:photo|image|figure|area|region)\s*(?:no\.?\s*)?#?\d+\s*[:,\-–—]?\s*/giu,
];

const INTERNAL_SCORE_PATTERNS = [
  /\bP\s*(?:değeri|degeri|puanı|puani)?\s*[=:]?\s*\d+(?:[.,]\d+)?\b/giu,
  /\bF\s*(?:değeri|degeri|puanı|puani)?\s*[=:]?\s*\d+(?:[.,]\d+)?\b/giu,
  /\bS\s*(?:değeri|degeri|puanı|puani)?\s*[=:]?\s*\d+(?:[.,]\d+)?\b/giu,
  /\b(?:FK|Fine[ -]?Kinney|5\s*[x×]\s*5)\s*(?:risk\s*)?(?:skoru?|puanı?|score)?\s*[=:]?\s*\d+(?:[.,]\d+)?\b/giu,
];

const ASSIGNMENT_PATTERNS = [
  /\b(?:sorumlu|responsible)\s*[:=][^.;\n]+[.;]?/giu,
  /\b(?:süre|tamamlanma süresi|termin|deadline|due date)\s*[:=][^.;\n]+[.;]?/giu,
  /\b\d+\s*(?:gün|iş günü|days?|business days?)\s*(?:içinde|within)\b/giu,
];

const UNVERIFIED_STANDARD_IDENTIFIER =
  /\b(?:API|ISO|IEC|NFPA|OSHA|TS(?:\s+EN)?|EN)\s*[A-Z]?\s*\d[\w./:-]*(?:\s*[-:]\s*\d[\w./:-]*)?\b/iu;

const EQUIPMENT_ORDINAL_NOUN =
  "makine|makina|makinesi|tezgah|tezgahı|tezgahi|torna tezgahı|freze|matkap|pres|pompa|pompası|tank|tankı|vinç|vinc|konveyör|konveyor|pano|panosu|kompresör|kompresor|jeneratör|jenerator|fırın|firin|kazan|silo|bant|robot|ünite|unite|ünitesi|ekipman|forklift|istasyon|hat|hattı|hatti|kabin|kabini";

const TURKISH_VOWELS = "aeıioöuü";
const TURKISH_BACK_VOWELS = "aıou";
const TURKISH_ROUNDED_VOWELS = "ouöü";
const TURKISH_VOICELESS = "fstkçşhp";

function lastVowelOf(word: string): string {
  for (let index = word.length - 1; index >= 0; index -= 1) {
    if (TURKISH_VOWELS.includes(word[index])) return word[index];
  }
  return "a";
}

function turkishGenitive(noun: string): string {
  const vowel = lastVowelOf(noun);
  const back = TURKISH_BACK_VOWELS.includes(vowel);
  const rounded = TURKISH_ROUNDED_VOWELS.includes(vowel);
  const suffix = back ? (rounded ? "un" : "ın") : (rounded ? "ün" : "in");
  return TURKISH_VOWELS.includes(noun[noun.length - 1])
    ? `${noun}n${suffix}`
    : `${noun}${suffix}`;
}

function turkishLocative(noun: string): string {
  const vowel = lastVowelOf(noun);
  const back = TURKISH_BACK_VOWELS.includes(vowel);
  const final = noun[noun.length - 1];
  const suffix = TURKISH_VOICELESS.includes(final)
    ? (back ? "ta" : "te")
    : (back ? "da" : "de");
  return "ıiuü".includes(final) ? `${noun}n${suffix}` : `${noun}${suffix}`;
}

function stripEquipmentOrdinals(value: string): string {
  const noun = `(?:${EQUIPMENT_ORDINAL_NOUN})`;
  return value
    .replace(
      new RegExp(
        `\\b(${noun})\\s*\\d+\\s*['’](deki|daki|teki|taki|de|da|te|ta)\\b`,
        "giu",
      ),
      (_match, word: string, suffix: string) =>
        `${turkishLocative(word)}${suffix.endsWith("ki") ? "ki" : ""}`,
    )
    .replace(
      new RegExp(
        `\\b(${noun})\\s*\\d+\\s*['’](?:in|ın|un|ün|nin|nın|nun|nün)\\b`,
        "giu",
      ),
      (_match, word: string) => turkishGenitive(word),
    )
    .replace(new RegExp(`\\b(${noun})\\s*\\d+\\b`, "giu"), "$1");
}

function cleanWhitespace(value: string): string {
  return value
    .replace(/[\t\r\n]+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .replace(/[,;:]+\s*([.!?…])/g, "$1")
    .replace(/([,;:])(?:\s*[,;:])+/g, "$1")
    .replace(/\s{2,}/g, " ")
    .replace(/^[\s,;:–—-]+|[\s,;:–—-]+$/g, "")
    .trim();
}

export function sanitizeNotebookText(value: unknown): string {
  let text = stripEquipmentOrdinals(typeof value === "string" ? value : "");
  for (const pattern of PHOTO_ADDRESS_PATTERNS) {
    text = text.replace(pattern, "");
  }
  for (const pattern of INTERNAL_SCORE_PATTERNS) {
    text = text.replace(pattern, "");
  }
  for (const pattern of ASSIGNMENT_PATTERNS) text = text.replace(pattern, "");
  return cleanWhitespace(text);
}

function sanitizeNotebookContentText(value: unknown): string {
  const clean = sanitizeNotebookText(value);
  if (!clean) return "";
  const sentences = clean.split(/(?<=[.!?…])\s+/u).map((rawSentence) =>
    rawSentence
      .split(/\s*;\s*/u)
      .filter((part) => !UNVERIFIED_STANDARD_IDENTIFIER.test(part))
      .join("; ")
  ).filter(Boolean);
  return cleanWhitespace(sentences.join(" "));
}

function sentence(value: string): string {
  const clean = sanitizeNotebookText(value);
  if (!clean) return "";
  return /[.!?…]$/.test(clean) ? clean : `${clean}.`;
}

function normalizedKeyPart(value: unknown): string {
  return sanitizeNotebookText(value)
    .toLocaleLowerCase("tr-TR")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9çğıöşü]+/giu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 100);
}

function pathValue(
  object: Record<string, unknown> | null | undefined,
  paths: string[][],
): string {
  for (const path of paths) {
    let value: unknown = object;
    for (const segment of path) {
      if (!value || typeof value !== "object") {
        value = undefined;
        break;
      }
      value = (value as Record<string, unknown>)[segment];
    }
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function metadataKey(
  finding: ProjectorFinding,
  metadata: V4ResultMetadata | undefined,
): string {
  const payload = metadata?.canonical_payload;
  const internal = metadata?.internal_priority;
  const mechanism = pathValue(payload, [
    ["mechanism_code"],
    ["condition_code"],
    ["normalized_condition_code"],
    ["event_path", "mechanism_code"],
    ["event_path", "mechanism"],
  ]) || pathValue(internal, [["mechanism_code"]]);
  const asset = sanitizeNotebookText(metadata?.asset_ref) ||
    pathValue(payload, [
      ["asset_ref"],
      ["equipment_family"],
      ["asset_family"],
      ["entity_family"],
      ["equipment", "family"],
      ["asset", "family"],
    ]) || pathValue(internal, [
      ["visible_entity_id"],
      ["asset_label"],
    ]);
  const region = metadata?.evidence_region ??
    (payload?.evidence_region as Record<string, unknown> | undefined);
  const regionNumbers = [
    Number(region?.x),
    Number(region?.y),
    Number(region?.width),
    Number(region?.height),
  ];
  if (
    !mechanism || !asset ||
    regionNumbers.some((value) => !Number.isFinite(value)) ||
    regionNumbers[2] <= 0 || regionNumbers[3] <= 0
  ) return `finding:${finding.id}`;
  const regionKey = regionNumbers
    .map((value) => Math.round(Math.max(0, Math.min(1, value)) * 20))
    .join("-");
  const photos = [...new Set(finding.source_photo_indices ?? [])]
    .filter((item) => Number.isInteger(item) && item > 0)
    .sort((a, b) => a - b)
    .join("-");
  return [
    `asset:${normalizedKeyPart(asset)}`,
    `mechanism:${normalizedKeyPart(mechanism)}`,
    `region:${regionKey}`,
    `photos:${photos || "legacy"}`,
  ].join("|");
}

function riskPriority(
  finding: ProjectorFinding,
  metadata: V4ResultMetadata | undefined,
): number {
  const criticality = String(metadata?.criticality ?? "ordinary");
  const band = String(finding.fk_band ?? finding.m5_band ?? "unknown");
  const base = criticality === "fatal"
    ? 500
    : criticality === "permanent"
    ? 420
    : criticality === "serious"
    ? 340
    : band === "critical"
    ? 400
    : band === "high"
    ? 300
    : band === "medium"
    ? 200
    : 100;
  const classOffset = finding.item_class === "observed_finding"
    ? 40
    : finding.item_class === "verification_request"
    ? 20
    : 0;
  return base + classOffset;
}

function uniqueSentences(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const raw of values) {
    const clean = sentence(raw);
    if (!clean) continue;
    const key = normalizedKeyPart(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function actionTexts(finding: ProjectorFinding): string[] {
  const primary = sanitizeNotebookContentText(finding.recommended_action);
  if (primary) return [primary];
  const measures = Array.isArray(finding.recommended_measures)
    ? finding.recommended_measures
      .map((item) => sanitizeNotebookContentText(item?.text))
      .filter(Boolean)
    : [];
  return measures.slice(0, 2);
}

function findingText(
  finding: ProjectorFinding,
  language: ResultHubLanguage,
  metadata?: V4ResultMetadata,
): string {
  const title = sanitizeNotebookContentText(finding.title);
  const description = sanitizeNotebookContentText(finding.description);
  const itemClass = finding.item_class ??
    (finding.is_scored === false ? "verification_request" : "observed_finding");

  if (itemClass === "assurance_requirement") {
    // The registry's own one-line tespit, where one exists. Written for the
    // logbook specifically -- see ExpertRegistryEntry.notebookTespitTr -- so
    // it names the equipment and the record in one short sentence instead of
    // the generic "X saha veya kayıt teyidi gerektirmektedir" every assurance
    // item used to get regardless of what it actually was.
    const registryTespit = language === "tr"
      ? sanitizeNotebookContentText(
        pathValue(metadata?.internal_priority, [["notebook_tespit"]]),
      )
      : "";
    if (registryTespit) return sentence(registryTespit);
    return language === "tr"
      ? sentence(
        `${
          title || "Teknik güvence konusu"
        } saha veya kayıt teyidi gerektirmektedir`,
      )
      : sentence(
        `${
          title || "The technical assurance topic"
        } requires field or record verification`,
      );
  }
  if (itemClass === "verification_request") {
    return language === "tr"
      ? sentence(
        `${title || "Kritik güvenlik konusu"} saha teyidi gerektirmektedir`,
      )
      : sentence(
        `${title || "The critical safety topic"} requires field verification`,
      );
  }

  const values = uniqueSentences([title, description]);
  return values.join(" ");
}

function recommendationText(
  finding: ProjectorFinding,
  language: ResultHubLanguage,
  metadata?: V4ResultMetadata,
  advisory?: ApprovedNotebookAdvisory,
): string {
  const itemClass = finding.item_class ??
    (finding.is_scored === false ? "verification_request" : "observed_finding");

  if (itemClass === "assurance_requirement") {
    // Was: the generic prefix followed by the specialist card's full
    // recommended_action -- for a registry card that is `ifPresentTr`, a
    // multi-sentence paragraph written for the Uzman Görüşü reader, not a
    // defter line. Analysis bc85eccd published five of these at 345-511
    // characters each, which is most of the "gereksiz uzun" the operator
    // flagged. notebookOneriTr is the one-sentence instruction written for
    // this purpose specifically -- server-authored, no model involvement.
    const registryOneri = language === "tr"
      ? sanitizeNotebookContentText(
        pathValue(metadata?.internal_priority, [["notebook_oneri"]]),
      )
      : "";
    if (
      registryOneri &&
      (language !== "tr" || isStrictTurkishNotebookAdvisory(registryOneri))
    ) return sentence(registryOneri);
  }

  // Onaylı Defter is an employer-facing recommendation, not the operational
  // command shown in Risk Analizi. Turkish rows therefore never fall through
  // to recommended_action: they use the canonical style-only sidecar, or a
  // conservative class-specific advisory while that sidecar self-heals.
  if (language === "tr") {
    const canonical = sanitizeNotebookContentText(advisory?.advisory_text);
    if (isStrictTurkishNotebookAdvisory(canonical)) return canonical;
    return notebookAdvisoryFallback(itemClass as ApprovedNotebookItemClass);
  }

  const actions = uniqueSentences(actionTexts(finding));
  const fallback =
    "Appropriate engineering and organisational controls should be identified and implemented.";
  const joined = actions.join(" ") || fallback;

  if (itemClass === "verification_request") {
    return `Field verification should be completed; if a nonconformity is confirmed, ${
      joined.charAt(0).toLowerCase()
    }${joined.slice(1)}`;
  }
  if (itemClass === "assurance_requirement") {
    // No registry-authored line -- a v4 legacy assurance item, or an English
    // report. Falls back to what shipped before.
    return `The relevant assurance should be verified through records, measurement, or an authorised field check. ${joined}`;
  }
  return joined;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function uuidFromHex(hex: string): string {
  const bytes = hex.slice(0, 32).split(/(?=(?:..)*$)/).filter(Boolean);
  const raw = bytes.map((value) => Number.parseInt(value, 16));
  raw[6] = (raw[6] & 0x0f) | 0x50;
  raw[8] = (raw[8] & 0x3f) | 0x80;
  const value = raw.map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${
    value.slice(16, 20)
  }-${value.slice(20, 32)}`;
}

export function firstSentenceTeaser(value: unknown, maxLength = 160): string {
  const clean = sanitizeNotebookText(value);
  if (!clean) return "";
  const match = clean.match(/^.*?[.!?…](?:\s|$)/u)?.[0]?.trim() ?? clean;
  if (match.length <= maxLength) return match;
  return `${match.slice(0, Math.max(1, maxLength - 1)).trimEnd()}…`;
}

export async function projectApprovedNotebookEntries(params: {
  analysisID: string;
  language: ResultHubLanguage;
  findings: ProjectorFinding[];
  metadata?: V4ResultMetadata[];
  advisories?: ApprovedNotebookAdvisory[];
}): Promise<ApprovedNotebookProjection[]> {
  const metadataByFinding = new Map(
    (params.metadata ?? [])
      .filter((item) => typeof item.public_finding_id === "string")
      .map((item) => [item.public_finding_id as string, item]),
  );
  const groups = new Map<string, Group>();
  const advisoryByFinding = new Map(
    (params.advisories ?? []).map((row) => [row.source_finding_id, row]),
  );

  for (const row of params.findings) {
    if (!row.id || !sanitizeNotebookText(row.title)) continue;
    const itemClass = row.item_class ??
      (row.is_scored === false ? "verification_request" : "observed_finding");
    if (
      !["observed_finding", "assurance_requirement", "verification_request"]
        .includes(itemClass)
    ) {
      continue;
    }
    const metadata = metadataByFinding.get(row.id);
    const key = metadataKey(row, metadata);
    const existing = groups.get(key) ?? {
      key,
      rows: [],
      metadata: [],
      priority: 0,
    };
    existing.rows.push({ ...row, item_class: itemClass });
    if (metadata) existing.metadata.push(metadata);
    existing.priority = Math.max(
      existing.priority,
      riskPriority(row, metadata),
    );
    groups.set(key, existing);
  }

  const ordered = [...groups.values()].sort((left, right) =>
    right.priority - left.priority ||
    Math.min(...left.rows.map((row) => row.display_order ?? 9999)) -
      Math.min(...right.rows.map((row) => row.display_order ?? 9999)) ||
    left.key.localeCompare(right.key)
  );

  return await Promise.all(ordered.map(async (group, index) => {
    const sourceIDs = [...new Set(group.rows.map((row) => row.id))].sort();
    const findings = uniqueSentences(
      group.rows.map((row) =>
        findingText(row, params.language, metadataByFinding.get(row.id))
      ),
    ).join(" ");
    const recommendations = uniqueSentences(
      group.rows.map((row) =>
        recommendationText(
          row,
          params.language,
          metadataByFinding.get(row.id),
          advisoryByFinding.get(row.id),
        )
      ),
    ).join(" ");
    const references = uniqueSentences(
      group.metadata.flatMap((item) => item.verified_references ?? []),
    );
    const referenceText = references.length > 0 ? references.join(" ") : null;
    const sourceHash = await sha256Hex(JSON.stringify({
      sourceIDs,
      findings,
      recommendations,
      referenceText,
      projection: APPROVED_NOTEBOOK_PROJECTION_VERSION,
      template: params.language === "tr"
        ? APPROVED_NOTEBOOK_TEMPLATE_TR
        : SAFETY_LOG_TEMPLATE_EN,
    }));
    const idHash = await sha256Hex([
      params.analysisID,
      params.language,
      APPROVED_NOTEBOOK_PROJECTION_VERSION,
      group.key,
    ].join("|"));
    return {
      id: uuidFromHex(idHash),
      grouping_key: group.key,
      source_finding_ids: sourceIDs,
      source_hash: sourceHash,
      finding_text: findings,
      recommendation_text: recommendations,
      reference_text: referenceText,
      display_order: index,
    };
  }));
}
