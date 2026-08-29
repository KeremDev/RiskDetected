import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  analysisFunctionForJob,
  requiresV4ForIOSRelease,
} from "./analysis-engine-route.ts";

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

Deno.test("iOS build 87 and newer require the trusted V4 route", () => {
  assertEquals(
    requiresV4ForIOSRelease({
      source: "trusted_analyze_enqueue",
      api_contract_version: 3,
      client_platform: "ios",
      client_app_build: "87",
      safety_claim_v4_scoreless: true,
    }),
    true,
  );
  assertEquals(
    requiresV4ForIOSRelease({
      source: "trusted_analyze_enqueue",
      api_contract_version: 3,
      client_platform: "android",
      client_app_build: "87",
      safety_claim_v4_scoreless: true,
    }),
    false,
  );
  assertEquals(
    requiresV4ForIOSRelease({
      source: "trusted_analyze_enqueue",
      api_contract_version: 3,
      client_platform: "ios",
      client_app_build: "86",
      safety_claim_v4_scoreless: true,
    }),
    false,
  );
});
