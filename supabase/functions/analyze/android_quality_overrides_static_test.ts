import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("Android layer audit and thinking overrides are platform isolated", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  assertStringIncludes(
    source,
    "multi_photo_layer_audit_enabled_android_builds",
  );
  assertStringIncludes(source, "multi_photo_layer_audit_min_android_build");
  assertStringIncludes(
    source,
    "multi_photo_thinking_budget_android_build_overrides",
  );
  assertStringIncludes(source, "multi_photo_thinking_budget_min_android_build");
  assertStringIncludes(source, 'client.platform === "ios"');
  assertStringIncludes(source, 'client.platform === "android"');
  assert(source.includes("multi_photo_thinking_budget_ios_build_overrides"));
});
