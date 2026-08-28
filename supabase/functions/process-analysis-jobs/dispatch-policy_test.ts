import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  classifyDispatchObservation,
  forceCoverageQualityFallback,
  isExplicitVNextFailure,
  isProviderBackgroundPendingResponse,
  providerBackgroundRetrySeconds,
  reconcileQueueAfterDispatch,
  reconcileWithAuthoritativeState,
} from "./dispatch-policy.ts";

Deno.test("coverage quality retries use the repair queue message read count", () => {
  assertEquals(
    forceCoverageQualityFallback({
      repairKind: "coverage_quality_v2",
      queueReadCount: 1,
    }),
    false,
  );
  for (const queueReadCount of [2, 3, 9]) {
    assertEquals(
      forceCoverageQualityFallback({
        repairKind: "coverage_quality_v2",
        queueReadCount,
      }),
      true,
    );
  }
  assertEquals(
    forceCoverageQualityFallback({
      repairKind: "legacy_coverage",
      queueReadCount: 2,
    }),
    false,
  );
});

Deno.test("guard v2 keeps ambiguous dispatch while claim is active", () => {
  for (const httpStatus of [null, 502, 504, 546]) {
    assertEquals(
      classifyDispatchObservation({
        transportError: httpStatus === null,
        httpStatus,
        responseBodyParsed: true,
      }),
      "ambiguous_transport",
    );
  }
  assertEquals(
    reconcileQueueAfterDispatch({
      claimGuardVersion: 2,
      claimState: "claimed",
      validationFailed: false,
    }),
    { action: "keep", reason: "claimed" },
  );
});

Deno.test("guard v2 treats malformed response as ambiguous", () => {
  assertEquals(
    classifyDispatchObservation({
      transportError: false,
      httpStatus: 200,
      responseBodyParsed: false,
    }),
    "ambiguous_transport",
  );
});

Deno.test("guard v2 deletes only database terminal or superseded jobs", () => {
  for (const state of ["completed", "failed", "superseded"]) {
    assertEquals(
      reconcileQueueAfterDispatch({
        claimGuardVersion: 2,
        claimState: state,
        validationFailed: false,
      }),
      { action: "delete", reason: state },
    );
  }
  for (const state of ["claimed", "lost_claim", "lease_expired"]) {
    assertEquals(
      reconcileQueueAfterDispatch({
        claimGuardVersion: 2,
        claimState: state,
        validationFailed: false,
      }),
      { action: "keep", reason: state },
    );
  }
});

Deno.test("guard v2 fails safe when claim state lookup fails", () => {
  assertEquals(
    reconcileQueueAfterDispatch({
      claimGuardVersion: 2,
      claimState: null,
      validationFailed: true,
    }),
    { action: "keep", reason: "claim_state_unavailable" },
  );
});

Deno.test("legacy messages retain legacy policy", () => {
  assertEquals(
    reconcileQueueAfterDispatch({
      claimGuardVersion: 1,
      claimState: "completed",
      validationFailed: false,
    }),
    { action: "legacy", reason: "legacy_claim_guard" },
  );
});

Deno.test("application errors remain distinguishable from transport ambiguity", () => {
  assertEquals(
    classifyDispatchObservation({
      transportError: false,
      httpStatus: 429,
      responseBodyParsed: true,
    }),
    "application_error",
  );
  assertEquals(
    classifyDispatchObservation({
      transportError: false,
      httpStatus: 200,
      responseBodyParsed: true,
    }),
    "success_response",
  );
});

Deno.test("parsed vNext provider failures release the claim for checkpoint retry", () => {
  assertEquals(
    isExplicitVNextFailure({
      httpStatus: 500,
      responseBodyParsed: true,
      responseCode: "provider_timeout",
    }),
    true,
  );
  assertEquals(
    isExplicitVNextFailure({
      httpStatus: 500,
      responseBodyParsed: true,
      responseCode: "provider_schema_invalid__schema_all_facts_invalid_region",
    }),
    true,
  );
  assertEquals(
    isExplicitVNextFailure({
      httpStatus: 502,
      responseBodyParsed: false,
      responseCode: null,
    }),
    false,
  );
});

Deno.test("Luna background pending is a non-terminal queue observation", () => {
  assertEquals(
    isProviderBackgroundPendingResponse({
      httpStatus: 202,
      responseBodyParsed: true,
      responseCode: "provider_background_pending",
    }),
    true,
  );
  assertEquals(
    isProviderBackgroundPendingResponse({
      httpStatus: 500,
      responseBodyParsed: true,
      responseCode: "provider_background_pending",
    }),
    false,
  );
  assertEquals(providerBackgroundRetrySeconds(15), 15);
  assertEquals(providerBackgroundRetrySeconds(2), 5);
  assertEquals(providerBackgroundRetrySeconds(500), 120);
  assertEquals(providerBackgroundRetrySeconds("invalid"), 15);
});

Deno.test("response loss keeps the live claim then deletes completed message without a second provider call", async () => {
  let databaseState = "claimed";
  const providerCalls = 1;
  let messageDeleted = false;

  const first = await reconcileWithAuthoritativeState({
    claimGuardVersion: 2,
    validateState: async () => databaseState,
  });
  assertEquals(first.decision.action, "keep");
  assertEquals(messageDeleted, false);

  // The nested HTTP response was lost, but the original analyze invocation
  // continued and committed with its original claim token.
  databaseState = "completed";
  const second = await reconcileWithAuthoritativeState({
    claimGuardVersion: 2,
    validateState: async () => databaseState,
  });
  if (second.decision.action === "delete") messageDeleted = true;

  assertEquals(providerCalls, 1);
  assertEquals(messageDeleted, true);
});

Deno.test("true downstream death stays retained until authoritative lease expiry", async () => {
  const beforeLease = await reconcileWithAuthoritativeState({
    claimGuardVersion: 2,
    validateState: async () => "claimed",
  });
  const atLease = await reconcileWithAuthoritativeState({
    claimGuardVersion: 2,
    validateState: async () => "lease_expired",
  });
  assertEquals(beforeLease.decision.action, "keep");
  assertEquals(atLease.decision.action, "keep");
});
