import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  retrieveOpenAIResponse,
  sendOpenAIResponse,
} from "./openai-provider-client.ts";

Deno.test("OpenAI Responses client applies authorization and body", async () => {
  let seenURL = "";
  let seenInit: RequestInit | undefined;
  const response = await sendOpenAIResponse({
    apiKey: "test-key",
    timeoutMs: 1_000,
    body: { model: "gpt-5.6-luna" },
    idempotencyKey: "analysis-photo-stable-key",
    fetchImpl: ((url: string | URL | Request, init?: RequestInit) => {
      seenURL = String(url);
      seenInit = init;
      return Promise.resolve(new Response("{}", { status: 200 }));
    }) as typeof fetch,
  });
  assertEquals(response.status, 200);
  assertEquals(seenURL, "https://api.openai.com/v1/responses");
  assertEquals(
    new Headers(seenInit?.headers).get("Authorization"),
    "Bearer test-key",
  );
  assertEquals(
    new Headers(seenInit?.headers).get("Idempotency-Key"),
    "analysis-photo-stable-key",
  );
  assertEquals(JSON.parse(String(seenInit?.body)).model, "gpt-5.6-luna");
});

Deno.test("OpenAI Responses client retrieves a persisted background response", async () => {
  let seenURL = "";
  let seenMethod = "";
  const response = await retrieveOpenAIResponse({
    apiKey: "test-key",
    responseID: "resp_background_123",
    timeoutMs: 1_000,
    fetchImpl: ((url: string | URL | Request, init?: RequestInit) => {
      seenURL = String(url);
      seenMethod = String(init?.method);
      return Promise.resolve(new Response("{}", { status: 200 }));
    }) as typeof fetch,
  });
  assertEquals(response.status, 200);
  assertEquals(
    seenURL,
    "https://api.openai.com/v1/responses/resp_background_123",
  );
  assertEquals(seenMethod, "GET");
});

Deno.test("OpenAI Responses client rejects unsafe response ids", async () => {
  await assertRejects(
    () =>
      retrieveOpenAIResponse({
        apiKey: "test-key",
        responseID: "../secret",
        timeoutMs: 1_000,
      }),
    Error,
    "OPENAI_RESPONSE_ID_INVALID",
  );
});

Deno.test("OpenAI Responses client rejects missing key", async () => {
  await assertRejects(
    () => sendOpenAIResponse({ apiKey: "", body: {}, timeoutMs: 1_000 }),
    Error,
    "OPENAI_API_KEY_MISSING",
  );
});
