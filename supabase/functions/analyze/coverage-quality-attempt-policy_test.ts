import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { coverageQualityFallbackAttemptState } from "./coverage-quality-attempt-policy.ts";

Deno.test("first quality repair fallback is enqueued but not reported as attempted", () => {
  assertEquals(
    coverageQualityFallbackAttemptState({
      queueReadCount: 1,
      priorModelGenerationPassCount: 1,
    }),
    {
      enqueued: true,
      attempted: false,
      modelGenerationPassCount: 1,
    },
  );
});

Deno.test("quality repair retry records exactly one prior logical attempt", () => {
  assertEquals(
    coverageQualityFallbackAttemptState({
      queueReadCount: 2,
      priorModelGenerationPassCount: 1,
    }),
    {
      enqueued: true,
      attempted: true,
      modelGenerationPassCount: 2,
    },
  );
});

Deno.test("quality repair retry keeps the three-pass ceiling", () => {
  assertEquals(
    coverageQualityFallbackAttemptState({
      queueReadCount: 9,
      priorModelGenerationPassCount: 3,
    }),
    {
      enqueued: true,
      attempted: true,
      modelGenerationPassCount: 3,
    },
  );
});
