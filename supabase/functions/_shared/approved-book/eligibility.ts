// Which source items may become a book paragraph at all.
//
// The writability matrix from the plan, expressed as code. Two ideas run
// through it:
//
//   An absence claim is only writable when the engine could actually see the
//   place the thing should have been. Evidence tier and localisation
//   confidence are the engine's own record of that, so they gate here rather
//   than being re-argued in prose.
//
//   A verification request is writable only when it names something concrete to
//   verify. "Bu modül sahada kontrol edilmeli" is not a book entry, and the
//   adapter already drops those by refusing items with no canonical codes.

import type { BookEntryClass, BookSourceItem } from "./contracts.ts";

export type Eligibility =
  | { eligible: true; entryClass: BookEntryClass }
  | { eligible: false; reason: string };

/** Mean of the three confidence axes the analysis engine records. */
function meanConfidence(item: BookSourceItem): number {
  const { visibility, localization, mechanism } = item.confidence;
  return (visibility + localization + mechanism) / 3;
}

const STRONG_TIERS = new Set(["E3", "E4", "E5"]);

/**
 * A fatal or permanent hazard with a person in the frame and a reachable event
 * path. This is the class the plan puts behind a separate approval, because the
 * wording it unlocks ("çalışma durdurulmalı", "derhal") is the wording an
 * employer acts on within the hour.
 */
function isCriticalImmediate(item: BookSourceItem): boolean {
  if (item.itemClass !== "observed_finding") return false;
  if (item.criticality !== "fatal" && item.criticality !== "permanent") {
    return false;
  }
  return item.accessibleEventPath && item.peopleVisible > 0;
}

export function classify(item: BookSourceItem): Eligibility {
  if (item.itemClass === "observed_finding") {
    if (!STRONG_TIERS.has(item.evidenceTier)) {
      return { eligible: false, reason: `evidence_tier:${item.evidenceTier}` };
    }
    // A claim the engine localised poorly cannot carry a location sentence, and
    // a book entry without a location is not actionable.
    if (item.confidence.localization < 0.5) {
      return { eligible: false, reason: "localization_confidence_low" };
    }
    if (meanConfidence(item) < 0.5) {
      return { eligible: false, reason: "mean_confidence_low" };
    }
    return {
      eligible: true,
      entryClass: isCriticalImmediate(item)
        ? "critical_immediate"
        : "observed_corrective",
    };
  }

  if (item.itemClass === "assurance_requirement") {
    if (!item.assuranceTopicId) {
      return { eligible: false, reason: "no_assurance_topic" };
    }
    // The asset has to be identified well enough to name in a record.
    if (item.confidence.visibility < 0.5) {
      return { eligible: false, reason: "asset_identity_low" };
    }
    return { eligible: true, entryClass: "assurance_verification" };
  }

  // verification_request
  if (!item.assetRef && !item.assuranceTopicId) {
    return { eligible: false, reason: "no_concrete_verification_target" };
  }
  return { eligible: true, entryClass: "measurement_or_test_request" };
}

export function eligibleItems(
  items: BookSourceItem[],
): Array<{ item: BookSourceItem; entryClass: BookEntryClass }> {
  const kept: Array<{ item: BookSourceItem; entryClass: BookEntryClass }> = [];
  for (const item of items) {
    const verdict = classify(item);
    if (verdict.eligible) kept.push({ item, entryClass: verdict.entryClass });
  }
  return kept;
}
