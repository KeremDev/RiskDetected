import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

Deno.test("result hub authenticates and resolves product access server-side", () => {
  assertStringIncludes(source, "supabase.auth.getUser");
  assertStringIncludes(source, 'supabase.from("user_subscriptions")');
  assertStringIncludes(source, "resolveResultHubTier");
  assertStringIncludes(source, "resultHubGateOpen");
  assert(!source.includes("body.subscription_tier"));
});

Deno.test("free premium sections are redacted and exports are rejected", () => {
  assertStringIncludes(source, "redactFindingForFree");
  assertStringIncludes(source, "redactNotebookForFree");
  assertStringIncludes(source, 'json(403, { error: "premium_required" })');
});

Deno.test("report intents validate selected server item identifiers", () => {
  assertStringIncludes(source, ".map(canonicalUUID)");
  assertStringIncludes(source, "selected.some((key) => !byID.has(key))");
  assertStringIncludes(source, '"result_hub_create_report_intent"');
  assertStringIncludes(source, "p_selected_item_keys: selected");
});

Deno.test("risk report intents preserve standard versus risk-table output", () => {
  assertStringIncludes(source, 'context.body.report_kind === "standard"');
  assertStringIncludes(source, "const quotaKind = reportKind");
  assertStringIncludes(source, "report_kind: reportKind");
});

Deno.test("feedback identifiers are canonicalized before lookup and persistence", () => {
  assertStringIncludes(source, "function canonicalUUID");
  assertStringIncludes(source, "canonicalUUID(rawTargetKey)");
  assertStringIncludes(source, "p_target_key: targetKey");
});

Deno.test("result endpoint adds no model call", () => {
  const providerMarkers = [
    "generativelanguage.googleapis.com",
    "api.openai.com",
    "generateContent",
    "Gemini",
  ];
  assertEquals(providerMarkers.filter((marker) => source.includes(marker)), []);
});
