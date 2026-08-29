import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { computeV4PromptSHA256 } from "./prompt-integrity.ts";
import {
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

const RELEASED_PROMPT_SHA256 =
  "7a1ff1e61401699a1264af54a71c3c65a97939a31511de0bc3193022be61d2e3";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v7");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});
