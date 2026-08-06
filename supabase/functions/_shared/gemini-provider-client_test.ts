import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  geminiGenerateContentURL,
  geminiRetryAfterMilliseconds,
  sendGeminiGenerateContent,
} from "./gemini-provider-client.ts";

Deno.test("shared Gemini transport keeps API keys out of the URL", async () => {
  let capturedURL = "";
  let capturedAPIKey = "";
  let capturedContentType = "";
  let capturedBody = "";
  const response = await sendGeminiGenerateContent({
    apiKey: "test-secret",
    model: "gemini-2.5-flash",
    body: { contents: [] },
    timeoutMs: 100,
    fetchImpl: (input, init) => {
      const requestInit = init as globalThis.RequestInit | undefined;
      const headers = new Headers(requestInit?.headers);
      capturedURL = String(input);
      capturedAPIKey = headers.get("x-goog-api-key") ?? "";
      capturedContentType = headers.get("content-type") ?? "";
      capturedBody = String(requestInit?.body);
      assert(requestInit?.signal instanceof AbortSignal);
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });

  assertEquals(response.status, 200);
  assertEquals(
    capturedURL,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
  );
  assertEquals(capturedURL.includes("test-secret"), false);
  assertEquals(capturedAPIKey, "test-secret");
  assertEquals(capturedContentType, "application/json");
  assertEquals(JSON.parse(capturedBody), { contents: [] });
});

Deno.test("shared Gemini transport validates model and timeout", async () => {
  assertRejects(
    () =>
      sendGeminiGenerateContent({
        apiKey: "test-secret",
        model: "../unsafe",
        body: {},
        timeoutMs: 100,
      }),
    Error,
    "GEMINI_MODEL_INVALID",
  );
  assertRejects(
    () =>
      sendGeminiGenerateContent({
        apiKey: "test-secret",
        model: "gemini-2.5-flash",
        body: {},
        timeoutMs: 0,
      }),
    Error,
    "GEMINI_TIMEOUT_INVALID",
  );
});

Deno.test("shared Gemini transport parses bounded Retry-After values", () => {
  assertEquals(
    geminiRetryAfterMilliseconds(new Headers({ "Retry-After": "7" })),
    7_000,
  );
  assertEquals(
    geminiRetryAfterMilliseconds(new Headers({ "Retry-After": "120" })),
    60_000,
  );
  assertEquals(
    geminiRetryAfterMilliseconds(
      new Headers({ "Retry-After": "Thu, 30 Jul 2026 12:00:05 GMT" }),
      Date.parse("Thu, 30 Jul 2026 12:00:00 GMT"),
    ),
    5_000,
  );
  assertEquals(geminiRetryAfterMilliseconds(new Headers()), 0);
});

Deno.test("shared Gemini URL rejects unsafe model path input", () => {
  assertEquals(
    geminiGenerateContentURL("gemini-2.5-flash"),
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
  );
  let thrown: unknown = null;
  try {
    geminiGenerateContentURL("gemini/../../secret");
  } catch (error) {
    thrown = error;
  }
  assert(thrown instanceof Error);
  assertEquals(thrown.message, "GEMINI_MODEL_INVALID");
});
