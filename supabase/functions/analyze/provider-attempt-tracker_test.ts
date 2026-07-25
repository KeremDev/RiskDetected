import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { ProviderAttemptTracker } from "./provider-attempt-tracker.ts";

Deno.test("provider tracker counts physical requests and all token usage", () => {
  const tracker = new ProviderAttemptTracker();
  tracker.record({
    provider: "gemini",
    model: "gemini-2.5-flash",
    api_key_alias: "gemini_primary",
    reason: "initial",
    http_status: 200,
    outcome: "max_tokens",
    duration_ms: 100,
    input_tokens: 10,
    output_tokens: 20,
    thoughts_tokens: 5,
    total_tokens: 35,
  });
  tracker.record({
    provider: "gemini",
    model: "gemini-2.5-flash",
    api_key_alias: "gemini_primary",
    reason: "max_tokens_retry",
    http_status: 200,
    outcome: "success",
    duration_ms: 80,
    input_tokens: 10,
    output_tokens: 30,
    thoughts_tokens: 5,
    total_tokens: 45,
  });
  assertEquals(tracker.requestCount, 2);
  assertEquals(tracker.totalTokens, 80);
  assertEquals(tracker.snapshot().map((item) => item.reason), [
    "initial",
    "max_tokens_retry",
  ]);
});

Deno.test("provider tracker stores no prompts, keys, response bodies or errors", () => {
  const tracker = new ProviderAttemptTracker();
  tracker.record({
    provider: "groq",
    model: "model",
    api_key_alias: "groq_free_primary",
    reason: "provider_fallback",
    http_status: 429,
    outcome: "provider_error",
  });
  assertEquals(Object.keys(tracker.snapshot()[0]).sort(), [
    "api_key_alias",
    "duration_ms",
    "http_status",
    "input_tokens",
    "model",
    "outcome",
    "output_tokens",
    "provider",
    "reason",
    "sequence",
    "thoughts_tokens",
    "total_tokens",
  ]);
});

Deno.test("provider tracker caps stored records but preserves aggregate count", () => {
  const tracker = new ProviderAttemptTracker();
  for (let index = 0; index < 40; index += 1) {
    tracker.record({
      provider: "gemini",
      model: "model",
      api_key_alias: "alias",
      reason: "key_fallback",
      http_status: 500,
      outcome: "provider_error",
      total_tokens: 1,
    });
  }
  assertEquals(tracker.snapshot().length, 32);
  assertEquals(tracker.requestCount, 40);
  assertEquals(tracker.totalTokens, 40);
});
