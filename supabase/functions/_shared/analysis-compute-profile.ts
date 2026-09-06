import { CANCELLED_PLUS_TRIAL_ROUTE } from "./cancelled-plus-trial-routing.ts";

export const ANALYSIS_COMPUTE_PROFILE_VERSION = "compute-profile-v1";

export type AIExecutionRoute =
  | "free_legacy"
  | "free_paid_trial"
  | "paid_plan"
  | typeof CANCELLED_PLUS_TRIAL_ROUTE;

export type AnalysisComputeProfile = "premium" | "economy";
export type AnalysisProviderPool = "paid_standard" | "paid_flex" | "free_standard";
export type AnalysisServiceTier = "standard" | "flex";

export type TrustedAnalysisComputeRouting = {
  snapshot_version: 1;
  ai_execution_route: AIExecutionRoute;
  compute_profile: AnalysisComputeProfile;
  compute_profile_version: typeof ANALYSIS_COMPUTE_PROFILE_VERSION;
  provider_pool: AnalysisProviderPool;
  requested_service_tier: AnalysisServiceTier;
  first_paid_ai_eligible: boolean;
  cancelled_plus_trial_free_candidate: boolean;
  cancelled_plus_trial_free_enabled: boolean;
  cancelled_plus_trial_routing_mode: string;
  cancelled_plus_trial_routing_reason: string;
  source: "trusted_analyze_enqueue";
};

export function computeProfileForAIExecutionRoute(
  route: AIExecutionRoute,
): AnalysisComputeProfile {
  return route === "free_legacy" || route === CANCELLED_PLUS_TRIAL_ROUTE
    ? "economy"
    : "premium";
}

export function buildTrustedAnalysisComputeRouting(params: {
  route: AIExecutionRoute;
  firstPaidAIEligible: boolean;
  cancelledTrial: {
    eligible: boolean;
    enabled: boolean;
    mode: string;
    reason: string;
  };
}): TrustedAnalysisComputeRouting {
  const computeProfile = computeProfileForAIExecutionRoute(params.route);
  return {
    snapshot_version: 1,
    ai_execution_route: params.route,
    compute_profile: computeProfile,
    compute_profile_version: ANALYSIS_COMPUTE_PROFILE_VERSION,
    provider_pool: computeProfile === "economy" ? "paid_flex" : "paid_standard",
    requested_service_tier: computeProfile === "economy" ? "flex" : "standard",
    first_paid_ai_eligible: params.firstPaidAIEligible,
    cancelled_plus_trial_free_candidate: params.cancelledTrial.eligible,
    cancelled_plus_trial_free_enabled: params.cancelledTrial.enabled,
    cancelled_plus_trial_routing_mode: params.cancelledTrial.mode,
    cancelled_plus_trial_routing_reason: params.cancelledTrial.reason,
    source: "trusted_analyze_enqueue",
  };
}
