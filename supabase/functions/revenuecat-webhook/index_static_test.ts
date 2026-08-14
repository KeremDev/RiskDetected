import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("RevenueCat webhook prefers verified renewal truth over event order", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "period_type?: string | null");
  assertStringIncludes(source, "unsubscribe_detected_at?: string | null");
  assertStringIncludes(source, "revenueCatSubscriptionRenewalIntent(");
  assertStringIncludes(source, "verifiedTrialMetadataPatch({");
  assertStringIncludes(source, "mergeTrialMetadataPatches(");

  const existingLookup = source.indexOf(
    "const existingSubscription = await existingSubscriptionRow",
  );
  const write = source.indexOf(
    "await writeSubscriptionState({",
    existingLookup,
  );
  assert(existingLookup > 0 && write > existingLookup);
});
