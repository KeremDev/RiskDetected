import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { fetchRevenueCatAttributes } from "./revenuecat-attribution-api.ts";

const NOW = new Date("2026-08-17T12:00:00.000Z");

function params(fetchImpl: typeof fetch) {
  return {
    apiKey: "test_read_only_key",
    projectID: "proj123",
    customerID: "00000000-0000-4000-8000-000000000001",
    now: NOW,
    fetchImpl,
  };
}

Deno.test("v2 client handles an empty successful attribute list", async () => {
  const calls: Array<{ url: string; headers: Headers }> = [];
  const fetchImpl: typeof fetch = (input, init) => {
    calls.push({
      url: String(input),
      headers: new Headers(
        (init as { headers?: HeadersInit } | undefined)?.headers,
      ),
    });
    return Promise.resolve(
      new Response(JSON.stringify({ object: "list", items: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };
  const result = await fetchRevenueCatAttributes(params(fetchImpl));
  assertEquals(result.kind, "ok");
  assertEquals(calls.length, 1);
  assertEquals(
    calls[0].headers.get("Authorization"),
    "Bearer test_read_only_key",
  );
  assertFalse(calls[0].headers.has("X-Platform"));
});

Deno.test("v2 client follows only valid RevenueCat pagination", async () => {
  const urls: string[] = [];
  const responses = [
    new Response(
      JSON.stringify({
        object: "list",
        items: [{
          name: "$mediaSource",
          value: "Apple Search Ads",
          updated_at: 1_786_959_600_000,
        }],
        next_page:
          "/v2/projects/proj123/customers/00000000-0000-4000-8000-000000000001/attributes?starting_after=%24mediaSource",
      }),
      { status: 200 },
    ),
    new Response(
      JSON.stringify({
        object: "list",
        items: [{
          name: "$campaign",
          value: "Campaign A",
          updated_at: 1_786_959_601_000,
        }],
      }),
      { status: 200 },
    ),
  ];
  const fetchImpl: typeof fetch = (input) => {
    urls.push(String(input));
    return Promise.resolve(responses.shift()!);
  };
  const result = await fetchRevenueCatAttributes(params(fetchImpl));
  assertEquals(urls.length, 2);
  assertEquals(result.kind, "ok");
  if (result.kind === "ok") {
    assertEquals(result.values.campaignName, "Campaign A");
  }
});

Deno.test("v2 client maps 404 without creating a customer", async () => {
  const result = await fetchRevenueCatAttributes(
    params(() => Promise.resolve(new Response(null, { status: 404 }))),
  );
  assertEquals(result, { kind: "not_found", status: 404 });
});

Deno.test("v2 client treats 401 and 403 as batch authorization failures", async () => {
  for (const status of [401, 403] as const) {
    const result = await fetchRevenueCatAttributes(
      params(() => Promise.resolve(new Response(null, { status }))),
    );
    assertEquals(result, { kind: "unauthorized", status });
  }
});

Deno.test("v2 client honors Retry-After on 429", async () => {
  const result = await fetchRevenueCatAttributes(
    params(() =>
      Promise.resolve(
        new Response(null, {
          status: 429,
          headers: { "Retry-After": "120" },
        }),
      )
    ),
  );
  assertEquals(result, {
    kind: "rate_limited",
    status: 429,
    retryAt: "2026-08-17T12:02:00.000Z",
  });
});

Deno.test("v2 client retries 5xx and malformed 200 responses", async () => {
  const serverError = await fetchRevenueCatAttributes(
    params(() => Promise.resolve(new Response(null, { status: 503 }))),
  );
  assertEquals(serverError, {
    kind: "retryable",
    status: 503,
    code: "revenuecat_server_error",
  });

  const malformed = await fetchRevenueCatAttributes(
    params(() =>
      Promise.resolve(
        new Response(JSON.stringify({ object: "list" }), { status: 200 }),
      )
    ),
  );
  assertEquals(malformed, {
    kind: "retryable",
    status: 502,
    code: "invalid_response",
  });
});
