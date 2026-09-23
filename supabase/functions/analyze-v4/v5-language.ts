import type { V5PhotoOutput } from "./v5-contracts.ts";

// Check prose, never JSON keys or the fixed Turkish layer/score identifiers.
// A visible Turkish place or product name can occur in otherwise English prose,
// so a single accented character is not enough to reject a finding.
const TURKISH_LETTERS = /[çğıöşüÇĞİÖŞÜ]/gu;
const TURKISH_WORDS =
  /(?:^|[^\p{L}])(?:ve|veya|ile|bir|bu|için|olarak|olan|gibi|yok|vardır|bulunmaktadır|bulunur|üzerinde|yanında|nedeniyle|sonucu|riski|çalışanlar|sağlayın|kontrol edin|kaldırın|yerleştirin)(?=$|[^\p{L}])/giu;
const TURKISH_SENTENCE_ENDINGS =
  /(?:^|[^\p{L}])\p{L}{5,}(?:maktadır|mektedir|malıdır|melidir|mıştır|miştir|unuz|ünüz)(?=$|[^\p{L}])/giu;

function isTurkishProse(value: string): boolean {
  if (value.length < 35) return false;
  const letters = (value.match(TURKISH_LETTERS) ?? []).length;
  const words = (value.match(TURKISH_WORDS) ?? []).length;
  const endings = (value.match(TURKISH_SENTENCE_ENDINGS) ?? []).length;
  return words + endings >= 3 ||
    (letters >= 2 && words + endings >= 1) ||
    (letters >= 4 && value.length >= 80);
}

/** One verdict per authored claim, so an English finding cannot hide a Turkish one. */
export function v5EnglishLanguageFailure(output: V5PhotoOutput): string | null {
  const blocks: Array<[string, string]> = [
    ["scene_summary", output.scene_summary],
    ...output.findings.map((finding, index): [string, string] => [
      `finding_${index + 1}`,
      [
        finding.title,
        finding.category,
        finding.description,
        finding.event_path,
        finding.root_cause,
        finding.fine_kinney["gerekçe"],
        finding.immediate_control,
        ...finding.corrective_steps,
        finding.preventive_measure,
        finding.training_recommendation ?? "",
        finding.ppe_recommendation ?? "",
      ].filter(Boolean).join(" "),
    ]),
    ...output.positive_controls.map((control, index): [string, string] => [
      `positive_control_${index + 1}`,
      `${control.title} ${control.description}`,
    ]),
    ["layer_scan", output.layer_scan.map((row) => row.note).join(" ")],
  ];
  return blocks.find(([, value]) => isTurkishProse(value))?.[0] ?? null;
}

/** A bounded second attempt with the same photograph and evidence rules. */
export function v5EnglishRetryPrompt(basePrompt: string): string {
  return `${basePrompt}\n\n## LANGUAGE CORRECTION FOR THIS ATTEMPT\nThe previous response used Turkish prose. That response was rejected and will not be shown to the user. Examine the same photograph again and write every reader-facing JSON value in English, including the scene summary, each finding, every corrective step, the score rationale, the layer notes and positive controls. Preserve the evidence and the JSON keys and fixed enum codes required by the schema. Do not copy or translate Turkish prose from the previous response. Return only the complete JSON object in English.`;
}
