import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  buildTrustedAnalysisComputeRouting,
  computeProfileForAIExecutionRoute,
} from "./analysis-compute-profile.ts";

Deno.test("execution routes map to subscription-independent compute profiles", () => {
  assertEquals(computeProfileForAIExecutionRoute("free_paid_trial"), "premium");
  assertEquals(computeProfileForAIExecutionRoute("paid_plan"), "premium");
  assertEquals(computeProfileForAIExecutionRoute("free_legacy"), "economy");
  assertEquals(
    computeProfileForAIExecutionRoute("cancelled_plus_trial_free"),
    "economy",
  );
});

Deno.test("trusted queue snapshot selects paid Flex only for economy", () => {
  const snapshot = buildTrustedAnalysisComputeRouting({
    route: "cancelled_plus_trial_free",
    firstPaidAIEligible: true,
    cancelledTrial: {
      eligible: true,
      enabled: true,
      mode: "on",
      reason: "enabled",
    },
  });
  assertEquals(snapshot.compute_profile, "economy");
  assertEquals(snapshot.provider_pool, "paid_flex");
  assertEquals(snapshot.requested_service_tier, "flex");
  assertEquals(snapshot.first_paid_ai_eligible, true);
});
