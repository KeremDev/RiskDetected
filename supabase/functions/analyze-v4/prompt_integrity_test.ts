import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  computeV4Gemini3PromptSHA256,
  computeV4PromptSHA256,
} from "./prompt-integrity.ts";
import {
  V4_GEMINI3_PROMPT_VERSION,
  V4_PROMPT_VERSION,
  V4_PROVIDER_CONTRACT_VERSION,
} from "./contracts.ts";

// The bundle embeds V4_PROMPT_VERSION (prompt.ts writes "SÜRÜM: ..." into
// V4_PROMPT_COMMON), so the version and the hash move together. Bump the
// version constant FIRST, then read the hash from this test and paste it here.
// Reading it before the bump gives a value that is already stale, which cost
// three rounds of chasing a hash that "kept changing".
const RELEASED_PROMPT_SHA256 =
  "823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e";

Deno.test("v4 prompt/schema bundle cannot change without versioned SHA update", async () => {
  assertEquals(V4_PROMPT_VERSION, "v4-vision-core-v10");
  assertEquals(V4_PROVIDER_CONTRACT_VERSION, "visual-claim-candidate-v1");
  assertEquals(await computeV4PromptSHA256(), RELEASED_PROMPT_SHA256);
});

// The Gemini 3 core prompt is hashed separately, so the base bundle -- and the
// gemini-2.5-flash path measured under it -- stays byte-identical. Same rule as
// above: bump V4_GEMINI3_PROMPT_VERSION first, then read the hash.
const RELEASED_GEMINI3_PROMPT_SHA256 =
  "394f5026da26d3bd73e30d7168e1a8fae44dfb9d7fb9858aa2ec807225107678";

Deno.test("Gemini 3 çekirdek istemi sürüm bumpı olmadan değişemez", async () => {
  assertEquals(V4_GEMINI3_PROMPT_VERSION, "v4-gemini3-core-v4");
  assertEquals(
    await computeV4Gemini3PromptSHA256(),
    RELEASED_GEMINI3_PROMPT_SHA256,
  );
});
