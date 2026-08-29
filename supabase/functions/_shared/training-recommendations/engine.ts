// Context -> rules -> merged cards -> Turkish text.
//
// Deterministic throughout. The same analysis and the same catalogue version
// produce the same bytes, because the alternative in this domain is a sentence
// that sends someone to the wrong certificate body.

import type {
  AudienceCode,
  HazardClass,
  RenderedDuration,
  StatutoryDuration,
  TrainingApplicability,
  TrainingContext,
  TrainingRecommendation,
} from "./contracts.ts";
import {
  AUDIENCE_TR,
  CLASS_LABEL_TR,
  HAZARD_CLASS_TR,
  type TrainingGroupCode,
} from "./contracts.ts";
import {
  EQUIPMENT_FAMILY_PATTERNS,
  TRAINING_CATALOG,
  TRAINING_RULES,
  type TrainingCatalogEntry,
  type TrainingRule,
} from "./catalog.tr.ts";

/** Book-source blocks the analysis already persists on every routed item. */
export type TrainingSourceItem = {
  sourceItemId: string;
  moduleId: string;
  mechanismCode: string | null;
  assuranceTopicId: string | null;
  assetRef: string | null;
  barrierComponentsAbsent: string[];
  peopleVisible: number;
};

export function equipmentFamilyOf(assetRef: string | null): string | null {
  if (!assetRef) return null;
  const normalised = assetRef.toLocaleLowerCase("tr-TR");
  for (const { family, pattern } of EQUIPMENT_FAMILY_PATTERNS) {
    if (pattern.test(normalised)) return family;
  }
  return null;
}

export function resolveContext(params: {
  sectorId: string | null;
  hazardClass: HazardClass | null;
  items: TrainingSourceItem[];
}): TrainingContext {
  const byTrigger: Record<string, string[]> = {};
  const push = (trigger: string, id: string) => {
    const list = byTrigger[trigger] ?? [];
    if (!list.includes(id)) list.push(id);
    byTrigger[trigger] = list;
  };

  const mechanisms = new Set<string>();
  const topics = new Set<string>();
  const modules = new Set<string>();
  const equipment = new Set<string>();
  const barriers = new Set<string>();
  let peopleVisible = 0;

  for (const item of params.items) {
    if (item.mechanismCode) {
      mechanisms.add(item.mechanismCode);
      push(item.mechanismCode, item.sourceItemId);
    }
    if (item.assuranceTopicId) {
      topics.add(item.assuranceTopicId);
      push(item.assuranceTopicId, item.sourceItemId);
    }
    modules.add(item.moduleId);
    const family = equipmentFamilyOf(item.assetRef);
    if (family) {
      equipment.add(family);
      push(family, item.sourceItemId);
    }
    for (const component of item.barrierComponentsAbsent) barriers.add(component);
    peopleVisible = Math.max(peopleVisible, item.peopleVisible);
  }

  return {
    sectorId: params.sectorId,
    hazardClass: params.hazardClass,
    mechanismCodes: [...mechanisms].sort(),
    assuranceTopicIds: [...topics].sort(),
    moduleIds: [...modules].sort(),
    equipmentFamilies: [...equipment].sort(),
    barrierComponentsAbsent: [...barriers].sort(),
    peopleVisible,
    sourceItemIdsByTrigger: byTrigger,
  };
}

type Match = {
  rule: TrainingRule;
  entry: TrainingCatalogEntry;
  applicability: TrainingApplicability;
  triggers: string[];
};

function matchRule(
  rule: TrainingRule,
  context: TrainingContext,
): { hit: boolean; triggers: string[] } {
  const triggers: string[] = [];
  for (const mechanism of rule.mechanisms ?? []) {
    if (context.mechanismCodes.includes(mechanism)) triggers.push(mechanism);
  }
  for (const topic of rule.assuranceTopics ?? []) {
    if (context.assuranceTopicIds.includes(topic)) triggers.push(topic);
  }
  for (const family of rule.equipment ?? []) {
    if (context.equipmentFamilies.includes(family)) triggers.push(family);
  }
  for (const sector of rule.sectors ?? []) {
    if (context.sectorId === sector) triggers.push(`sector:${sector}`);
  }
  if (triggers.length > 0) return { hit: true, triggers };
  if (rule.always) return { hit: true, triggers: ["baseline"] };
  return { hit: false, triggers: [] };
}

/**
 * Mood, not strength.
 *
 * A special role has to be assigned before its training means anything, so it
 * stays conditional whoever is in the frame. Otherwise: people visible and a
 * hazard trigger means the exposure is real and the sentence can say so;
 * equipment alone means the picture does not show anyone operating it, and
 * saying otherwise would be a claim about a person.
 */
