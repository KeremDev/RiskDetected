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

Deno.test("feedback validates the target kind for all four result sections", () => {
  assertStringIncludes(
    source,
    'target_kind?: "finding" | "notebook_entry" | "training_card"',
  );
  assertStringIncludes(source, 'section === "training_recommendations"');
  assertStringIncludes(source, '? "training_card"');
  assertStringIncludes(source, 'error: "invalid_feedback_target_kind"');
});

Deno.test("v5 analyses skip the mechanism-template book and keep the site-observation disclaimer", () => {
  // bc85eccd: the v1 book engine's ~12 mechanism templates predate the free
  // engine's broader hazard vocabulary. On that analysis it gave a suspended
  // lifting hook the generic falling-object-from-a-platform-edge paragraph and
  // an arc-radiation/fume exposure the hot-surface-contact paragraph, and it
  // never saw the registry's Uzman Görüşü cards at all -- book_source was
  // never attached to them. v5 analyses now skip it outright.
  assertStringIncludes(source, 'internal_priority).engine_mode === "free"');
  assertStringIncludes(source, "const book = isFreeEngineAnalysis");
  // The book-only gate on this disclaimer went to zero for every v5 analysis
  // the moment the line above shipped; it must key off what is actually being
  // shown, not off which engine produced it.
  assertStringIncludes(
    source,
    "observationBasis: notebookFull.length > 0 ? FIXED_OBSERVATION_BASIS : null",
  );
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
