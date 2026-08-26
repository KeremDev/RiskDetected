import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { computeV4PromptSHA256 } from "./prompt-integrity.ts";
import {
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

const RELEASED_PROMPT_SHA256 =
  "116ac911e576c83c61810ecfc956a8f7d0a4b1bb51b16fe8a7c4ec3d1caefb2e";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v5");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});
