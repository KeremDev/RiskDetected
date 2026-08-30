import type {
  AnalysisComputeProfile,
  AnalysisProviderPool,
  AnalysisServiceTier,
} from "../_shared/analysis-compute-profile.ts";

export type VNextProviderName = "gemini" | "openai";
export type OpenAIReasoningEffort = "high" | "xhigh" | "max";
export type GeminiThinkingLevel = "MINIMAL" | "LOW" | "MEDIUM" | "HIGH";

const THINKING_LEVELS: GeminiThinkingLevel[] = [
  "MINIMAL",
  "LOW",
  "MEDIUM",
  "HIGH",
];

function thinkingLevel(value: unknown): GeminiThinkingLevel | null {
  const raw = String(value ?? "").trim().toUpperCase();
  return (THINKING_LEVELS as string[]).includes(raw)
    ? raw as GeminiThinkingLevel
    : null;
}

export type ResolvedVNextConfig = {
  primaryProvider: VNextProviderName;
  primaryModel: string;
  fallbackProvider: VNextProviderName;
  fallbackModel: string;
  geminiThinkingBudget: number;
  /**
   * Gemini 3 replaced the numeric budget with an enum, and sending both in
   * one request is a 400. The budget stays for 2.5; the provider picks
   * whichever the model understands.
   */
  geminiThinkingLevel: GeminiThinkingLevel;
  geminiRetryThinkingBudget: number;
  geminiTargetedThinkingBudget: number;
  geminiThinkingByPhotoEnabled: boolean;
  geminiThinkingPolicyVersion: string;
  verifiedPhotoCount: number | null;
  maxProviderOutputTokens: number;
  targetedMaxProviderOutputTokens: number;
  openAIReasoningEffort: OpenAIReasoningEffort;
  sectorProfileEnabled: boolean;
  sectorFrequencyPriorEnabled: boolean;
  sectorControlPreferencesEnabled: boolean;
  sectorNegativeRulesEnabled: boolean;
  sectorRegulationAnchorsEnabled: boolean;
  multiPhotoHighHazardCoverageEnabled: boolean;
  aiExecutionRoute: string;
  computeProfile: AnalysisComputeProfile;
  computeProfileVersion: string;
  providerPool: AnalysisProviderPool;
  requestedServiceTier: AnalysisServiceTier;
  fallbackServiceTier: "standard";
  economyStandardFallbackEnabled: boolean;
  compactProviderContractEnabled: boolean;
  openAILunaBackgroundEnabled: boolean;
  openAILunaBackgroundVersion: string;
  openAILunaBackgroundPollSeconds: number;
  providerExperimentID: string | null;
  providerExperimentLabel: string | null;
  providerExperimentOneShot: boolean;
  contextualFallBarrierAliasEnabled: boolean;
  personBarrierEquivalentMergeEnabled: boolean;
  providerAttemptBudgetTraceEnabled: boolean;
  promptBundleIntegrityEnabled: boolean;
};

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  const selected = Number.isFinite(parsed) ? Math.round(parsed) : fallback;
  return Math.max(minimum, Math.min(maximum, selected));
}

function provider(
  value: unknown,
  fallback: VNextProviderName,
): VNextProviderName {
  return value === "openai"
    ? "openai"
    : value === "gemini"
    ? "gemini"
    : fallback;
}

