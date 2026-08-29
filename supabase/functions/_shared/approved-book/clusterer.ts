// One paragraph per event path and corrective family.
//
// Two failure modes to avoid, and they pull in opposite directions:
//
//   Splitting. One fall from one edge should not become five entries because
//   the guardrail, the anchor, the personal system and the rescue plan are four
//   layers of the same control. They share a mechanism and an asset, so they
//   share a paragraph.
//
//   Merging. Unrelated defects that happen to sit in one photograph must not be
//   pressed into one record. A missing mid rail and an unguarded mixer drum are
//   two entries even though the camera saw them together.
//
// The key is therefore mechanism plus asset family, never the photograph.

import type {
  ApprovedBookCluster,
  BookEntryClass,
  BookSourceItem,
  BookUrgency,
  Criticality,
} from "./contracts.ts";

const CRITICALITY_RANK: Record<Criticality, number> = {
  fatal: 4,
  permanent: 3,
  serious: 2,
  ordinary: 1,
};

const ENTRY_CLASS_RANK: Record<BookEntryClass, number> = {
  critical_immediate: 4,
  observed_corrective: 3,
  measurement_or_test_request: 2,
  assurance_verification: 1,
};

function urgencyFor(
  entryClass: BookEntryClass,
  criticality: Criticality,
): BookUrgency {
  if (entryClass === "critical_immediate") return "immediate";
  if (criticality === "fatal" || criticality === "permanent") {
    return "short_term";
  }
  return "planned";
}

/**
 * Cluster key.
 *
 * An observed finding keys on mechanism plus asset family: the same fall from
 * the same platform is one entry however many barrier layers are named. An
 * assurance item keys on its topic, because the topic IS the claim. A
 * verification request keys on its target so two questions about one asset ask
 * once.
 */
function clusterKey(
  item: BookSourceItem,
  entryClass: BookEntryClass,
): string {
  if (entryClass === "assurance_verification") {
    return `assurance:${item.assuranceTopicId}:${item.assetRef ?? "-"}`;
  }
  if (entryClass === "measurement_or_test_request") {
    return `verify:${item.assuranceTopicId ?? item.moduleId}:${
      item.assetRef ?? "-"
    }`;
  }
  return `observed:${item.mechanismCode ?? item.moduleId}:${item.assetFamily}:${
    item.assetRef ?? "-"
  }`;
}

export function clusterItems(
  entries: Array<{ item: BookSourceItem; entryClass: BookEntryClass }>,
): ApprovedBookCluster[] {
  const byKey = new Map<string, ApprovedBookCluster>();

  for (const { item, entryClass } of entries) {
    const key = clusterKey(item, entryClass);
    const existing = byKey.get(key);
    if (!existing) {
      byKey.set(key, {
        clusterId: key,
        entryClass,
        urgency: urgencyFor(entryClass, item.criticality),
        criticality: item.criticality,
        moduleId: item.moduleId,
        mechanismCode: item.mechanismCode,
        assuranceTopicId: item.assuranceTopicId,
        assetFamily: item.assetFamily,
        barrierComponentsAbsent: [...item.barrierComponentsAbsent],
        peopleVisible: item.peopleVisible,
        sourceItemIds: [item.sourceItemId],
        photoIndices: [...item.photoIndices],
        priority: 0,
      });
      continue;
    }

    // The strongest member sets the class, the criticality and therefore the
    // language. A cluster that contains one fatal layer is a fatal entry.
    if (ENTRY_CLASS_RANK[entryClass] > ENTRY_CLASS_RANK[existing.entryClass]) {
      existing.entryClass = entryClass;
    }
    if (
      CRITICALITY_RANK[item.criticality] >
        CRITICALITY_RANK[existing.criticality]
    ) {
      existing.criticality = item.criticality;
    }
    existing.urgency = urgencyFor(existing.entryClass, existing.criticality);
    existing.peopleVisible = Math.max(
      existing.peopleVisible,
      item.peopleVisible,
    );
    existing.barrierComponentsAbsent = [
      ...new Set([
        ...existing.barrierComponentsAbsent,
        ...item.barrierComponentsAbsent,
      ]),
    ].sort();
    existing.sourceItemIds = [
      ...new Set([...existing.sourceItemIds, item.sourceItemId]),
    ].sort();
    existing.photoIndices = [
      ...new Set([...existing.photoIndices, ...item.photoIndices]),
    ].sort((left, right) => left - right);
  }

  const clusters = [...byKey.values()];
  for (const cluster of clusters) {
    cluster.priority = ENTRY_CLASS_RANK[cluster.entryClass] * 10 +
      CRITICALITY_RANK[cluster.criticality];
  }
  // Most urgent first; the key breaks ties so the order never depends on the
  // Turkish alphabet or on insertion order.
  return clusters.sort((left, right) =>
    right.priority - left.priority ||
    left.clusterId.localeCompare(right.clusterId, "en")
  );
}
