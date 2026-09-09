import type { NormalizedCandidate } from "./contracts.ts";

// Every scored finding drew its recommended action from a deterministic
// catalog keyed by mechanism. Across seven analyses that catalog published
// thirteen byte-identical `recommended_action` strings, and across twelve
// analyses, twelve. The repetition is the visible symptom; the miss is worse.
// In analysis af4b0f76 a worker carrying a timber on his shoulder normalized to
// `vehicle_person_interface` -- the closest of a small set of mechanism codes --
// and published "Ekipmanın hareket ve dönüş alanına yaya girişini fiziksel
// olarak kapatın." There is no equipment in the photograph. A rich observation
// was compressed into an enum, and the enum pulled the wrong catalog row.
//
// The model already holds what the catalog lost: which object, which edge,
// which direction. So it writes the line and this module decides whether the
// line may be published. What it guards is exactly what the model is not
// allowed to assert anywhere else in the contract -- regulation, standard,
// article, score, risk band, and nonconformity about things the photograph
// cannot show. Anything rejected falls back to the catalog sentence, which is
// the behaviour that shipped before, so a failed lint costs a repeat and never
// a missing action.

/** Regulation, standard, article and clause references. */
const CITES_AUTHORITY =
  /(?:\b\d{4,5}\s*say[ıi]l[ıi]|\bmadde\s*\d|\bmd\.\s*\d|\bTS\s?EN\b|\bTSE\b|\bEN\s?\d{3}|\bISO\s?\d|\bIEC\s?\d|\bOSHA\b|\bNFPA\b|\bAPI\s?\d|y[öo]netmeli[ğg]i|\bmevzuat|\bkanun|\btebli[ğg]i|\bgenelge)/iu;

/** Scores, bands and the scoring vocabulary itself. */
const CITES_SCORE =
  /(?:fine\s*-?\s*kinney|\brisk\s*(?:skor|puan|band|derece|seviyes)|[şs]iddet\s*(?:de[ğg]er|puan|skor)|olas[ıi]l[ıi]k\s*(?:de[ğg]er|puan|[×x*])|\bkabul\s*edilemez\s*risk|\b(?:d[üu][şs][üu]k|orta|y[üu]ksek|kritik)\s*risk\s*(?:band|seviye))/iu;

// A control may legitimately prescribe a document -- "izin sistemi kurun" is a
// control, not a claim. What it may not do is assert that an invisible record
// is missing, which is the same line the candidate contract already forbids.
const ASSERTS_INVISIBLE_ABSENCE =
  /(?:e[ğg]itim|sertifika|belge|yetki\s*belges|periyodik\s*kontrol|muayene\s*raporu|[öo]l[çc][üu]m|kalibrasyon)\w*\s+(?:[^.]{0,24}?)(?:yok|yoktur|bulunmuyor|bulunmamakta|eksik|yap[ıi]lmam[ıi][şs]|al[ıi]nmam[ıi][şs]|mevcut\s*de[ğg]il|ge[çc]ersiz)/iu;

// The model is being asked for an instruction. A sentence that describes the
// scene instead has answered the wrong question, and publishing it would put an
// observation where the reader looks for an action.
const READS_AS_OBSERVATION =
  /(?:g[öo]r[üu]lmekte|g[öo]r[üu]lmüştür|mevcuttur|bulunmaktad[ıi]r|tespit\s*edil(?:mi[şs]|di)|riski\s*(?:vard[ıi]r|bulunmakta)|olu[şs]turmaktad[ıi]r|te[şs]kil\s*etmektedir)/iu;

/** Markup, placeholders and links have no place in published copy. */
const NOT_PROSE = /[<>{}\[\]|]|https?:\/\/|\{\{|\$\{/u;

const TURKISH_LETTERS = /[çğıöşüÇĞİÖŞÜ]/u;
const TURKISH_FUNCTION_WORDS =
  /\b(?:ve|ile|icin|için|olan|bir|bu|veya|kadar|gibi)\b/giu;

const MIN_LENGTH = 24;
const MAX_LENGTH = 320;

export type ControlLintResult =
  | { ok: true; text: string }
  | { ok: false; reason: string };

/**
 * A line long enough to be Turkish prose but carrying no Turkish letter at all
 * is diacritic-stripped Turkish ("gorulen kenari kapatin"), which the output
 * language contract already rejects for the rest of the payload.
 */
function diacriticsStripped(text: string): boolean {
  if (TURKISH_LETTERS.test(text)) return false;
  return (text.match(TURKISH_FUNCTION_WORDS) ?? []).length >= 2;
}

/**
 * A control that only restates the finding's own label tells the reader
 * nothing they did not just read in the title.
 */
function echoesLabel(text: string, candidate: NormalizedCandidate): boolean {
  const normalize = (value: string) =>
    value.toLocaleLowerCase("tr-TR").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const line = normalize(text);
  const label = normalize(candidate.raw_label ?? "");
  if (!label || label.length < 12) return false;
  return line === label || line.startsWith(`${label} `);
}

export function lintControlText(
  raw: unknown,
  candidate: NormalizedCandidate,
): ControlLintResult {
  if (typeof raw !== "string") return { ok: false, reason: "absent" };
  const text = raw.replace(/\s+/gu, " ").trim();
  if (!text) return { ok: false, reason: "absent" };
  if (text.length < MIN_LENGTH) return { ok: false, reason: "too_short" };
  if (text.length > MAX_LENGTH) return { ok: false, reason: "too_long" };
  if (NOT_PROSE.test(text)) return { ok: false, reason: "not_prose" };
  if (diacriticsStripped(text)) {
    return { ok: false, reason: "diacritics_stripped" };
  }
  if (CITES_AUTHORITY.test(text)) {
    return { ok: false, reason: "cites_authority" };
  }
  if (CITES_SCORE.test(text)) return { ok: false, reason: "cites_score" };
  if (ASSERTS_INVISIBLE_ABSENCE.test(text)) {
    return { ok: false, reason: "asserts_invisible_absence" };
  }
  if (READS_AS_OBSERVATION.test(text)) {
    return { ok: false, reason: "reads_as_observation" };
  }
  if (echoesLabel(text, candidate)) {
    return { ok: false, reason: "echoes_label" };
  }
  return { ok: true, text: text.endsWith(".") ? text : `${text}.` };
}
