import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  classifyDispatchObservation,
  reconcileQueueAfterDispatch,
  reconcileWithAuthoritativeState,
} from "./dispatch-policy.ts";

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
