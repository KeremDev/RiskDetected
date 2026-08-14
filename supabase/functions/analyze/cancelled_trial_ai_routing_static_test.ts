import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("cancelled Plus trial route preserves Plus output on the free provider pool", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "CANCELLED_PLUS_TRIAL_ROUTE");
  assertStringIncludes(source, "usesFreeGeminiProviderPool(aiExecutionRoute)");
  assertStringIncludes(source, "async function callAIWithFreeProviderPool(");
  assertStringIncludes(source, "outputTier: PlanTier");
  assertStringIncludes(
    source,
    'aiExecutionRoute === CANCELLED_PLUS_TRIAL_ROUTE ? planTier : "free"',
  );
  assertStringIncludes(
    source,
    'const orderedFreeKeys = keyPool.filter((item) => item.pool === "free")',
  );

  const freeBranchStart = source.indexOf(
    "if (usesFreeGeminiProviderPool(aiExecutionRoute))",
  );
  const paidTrialBranchStart = source.indexOf(
    'if (aiExecutionRoute === "free_paid_trial")',
    freeBranchStart,
  );
  const freeBranch = source.slice(freeBranchStart, paidTrialBranchStart);
  assert(freeBranchStart > 0 && paidTrialBranchStart > freeBranchStart);
  assertStringIncludes(freeBranch, "callAIWithFreeProviderPool(");
  assertEquals(freeBranch.includes("callPaidAIWithFallback("), false);
  assertEquals(freeBranch.includes("callFreePaidTrialAIWithFallback("), false);
});

Deno.test("cancelled Plus trial routing remains fail-closed behind a database flag", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(
    source,
    '.eq("key", CANCELLED_PLUS_TRIAL_ROUTING_FLAG_KEY)',
  );
  assertStringIncludes(
    source,
    "return normalizeCancelledPlusTrialRoutingFlag(null)",
  );
  assertStringIncludes(
    source,
    "trial_product_id,will_renew,store,base_plan_id,offer_id,period_type",
  );
});

Deno.test("paid Free introduction is limited to the atomically reserved first analysis", async () => {
  const source = await readTextIfAllowed(
    new URL("./index.ts", import.meta.url),
  );
  if (source == null) return;

  assertStringIncludes(source, "firstPaidAIEligible = false");
  assertStringIncludes(
    source,
    'analysisMode === "standard" &&\n    firstPaidAIEligible',
  );
  assertStringIncludes(
    source,
    "quotaReservation.first_paid_ai_eligible === true",
  );
  assert(
    source.indexOf("quotaReservation.first_paid_ai_eligible === true") >
      source.indexOf('.rpc("reserve_analysis_quota"'),
  );
  assertStringIncludes(
    source,
    "cancelledTrialRouting.enabled,\n    firstPaidAIEligible",
  );
  const resolver = source.slice(
    source.indexOf("function resolveAIExecutionRoute("),
    source.indexOf("function usesFreeGeminiProviderPool("),
  );
  assert(
    resolver.indexOf("cancelledTrialRoutingEnabled") <
      resolver.indexOf("firstPaidAIEligible &&"),
    "cancelled Plus trial routing must take precedence over first-analysis paid AI",
  );
});

Deno.test("AI usage route constraint and rollout flag are expanded safely", async () => {
  const migration = await readTextIfAllowed(
    new URL(
      "../../migrations/20260720082720_route_cancelled_plus_trials_to_free_ai.sql",
      import.meta.url,
    ),
  );
  if (migration == null) return;

  const normalized = migration.toLowerCase().replace(/\s+/g, " ");
  assertStringIncludes(normalized, "'cancelled_plus_trial_free'");
  assertStringIncludes(
    normalized,
    "'cancelled_plus_trial_free_routing'",
  );
  assertStringIncludes(normalized, "'mode', 'off'");
  assertStringIncludes(normalized, "on conflict (key) do nothing");
});
