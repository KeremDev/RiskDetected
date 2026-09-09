import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  shouldRetrySameProvider,
  shouldUseEconomyStandardFallback,
  shouldUseFallbackProvider,
} from "./recovery-policy.ts";

Deno.test("schema-invalid output receives one bounded technical retry after salvage", () => {
  assertEquals(
    shouldRetrySameProvider({
      schemaError: true,
      code: "provider_schema_invalid__schema_all_facts_invalid",
    }),
    true,
  );
});

Deno.test("economy falls back from Flex capacity to one Standard attempt", () => {
  assertEquals(
    shouldUseEconomyStandardFallback({
      schemaError: false,
      code: "provider_unavailable",
    }),
    true,
  );
  assertEquals(
    shouldUseEconomyStandardFallback({
      schemaError: false,
      code: "provider_timeout",
    }),
    true,
  );
  assertEquals(
    shouldUseEconomyStandardFallback({
      schemaError: true,
      code: "provider_schema_invalid__fact",
    }),
    false,
  );
});

Deno.test("timeout gets one lower-budget same-provider retry but rate limit does not", () => {
  assertEquals(
    shouldRetrySameProvider({
      schemaError: false,
      code: "provider_timeout",
    }),
    true,
  );
  assertEquals(
    shouldRetrySameProvider({
      schemaError: false,
      code: "provider_rate_limited",
    }),
    false,
  );
});

Deno.test("timeout does not enter the slow Luna fallback path", () => {
  assertEquals(
    shouldUseFallbackProvider({
      schemaError: false,
      code: "provider_timeout",
    }),
    false,
  );
  assertEquals(
    shouldUseFallbackProvider({
      schemaError: true,
      code: "provider_schema_invalid__schema_all_facts_invalid",
    }),
    true,
  );
  assertEquals(
    shouldUseFallbackProvider({
      schemaError: false,
      code: "provider_rate_limited",
    }),
    true,
  );
  assertEquals(
    shouldUseFallbackProvider({
      schemaError: false,
      code: "provider_transport_error",
    }),
    true,
  );
});

Deno.test("one transient transport failure may retry the primary provider", () => {
  assertEquals(
    shouldRetrySameProvider({
      schemaError: false,
      code: "provider_transport_error",
    }),
    true,
  );
});
