import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { fetchWithDeadline } from "./provider-fetch.ts";

Deno.test("provider fetch uses the injected implementation", async () => {
  let calls = 0;
  const fetchImpl: typeof fetch = (_input, init) => {
    calls += 1;
    const signal = (init as { signal?: AbortSignal } | undefined)?.signal;
    assert(signal instanceof AbortSignal);
    return Promise.resolve(new Response('{"ok":true}', { status: 200 }));
  };
  const response = await fetchWithDeadline(
    fetchImpl,
    "https://provider.invalid/test",
    { method: "POST" },
    100,
  );
  assertEquals(calls, 1);
  assertEquals(response.status, 200);
});

Deno.test("provider fetch aborts a controlled hanging request", async () => {
  const fetchImpl: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => {
      const signal = (init as { signal?: AbortSignal } | undefined)?.signal;
      signal?.addEventListener("abort", () => {
        reject(new DOMException("aborted", "AbortError"));
      });
    });
  await assertRejects(
    () =>
      fetchWithDeadline(
        fetchImpl,
        "https://provider.invalid/timeout",
        { method: "POST" },
        5,
      ),
    DOMException,
    "aborted",
  );
});
