import {
  assertEquals,
  assertLess,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  ANALYZE_NESTED_REQUEST_TIMEOUT_MS,
  fallbackProviderTimeoutMs,
  maximumOpenAIHappyPathMs,
  OPENAI_BACKGROUND_POLL_TIMEOUT_MS,
  OPENAI_BACKGROUND_SUBMIT_TIMEOUT_MS,
  primaryProviderAttemptLimit,
  primaryProviderTimeoutMs,
  shouldUseOpenAILunaBackground,
  targetedProviderTimeoutMs,
} from "./provider-execution-policy.ts";

Deno.test("Luna receives one long primary request instead of a duplicate retry", () => {
  assertEquals(primaryProviderTimeoutMs("openai"), 95_000);
  assertEquals(primaryProviderAttemptLimit("openai", "premium"), 1);
  assertEquals(primaryProviderAttemptLimit("openai", "economy"), 1);
  assertEquals(fallbackProviderTimeoutMs("openai"), 95_000);
});

Deno.test("Gemini premium and economy retain one bounded technical retry", () => {
  assertEquals(primaryProviderTimeoutMs("gemini"), 50_000);
  assertEquals(primaryProviderAttemptLimit("gemini", "premium"), 2);
  assertEquals(primaryProviderAttemptLimit("gemini", "economy"), 2);
  assertEquals(targetedProviderTimeoutMs("gemini"), 30_000);
});

Deno.test("Luna happy path stays below Supabase request idle timeout", () => {
  assertEquals(targetedProviderTimeoutMs("openai"), 40_000);
  assertLess(maximumOpenAIHappyPathMs(), ANALYZE_NESTED_REQUEST_TIMEOUT_MS);
  assertLess(ANALYZE_NESTED_REQUEST_TIMEOUT_MS, 150_000);
});

Deno.test("background transport is isolated to explicitly enabled Luna", () => {
  assertEquals(
    shouldUseOpenAILunaBackground({
      provider: "openai",
      model: "gpt-5.6-luna",
      enabled: true,
    }),
    true,
  );
  for (
    const candidate of [
      { provider: "gemini" as const, model: "gemini-2.5-flash", enabled: true },
      { provider: "openai" as const, model: "gpt-5.6-sol", enabled: true },
      { provider: "openai" as const, model: "gpt-5.6-luna", enabled: false },
    ]
  ) {
    assertEquals(shouldUseOpenAILunaBackground(candidate), false);
  }
  assertLess(OPENAI_BACKGROUND_SUBMIT_TIMEOUT_MS, 30_000);
  assertLess(OPENAI_BACKGROUND_POLL_TIMEOUT_MS, 30_000);
});
