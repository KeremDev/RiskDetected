import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { deliverToAPNs, mapWithConcurrency } from "./apns-delivery.ts";

Deno.test("APNs transient response retries only the failed device request", async () => {
  let calls = 0;
  let sawTimeoutSignal = false;
  const waits: number[] = [];
  const result = await deliverToAPNs({
    url: "https://api.push.apple.com/3/device/test",
    headers: {},
    payload: { aps: {} },
    fetchImpl: (_input, init) => {
      calls += 1;
      sawTimeoutSignal = init?.signal instanceof AbortSignal;
      return Promise.resolve(
        calls === 1
          ? new Response('{"reason":"TooManyRequests"}', { status: 429 })
          : new Response(null, {
            status: 200,
            headers: { "apns-id": "accepted-id" },
          }),
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
  assertEquals(result.final.apnsID, "accepted-id");
});

Deno.test("APNs transport ambiguity is recorded without automatic retry", async () => {
  let calls = 0;
  const result = await deliverToAPNs({
    url: "https://api.push.apple.com/3/device/test",
    headers: {},
    payload: { aps: {} },
    fetchImpl: () => {
      calls += 1;
      return Promise.reject(new TypeError("connection reset"));
    },
    waitImpl: () => Promise.resolve(),
  });

  assertEquals(calls, 1);
  assertEquals(result.final.outcome, "ambiguous");
  assertEquals(result.final.retryable, false);
});

Deno.test("bounded concurrency preserves input result order", async () => {
  let active = 0;
  let maxActive = 0;
  const result = await mapWithConcurrency([1, 2, 3, 4, 5], 2, async (value) => {
    active += 1;
    maxActive = Math.max(maxActive, active);
    await new Promise((resolve) => setTimeout(resolve, 1));
    active -= 1;
    return value * 10;
  });

  assertEquals(result, [10, 20, 30, 40, 50]);
  assertEquals(maxActive <= 2, true);
});
