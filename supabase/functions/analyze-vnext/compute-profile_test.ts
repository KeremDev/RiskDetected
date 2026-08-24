import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  type AIExecutionRoute,
  computeProfileForAIExecutionRoute,
} from "../_shared/analysis-compute-profile.ts";
import { resolveVNextConfig } from "./compute-profile.ts";

const engineConfig = {
  primary_provider: "gemini",
  primary_model: "gemini-2.5-flash",
  fallback_provider: "openai",
  fallback_model: "gpt-5.6-luna",
  gemini_thinking_budget: 3072,
  technical_retry_gemini_thinking_budget: 2048,
  targeted_gemini_thinking_budget: 1024,
  max_provider_output_tokens: 12288,
  targeted_max_provider_output_tokens: 4096,
  compute_profile_routing_enabled: true,
  paid_flex_enabled: true,
  premium_thinking_optimization_enabled: true,
  gemini_thinking_by_photo_enabled: true,
  gemini_thinking_policy_version: "gemini-thinking-by-photo-v1",
  compact_provider_contract_enabled: true,
  openai_luna_background_enabled: true,
  openai_luna_background_version: "openai-luna-background-v1",
  openai_luna_background_poll_seconds: 15,
  economy_standard_fallback_enabled: true,
  multi_photo_high_hazard_critical_coverage_enabled: true,
  compute_profiles: {
    premium: {
      primary_provider: "gemini",
      primary_model: "gemini-2.5-flash",
      fallback_provider: "openai",
      fallback_model: "gpt-5.6-luna",
      gemini_thinking_budget: 2048,
      single_photo_gemini_thinking_budget: 3072,
      multi_photo_gemini_thinking_budget: 2048,
      technical_retry_gemini_thinking_budget: 1536,
      targeted_gemini_thinking_budget: 768,
      max_provider_output_tokens: 8192,
      targeted_max_provider_output_tokens: 3072,
    },
    economy: {
      primary_provider: "gemini",
      primary_model: "gemini-2.5-flash",
      fallback_provider: "gemini",
      fallback_model: "gemini-2.5-flash",
      gemini_thinking_budget: 1024,
      single_photo_gemini_thinking_budget: 1024,
      multi_photo_gemini_thinking_budget: 1024,
      technical_retry_gemini_thinking_budget: 256,
      targeted_gemini_thinking_budget: 256,
      max_provider_output_tokens: 6144,
      targeted_max_provider_output_tokens: 2048,
    },
  },
};

Deno.test("premium single-photo profile uses 3072 with controlled secondary budgets", () => {
  const config = resolveVNextConfig({
    engine_config: engineConfig,
    compute_routing: {
      ai_execution_route: "free_paid_trial",
      compute_profile: "premium",
      compute_profile_version: "compute-profile-v1",
    },
  }, 1);
  assertEquals(config.computeProfile, "premium");
  assertEquals(config.requestedServiceTier, "standard");
  assertEquals(config.geminiThinkingBudget, 3072);
  assertEquals(config.geminiRetryThinkingBudget, 1536);
  assertEquals(config.geminiTargetedThinkingBudget, 768);
  assertEquals(config.geminiThinkingByPhotoEnabled, true);
  assertEquals(
    config.geminiThinkingPolicyVersion,
    "gemini-thinking-by-photo-v1",
  );
  assertEquals(config.verifiedPhotoCount, 1);
  assertEquals(config.targetedMaxProviderOutputTokens, 3072);
  assertEquals(config.openAILunaBackgroundEnabled, true);
  assertEquals(config.openAILunaBackgroundVersion, "openai-luna-background-v1");
  assertEquals(config.multiPhotoHighHazardCoverageEnabled, true);
  assertEquals(config.openAILunaBackgroundPollSeconds, 15);
});

