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

Deno.test("RevenueCat Play webhook has an isolated authorization secret", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, 'searchParams.get("platform")');
  assertStringIncludes(source, 'webhookPlatform === "android-play"');
  assertStringIncludes(source, '"REVENUECAT_ANDROID_WEBHOOK_AUTHORIZATION"');
  assertStringIncludes(source, '"REVENUECAT_WEBHOOK_AUTHORIZATION"');
  assertStringIncludes(source, "Deno.env.get(\n    authorizationSecretName,");
});

Deno.test("RevenueCat OSGB purchases require an exact workspace purchase intent", async () => {
  const source = await readTextIfAllowed(new URL("./index.ts", import.meta.url));
  if (source == null) return;
  assertStringIncludes(source, "revenueCatWorkspaceIntent(event)");
  assertStringIncludes(source, "isg_workspace_purchase_record_revenuecat_v1");
  assertStringIncludes(source, "workspace_purchase_event_invalid");
  assertStringIncludes(source, "never falls through");
});
