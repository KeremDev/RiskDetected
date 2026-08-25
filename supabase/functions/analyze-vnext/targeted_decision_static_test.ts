import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const indexSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

Deno.test("screening runs even when the targeted provider call is suppressed", () => {
  // The 2026-08-24 construction analysis rejected a scaffold guardrail fact and
  // then reported `screened_facts: []` with `candidate_count: 0`, because a
  // technical retry short-circuited selectTargetedDecision entirely. The
  // diagnostic disappeared along with the remedy. Screening is pure
  // computation over facts already paid for, so it always runs now.
  assertStringIncludes(
    indexSource,
    "const targetedDecision = selectTargetedDecision(",
  );
  assert(
    !indexSource.includes("const targetedDecision = !schemaRepairUsed"),
    "targeted screening must not be gated on schemaRepairUsed",
  );
});

Deno.test("a high-consequence rejection overrides the retry budget suppression", () => {
  // Suppressing the targeted pass after a technical retry protects the call
  // budget. That trade is wrong when screening rejected a fact whose
  // consequence class reaches permanent disability or worse: the targeted pass
  // is the only remaining way to recover it.
  assertStringIncludes(
    indexSource,
    "const targetedRescuesHighConsequence = targetedDecision.screened_facts",
  );
  assertStringIncludes(
    indexSource,
    ".some((fact) => fact.targeted_eligible === true) ||",
  );
  // The sector critical-coverage net raises candidates that no rejected fact
  // accounts for. Checking only the rejection path left a selected
  // scaffold-guardrail candidate suppressed beside a candidate_count of 1.
  assertStringIncludes(
    indexSource,
    "targetedDecision.candidates\n        .some((candidate) => candidate.sector_critical_component === true);",
  );
  assertStringIncludes(
    indexSource,
    "const suppressTargetedForBudget = schemaRepairUsed &&\n      !targetedRescuesHighConsequence;",
  );

  // The status label and the signal must both follow the same decision, or the
  // run reports a skip it did not take.
  assertStringIncludes(
    indexSource,
    "const targetedSignal = suppressTargetedForBudget\n      ? null\n      : targetedDecision.signal;",
  );
  assertStringIncludes(
    indexSource,
    '| "skipped_schema_repair" = suppressTargetedForBudget',
  );
});

Deno.test("provider output budget usage reaches the quality trace", () => {
  // Raw fact production sat at exactly three per photo across prompt versions,
  // two output budgets and a schema reordering. Nothing recorded whether the
  // model was filling its budget or stopping on its own, and vNext writes no
  // ai_usage_logs row, so the question could not be settled from production.
  assertStringIncludes(
    indexSource,
    "product.qualityTrace.provider_output_budget = photoResults.map((result) => {",
  );
  assertStringIncludes(indexSource, "output_budget_used_pct:");
  assertStringIncludes(
    indexSource,
    "const generated = output + reasoning;",
  );
  assertStringIncludes(
    indexSource,
    "product.qualityTrace.provider_attempt_output_budget =",
  );
  assertStringIncludes(indexSource, '"output_cap_exhausted"');
  assertStringIncludes(
    indexSource,
    "promptHash: renderedPromptHash,",
  );
  assertStringIncludes(
    indexSource,
    "raw_fact_count: result.output.hazard_facts.length,",
  );

  // Both provider paths must carry usage or the primary/fallback split shows up
  // as missing data rather than as a measurement.
  assertEquals(
    indexSource.split("inputTokens: result.usage.inputTokens,").length - 1,
    2,
    "usage must be attached on both the primary and fallback result paths",
  );
});
