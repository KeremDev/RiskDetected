import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  ambiguousNestedTransportDecision,
  notificationJobCompletionDecision,
} from "./job-result-policy.ts";

const workerSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

Deno.test("automation policy maps sender acceptance and skip", () => {
  assertEquals(
    notificationJobCompletionDecision(true, {
      status: "sent",
      event_id: "event-1",
    }),
    {
      result: "sent",
      retryable: false,
      eventID: "event-1",
      errorCode: null,
    },
  );
  assertEquals(
    notificationJobCompletionDecision(true, {
      status: "skipped",
      reason: "user_preference_disabled",
    }).result,
    "skipped",
  );
});

Deno.test("automation policy retries only an explicit sender-level retry contract", () => {
  assertEquals(
    notificationJobCompletionDecision(true, {
      status: "failed",
      retryable: true,
    }).retryable,
    true,
  );
  assertEquals(
    notificationJobCompletionDecision(false, {
      error: "internal",
    }).retryable,
    false,
  );
  assertEquals(
    notificationJobCompletionDecision(true, {
      status: "failed",
      retryable: false,
    }).retryable,
    false,
  );
});

Deno.test("nested transport ambiguity is terminal to prevent duplicate push", () => {
  assertEquals(ambiguousNestedTransportDecision(), {
    result: "ambiguous",
    retryable: false,
    eventID: null,
    errorCode: "nested_sender_transport_ambiguous",
  });
});

Deno.test("worker reconciles accepted response loss and keeps eligibility deferrals", () => {
  assertEquals(
    workerSource.includes(
      'validation?.reason === "already_delivered_current_job"',
    ),
    true,
  );
  assertEquals(workerSource.includes("validation?.deferred === true"), true);
  assertEquals(workerSource.includes("AbortSignal.timeout(120_000)"), true);
});