function applicabilityFor(
  rule: TrainingRule,
  context: TrainingContext,
  triggers: string[],
): TrainingApplicability {
  if (rule.specialRole) return "conditional_if_special_role_assigned";
  if (triggers.includes("baseline")) return "sector_role_match";
  if (rule.directWhenPeopleVisible && context.peopleVisible > 0) {
    return "direct_hazard_exposure_match";
  }
  return "conditional_if_task_performed";
}

/** At most two audience families; more reads as a list rather than a reader. */
function audienceLabel(audiences: AudienceCode[]): string {
  const named = audiences.map((code) => AUDIENCE_TR[code]).filter(Boolean);
  if (named.length === 0) return "İlgili çalışanlar";
  if (named.length <= 2) return named.join(" ve ");
  return "İlgili çalışanlar";
}

/**
 * "a, b, c ve d" -- at most five, per the writing standard.
 *
 * A final item that already contains "ve" is joined with a comma instead:
 * "... dökülme müdahalesi ve kişisel korunma ve dekontaminasyon" is the kind of
 * sentence a reader stumbles over and an editor would never write. The
 * catalogue avoids internal conjunctions in last position, and this is the
 * guard for the day someone adds one.
 */
function topicList(topics: string[]): string {
  const kept = topics.slice(0, 5);
  if (kept.length === 0) return "";
  if (kept.length === 1) return kept[0];
  const last = kept[kept.length - 1];
  const head = kept.slice(0, -1).join(", ");
  // The clash is with whatever sits next to the joining "ve", so both of the
  // final two items matter: "... kanama ve yaralanmada ilk davranış ve
  // sertifikalı ilk yardımcıya yönlendirme" reads as badly as a conjunction in
  // last position, and a test caught it after the first fix missed it.
  const neighbours = kept.slice(-2);
  const clashes = neighbours.some((topic) => / ve /u.test(topic));
  return clashes ? `${head}, ${last}` : `${head} ve ${last}`;
}

function renderText(
  entry: TrainingCatalogEntry,
  applicability: TrainingApplicability,
): string {
  const topics = topicList(entry.topics);

  let first: string;
  if (entry.recommendationClass === "meb_operator_authorization") {
    // Never "has no licence". The recommendation is that whoever operates it
    // holds the authorisation for that machine class and is trained on this
    // particular site.
    first =
      `${entry.conditionalContext} kullanacak personelin ilgili ekipman türüne ait operatörlük yetkisini taşıması ve ${topics} konularında uygulamalı eğitim alması önerilir.`;
  } else if (entry.recommendationClass === "myk_qualification_verification") {
    // Never "MYK kursu". It is an examination and certification route, and the
    // recommendation is to verify the requirement against current records.
    first =
      `${entry.conditionalContext} görevi yürütülecekse, görevle eşleşen güncel mesleki yeterlilik veya mevzuatta kabul edilen eşdeğer mesleki belge koşulunun resmî kayıtlar üzerinden doğrulanması önerilir.`;
  } else if (applicability === "conditional_if_special_role_assigned") {
    first =
      `${entry.conditionalContext} görevlendirilecek personele; ${topics} konularını içeren göreve özgü eğitim verilmesi önerilir.`;
  } else if (applicability === "direct_hazard_exposure_match") {
    first =
      `${entry.directContext ?? entry.conditionalContext} görev yapan personele; ${topics} konularını içeren uygulamalı eğitim verilmesi önerilir.`;
  } else {
    first =
      `${entry.conditionalContext} görev yapacak personele; ${topics} konularını içeren eğitim verilmesi önerilir.`;
  }

  return entry.secondSentence ? `${first} ${entry.secondSentence}` : first;
}

/** "yılda bir", "iki yılda bir", "üç yılda bir" -- no bare digits in prose. */
const YEAR_WORD_TR: Record<number, string> = {
  1: "yılda bir",
  2: "iki yılda bir",
  3: "üç yılda bir",
};

const NUMBER_WORD_TR: Record<number, string> = { 1: "bir", 2: "iki", 3: "üç" };

const CLASS_ORDER: HazardClass[] = ["low", "medium", "high"];

/**
 * A statutory duration, resolved against whatever the workplace class is known
 * to be.
 *
 * Known class: the reader's own row, and only that row. Unknown class: all
 * three, which is the honest form -- the alternative is picking one, and
 * picking one means asserting a hazard class nobody stated. The row is data,
 * not prose, so it never passes through the linter and never has to satisfy
 * the two-sentence rule.
 */
