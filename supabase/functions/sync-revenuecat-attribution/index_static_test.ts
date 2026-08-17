import {
  assertEquals,
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const apiSource = await Deno.readTextFile(
  new URL("../_shared/revenuecat-attribution-api.ts", import.meta.url),
);

Deno.test("worker uses only RevenueCat API v2 read endpoint", () => {
  assertStringIncludes(apiSource, "/v2/projects/");
  assertStringIncludes(apiSource, "/customers/");
  assertStringIncludes(apiSource, "/attributes?limit=100");
  assertFalse(apiSource.includes("/v1/subscribers"));
  assertFalse(apiSource.includes('"X-Platform":'));
});

Deno.test("worker is private, bounded and writes only attribution table", () => {
  assertStringIncludes(source, "x-attribution-sync-secret");
  assertStringIncludes(source, "constantTimeEquals");
  assertStringIncludes(source, "Math.min(25");
  assertStringIncludes(source, "offset += 5");
  assertEquals(source.includes('.from("analyses").update'), false);
  assertEquals(source.includes('.from("profiles").update'), false);
  assertEquals(source.includes('.from("user_subscriptions").update'), false);
  assertEquals(source.includes('.from("subscription_events").update'), false);
});

Deno.test("authorization errors abort and alert the batch", () => {
  assertStringIncludes(
    apiSource,
    "response.status === 401 || response.status === 403",
  );
  assertStringIncludes(source, "sendAuthorizationAlert");
  assertStringIncludes(source, "revenuecat_authorization_failed");
});
