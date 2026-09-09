import {
  PHOTO_ANALYSIS_JSON_SCHEMA,
  PHOTO_ANALYSIS_JSON_SCHEMA_V3_4,
} from "./contracts.ts";
import {
  geminiCost,
  openAICost,
  parseProviderStructuredJSON,
  pollOpenAIBackgroundPhotoProvider,
  ProviderCallError,
  startOpenAIBackgroundPhotoProvider,
  toGeminiResponseSchema,
} from "./provider.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Gemini response schema uses OpenAPI type enums", () => {
  const schema = toGeminiResponseSchema(PHOTO_ANALYSIS_JSON_SCHEMA) as Record<
    string,
    unknown
  >;
  const encoded = JSON.stringify(schema);
  assert(schema.type === "OBJECT", "root type must be OBJECT");
  assert(!encoded.includes('"type":"object"'), "lowercase object leaked");
  assert(!encoded.includes('"type":"string"'), "lowercase string leaked");
  assert(!encoded.includes('"type":"array"'), "lowercase array leaked");
  assert(
    !encoded.includes('"additionalProperties"'),
    "strict-only keyword leaked",
  );
  assert(encoded.includes('"type":"INTEGER"'), "integer type missing");
  assert(encoded.includes('"type":"NUMBER"'), "number type missing");
  assert(encoded.includes('"type":"BOOLEAN"'), "boolean type missing");
});

Deno.test("Gemini schema translation does not mutate canonical schema", () => {
  const before = JSON.stringify(PHOTO_ANALYSIS_JSON_SCHEMA);
  toGeminiResponseSchema(PHOTO_ANALYSIS_JSON_SCHEMA);
  assert(
    JSON.stringify(PHOTO_ANALYSIS_JSON_SCHEMA) === before,
    "canonical schema mutated",
  );
});

Deno.test("v3.5 provider schema is compact while v3.4 rollback stays available", () => {
  const compact = JSON.stringify(PHOTO_ANALYSIS_JSON_SCHEMA);
  const legacy = JSON.stringify(PHOTO_ANALYSIS_JSON_SCHEMA_V3_4);
  assert(
    compact.includes('"scanned_module_ids"'),
    "compact module ids missing",
  );
  assert(!compact.includes('"module_audit"'), "legacy audit leaked into v3.5");
  assert(legacy.includes('"module_audit"'), "v3.4 rollback schema missing");
});

Deno.test("provider JSON safely repairs trailing commas and records diagnostics", () => {
  const output = parseProviderStructuredJSON(
    JSON.stringify({
      scene_inventory: [],
      scanned_module_ids: [],
      mandatory_module_outcomes: [],
      sector_context_evidence: [],
      hazard_facts: [],
      inspection_signals: [],
    }).replace(/}$/, ",}"),
    1,
  );
  assert(output._schema_diagnostics_v1?.salvaged === true, "repair not traced");
  assert(
    output._schema_diagnostics_v1?.reason_codes.includes(
      "json_trailing_comma_repaired",
    ),
    "repair reason missing",
  );
});

Deno.test("provider JSON repair does not guess broken strings or missing fields", () => {
  let threw = false;
  try {
    parseProviderStructuredJSON('{"scene_inventory":["broken]}', 1);
  } catch {
    threw = true;
  }
  assert(threw, "unsafe JSON was unexpectedly repaired");
});

Deno.test("Gemini Flex actual cost is half the Standard equivalent", () => {
  const usage = {
    inputTokens: 10_000,
    outputTokens: 4_000,
    reasoningTokens: 2_000,
    cachedInputTokens: 2_000,
  };
  const standard = geminiCost("gemini-2.5-flash", "standard", usage);
  const flex = geminiCost("gemini-2.5-flash", "flex", usage);
  assert(standard === 0.01746, `unexpected standard cost: ${standard}`);
  assert(flex === 0.00873, `unexpected flex cost: ${flex}`);
});

Deno.test("OpenAI cost bills visible and reasoning output without double counting", () => {
  const cost = openAICost({
    inputTokens: 10_000,
    outputTokens: 4_000,
    reasoningTokens: 2_000,
    cachedInputTokens: 2_000,
  });
  assert(cost === 0.00884, `unexpected OpenAI cost: ${cost}`);
});

Deno.test("Luna background submission is store-false and returns a durable pending id", async () => {
  let requestBody: Record<string, unknown> = {};
  let idempotencyKey = "";
  const observation = await startOpenAIBackgroundPhotoProvider({
    apiKey: "test-key",
    model: "gpt-5.6-luna",
    prompt: "test",
    imageData: "AQID",
    mimeType: "image/jpeg",
    photoIndex: 1,
    timeoutMs: 1_000,
    reasoningEffort: "high",
    maxOutputTokens: 8_192,
    compactProviderContract: true,
    idempotencyKey: "riskdetected-bg-stable",
    fetchImpl: (async (
      _url: string | URL | Request,
      init?: RequestInit,
    ) => {
      requestBody = JSON.parse(String(init?.body));
      idempotencyKey = new Headers(init?.headers).get("Idempotency-Key") ?? "";
      return new Response(
        JSON.stringify({ id: "resp_luna_1", status: "queued" }),
        { status: 200 },
      );
    }) as typeof fetch,
  });
  assert(requestBody.background === true, "background flag missing");
  assert(requestBody.store === false, "background retention must stay bounded");
  assert(
    idempotencyKey === "riskdetected-bg-stable",
    "idempotency key missing",
  );
  assert(
    observation.state === "pending",
    "queued response must remain pending",
  );
  assert(
    observation.providerRequestID === "resp_luna_1",
    "response id not preserved",
  );
});

Deno.test("Luna background polling reuses the response id without resubmitting input", async () => {
  let method = "";
  let bodyWasPresent = false;
  const observation = await pollOpenAIBackgroundPhotoProvider({
    apiKey: "test-key",
    responseID: "resp_luna_2",
    model: "gpt-5.6-luna",
    photoIndex: 2,
    timeoutMs: 1_000,
    fetchImpl: (async (
      _url: string | URL | Request,
      init?: RequestInit,
    ) => {
      method = String(init?.method);
      bodyWasPresent = init?.body !== undefined && init.body !== null;
      return new Response(
        JSON.stringify({ id: "resp_luna_2", status: "in_progress" }),
        { status: 200 },
      );
    }) as typeof fetch,
  });
  assert(method === "GET", "poll must use GET");
  assert(!bodyWasPresent, "poll must not resend image or prompt");
  assert(
    observation.state === "pending",
    "in-progress response must remain pending",
  );
});

Deno.test("Luna background terminal failure is explicit", async () => {
  let caught: unknown = null;
  try {
    await pollOpenAIBackgroundPhotoProvider({
      apiKey: "test-key",
      responseID: "resp_luna_failed",
      model: "gpt-5.6-luna",
      photoIndex: 1,
      timeoutMs: 1_000,
      fetchImpl: (async () =>
        new Response(
          JSON.stringify({ id: "resp_luna_failed", status: "failed" }),
          { status: 200 },
        )) as typeof fetch,
    });
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof ProviderCallError, "terminal failure must be typed");
  assert(
    (caught as ProviderCallError).code === "provider_background_failed",
    "terminal status code lost",
  );
});