export function resolveVNextConfig(
  snapshotValue: unknown,
  verifiedPhotoCountValue?: number,
): ResolvedVNextConfig {
  const snapshot = record(snapshotValue);
  const engineConfig = record(snapshot.engine_config);
  const routing = record(snapshot.compute_routing);
  const routingEnabled = engineConfig.compute_profile_routing_enabled === true;
  const requestedProfile = routing.compute_profile === "economy"
    ? "economy"
    : "premium";
  const computeProfile: AnalysisComputeProfile = routingEnabled
    ? requestedProfile
    : "premium";
  const profiles = record(engineConfig.compute_profiles);
  const selectedProfile = record(profiles[computeProfile]);
  const premiumOptimizationEnabled =
    engineConfig.premium_thinking_optimization_enabled === true;
  const useSelectedProfile = computeProfile === "economy" ||
    premiumOptimizationEnabled;
  const selected = useSelectedProfile ? selectedProfile : engineConfig;
  const normalizedPhotoCount = Number(verifiedPhotoCountValue);
  const verifiedPhotoCount = Number.isInteger(normalizedPhotoCount) &&
      normalizedPhotoCount >= 1 && normalizedPhotoCount <= 3
    ? normalizedPhotoCount
    : null;
  const geminiThinkingByPhotoEnabled =
    engineConfig.gemini_thinking_by_photo_enabled === true;
  const geminiThinkingPolicyVersion = geminiThinkingByPhotoEnabled
    ? String(
      engineConfig.gemini_thinking_policy_version ??
        "gemini-thinking-by-photo-v1",
    )
    : "legacy-profile-budget";

  const primaryProvider = provider(
    selected.primary_provider,
    provider(engineConfig.primary_provider, "gemini"),
  );
  const primaryModel = String(
    selected.primary_model ?? engineConfig.primary_model ??
      (primaryProvider === "gemini" ? "gemini-2.5-flash" : "gpt-5.6-luna"),
  );
  let fallbackProvider = provider(
    selected.fallback_provider,
    provider(engineConfig.fallback_provider, "openai"),
  );
  let fallbackModel = String(
    selected.fallback_model ?? engineConfig.fallback_model ??
      (fallbackProvider === "gemini" ? "gemini-2.5-flash" : "gpt-5.6-luna"),
  );
  if (computeProfile === "economy") {
    // Economy never crosses into a more expensive/different model. Its one
    // continuity fallback changes only Flex -> Standard service tier.
    fallbackProvider = primaryProvider;
    fallbackModel = primaryModel;
  }

  const profileThinking = boundedInteger(
    selected.gemini_thinking_budget,
    computeProfile === "economy" && geminiThinkingByPhotoEnabled
      ? 1_024
      : computeProfile === "economy"
      ? 512
      : 3_072,
    0,
    24_576,
  );
  const thinking = geminiThinkingByPhotoEnabled &&
      computeProfile === "premium" && verifiedPhotoCount !== null
    ? boundedInteger(
      verifiedPhotoCount === 1
        ? selected.single_photo_gemini_thinking_budget
        : selected.multi_photo_gemini_thinking_budget,
      profileThinking,
      0,
      24_576,
    )
    : profileThinking;
  const retryThinking = Math.min(
    thinking,
    boundedInteger(
      selected.technical_retry_gemini_thinking_budget,
      computeProfile === "economy" ? 256 : 2_048,
      0,
      24_576,
    ),
  );
  const targetedThinking = Math.min(
    thinking,
    boundedInteger(
      selected.targeted_gemini_thinking_budget,
      computeProfile === "economy" ? 256 : 1_024,
      0,
      24_576,
    ),
  );
  // MEDIUM rather than HIGH on purpose. Raising the 2.5 budget from 3072 to
  // 6144 bought nothing on this workload and was reverted, and the defects
  // this engine keeps producing are perceptual -- a twelve-pixel hook latch
  // -- which no amount of reasoning resolves. Media resolution is the lever
  // for those. MEDIUM also keeps the model switch a single variable.
  const geminiThinkingLevel = thinkingLevel(selected.gemini_thinking_level) ??
    thinkingLevel(engineConfig.gemini_thinking_level) ??
    (computeProfile === "economy" ? "LOW" : "MEDIUM");

  const maxProviderOutputTokens = boundedInteger(
    selected.max_provider_output_tokens,
    computeProfile === "economy" ? 6_144 : 12_288,
    4_096,
    20_480,
  );
  const targetedMaxProviderOutputTokens = Math.min(
    maxProviderOutputTokens,
    boundedInteger(
      selected.targeted_max_provider_output_tokens,
      computeProfile === "economy" ? 2_048 : 4_096,
      1_024,
      20_480,
    ),
  );
  const effort = ["high", "xhigh", "max"].includes(
      String(selected.openai_reasoning_effort),
    )
    ? String(selected.openai_reasoning_effort) as OpenAIReasoningEffort
    : "high";
  const flexEnabled = engineConfig.paid_flex_enabled === true;
  const requestedServiceTier: AnalysisServiceTier = computeProfile ===
        "economy" && flexEnabled && primaryProvider === "gemini"
    ? "flex"
    : "standard";
  const providerPool: AnalysisProviderPool = requestedServiceTier === "flex"
    ? "paid_flex"
    : "paid_standard";

  return {
    primaryProvider,
    primaryModel,
    fallbackProvider,
    fallbackModel,
    geminiThinkingBudget: thinking,
    geminiThinkingLevel,
    geminiRetryThinkingBudget: retryThinking,
    geminiTargetedThinkingBudget: targetedThinking,
    geminiThinkingByPhotoEnabled,
    geminiThinkingPolicyVersion,
    verifiedPhotoCount,
    maxProviderOutputTokens,
    targetedMaxProviderOutputTokens,
    openAIReasoningEffort: effort,
    sectorProfileEnabled: engineConfig.sector_profile_enabled === true,
    sectorFrequencyPriorEnabled:
      engineConfig.sector_frequency_prior_enabled === true,
    sectorControlPreferencesEnabled:
      engineConfig.sector_control_preferences_enabled === true,
    sectorNegativeRulesEnabled:
      engineConfig.sector_negative_rules_enabled === true,
    sectorRegulationAnchorsEnabled:
      engineConfig.sector_regulation_anchors_enabled === true,
    multiPhotoHighHazardCoverageEnabled:
      typeof engineConfig.high_hazard_critical_coverage_enabled === "boolean"
        ? engineConfig.high_hazard_critical_coverage_enabled === true
        : engineConfig.multi_photo_high_hazard_critical_coverage_enabled ===
          true,
    aiExecutionRoute: String(
      routing.ai_execution_route ?? "compute_route_snapshot_missing",
    ),
    computeProfile,
    computeProfileVersion: String(
      routing.compute_profile_version ?? "compute-profile-v1",
    ),
    providerPool,
    requestedServiceTier,
    fallbackServiceTier: "standard",
    economyStandardFallbackEnabled:
      engineConfig.economy_standard_fallback_enabled === true,
    compactProviderContractEnabled:
      engineConfig.compact_provider_contract_enabled === true,
    openAILunaBackgroundEnabled:
      engineConfig.openai_luna_background_enabled === true,
    openAILunaBackgroundVersion: String(
      engineConfig.openai_luna_background_version ??
        "openai-luna-background-disabled",
    ),
    openAILunaBackgroundPollSeconds: boundedInteger(
      engineConfig.openai_luna_background_poll_seconds,
      15,
      5,
      120,
    ),
    providerExperimentID: typeof routing.provider_experiment_id === "string"
      ? routing.provider_experiment_id
      : null,
    providerExperimentLabel:
      typeof routing.provider_experiment_label === "string"
        ? routing.provider_experiment_label
        : null,
    providerExperimentOneShot: routing.provider_experiment_one_shot === true,
    contextualFallBarrierAliasEnabled:
      engineConfig.contextual_fall_barrier_alias_enabled === true,
    personBarrierEquivalentMergeEnabled:
      engineConfig.person_barrier_equivalent_merge_enabled === true,
    providerAttemptBudgetTraceEnabled:
      engineConfig.provider_attempt_budget_trace_enabled === true,
    promptBundleIntegrityEnabled:
      engineConfig.prompt_bundle_integrity_enabled === true,
  };
}
