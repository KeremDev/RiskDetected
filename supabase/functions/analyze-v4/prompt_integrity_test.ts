import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { computeV4PromptSHA256 } from "./prompt-integrity.ts";
import {
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

const RELEASED_PROMPT_SHA256 =
  "5b3e980edc035e3e6d4206b31011e159c6319e98850475c2c0cd4c55b1cb7e12";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v8");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});
