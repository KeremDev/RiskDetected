import {
  hazardClassFrom,
  TRAINING_CATALOG_VERSION,
  TRAINING_ENGINE_VERSION,
  type TrainingItemRow,
  trainingRecommendationsFor,
} from "./index.ts";

export type TrainingCardSnapshot = {
  id: string;
  catalog_code: string;
  recommendation_class: string;
  applicability: string;
  group_code: string;
  title: string;
  category_label: string;
  audience_label: string;
  text: string;
  recommendation_text: string;
  duration_label: string | null;
  duration_value: string | null;
  duration_note: string | null;
  trigger_codes: string[];
  source_finding_ids: string[];
  display_order: number;
};

/** Stable per-analysis/card id shared by mobile reactions and the DB snapshot. */
export function trainingCardID(
  analysisID: string,
  catalogCode: string,
): string {
  let hash = 0x811c9dc5;
  for (const char of `${analysisID}|${catalogCode}`) {
    hash ^= char.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  const seed = hash.toString(16).padStart(8, "0");
  const body = `${seed}${analysisID.replace(/-/g, "").slice(0, 24)}`.slice(
    0,
    32,
  ).padEnd(32, "0");
  return `${body.slice(0, 8)}-${body.slice(8, 12)}-5${body.slice(13, 16)}-a${
    body.slice(17, 20)
  }-${body.slice(20, 32)}`;
}

export function buildTrainingCardSnapshots(params: {
  analysisID: string;
  sectorID: string | null;
  hazardClass: unknown;
  rows: TrainingItemRow[];
}): TrainingCardSnapshot[] {
  return trainingRecommendationsFor({
    sectorId: params.sectorID,
    hazardClass: hazardClassFrom(params.hazardClass),
    rows: params.rows,
  }).map((card) => ({
    id: trainingCardID(params.analysisID, card.catalogCode),
    catalog_code: card.catalogCode,
    recommendation_class: card.recommendationClass,
    applicability: card.applicability,
    group_code: card.groupCode,
    title: card.title,
    category_label: card.categoryLabel,
    audience_label: card.audienceLabel,
    text: card.text,
    recommendation_text: card.text,
    duration_label: card.duration?.label ?? null,
    duration_value: card.duration?.value ?? null,
    duration_note: card.duration?.note ?? null,
    trigger_codes: card.triggerCodes,
    source_finding_ids: card.sourceItemIds,
    display_order: card.displayOrder,
  }));
}

// deno-lint-ignore no-explicit-any
export async function persistTrainingCardSnapshots(
  supabase: any,
  params: {
    userID: string;
    analysisID: string;
    cards: TrainingCardSnapshot[];
  },
): Promise<void> {
  const { data, error } = await supabase.rpc(
    "result_hub_replace_training_cards_v1",
    {
      p_user_id: params.userID,
      p_analysis_id: params.analysisID,
      p_engine_version: TRAINING_ENGINE_VERSION,
      p_catalog_version: TRAINING_CATALOG_VERSION,
      p_cards: params.cards,
    },
  );
  if (error || data?.ok !== true) {
    throw new Error(
      `training_snapshot_write_failed:${
        String(error?.message ?? data?.state ?? "unknown")
      }`,
    );
  }
}

/**
 * Rebuilds the snapshot from the same canonical V4 metadata used by the mobile
 * result hub. Safe to call repeatedly; the database RPC replaces atomically.
 */
// deno-lint-ignore no-explicit-any
export async function refreshTrainingCardSnapshot(
  supabase: any,
  params: { userID: string; analysisID: string },
): Promise<TrainingCardSnapshot[]> {
  const { data: analysis, error: analysisError } = await supabase
    .from("analyses")
    .select("analysis_sector,companies(hazard_class)")
    .eq("id", params.analysisID)
    .eq("user_id", params.userID)
    .maybeSingle();
  if (analysisError || !analysis) {
    throw new Error(
      `training_snapshot_analysis_fetch_failed:${
        String(analysisError?.message ?? "not_found")
      }`,
    );
  }

  const { data: metadata, error: metadataError } = await supabase.rpc(
    "result_hub_v4_metadata",
    {
      p_user_id: params.userID,
      p_analysis_id: params.analysisID,
    },
  );
  if (metadataError) {
    throw new Error(
      `training_snapshot_metadata_fetch_failed:${metadataError.message}`,
    );
  }

  const company = analysis.companies && typeof analysis.companies === "object"
    ? analysis.companies as Record<string, unknown>
    : {};
  const cards = buildTrainingCardSnapshots({
    analysisID: params.analysisID,
    sectorID: typeof analysis.analysis_sector === "string"
      ? analysis.analysis_sector.trim() || null
      : null,
    hazardClass: company.hazard_class,
    rows: (Array.isArray(metadata) ? metadata : []) as TrainingItemRow[],
  });
  await persistTrainingCardSnapshots(supabase, { ...params, cards });
  return cards;
}
