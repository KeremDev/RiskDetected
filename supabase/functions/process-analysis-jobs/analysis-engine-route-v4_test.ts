import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { analysisFunctionForJob } from "./analysis-engine-route.ts";

Deno.test("v4 variant dispatches only the isolated analyze-v4 function", () => {
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: false,
      resolvedEngine: "vnext",
      resolvedVariant: "vnext-v4",
    }),
    "analyze-v4",
  );
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: false,
      resolvedEngine: "vnext",
      resolvedVariant: "vnext-v3",
    }),
    "analyze-vnext",
  );
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: false,
      resolvedEngine: "legacy",
      resolvedVariant: null,
    }),
    "analyze",
  );
});
