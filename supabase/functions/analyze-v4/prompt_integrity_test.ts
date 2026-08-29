import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { computeV4PromptSHA256 } from "./prompt-integrity.ts";
import {
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

// The bundle embeds V4_PROMPT_VERSION (prompt.ts writes "SÜRÜM: ..." into
// V4_PROMPT_COMMON), so the version and the hash move together. Bump the
// version constant FIRST, then read the hash from this test and paste it here.
// Reading it before the bump gives a value that is already stale, which cost
// three rounds of chasing a hash that "kept changing".
const RELEASED_PROMPT_SHA256 =
  "41008e19f4b4e95f79fb2f6e8630c118ad71bed4f350420a42715a60cb1da656";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v9");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});
