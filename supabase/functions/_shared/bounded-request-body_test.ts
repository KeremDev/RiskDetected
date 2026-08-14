import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  readBoundedRequestBody,
  readBoundedRequestText,
  RequestBodyTooLargeError,
} from "./bounded-request-body.ts";

Deno.test("bounded body accepts legitimate payload at the byte limit", async () => {
  const request = new Request("https://example.invalid", {
    method: "POST",
    body: "12345678",
  });

  assertEquals(await readBoundedRequestText(request, 8), "12345678");
});

Deno.test("bounded body rejects an excessive declared length before reading", async () => {
  const request = new Request("https://example.invalid", {
    method: "POST",
    headers: { "content-length": "9" },
    body: "123456789",
  });

  await assertRejects(
    () => readBoundedRequestBody(request, 8),
    RequestBodyTooLargeError,
  );
  assertEquals(request.bodyUsed, false);
});

Deno.test("bounded body stops chunked input once the cap is crossed", async () => {
  const request = new Request("https://example.invalid", {
    method: "POST",
    body: new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array([1, 2, 3, 4]));
        controller.enqueue(new Uint8Array([5, 6, 7, 8, 9]));
        controller.close();
      },
    }),
  });

  await assertRejects(
    () => readBoundedRequestBody(request, 8),
    RequestBodyTooLargeError,
  );
});
