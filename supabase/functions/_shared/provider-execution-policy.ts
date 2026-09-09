import type { AnalysisComputeProfile } from "./analysis-compute-profile.ts";

export type AnalysisProvider = "gemini" | "openai";

// Supabase's hosted request idle limit is 150 seconds. The outer queue worker
// must stop first so it can persist a deterministic retry instead of surfacing
// a platform-generated 504 response.
export const ANALYZE_NESTED_REQUEST_TIMEOUT_MS = 145_000;

const GEMINI_PRIMARY_TIMEOUT_MS = 50_000;
const GEMINI_RETRY_TIMEOUT_MS = 35_000;
const GEMINI_FALLBACK_TIMEOUT_MS = 65_000;
const GEMINI_TARGETED_TIMEOUT_MS = 30_000;

// Luna with image input and structured output can legitimately exceed the
// Gemini-tuned 50 second budget. A single 95 second request is cheaper and
// safer than aborting it and immediately duplicating the same generation.
const OPENAI_PRIMARY_TIMEOUT_MS = 95_000;
const OPENAI_FALLBACK_TIMEOUT_MS = 95_000;
const OPENAI_TARGETED_TIMEOUT_MS = 40_000;

// Background create/retrieve requests return only a response object and must
// stay short. The long-running Luna generation continues at OpenAI.
export const OPENAI_BACKGROUND_SUBMIT_TIMEOUT_MS = 20_000;
export const OPENAI_BACKGROUND_POLL_TIMEOUT_MS = 15_000;

export function shouldUseOpenAILunaBackground(params: {
  provider: AnalysisProvider;
  model: string;
  enabled: boolean;
}): boolean {
  return params.enabled && params.provider === "openai" &&
    params.model.trim().toLowerCase() === "gpt-5.6-luna";
}

export function primaryProviderTimeoutMs(provider: AnalysisProvider): number {
  return provider === "openai"
    ? OPENAI_PRIMARY_TIMEOUT_MS
    : GEMINI_PRIMARY_TIMEOUT_MS;
}

export function retryProviderTimeoutMs(provider: AnalysisProvider): number {
  return provider === "openai"
    ? OPENAI_PRIMARY_TIMEOUT_MS
    : GEMINI_RETRY_TIMEOUT_MS;
}

export function fallbackProviderTimeoutMs(provider: AnalysisProvider): number {
  return provider === "openai"
    ? OPENAI_FALLBACK_TIMEOUT_MS
    : GEMINI_FALLBACK_TIMEOUT_MS;
}

export function targetedProviderTimeoutMs(provider: AnalysisProvider): number {
  return provider === "openai"
    ? OPENAI_TARGETED_TIMEOUT_MS
    : GEMINI_TARGETED_TIMEOUT_MS;
}

export function primaryProviderAttemptLimit(
  provider: AnalysisProvider,
  _computeProfile: AnalysisComputeProfile,
): number {
  // Do not duplicate a long-running OpenAI generation in the same worker.
  // Durable queue retry remains available if the single request really fails.
  if (provider === "openai") return 1;
  // Both profiles have one bounded technical retry. Economy keeps its lower
  // retry thinking budget and service tier, so this does not promote it to a
  // premium generation.
  return 2;
}

export function maximumOpenAIHappyPathMs(): number {
  return OPENAI_PRIMARY_TIMEOUT_MS + OPENAI_TARGETED_TIMEOUT_MS;
}
