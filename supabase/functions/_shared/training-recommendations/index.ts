// Training recommendations for one analysis.
//
// Reads the canonical codes the router already persists, matches them against
// the catalogue, and returns finished Turkish cards. No user input, no second
// model call, no approval step: the plan's first product decision is that these
// appear automatically in the same response as the analysis.

import type { TrainingRecommendation } from "./contracts.ts";
import {
  buildTrainingRecommendations,
  resolveContext,
  type TrainingSourceItem,
} from "./engine.ts";
import { lintTrainingText } from "./linter.ts";

export const TRAINING_ENGINE_VERSION = "training-recommendations-v1";
export const TRAINING_CATALOG_VERSION = "training-catalog-tr-v1";

export type TrainingItemRow = {
  public_finding_id?: string | null;
  internal_priority?: Record<string, unknown> | null;
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/**
 * Source items, from the same canonical block the approved-book engine reads.
 *
 * An item without `book_source` contributes nothing. That is correct rather
 * than lossy: those are positive controls and coverage records, and neither
 * says anything about what anyone needs to be taught.
 */
export function adaptTrainingItems(rows: TrainingItemRow[]): TrainingSourceItem[] {
  const items: TrainingSourceItem[] = [];
  for (const row of rows) {
    const book = record(record(row.internal_priority).book_source);
    if (text(book.schema) !== "book-source-v1") continue;
    const moduleId = text(book.module_id);
    if (!moduleId) continue;
    items.push({
      sourceItemId: text(row.public_finding_id),
      moduleId,
      mechanismCode: text(book.mechanism_code) || null,
      assuranceTopicId: text(book.assurance_topic_id) || null,
      assetRef: text(book.asset_ref) || null,
      barrierComponentsAbsent: Array.isArray(book.barrier_components_absent)
        ? book.barrier_components_absent.map(text).filter(Boolean)
        : [],
      peopleVisible: Math.max(0, Math.trunc(Number(book.people_visible) || 0)),
    });
  }
  return items;
}

export function trainingRecommendationsFor(params: {
  sectorId: string | null;
  rows: TrainingItemRow[];
}): TrainingRecommendation[] {
  const items = adaptTrainingItems(params.rows);
  // No canonical codes means a v3 analysis or one predating the router change.
  // An empty list is the honest answer; the section simply does not appear.
  if (items.length === 0) return [];

  const context = resolveContext({ sectorId: params.sectorId, items });
  const cards = buildTrainingRecommendations(context);

  // A card that trips the linter is dropped, not repaired. Every sentence here
  // comes from a hand-written template, so a hit means the template is wrong
  // and the right response is to stop shipping that sentence.
  return cards.filter((card) => lintTrainingText(card.text).length === 0);
}

export type { TrainingRecommendation, TrainingSourceItem };
export * from "./contracts.ts";
export { lintTrainingText } from "./linter.ts";
