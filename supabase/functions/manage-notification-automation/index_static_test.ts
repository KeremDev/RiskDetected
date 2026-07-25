import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

Deno.test("operations API validates user token and delegates authorization to scoped RPCs", () => {
  assert(source.includes("supabase.auth.getUser"));
  assert(source.includes("admin_notification_snapshot_v1"));
  assert(source.includes("admin_notification_preview_v1"));
  assert(source.includes("admin_notification_mutation_v1"));
  assertEquals(
    [...source.matchAll(/SUPABASE_SERVICE_ROLE_KEY/g)].length,
    1,
  );
});

Deno.test("operations API does not expose a browser service-role contract", () => {
  assert(source.includes('"Cache-Control": "no-store"'));
  assert(!source.includes("service_role_key:"));
});

Deno.test("operations API uses an explicit browser origin allowlist", () => {
  assert(source.includes("OPERATIONS_CENTER_ALLOWED_ORIGINS"));
  assert(source.includes('req.method === "OPTIONS"'));
  assert(source.includes('"Vary": "Origin"'));
  assert(!source.includes('"Access-Control-Allow-Origin": "*"'));
});
