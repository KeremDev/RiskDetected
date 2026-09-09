import type { ExpertRecommendation, ExpertRegistryEntry } from "./contracts.ts";
import { EXPERT_REGISTRY } from "./registry.tr.ts";

/**
 * Deterministic throughout, like the training catalogue and for the same
 * reason: the same photograph must produce the same paragraph, because a
 * sentence that moves between runs cannot be reviewed, corrected or trusted.
 */

const CLASS_ORDER: Record<string, number> = {
  periodic_inspection_record: 0,
  measurement_record: 1,
  site_verification: 2,
};

function endSentence(value: string): string {
  const text = value.trim();
  if (!text) return "";
  return /[.!?:]$/u.test(text) ? text : `${text}.`;
}

/**
 * The specialist's paragraph: what is visible, then what must be on file.
 *
 * The requirements are numbered rather than run together because the reader is
 * going to walk them one at a time against a folder.
 */
export function renderExpertText(entry: ExpertRegistryEntry): string {
  const lines = entry.requirementsTr
    .map((line, index) => `${index + 1}. ${endSentence(line)}`)
    .join("\n");
  const interval = entry.interval
    ? `\n\nKontrol periyodu: ${endSentence(entry.interval.textTr)}`
    : "";
  return `${endSentence(entry.observationTr)}\n\n${lines}${interval}`;
}

/**
 * The preventive half.
 *
 * Without a verified interval this says how to keep the record current without
 * naming a period, which is the honest form of the same advice.
 */
function ongoingFor(entry: ExpertRegistryEntry): string {
  return entry.interval
    ? `Ekipmanı periyodik kontrol takvimine bağlayın ve bir sonraki kontrol tarihini envantere işleyin. Kontrol periyodu: ${
      endSentence(entry.interval.textTr)
    }`
    : "Ekipmanı muayene planına bağlayın, bir sonraki muayene tarihini kalan ömür hesabına göre belirleyin ve envantere işleyin.";
}

export type ExpertBuildResult = {
  recommendations: ExpertRecommendation[];
  /**
   * Families the model reported but the registry has no entry for.
   *
   * Reported rather than silently dropped: this list is the work queue for the
   * registry, and a family that keeps appearing here is the next entry to
   * write.
   */
  familiesWithoutEntry: string[];
};

export function expertRecommendationsFor(
  observedFamilies: string[],
): ExpertBuildResult {
  const seen = new Set<string>();
  const matched: ExpertRegistryEntry[] = [];
  const missing: string[] = [];

  for (const family of observedFamilies) {
    if (seen.has(family)) continue;
    seen.add(family);
    const entry = EXPERT_REGISTRY[family];
    if (!entry) {
      missing.push(family);
      continue;
    }
    matched.push(entry);
  }

  matched.sort((a, b) => {
    const byClass = (CLASS_ORDER[a.recommendationClass] ?? 9) -
      (CLASS_ORDER[b.recommendationClass] ?? 9);
    return byClass !== 0 ? byClass : a.family.localeCompare(b.family, "tr");
  });

  return {
    recommendations: matched.map((entry, index) => ({
      family: entry.family,
      recommendationClass: entry.recommendationClass,
      title: entry.titleTr,
      categoryLabel: entry.categoryLabelTr,
      text: renderExpertText(entry),
      action: endSentence(entry.ifPresentTr),
      ifAbsent: endSentence(entry.ifAbsentTr),
      ongoing: endSentence(ongoingFor(entry)),
      references: entry.referencesTr.map(endSentence).join("\n"),
      displayOrder: index + 1,
      notebookTespit: endSentence(entry.notebookTespitTr),
      notebookOneri: endSentence(entry.notebookOneriTr),
    })),
    familiesWithoutEntry: missing.sort(),
  };
}