export function renderDuration(
  duration: StatutoryDuration | undefined,
  hazardClass: HazardClass | null,
): RenderedDuration | null {
  if (!duration) return null;
  const label = "Yasal süre";

  if (typeof duration.minimumHours === "number") {
    return {
      label,
      value: `En az ${duration.minimumHours} saat`,
      ...(duration.noteTr ? { note: duration.noteTr } : {}),
    };
  }

  const hours = duration.hoursByHazardClass;
  if (!hours) return null;
  const refresh = duration.refreshYearsByHazardClass;

  if (hazardClass) {
    const interval = refresh ? YEAR_WORD_TR[refresh[hazardClass]] : undefined;
    const note = interval ? `Yenileme: ${interval}` : duration.noteTr;
    return {
      label,
      value: `${HAZARD_CLASS_TR[hazardClass]} sınıf · en az ${
        hours[hazardClass]
      } saat`,
      ...(note ? { note } : {}),
    };
  }

  // No company on the analysis, so no stated class. Say all three rather than
  // guess one; the reader knows which line is theirs and the engine does not.
  const value = CLASS_ORDER
    .map((code) => `${HAZARD_CLASS_TR[code]} ${hours[code]}`)
    .join(" · ") + " saat";
  // "üç yılda bir, iki yılda bir, yılda bir" says "bir" three times for no
  // reason. The interval word is shared, so factor it out and list the numbers.
  const note = refresh
    ? `Yenileme: sırasıyla ${
      CLASS_ORDER.slice(0, -1).map((code) => NUMBER_WORD_TR[refresh[code]] ?? "")
        .join(", ")
    } ve ${
      NUMBER_WORD_TR[refresh[CLASS_ORDER[CLASS_ORDER.length - 1]]] ?? ""
    } yılda bir`
    : undefined;
  return { label, value, ...(note ? { note } : {}) };
}

const GROUP_ORDER: TrainingGroupCode[] = [
  "task_and_equipment",
  "qualification_and_authorization",
  "emergency_and_rescue",
  "general_and_induction",
  "toolbox",
];

export function buildTrainingRecommendations(
  context: TrainingContext,
): TrainingRecommendation[] {
  const matches: Match[] = [];
  for (const rule of TRAINING_RULES) {
    const entry = TRAINING_CATALOG[rule.entry];
    if (!entry) continue;
    const { hit, triggers } = matchRule(rule, context);
    if (!hit) continue;
    matches.push({
      rule,
      entry,
      applicability: applicabilityFor(rule, context, triggers),
      triggers,
    });
  }

  // One card per merge key. The strongest mood wins: a hazard seen with people
  // beside it should not be softened because a second, weaker rule matched the
  // same catalogue entry.
  const byMerge = new Map<string, Match>();
  for (const match of matches) {
    const existing = byMerge.get(match.entry.mergeKey);
    if (!existing) {
      byMerge.set(match.entry.mergeKey, match);
      continue;
    }
    const rank = (value: TrainingApplicability) =>
      value === "direct_task_match" || value === "direct_hazard_exposure_match"
        ? 3
        : value === "conditional_if_task_performed"
        ? 2
        : 1;
    if (rank(match.applicability) > rank(existing.applicability)) {
      byMerge.set(match.entry.mergeKey, {
        ...existing,
        applicability: match.applicability,
      });
    }
    existing.triggers = [...new Set([...existing.triggers, ...match.triggers])];
  }

  const cards = [...byMerge.values()].map((match) => {
    const sourceItemIds = [
      ...new Set(
        match.triggers.flatMap((trigger) =>
          context.sourceItemIdsByTrigger[trigger] ?? []
        ),
      ),
    ].sort();
    return {
      catalogCode: match.entry.code,
      recommendationClass: match.entry.recommendationClass,
      groupCode: match.entry.groupCode,
      title: match.entry.title,
      categoryLabel: CLASS_LABEL_TR[match.entry.recommendationClass],
      audienceLabel: audienceLabel(match.entry.audiences),
      text: renderText(match.entry, match.applicability),
      duration: renderDuration(match.entry.statutoryDuration, context.hazardClass),
      applicability: match.applicability,
      triggerCodes: [...match.triggers].sort(),
      sourceItemIds,
      displayOrder: 0,
    } satisfies TrainingRecommendation;
  });

  // Hazard-driven cards first: they came from something visible in this
  // photograph. The baseline entries are true of any workplace and belong
  // underneath, not above.
  cards.sort((left, right) => {
    const groupDelta = GROUP_ORDER.indexOf(left.groupCode) -
      GROUP_ORDER.indexOf(right.groupCode);
    if (groupDelta !== 0) return groupDelta;
    return left.catalogCode.localeCompare(right.catalogCode, "en");
  });
  cards.forEach((card, index) => {
    card.displayOrder = index;
  });
  return cards;
}