Deno.test("all-photo high-hazard coverage flag overrides the legacy multi-photo flag", () => {
  const config = resolveVNextConfig({
    engine_config: {
      ...engineConfig,
      high_hazard_critical_coverage_enabled: false,
      multi_photo_high_hazard_critical_coverage_enabled: true,
    },
    compute_routing: {
      ai_execution_route: "paid_plan",
      compute_profile: "premium",
      compute_profile_version: "compute-profile-v1",
    },
  }, 1);
  assertEquals(config.multiPhotoHighHazardCoverageEnabled, false);
});

Deno.test("premium two- and three-photo profiles use 2048", () => {
  for (const photoCount of [2, 3]) {
    const config = resolveVNextConfig({
      engine_config: engineConfig,
      compute_routing: {
        ai_execution_route: "paid_plan",
        compute_profile: "premium",
        compute_profile_version: "compute-profile-v1",
      },
    }, photoCount);
    assertEquals(config.computeProfile, "premium");
    assertEquals(config.geminiThinkingBudget, 2048);
    assertEquals(config.geminiRetryThinkingBudget, 1536);
    assertEquals(config.geminiTargetedThinkingBudget, 768);
    assertEquals(config.verifiedPhotoCount, photoCount);
  }
});

Deno.test("economy profile always uses 1024, Flex and never selects Luna", () => {
  for (const photoCount of [1, 2, 3]) {
    const config = resolveVNextConfig({
      engine_config: engineConfig,
      compute_routing: {
        ai_execution_route: "cancelled_plus_trial_free",
        compute_profile: "economy",
        compute_profile_version: "compute-profile-v1",
      },
    }, photoCount);
    assertEquals(config.computeProfile, "economy");
    assertEquals(config.primaryModel, "gemini-2.5-flash");
    assertEquals(config.fallbackProvider, "gemini");
    assertEquals(config.fallbackModel, "gemini-2.5-flash");
    assertEquals(config.requestedServiceTier, "flex");
    assertEquals(config.providerPool, "paid_flex");
    assertEquals(config.geminiThinkingBudget, 1024);
    assertEquals(config.geminiRetryThinkingBudget, 256);
    assertEquals(config.geminiTargetedThinkingBudget, 256);
    assertEquals(config.maxProviderOutputTokens, 6144);
  }
});

Deno.test("subscription route matrix selects the requested primary budget", () => {
  const cases = [
    { label: "free_first", route: "free_paid_trial", photos: 1, budget: 3072 },
    { label: "free_second", route: "free_legacy", photos: 1, budget: 1024 },
    { label: "plus_single", route: "paid_plan", photos: 1, budget: 3072 },
    { label: "plus_double", route: "paid_plan", photos: 2, budget: 2048 },
    { label: "plus_triple", route: "paid_plan", photos: 3, budget: 2048 },
    { label: "pro_single", route: "paid_plan", photos: 1, budget: 3072 },
    { label: "pro_double", route: "paid_plan", photos: 2, budget: 2048 },
    { label: "pro_triple", route: "paid_plan", photos: 3, budget: 2048 },
    {
      label: "active_trial_single",
      route: "paid_plan",
      photos: 1,
      budget: 3072,
    },
    {
      label: "active_trial_double",
      route: "paid_plan",
      photos: 2,
      budget: 2048,
    },
    {
      label: "active_trial_triple",
      route: "paid_plan",
      photos: 3,
      budget: 2048,
    },
    {
      label: "cancelled_trial_single",
      route: "cancelled_plus_trial_free",
      photos: 1,
      budget: 1024,
    },
    {
      label: "cancelled_trial_double",
      route: "cancelled_plus_trial_free",
      photos: 2,
      budget: 1024,
    },
    {
      label: "cancelled_trial_triple",
      route: "cancelled_plus_trial_free",
      photos: 3,
      budget: 1024,
    },
  ] satisfies Array<{
    label: string;
    route: AIExecutionRoute;
    photos: number;
    budget: number;
  }>;
  for (const testCase of cases) {
    const profile = computeProfileForAIExecutionRoute(testCase.route);
    const config = resolveVNextConfig({
      engine_config: engineConfig,
      compute_routing: {
        ai_execution_route: testCase.route,
        compute_profile: profile,
        compute_profile_version: "compute-profile-v1",
      },
    }, testCase.photos);
    assertEquals(config.geminiThinkingBudget, testCase.budget);
    assertEquals(
      config.geminiRetryThinkingBudget,
      profile === "premium" ? 1536 : 256,
      `${testCase.label}: retry budget`,
    );
    assertEquals(
      config.geminiTargetedThinkingBudget,
      profile === "premium" ? 768 : 256,
      `${testCase.label}: targeted budget`,
    );
    assertEquals(
      config.requestedServiceTier,
      profile === "premium" ? "standard" : "flex",
      `${testCase.label}: service tier`,
    );
  }
});

