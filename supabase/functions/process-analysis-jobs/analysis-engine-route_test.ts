import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { analysisFunctionForJob } from "./analysis-engine-route.ts";

Deno.test("vNext routes only primary pipeline v2 jobs", () => {
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: false,
      resolvedEngine: "vnext",
    }),
    "analyze-vnext",
  );
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: true,
      resolvedEngine: "vnext",
    }),
    "analyze",
  );
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: false,
      repairJob: false,
      resolvedEngine: "vnext",
    }),
    "analyze",
  );
  assertEquals(
    analysisFunctionForJob({
      pipelineV2: true,
      repairJob: false,
      resolvedEngine: null,
    }),
    "analyze",
  );
});
