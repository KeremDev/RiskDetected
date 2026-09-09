import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  buildNotebookAdvisoryRefreshPlan,
  type NotebookAdvisoryCandidate,
} from "./approved-notebook-advisory-snapshot.ts";

const finding = {
  id: "11111111-1111-4111-8111-111111111111",
  item_class: "observed_finding",
  is_scored: true,
  title: "Açık elektrik panosu",
  description: "Pano kapağı açık ve canlı bölümlere erişilebiliyor.",
  recommended_action: "Pano enerjisini kesin ve kapağı kapatın.",
};

Deno.test("advisory generator retries invalid prose once", async () => {
  let calls = 0;
  const plan = await buildNotebookAdvisoryRefreshPlan({
    findings: [finding],
    generator: (candidates: NotebookAdvisoryCandidate[]) => {
      calls += 1;
      return Promise.resolve(
        new Map([[
          candidates[0].sourceFindingID,
          calls === 1
            ? "Pano enerjisini kesin ve kapağı kapatın."
            : "Pano enerjisinin kesilmesi ve kapağın kapatılması önerilmektedir.",
        ]]),
      );
    },
  });
  assertEquals(calls, 2);
  assertEquals(plan.generatedCount, 1);
  assertEquals(plan.fallbackCount, 0);
  assertEquals(
    plan.toUpsert[0].advisory_text,
    "Pano enerjisinin kesilmesi ve kapağın kapatılması önerilmektedir.",
  );
});

Deno.test("advisory refresh is idempotent for the same source hash", async () => {
  const first = await buildNotebookAdvisoryRefreshPlan({
    findings: [finding],
    generator: (candidates) =>
      Promise.resolve(
        new Map([[
          candidates[0].sourceFindingID,
          "Pano enerjisinin kesilmesi ve kapağın kapatılması önerilmektedir.",
        ]]),
      ),
  });
  const second = await buildNotebookAdvisoryRefreshPlan({
    findings: [finding],
    existingAdvisories: first.advisories,
    generator: () => {
      throw new Error("generator must not run");
    },
  });
  assertEquals(second.toUpsert.length, 0);
  assertEquals(second.reusedCount, 1);
  assertEquals(second.advisories, first.advisories);
});

Deno.test("user-edited notebook sources are never rewritten", async () => {
  let called = false;
  const plan = await buildNotebookAdvisoryRefreshPlan({
    findings: [finding],
    notebookEntries: [{
      is_user_edited: true,
      source_finding_ids: [finding.id],
    }],
    generator: () => {
      called = true;
      return Promise.resolve(new Map());
    },
  });
  assertEquals(called, false);
  assertEquals(plan.toUpsert.length, 0);
  assertEquals(plan.skippedUserEditedCount, 1);
});

Deno.test("provider failure uses strict class-specific fallback", async () => {
  const plan = await buildNotebookAdvisoryRefreshPlan({
    findings: [{ ...finding, recommended_action: "" }],
    generator: () => Promise.reject(new Error("provider unavailable")),
  });
  assertEquals(plan.generatedCount, 0);
  assertEquals(plan.fallbackCount, 1);
  assert(plan.toUpsert[0].advisory_text.endsWith("önerilmektedir."));
});
