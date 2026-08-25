import { PROMPT_BUNDLE_SHA256, PROMPT_VERSION } from "./contracts.ts";
import { computePromptBundleSHA256 } from "./prompt-integrity.ts";

Deno.test("v28 prompt bundle hash changes only with an explicit version bump", async () => {
  if (!/^[0-9a-f]{64}$/.test(PROMPT_BUNDLE_SHA256)) {
    throw new Error(`invalid prompt bundle hash: ${PROMPT_BUNDLE_SHA256}`);
  }
  if (PROMPT_VERSION !== "vnext-photo-expert-v28") {
    throw new Error(`unexpected prompt version: ${PROMPT_VERSION}`);
  }
  const actual = await computePromptBundleSHA256();
  if (actual !== PROMPT_BUNDLE_SHA256) {
    throw new Error(
      `Prompt-bearing content changed without updating PROMPT_VERSION and PROMPT_BUNDLE_SHA256. expected=${PROMPT_BUNDLE_SHA256} actual=${actual}`,
    );
  }
});
