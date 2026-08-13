import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("analyze authenticates callers and bounds the body before parsing", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const handler = source.slice(source.indexOf("serve(async (req: Request)"));
  const authHeaderIndex = handler.indexOf(
    'req.headers.get("Authorization")',
  );
  const userAuthIndex = handler.indexOf("supabase.auth\n      .getUser(");
  const boundedReadIndex = handler.indexOf("readBoundedRequestText(");
  const parseIndex = handler.indexOf("JSON.parse(");

  assertStringIncludes(handler, "MAX_ANALYZE_REQUEST_BODY_BYTES");
  assertStringIncludes(handler, 'code: "request_body_too_large"');
  assertEquals(handler.includes("await req.json()"), false);
  assertEquals(
    authHeaderIndex >= 0 && authHeaderIndex < boundedReadIndex,
    true,
  );
  assertEquals(userAuthIndex >= 0 && userAuthIndex < boundedReadIndex, true);
  assertEquals(parseIndex >= 0 && parseIndex < boundedReadIndex, true);
});

Deno.test("analyze preserves authenticated user and service-role worker paths", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  assertStringIncludes(
    source,
    "const hasServiceRoleAuth = authHeader === `Bearer ${serviceRoleKey}`;",
  );
  assertStringIncludes(
    source,
    "const isWorkerInvocation = hasServiceRoleAuth &&",
  );
  assertStringIncludes(source, "else if (authenticatedUser)");
  assertStringIncludes(source, "user = authenticatedUser;");
});
