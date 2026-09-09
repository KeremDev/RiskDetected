// deno-lint-ignore-file no-import-prefix -- Match the pinned Deno std used by the existing suite.
import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  sendStructuredGemini,
  type StructuredGeminiCall,
  V4ProviderError,
} from "./provider.ts";

const request: StructuredGeminiCall = {
  apiKey: "synthetic-not-a-real-key",
  model: "gemini-3.5-flash-lite",
  prompt: "Synthetic test",
  imageData: "AA==",
  mimeType: "image/png",
  timeoutMs: 110000,
  thinkingBudget: 3072,
  thinkingLevel: "HIGH",
  maxOutputTokens: 32768,
  serviceTier: "standard",
  billingTier: "free",
};

Deno.test("free API preserves tokens and standard-equivalent cost, not paid cost", async () => {
  const original = globalThis.fetch;
  let sent: Record<string, unknown> = {};
  globalThis.fetch = (_url, init) => {
    sent = JSON.parse(String((init as { body?: unknown })?.body));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [{
            finishReason: "STOP",
            content: { parts: [{ text: "{}" }] },
          }],
          usageMetadata: {
            promptTokenCount: 100,
            candidatesTokenCount: 200,
            thoughtsTokenCount: 50,
          },
        }),
        { status: 200 },
      ),
    );
  };
  try {
    const result = await sendStructuredGemini(request, { type: "OBJECT" });
    assertEquals(result.usage.costUSD, 0);
    assertEquals(result.usage.inputTokens, 100);
    assertEquals(result.usage.standardEquivalentCostUSD > 0, true);
    assertEquals("service_tier" in sent, false);
    const config = sent.generationConfig as Record<string, unknown>;
    assertEquals(config.thinkingConfig, { thinkingLevel: "HIGH" });
    assertEquals(config.maxOutputTokens, 32768);
    await assertRejects(
      () => sendStructuredGemini({ ...request, serviceTier: "flex" }, {}),
      V4ProviderError,
    );
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("safety-blocked empty response is not retryable", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({ promptFeedback: { blockReason: "SAFETY" } }),
      ),
    );
  try {
    const error = await assertRejects(
      () => sendStructuredGemini(request, {}),
      V4ProviderError,
    );
    assertEquals(error.code, "provider_output_blocked");
    assertEquals(error.retryable, false);
  } finally {
    globalThis.fetch = original;
  }
});
