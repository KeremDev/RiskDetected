import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  redactFindingForFree,
  resolveResultHubTier,
  resultHubGateOpen,
  sectionAccess,
} from "./analysis-result-hub.ts";

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
