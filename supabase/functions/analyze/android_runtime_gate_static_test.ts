import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("analyze enforces the Android submit gate only for external Android requests", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assertStringIncludes(
    source,
    '!isWorkerInvocation && clientRelease.platform === "android"',
  );
  assertStringIncludes(source, "runtimeGates?.analysis_submit");
  assertStringIncludes(source, "android_analysis_submit_disabled");
});