Deno.test("disabled photo policy preserves pinned legacy profile budgets", () => {
  const disabled = {
    ...engineConfig,
    gemini_thinking_by_photo_enabled: false,
    compute_profiles: {
      ...engineConfig.compute_profiles,
      economy: {
        ...engineConfig.compute_profiles.economy,
        gemini_thinking_budget: 512,
      },
    },
  };
  const premium = resolveVNextConfig({
    engine_config: disabled,
    compute_routing: { compute_profile: "premium" },
  }, 1);
  const economy = resolveVNextConfig({
    engine_config: disabled,
    compute_routing: { compute_profile: "economy" },
  }, 3);
  assertEquals(premium.geminiThinkingBudget, 2048);
  assertEquals(economy.geminiThinkingBudget, 512);
  assertEquals(premium.geminiThinkingPolicyVersion, "legacy-profile-budget");
});

Deno.test("missing verified photo count falls back to the pinned profile budget", () => {
  const config = resolveVNextConfig({
    engine_config: engineConfig,
    compute_routing: { compute_profile: "premium" },
  });
  assertEquals(config.geminiThinkingBudget, 2048);
  assertEquals(config.verifiedPhotoCount, null);
});

Deno.test("missing trusted route fails safe to premium Standard", () => {
  const config = resolveVNextConfig({ engine_config: engineConfig });
  assertEquals(config.computeProfile, "premium");
  assertEquals(config.requestedServiceTier, "standard");
});

Deno.test("one-shot Luna experiment is pinned by the trusted route snapshot", () => {
  const lunaProfile = {
    ...engineConfig,
    compute_profiles: {
      ...engineConfig.compute_profiles,
      premium: {
        ...engineConfig.compute_profiles.premium,
        primary_provider: "openai",
        primary_model: "gpt-5.6-luna",
        fallback_provider: "openai",
        fallback_model: "gpt-5.6-luna",
        openai_reasoning_effort: "high",
      },
    },
  };
  const config = resolveVNextConfig({
    engine_config: lunaProfile,
    compute_routing: {
      ai_execution_route: "paid_plan",
      compute_profile: "premium",
      compute_profile_version: "compute-profile-v1",
      provider_experiment_id: "experiment-id",
      provider_experiment_label: "luna-quality-cost-a-b-v1",
      provider_experiment_one_shot: true,
    },
  });
  assertEquals(config.primaryProvider, "openai");
  assertEquals(config.primaryModel, "gpt-5.6-luna");
  assertEquals(config.fallbackProvider, "openai");
  assertEquals(config.fallbackModel, "gpt-5.6-luna");
  assertEquals(config.openAIReasoningEffort, "high");
  assertEquals(config.providerExperimentID, "experiment-id");
  assertEquals(config.providerExperimentLabel, "luna-quality-cost-a-b-v1");
  assertEquals(config.providerExperimentOneShot, true);
  assertEquals(config.openAILunaBackgroundEnabled, true);
});

Deno.test("Luna background flag fails closed when absent", () => {
  const config = resolveVNextConfig({
    engine_config: {
      ...engineConfig,
      openai_luna_background_enabled: undefined,
    },
  });
  assertEquals(config.openAILunaBackgroundEnabled, false);
});
