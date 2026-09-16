import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  canReportSection,
  redactFindingForFree,
  resolveResultHubTier,
  resultHubGateOpen,
  sectionAccess,
} from "./analysis-result-hub.ts";

Deno.test("training reports require a paid plan and a capable renderer", () => {
  for (const tier of ["free", "plus", "pro"] as const) {
    assertEquals(
      canReportSection("training_recommendations", tier, true),
      tier !== "free",
    );
    assertEquals(
      canReportSection("training_recommendations", tier, false),
      false,
    );
    assertEquals(canReportSection("risk_analysis", tier), true);
    assertEquals(
      canReportSection("expert_recommendations", tier),
      tier !== "free",
    );
    assertEquals(canReportSection("approved_notebook", tier), tier !== "free");
  }
});

Deno.test("cancelled renewal remains product paid until active period expires", () => {
  assertEquals(
    resolveResultHubTier({
      tier: "plus",
      status: "trialing",
      current_period_ends_at: "2099-01-01T00:00:00Z",
    }),
    "plus",
  );
});

Deno.test("client cannot open result hub without capability", () => {
  assertEquals(
    resultHubGateOpen({
      flag: { rollout_mode: "user_allowlist", kill_switch: false },
      allowlisted: true,
      capability: false,
      platform: "ios",
      build: "99",
    }),
    false,
  );
});

Deno.test("free expert access is teaser and contains no premium body", () => {
  assertEquals(sectionAccess("expert_recommendations", "free"), "teaser");
  const row = redactFindingForFree({
    id: "finding",
    title: "Elektrik panosu",
    description: "İlk cümle. Gizli ikinci cümle.",
    recommended_action: "Gizli önlem",
    references_text: "Gizli mevzuat",
  });
  assertEquals(row.description, "İlk cümle.");
  assertEquals(row.recommended_action, null);
  assertEquals(row.references_text, null);
});

Deno.test("pilot builds need explicit result-hub rollout membership", () => {
  const previousBuilds = ["87", "88", "89", "90", "91"];
  const flag = { rollout_mode: "build_allowlist", kill_switch: false,
    enabled_ios_builds: previousBuilds, enabled_android_builds: ["14"] };
  const client = { flag, allowlisted: true, capability: true, platform: "ios", build: "110" };
  // Being a pilot account alone does not bypass a build-based rollout.
  assertEquals(resultHubGateOpen(client), false);
  const updated = { ...flag, enabled_ios_builds: [...previousBuilds,
    ...Array.from({ length: 16 }, (_, index) => String(index + 101))] };
  for (const build of updated.enabled_ios_builds) {
    assertEquals(resultHubGateOpen({ ...client, flag: updated, build }), true);
  }
  assertEquals(resultHubGateOpen({ ...client, flag: updated, build: "117" }), false);
  assertEquals(resultHubGateOpen({ ...client, flag: updated, capability: false }), false);
  assertEquals(resultHubGateOpen({ ...client, flag: { ...updated, kill_switch: true } }), false);
  assertEquals(resultHubGateOpen({ ...client, flag: updated, platform: "android" }), false);
});
