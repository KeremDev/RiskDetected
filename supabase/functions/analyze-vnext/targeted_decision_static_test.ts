import {
  assert,
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
    ".some((fact) => fact.targeted_eligible === true)",
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
