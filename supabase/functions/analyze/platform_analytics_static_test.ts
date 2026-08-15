import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("AI usage platform is derived from the owned analysis with client fallback", async () => {
  const path = decodeURIComponent(
    new URL("./index.ts", import.meta.url).pathname,
  );
  const source = await Deno.readTextFile(path);
  assertStringIncludes(
    source,
    "primary_method,client_platform,analysis_sector",
  );
  assertStringIncludes(
    source,
    "const analysisClientPlatform = ownedAnalysis.client_platform",
  );
  assertStringIncludes(source, "client_platform: analysisClientPlatform");
});
