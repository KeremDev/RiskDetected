import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { computeV4PromptSHA256 } from "./prompt-integrity.ts";
import {
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

const RELEASED_PROMPT_SHA256 =
  "c066259216d0dbb3c43e966e2b9bad48afc6f8c33fd133a0ca0b07fd2e96cb61";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v6");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});
