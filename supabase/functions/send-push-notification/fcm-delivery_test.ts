import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { deliverToFcm } from "./fcm-delivery.ts";

Deno.test("FCM transient response retries only the failed device request", async () => {
  let calls = 0;
  let sawTimeoutSignal = false;
  const waits: number[] = [];
  const result = await deliverToFcm({
    url: "https://fcm.googleapis.com/v1/projects/test/messages:send",
    headers: {},
    payload: { message: { token: "test" } },
    fetchImpl: (_input, init) => {
      calls += 1;
      sawTimeoutSignal = init?.signal instanceof AbortSignal;
      return Promise.resolve(
        calls === 1
          ? new Response(
            '{"error":{"status":"UNAVAILABLE","message":"backend unavailable"}}',
            { status: 503 },
          )
          : new Response(
            '{"name":"projects/test/messages/accepted-id"}',
            { status: 200 },
          ),
      );
    },
    waitImpl: (milliseconds) => {
      waits.push(milliseconds);
      return Promise.resolve();
    },
  });

  assertEquals(calls, 2);
  assertEquals(sawTimeoutSignal, true);
  assertEquals(waits, [250]);
  assertEquals(result.attempts.map((attempt) => attempt.outcome), [
    "transient",
    "accepted",
  ]);
  assertEquals(result.final.messageID, "projects/test/messages/accepted-id");
});

Deno.test("FCM UNREGISTERED token is permanent and disables the token, no retry", async () => {
  let calls = 0;
  const result = await deliverToFcm({
    url: "https://fcm.googleapis.com/v1/projects/test/messages:send",
    headers: {},
    payload: { message: { token: "dead-token" } },
    fetchImpl: () => {
      calls += 1;
      return Promise.resolve(
        new Response(
          '{"error":{"status":"UNREGISTERED","message":"app uninstalled"}}',
          { status: 404 },
        ),
      );
    },
    waitImpl: () => Promise.resolve(),
  });

  assertEquals(calls, 1);
  assertEquals(result.final.outcome, "permanent");
  assertEquals(result.final.disableToken, true);
  assertEquals(result.final.retryable, false);
});

Deno.test("FCM transport ambiguity is recorded without automatic retry", async () => {
  let calls = 0;
  const result = await deliverToFcm({
    url: "https://fcm.googleapis.com/v1/projects/test/messages:send",
    headers: {},
    payload: { message: { token: "test" } },
    fetchImpl: () => {
      calls += 1;
      return Promise.reject(new TypeError("connection reset"));
    },
    waitImpl: () => Promise.resolve(),
  });

  assertEquals(calls, 1);
  assertEquals(result.final.outcome, "ambiguous");
  assertEquals(result.final.retryable, false);
  assertEquals(result.final.messageID, null);
});
