import { firstSentenceTeaser } from "./approved-notebook-projector.ts";

export const ANALYSIS_RESULT_CONTRACT_VERSION = "analysis-result-sections-v1";
export const ANALYSIS_RESULT_UI_VERSION = "analysis-result-hub-v1";

export type ResultHubTier = "free" | "plus" | "pro";
export type ResultHubSection =
  | "risk_analysis"
  | "expert_recommendations"
  | "approved_notebook";

export const RESULT_HUB_SECTIONS: ResultHubSection[] = [
  "risk_analysis",
  "expert_recommendations",
  "approved_notebook",
];

export function isPaidTier(tier: ResultHubTier): boolean {
  return tier === "plus" || tier === "pro";
}

export function resolveResultHubTier(
  subscription: {
    tier?: string | null;
    status?: string | null;
    current_period_ends_at?: string | null;
  } | null,
): ResultHubTier {
  if (!subscription) return "free";
  const status = String(subscription.status ?? "").toLowerCase();
  if (!["active", "trialing", "grace_period"].includes(status)) return "free";
  const hasExpiry = Boolean(subscription.current_period_ends_at);
  const expiry = hasExpiry
    ? Date.parse(subscription.current_period_ends_at as string)
    : null;
  if (
    hasExpiry && (!Number.isFinite(expiry) || (expiry as number) <= Date.now())
  ) {
    return "free";
  }
  return subscription.tier === "pro"
    ? "pro"
    : subscription.tier === "plus"
    ? "plus"
    : "free";
}

export function resultHubGateOpen(params: {
  flag: Record<string, unknown> | null;
  allowlisted: boolean;
  capability: boolean;
  platform: string;
  build: string;
}): boolean {
  const flag = params.flag;
  if (!flag || flag.kill_switch === true || params.capability !== true) {
    return false;
  }
  const mode = String(flag.rollout_mode ?? "off").toLowerCase();
  if (mode === "all") return true;
  if (mode === "user_allowlist") return params.allowlisted;
  const buildNumber = Number.parseInt(params.build, 10);
  if (mode === "min_build" && Number.isFinite(buildNumber)) {
    const minimum = Number(
      params.platform === "android"
        ? flag.min_android_build
        : flag.min_ios_build,
    );
    return Number.isFinite(minimum) && buildNumber >= minimum;
  }
  if (mode === "build_allowlist") {
    const raw = params.platform === "android"
      ? flag.enabled_android_builds
      : flag.enabled_ios_builds;
    return Array.isArray(raw) && raw.map(String).includes(params.build);
  }
  return false;
}

export function safeObject(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export function findingSection(row: Record<string, unknown>): ResultHubSection {
  return row.is_scored === false ||
      ["assurance_requirement", "verification_request"].includes(
        String(row.item_class ?? ""),
      )
    ? "expert_recommendations"
    : "risk_analysis";
}

export function redactFindingForFree(
  row: Record<string, unknown>,
): Record<string, unknown> {
  return {
    id: row.id,
    analysis_id: row.analysis_id,
    item_class: row.item_class,
    is_scored: false,
    title: String(row.title ?? "").slice(0, 240),
    description: firstSentenceTeaser(row.description, 160),
    source_photo_indices: row.source_photo_indices ?? [],
    display_order: row.display_order,
    needs_field_verification: true,
    locked: true,
    recommended_action: null,
    recommended_measures: null,
    root_cause_text: null,
    references_text: null,
    fk_probability: null,
    fk_frequency: null,
    fk_severity: null,
    fk_score: null,
    fk_band: "unknown",
    m5_probability: null,
    m5_severity: null,
    m5_score: null,
    m5_band: "unknown",
  };
}

export function redactNotebookForFree(
  row: Record<string, unknown>,
): Record<string, unknown> {
  return {
    id: row.id,
    source_finding_ids: row.source_finding_ids ?? [],
    finding_text: firstSentenceTeaser(row.finding_text, 160),
    recommendation_text: null,
    reference_text: null,
    display_order: row.display_order,
    is_user_edited: false,
    is_stale: false,
    is_suppressed: false,
    locked: true,
  };
}

export function sectionAccess(
  section: ResultHubSection,
  tier: ResultHubTier,
): "full" | "teaser" {
  return section === "risk_analysis" || isPaidTier(tier) ? "full" : "teaser";
}
