// The provider answered a Turkish analysis in English and nothing stopped it.
//
// Analysis 8747d7c1 published "Missing toeboard on elevated platform guardrail"
// and "Unguarded rotating machinery parts" to a tr-TR report, with the sentence
// template welded around English fragments: "Bu durum contact with exposed
// rotating parts yoluyla entanglement or crushing injury sonucuna neden
// olabilir." Every one of the five primary candidates came back in English.
//
// v4 states the output language in the prompt and then never checks it --
// language_validation_status has read "not_evaluated" on every run this engine
// has ever done. The shared validator in _shared/ai-localization-validation.ts
// would not have caught it either: its language check looks for incompatible
// SCRIPTS (Han, Cyrillic, Arabic...), and English is Latin like Turkish.
//
// Turkish prose of any length carries its own letters. A page of Turkish safety
// text without a single ç, ğ, ı, ö, ş or ü, carrying English function words, is
// not Turkish. That is the whole test -- deliberately blunt, because the failure
// it catches is blunt, and because a false alarm only costs one retry.

import type { ProviderPhotoOutput } from "./contracts.ts";

const TURKISH_LETTERS = /[çğıöşüÇĞİÖŞÜ]/u;

/** Function words that carry no meaning in Turkish and are common in English. */
const ENGLISH_MARKERS =
  /\b(?:the|of|and|with|from|for|is|are|was|were|to|on|in|at|by|between|below|above|near|missing|exposed|unguarded|rotating|falling|contact|injury|person|worker|platform|edge|guard(?:rail)?|machinery|equipment|surface|visible|no|not)\b/giu;

/**
 * User-facing text the provider authored, one block per claim.
 *
 * Per claim, not one pooled string: analysis d32d23f8 answered in BOTH
 * languages -- one Turkish candidate, then three English ones, with English
 * field checks and an English positive control -- and a whole-output test sees
 * the first block's diacritics and passes the rest. The report published
 * "Missing mid-rail on the foreground right platform guardrail" underneath a
 * Turkish finding.
 */
function providerTextBlocks(output: ProviderPhotoOutput): string[] {
  const blocks: string[] = [];
  for (const candidate of output.candidates) {
    blocks.push(
      [
        candidate.raw_label ?? "",
        ...(candidate.affirmative_cues ?? []),
        ...(candidate.counter_cues ?? []),
        candidate.event_path?.source ?? "",
        candidate.event_path?.contact_or_failure ?? "",
        candidate.event_path?.consequence ?? "",
      ].filter((part) => part.trim().length > 0).join(" ").trim(),
    );
  }
  for (const control of output.positive_controls) {
    blocks.push(
      [control.description ?? "", ...(control.affirmative_cues ?? [])]
        .filter((part) => part.trim().length > 0).join(" ").trim(),
    );
  }
  return blocks.filter((block) => block.length > 0);
}

/** Non-null when this one block is English. */
function blockIsEnglish(block: string): boolean {
  // Short blocks are never judged: a label like "motor kaplini" can legitimately
  // carry no diacritic, and a false alarm costs a retry on a correct answer.
  if (block.length < 60) return false;
  if (TURKISH_LETTERS.test(block)) return false;
  return (block.match(ENGLISH_MARKERS) ?? []).length >= 3;
}

/**
 * Non-null when the provider ignored the Turkish output contract.
 *
 * Only "tr" is judged. Other languages fall through untouched rather than being
 * guessed at: a wrong verdict here costs a retry on a correct answer.
 */
export function outputLanguageFailure(
  output: ProviderPhotoOutput,
  expectedLanguage: string,
): string | null {
  if (expectedLanguage !== "tr") return null;
  const blocks = providerTextBlocks(output);
  if (blocks.length === 0) return null;
  const english = blocks.filter(blockIsEnglish);
  if (english.length === 0) return null;
  return `output_language_not_turkish:blocks=${english.length}/${blocks.length}:len=${
    english[0].length
  }`;
}

/**
 * Appended to the prompt when a retry is spent on the language contract.
 * Part of the hashed bundle: it reaches the provider, so the integrity contract
 * has to cover it the way it already covers the coverage-repair text.
 */
export const V4_LANGUAGE_CORRECTION_COMMON = `ÇIKTI DİLİ DÜZELTMESİ
- Önceki cevap Türkçe değil, İngilizce yazılmıştı ve sözleşmeye aykırıydı.
- raw_label, affirmative_cues, counter_cues ve event_path alanlarının TAMAMINI Türkçe yaz. Tek bir İngilizce cümle veya ifade bırakma.
- Yalnız uluslararası standart adları (API 653, TS EN ISO 12100 gibi) ve fotoğraftaki okunan yazılar özgün hâlinde kalabilir.
- Aynı görsel kanıta bağlı kal; bulguları değiştirme, yalnız dili düzelt.`;

export function languageContractCorrection(basePrompt: string): string {
  return `${basePrompt}\n\n${V4_LANGUAGE_CORRECTION_COMMON}`;
}
